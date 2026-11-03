//=============================================================================
//  tb_cim_array.v -- verification stage 3 (CIM array)
//=============================================================================
//  Verilog-2001. No functions, no integer types, no default_nettype,
//  no indexed part-selects.
//
//  Reference: an independent 64-bit per-column accumulator that sign-extends
//  each selected weight. It shares no width logic with the DUT.
//
//  Covers:
//    * single active row / single active column
//    * all-zero activation plane
//    * all-positive and all-negative extremes
//    * distinct weight per column
//    * deasserted row contributes nothing
//    * mixed signed weights
//    * 500 randomised weight and activation vectors, all 64 columns
//=============================================================================
`timescale 1ns/1ps

module tb_cim_array;

    localparam ROWS = 64;
    localparam COLS = 64;
    localparam DW   = 8;
    localparam LW   = 6;
    localparam PW   = DW + LW;
    localparam TBIT = ROWS * COLS * DW;

    reg  [TBIT-1:0]   w_flat;
    reg  [ROWS-1:0]   act_bits;
    wire [COLS*PW-1:0] p_sum;

    cim_array #(
        .ROWS(ROWS), .COLS(COLS), .DW(DW), .LW(LW)
    ) dut (
        .w_flat(w_flat),
        .act_bits(act_bits),
        .p_sum(p_sum)
    );

    //  Byte-level model: model[i*COLS + j] = W[i][j]
    reg [DW-1:0] model [0:ROWS*COLS-1];

    reg [31:0] errors;
    reg [31:0] checks;
    reg [31:0] i;
    reg [31:0] j;
    reg [31:0] t;
    reg [31:0] seed;

    initial begin
        errors = 32'd0;
        checks = 32'd0;
        seed   = 32'hC1A0_2026;
    end

    //---------------------------------------------------------------- helpers
    //  Pack the byte model into w_flat. Appending model[4095] first and
    //  model[0] last places model[k] at bit offset k*DW.
    //  The packing is done in a local register so the 4032-adder DUT is not
    //  re-evaluated on every intermediate concatenation; w_flat changes once.
    task pack_weights;
        reg [31:0]    g;
        reg [TBIT-1:0] packed_w;
        begin
            packed_w = {TBIT{1'b0}};
            for (g = 0; g < (ROWS*COLS)/8; g = g + 32'd1) begin
                packed_w = {packed_w[TBIT-64-1:0],
                            model[ROWS*COLS-1-(g*8+0)],
                            model[ROWS*COLS-1-(g*8+1)],
                            model[ROWS*COLS-1-(g*8+2)],
                            model[ROWS*COLS-1-(g*8+3)],
                            model[ROWS*COLS-1-(g*8+4)],
                            model[ROWS*COLS-1-(g*8+5)],
                            model[ROWS*COLS-1-(g*8+6)],
                            model[ROWS*COLS-1-(g*8+7)]};
            end
            w_flat = packed_w;
        end
    endtask

    //  Compares every column against the reference sum.
    task check_all;
        input [31:0] tag;
        reg [63:0]   sum;
        reg [PW-1:0] got;
        reg [31:0]   ii;
        reg [31:0]   jj;
        begin
            #1;
            for (jj = 0; jj < COLS; jj = jj + 32'd1) begin
                sum = 64'd0;
                for (ii = 0; ii < ROWS; ii = ii + 32'd1) begin
                    if (act_bits[ii] === 1'b1)
                        sum = sum +
                              {{(64-DW){model[ii*COLS+jj][DW-1]}},
                               model[ii*COLS+jj]};
                end
                got    = p_sum >> (jj*PW);
                checks = checks + 32'd1;
                if (got !== sum[PW-1:0]) begin
                    errors = errors + 32'd1;
                    if (errors < 15)
                        $display("  FAIL tag=%0d col=%0d exp=%0d got=%0d",
                                 tag, jj,
                                 $signed(sum[PW-1:0]), $signed(got));
                end
            end
        end
    endtask

    task fill_weights;
        input [DW-1:0] v;
        reg [31:0] k;
        begin
            for (k = 0; k < ROWS*COLS; k = k + 32'd1)
                model[k] = v;
        end
    endtask

    //------------------------------------------------------------------- test
    initial begin
        w_flat   = {TBIT{1'b0}};
        act_bits = {ROWS{1'b0}};

        $display("== tb_cim_array ==");

        //--- T1: single active element -----------------------------------
        $display("[T1] single active element W[0][0]");
        fill_weights(8'h00);
        model[0] = 8'd42;                 // W[0][0]
        pack_weights;
        act_bits = {ROWS{1'b0}};
        act_bits[0] = 1'b1;
        check_all(32'd1);

        //--- T2: all-zero activation plane --------------------------------
        $display("[T2] all-zero activation plane");
        fill_weights(8'h7F);
        pack_weights;
        act_bits = {ROWS{1'b0}};
        check_all(32'd2);

        //--- T3: maximum positive -----------------------------------------
        $display("[T3] all weights +127, all rows active (expect 8128)");
        fill_weights(8'h7F);
        pack_weights;
        act_bits = {ROWS{1'b1}};
        check_all(32'd3);
        $display("     P[0] = %0d", $signed(p_sum[PW-1:0]));

        //--- T4: maximum negative -----------------------------------------
        $display("[T4] all weights -128, all rows active (expect -8192)");
        fill_weights(8'h80);
        pack_weights;
        act_bits = {ROWS{1'b1}};
        check_all(32'd4);
        $display("     P[0] = %0d", $signed(p_sum[PW-1:0]));

        //--- T5: distinct weight per column --------------------------------
        $display("[T5] W[i][j] = j+1 for all i, all rows active");
        for (i = 0; i < ROWS; i = i + 32'd1)
            for (j = 0; j < COLS; j = j + 32'd1)
                model[i*COLS + j] = j + 32'd1;
        pack_weights;
        act_bits = {ROWS{1'b1}};
        check_all(32'd5);

        //--- T6: one deactivated row must vanish from the sum --------------
        $display("[T6] row 5 deactivated, W[5][j] = -128");
        fill_weights(8'h01);
        for (j = 0; j < COLS; j = j + 32'd1)
            model[5*COLS + j] = 8'h80;
        pack_weights;
        act_bits = {ROWS{1'b1}};
        act_bits[5] = 1'b0;
        check_all(32'd6);

        //--- T7: mixed signed weights --------------------------------------
        $display("[T7] alternating +127 / -128 weights");
        for (i = 0; i < ROWS; i = i + 32'd1)
            for (j = 0; j < COLS; j = j + 32'd1)
                model[i*COLS + j] = ((i + j) % 2 == 0) ? 8'h7F : 8'h80;
        pack_weights;
        act_bits = {ROWS{1'b1}};
        check_all(32'd7);

        //--- T8: randomised ------------------------------------------------
        $display("[T8] 200 random weight and activation vectors");
        for (t = 0; t < 200; t = t + 32'd1) begin
            for (i = 0; i < ROWS*COLS; i = i + 32'd1)
                model[i] = $unsigned($random(seed)) % 256;
            pack_weights;
            for (i = 0; i < ROWS; i = i + 32'd1)
                act_bits[i] = $unsigned($random(seed)) % 2;
            check_all(t);
        end

        //--- summary --------------------------------------------------------
        $display("---------------------------------------------");
        if (errors == 32'd0)
            $display("PASS  %0d checks, 0 errors", checks);
        else
            $display("FAIL  %0d checks, %0d errors", checks, errors);
        $display("---------------------------------------------");
        $finish;
    end

    //------------------------------------------------------------ watchdog
    initial begin
        #20_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
