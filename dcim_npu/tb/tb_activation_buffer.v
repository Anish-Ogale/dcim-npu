//=============================================================================
//  tb_activation_buffer.v -- verification stage 1 (activation store)
//=============================================================================
//  Verilog-2001. No functions, no integer types, no default_nettype,
//  no indexed part-selects.
//
//  Covers:
//    * bulk clear
//    * load / readback of all 64 activations
//    * bit-slice correctness for every bit_sel, 0..7
//    * signed extremes: -128 (0x80), +127 (0x7F), 0
//    * load protection while lock is asserted
//    * randomised vectors and randomised bit_sel
//=============================================================================
`timescale 1ns/1ps

module tb_activation_buffer;

    localparam N      = 64;
    localparam DW     = 8;
    localparam BW     = 3;
    localparam ADDR_W = 6;

    reg                   clk;
    reg                   rst;
    reg                   lock;
    reg                   ld_en;
    reg  [ADDR_W-1:0]     ld_addr;
    reg  [DW-1:0]         ld_data;
    reg  [BW-1:0]         bit_sel;
    reg  [ADDR_W-1:0]     rd_addr;
    wire [DW-1:0]         rd_data;
    wire [N-1:0]          act_bits;

    activation_buffer #(
        .N(N), .DW(DW), .BW(BW), .ADDR_W(ADDR_W)
    ) dut (
        .clk(clk), .rst(rst), .lock(lock),
        .ld_en(ld_en), .ld_addr(ld_addr), .ld_data(ld_data),
        .bit_sel(bit_sel), .rd_addr(rd_addr), .rd_data(rd_data),
        .act_bits(act_bits)
    );

    //------------------------------------------------------- reference model
    reg [DW-1:0] model [0:N-1];

    reg [31:0] errors;
    reg [31:0] checks;
    reg [31:0] i;
    reg [31:0] b;
    reg [31:0] seed;

    initial begin
        errors = 32'd0;
        checks = 32'd0;
        seed   = 32'h0BAD_F00D;
    end

    initial clk = 1'b0;
    always #5 clk = ~clk;

    //---------------------------------------------------------------- helpers
    task load_one;
        input [ADDR_W-1:0] addr;
        input [DW-1:0]     data;
        begin
            @(negedge clk);
            ld_en   = 1'b1;
            ld_addr = addr;
            ld_data = data;
            @(negedge clk);
            ld_en   = 1'b0;
        end
    endtask

    task clear_mem;
        begin
            @(negedge clk);
            rst = 1'b1;
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task check_byte;
        input [ADDR_W-1:0] addr;
        begin
            rd_addr = addr;
            #1;
            checks = checks + 32'd1;
            if (rd_data !== model[addr]) begin
                errors = errors + 32'd1;
                $display("  FAIL readback x[%0d] exp=%h got=%h", addr,
                         model[addr], rd_data);
            end
        end
    endtask

    //  Compares all N broadcast bits against the model for bit position b.
    task check_plane;
        input [31:0] bitpos;
        reg [31:0] k;
        begin
            bit_sel = bitpos[BW-1:0];
            #1;
            for (k = 0; k < N; k = k + 32'd1) begin
                checks = checks + 32'd1;
                if (act_bits[k] !== model[k][bitpos[BW-1:0]]) begin
                    errors = errors + 32'd1;
                    $display("  FAIL plane b=%0d i=%0d exp=%b got=%b",
                             bitpos, k, model[k][bitpos[BW-1:0]], act_bits[k]);
                end
            end
        end
    endtask

    //  Loads the whole buffer from the model.
    task load_all;
        reg [31:0] n;
        begin
            for (n = 0; n < N; n = n + 32'd1)
                load_one(n[ADDR_W-1:0], model[n]);
        end
    endtask

    //------------------------------------------------------------------- test
    initial begin
        rst = 1'b0; lock = 1'b0; ld_en = 1'b0;
        ld_addr = {ADDR_W{1'b0}};
        ld_data = {DW{1'b0}};
        bit_sel = {BW{1'b0}};
        rd_addr = {ADDR_W{1'b0}};

        $display("== tb_activation_buffer ==");

        //--- T1: clear ---------------------------------------------------
        $display("[T1] bulk clear");
        clear_mem;
        for (i = 0; i < N; i = i + 32'd1) model[i] = 8'h00;
        for (i = 0; i < N; i = i + 32'd1) check_byte(i[ADDR_W-1:0]);
        for (b = 0; b < DW; b = b + 32'd1) check_plane(b);

        //--- T2: full-range pattern, all bit positions --------------------
        $display("[T2] load 64 values, verify readback and all 8 planes");
        for (i = 0; i < N; i = i + 32'd1)
            model[i] = ((i*29 + 17) % 256);
        load_all;
        for (i = 0; i < N; i = i + 32'd1) check_byte(i[ADDR_W-1:0]);
        for (b = 0; b < DW; b = b + 32'd1) check_plane(b);

        //--- T3: signed extremes -----------------------------------------
        $display("[T3] signed extremes 0x80 / 0x7F / 0x00");
        for (i = 0; i < N; i = i + 32'd1) begin
            if (i % 3 == 0)      model[i] = 8'h80;   // -128
            else if (i % 3 == 1) model[i] = 8'h7F;   // +127
            else                 model[i] = 8'h00;   //    0
        end
        load_all;
        for (i = 0; i < N; i = i + 32'd1) check_byte(i[ADDR_W-1:0]);
        for (b = 0; b < DW; b = b + 32'd1) check_plane(b);

        //--- T4: load protection under lock -------------------------------
        $display("[T4] load protection while locked");
        @(negedge clk);
        lock = 1'b1;
        load_one(6'd5, 8'hAA);          // must be ignored
        check_byte(6'd5);
        @(negedge clk);
        lock = 1'b0;
        check_byte(6'd5);

        //--- T5: load accepted after lock release -------------------------
        $display("[T5] load accepted after lock release");
        model[6'd5] = 8'hAA;
        load_one(6'd5, 8'hAA);
        check_byte(6'd5);
        for (b = 0; b < DW; b = b + 32'd1) check_plane(b);

        //--- T6: randomised vectors and bit selections --------------------
        $display("[T6] 500 random vectors, random bit_sel");
        for (i = 0; i < 500; i = i + 32'd1) begin
            for (b = 0; b < N; b = b + 32'd1)
                model[b] = $unsigned($random(seed)) % 256;
            load_all;
            check_byte($unsigned($random(seed)) % N);
            check_plane($unsigned($random(seed)) % DW);
        end

        //--- summary ------------------------------------------------------
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
        #5_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
