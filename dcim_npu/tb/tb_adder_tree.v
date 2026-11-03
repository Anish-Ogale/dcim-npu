//=============================================================================
//  tb_adder_tree.v -- verification stage 2 (arithmetic)
//=============================================================================
//  Verilog-2001. No functions, no integer types, no default_nettype,
//  no indexed part-selects.
//
//  Reference: a 64-bit accumulator that sign-extends every input, so the
//  expected result is computed independently of the tree's own widths.
//
//  Covers:
//    * all-zero inputs
//    * maximum positive sum   (64 x +127 = +8128)
//    * minimum negative sum   (64 x -128 = -8192)
//    * alternating extremes
//    * one outlier among extremes
//    * 2000 randomised vectors
//=============================================================================
`timescale 1ns/1ps

module tb_adder_tree;

    localparam N  = 64;
    localparam W  = 8;
    localparam LW = 6;
    localparam OW = W + LW;
    localparam DINW = N * W;

    reg  [DINW-1:0] din;
    wire [OW-1:0]   dout;

    adder_tree #(.N(N), .W(W), .LW(LW)) dut (
        .din(din), .dout(dout)
    );

    reg [63:0] acc;         // reference sum, 64-bit so it cannot overflow
    reg [31:0] errors;
    reg [31:0] checks;
    reg [31:0] seed;
    reg [31:0] t;

    initial begin
        errors = 32'd0;
        checks = 32'd0;
        seed   = 32'h5EED_1234;
    end

    //---------------------------------------------------------------- helpers
    //  Fill all N inputs with the same byte, building din by repeated
    //  append so no computed part-select is needed.
    task load_fill;
        input [7:0] v;
        reg [31:0] n;
        begin
            din = {DINW{1'b0}};
            acc = 64'd0;
            for (n = 0; n < N; n = n + 32'd1) begin
                din = {din[DINW-W-1:0], v};
                acc = acc + {{56{v[7]}}, v};
            end
        end
    endtask

    task load_random;
        reg [31:0] n;
        reg [7:0]  v;
        begin
            din = {DINW{1'b0}};
            acc = 64'd0;
            for (n = 0; n < N; n = n + 32'd1) begin
                v   = $unsigned($random(seed)) % 256;
                din = {din[DINW-W-1:0], v};
                acc = acc + {{56{v[7]}}, v};
            end
        end
    endtask

    task check;
        input [31:0] tag;
        begin
            #1;
            checks = checks + 32'd1;
            if (dout !== acc[OW-1:0]) begin
                errors = errors + 32'd1;
                $display("  FAIL case %0d  exp=%0d got=%0d",
                         tag, $signed(acc[OW-1:0]), $signed(dout));
            end
        end
    endtask

    //------------------------------------------------------------------- test
    initial begin
        din = {DINW{1'b0}};
        acc = 64'd0;

        $display("== tb_adder_tree ==");

        //--- T1: all zero -----------------------------------------------
        $display("[T1] all zero");
        load_fill(8'h00);
        check(32'd1);

        //--- T2: maximum positive sum -----------------------------------
        $display("[T2] all +127  (expected +8128)");
        load_fill(8'h7F);
        check(32'd2);
        $display("     sum = %0d", $signed(dout));

        //--- T3: minimum negative sum -----------------------------------
        $display("[T3] all -128  (expected -8192)");
        load_fill(8'h80);
        check(32'd3);
        $display("     sum = %0d", $signed(dout));

        //--- T4: alternating extremes -----------------------------------
        $display("[T4] alternating +127 / -128");
        din = {DINW{1'b0}};
        acc = 64'd0;
        for (t = 0; t < N; t = t + 32'd1) begin
            if (t % 2 == 0) begin
                din = {din[DINW-W-1:0], 8'h7F};
                acc = acc + 64'sd127;
            end else begin
                din = {din[DINW-W-1:0], 8'h80};
                acc = acc - 64'sd128;
            end
        end
        check(32'd4);

        //--- T5: single outlier among maxima -----------------------------
        $display("[T5] 63 x +127 and one -128");
        din = {DINW{1'b0}};
        acc = 64'd0;
        for (t = 0; t < N; t = t + 32'd1) begin
            if (t == 32'd17) begin
                din = {din[DINW-W-1:0], 8'h80};
                acc = acc - 64'sd128;
            end else begin
                din = {din[DINW-W-1:0], 8'h7F};
                acc = acc + 64'sd127;
            end
        end
        check(32'd5);

        //--- T6: single outlier among minima -----------------------------
        $display("[T6] 63 x -128 and one +127");
        din = {DINW{1'b0}};
        acc = 64'd0;
        for (t = 0; t < N; t = t + 32'd1) begin
            if (t == 32'd40) begin
                din = {din[DINW-W-1:0], 8'h7F};
                acc = acc + 64'sd127;
            end else begin
                din = {din[DINW-W-1:0], 8'h80};
                acc = acc - 64'sd128;
            end
        end
        check(32'd6);

        //--- T7: randomised ----------------------------------------------
        $display("[T7] 2000 random vectors");
        for (t = 0; t < 2000; t = t + 32'd1) begin
            load_random;
            check(t);
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
        #1_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
