//=============================================================================
//  tb_weight_mem.v -- verification stage 1 (memory)
//=============================================================================
//  Verilog-2001. No functions, no integer types, no default_nettype.
//
//  Covers:
//    * bulk clear
//    * address correctness / row-major layout (all 512 words)
//    * readback port vs. stationary port agreement
//    * boundary elements W[0][0], W[0][63], W[63][0], W[63][63]
//    * full 8-bit signed range incl. 0x80 (-128) and 0x7F (+127)
//    * write protection while lock is asserted
//    * randomised single-word writes
//=============================================================================
`timescale 1ns/1ps

module tb_weight_mem;

    localparam ROWS      = 64;
    localparam COLS      = 64;
    localparam DW        = 8;
    localparam WR_DATA_W = 64;
    localparam WPR       = WR_DATA_W / DW;
    localparam WR_WORDS  = COLS / WPR;
    localparam ADDR_W    = 9;
    localparam TBITS     = ROWS * COLS * DW;

    reg                   clk;
    reg                   rst;
    reg                   lock;
    reg                   wr_en;
    reg  [ADDR_W-1:0]     wr_addr;
    reg  [WR_DATA_W-1:0]  wr_data;
    reg  [ADDR_W-1:0]     rd_addr;
    wire [WR_DATA_W-1:0]  rd_data;
    wire [TBITS-1:0]      w_flat;

    weight_mem #(
        .ROWS(ROWS), .COLS(COLS), .DW(DW),
        .WR_DATA_W(WR_DATA_W), .ADDR_W(ADDR_W)
    ) dut (
        .clk(clk), .rst(rst), .lock(lock),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_addr(rd_addr), .rd_data(rd_data), .w_flat(w_flat)
    );

    //------------------------------------------------------- reference model
    reg [DW-1:0] model [0:ROWS*COLS-1];

    reg [31:0] errors;
    reg [31:0] checks;
    reg [31:0] a;
    reg [31:0] i;
    reg [31:0] j;
    reg [31:0] seed;

    initial begin
        errors = 32'd0;
        checks = 32'd0;
        seed   = 32'h1234_5678;
    end

    //------------------------------------------------------------------ clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //---------------------------------------------------------------- helpers
    //  Build the expected 64-bit write word for a word address from the
    //  byte-level reference model.
    task build_word;
        input  [ADDR_W-1:0]    addr;
        output [WR_DATA_W-1:0] word;
        reg [31:0] r;
        reg [31:0] g;
        reg [31:0] k;
        begin
            r = addr / WR_WORDS;
            g = addr % WR_WORDS;
            word = {WR_DATA_W{1'b0}};
            for (k = 0; k < WPR; k = k + 1)
                word = word |
                       ({{(WR_DATA_W-DW){1'b0}}, model[r*COLS + g*WPR + k]}
                        << (k*DW));
        end
    endtask

    task wr_word;
        input [ADDR_W-1:0]    addr;
        input [WR_DATA_W-1:0] data;
        begin
            @(negedge clk);
            wr_en   = 1'b1;
            wr_addr = addr;
            wr_data = data;
            @(negedge clk);
            wr_en   = 1'b0;
        end
    endtask

    //  Loads one word whose contents are taken from the reference model.
    task wr_word_from_model;
        input [ADDR_W-1:0] addr;
        reg [WR_DATA_W-1:0] word;
        begin
            build_word(addr, word);
            wr_word(addr, word);
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

    task check_word;
        input [ADDR_W-1:0] addr;
        reg [WR_DATA_W-1:0] exp_word;
        reg [WR_DATA_W-1:0] flat_word;
        begin
            build_word(addr, exp_word);
            rd_addr = addr;
            #1;
            checks = checks + 32'd1;
            if (rd_data !== exp_word) begin
                errors = errors + 32'd1;
                $display("  FAIL readback addr=%0d exp=%h got=%h", addr,
                         exp_word, rd_data);
            end
            checks = checks + 32'd1;
            //  Shift right and let the assignment truncate to 64 bits;
            //  avoids any computed part-select on w_flat.
            flat_word = w_flat >> (addr*WR_DATA_W);
            if (flat_word !== exp_word) begin
                errors = errors + 32'd1;
                $display("  FAIL stationary addr=%0d exp=%h got=%h", addr,
                         exp_word, flat_word);
            end
        end
    endtask

    task check_elem;
        input [31:0] ri;
        input [31:0] cj;
        reg [DW-1:0] got;
        begin
            got = w_flat >> ((ri*COLS + cj)*DW);
            checks = checks + 32'd1;
            if (got !== model[ri*COLS + cj]) begin
                errors = errors + 32'd1;
                $display("  FAIL W[%0d][%0d] exp=%h got=%h", ri, cj,
                         model[ri*COLS + cj], got);
            end
        end
    endtask

    //------------------------------------------------------------------- test
    initial begin
        rst = 1'b0; lock = 1'b0; wr_en = 1'b0;
        wr_addr = {ADDR_W{1'b0}};
        wr_data = {WR_DATA_W{1'b0}};
        rd_addr = {ADDR_W{1'b0}};

        $display("== tb_weight_mem ==");

        //--- T1: bulk clear ---------------------------------------------
        $display("[T1] bulk clear");
        clear_mem;
        for (a = 0; a < ROWS*COLS; a = a + 32'd1) model[a] = 8'h00;
        for (a = 0; a < ROWS*WR_WORDS; a = a + 32'd1) check_word(a);

        //--- T2: full-range pattern, every word -------------------------
        //  (i*37 + j*23) mod 256 sweeps all 256 byte values including
        //  0x80 (-128) and 0x7F (+127).
        $display("[T2] program + readback, all 512 words");
        for (i = 0; i < ROWS; i = i + 32'd1)
            for (j = 0; j < COLS; j = j + 32'd1)
                model[i*COLS + j] = ((i*37 + j*23) % 256);

        for (a = 0; a < ROWS*WR_WORDS; a = a + 32'd1)
            wr_word_from_model(a[ADDR_W-1:0]);

        for (a = 0; a < ROWS*WR_WORDS; a = a + 32'd1) check_word(a);

        //--- T3: boundary elements --------------------------------------
        $display("[T3] boundary elements");
        check_elem(32'd0,  32'd0);
        check_elem(32'd0,  COLS-1);
        check_elem(ROWS-1, 32'd0);
        check_elem(ROWS-1, COLS-1);

        //--- T4: signed extremes ----------------------------------------
        $display("[T4] signed extremes: -128 and +127");
        for (i = 0; i < ROWS; i = i + 32'd1)
            for (j = 0; j < COLS; j = j + 32'd1)
                model[i*COLS + j] = j[0] ? 8'h80 : 8'h7F;
        for (a = 0; a < ROWS*WR_WORDS; a = a + 32'd1)
            wr_word_from_model(a[ADDR_W-1:0]);
        for (a = 0; a < ROWS*WR_WORDS; a = a + 32'd1) check_word(a);

        //--- T5: write protection under lock -----------------------------
        $display("[T5] write protection while locked");
        @(negedge clk);
        lock = 1'b1;
        wr_word(9'd100, {WR_DATA_W{1'b1}});   // must be ignored
        check_word(9'd100);                    // model unchanged -> must match
        @(negedge clk);
        lock = 1'b0;
        check_word(9'd100);

        //--- T6: write accepted after lock release ----------------------
        $display("[T6] unlocked write after lock release");
        model[9'd100*WPR] = 8'h5A;
        wr_word_from_model(9'd100);
        check_word(9'd100);

        //--- T7: random single-word writes ------------------------------
        $display("[T7] 2000 random word writes");
        for (i = 0; i < 2000; i = i + 32'd1) begin
            a = $unsigned($random(seed)) % (ROWS*WR_WORDS);
            for (j = 0; j < WPR; j = j + 32'd1)
                model[(a/WR_WORDS)*COLS + (a%WR_WORDS)*WPR + j] =
                    $unsigned($random(seed)) % 256;
            wr_word_from_model(a[ADDR_W-1:0]);
            check_word(a[ADDR_W-1:0]);
        end

        //--- summary -----------------------------------------------------
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
        #500_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
