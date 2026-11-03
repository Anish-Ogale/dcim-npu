//=============================================================================
//  weight_mem.v -- stationary weight storage for the DCIM compute tile
//=============================================================================
//  Verilog-2001, synthesizable, no vendor primitives.
//  ANSI-style ports, no functions, no integer types, no default_nettype,
//  no indexed part-selects (no +: or -:).
//
//  Logical geometry
//  ----------------
//      ROWS  input features        i = 0 .. ROWS-1
//      COLS  output neurons        j = 0 .. COLS-1
//      DW    weight width (8, signed two's complement)
//
//      W[i][j]  where i is the outer (row) index  ->  row-major layout
//
//  Storage organization
//  --------------------
//      The array is held as N_WORDS words of WR_DATA_W bits, one word being
//      a group of WR_DATA_W/DW adjacent columns of a single row.
//
//          word index  w  =  i*(COLS*DW/WR_DATA_W) + g
//          wmem[w]        =  { W[i][8g+7], ... , W[i][8g+0] }
//
//      Nothing in the module slices a vector at a computed offset, so the
//      storage is a plain array of words and both ports are simple indexing.
//
//  Flat bit position of an element
//  -------------------------------
//      With the defaults, word w occupies w_flat[w*64 + 63 : w*64], and
//
//          W[i][j]  ==  w_flat[i*512 + j*8 + 7 : i*512 + j*8]
//
//  Compute-side port
//  -----------------
//      w_flat exposes every weight combinationally. The compute array
//      therefore never generates a weight address during a dot product:
//      this is the hardware meaning of "weight stationary" in this design.
//
//  Notes
//  -----
//  * rst is a synchronous bulk clear of the weight array. It is used for
//    bring-up and to guarantee deterministic contents before the first
//    load; it does not run during normal operation.
//  * lock freezes the array. The controller asserts it whenever the
//    datapath is computing, so a stray load cannot corrupt an in-flight
//    dot product (verification stage 1, "write protection").
//  * Geometry must satisfy: COLS*DW is an exact multiple of WR_DATA_W,
//    and ROWS*(COLS*DW/WR_DATA_W) must be exactly 2**ADDR_W.
//    ADDR_W is therefore stated explicitly and must be updated by hand
//    if ROWS, COLS or WR_DATA_W change.
//  * rd_data is a debug/load-verify port and costs a wide multiplexer.
//    It can be dropped for a release build without touching anything else.
//=============================================================================
`timescale 1ns/1ps

module weight_mem #(
    parameter ROWS      = 64,
    parameter COLS      = 64,
    parameter DW        = 8,
    parameter WR_DATA_W = 64,
    parameter ADDR_W    = 9
)(
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    lock,
    input  wire                    wr_en,
    input  wire [ADDR_W-1:0]       wr_addr,
    input  wire [WR_DATA_W-1:0]    wr_data,
    input  wire [ADDR_W-1:0]       rd_addr,
    output wire [WR_DATA_W-1:0]    rd_data,
    output wire [ROWS*COLS*DW-1:0] w_flat
);

    //-------------------------------------------------------- derived values
    localparam WPR      = WR_DATA_W / DW;              // weights per word
    localparam WR_WORDS = (COLS + WPR - 1) / WPR;      // words per row
    localparam N_WORDS  = ROWS * WR_WORDS;             // 512 for defaults

    //---------------------------------------------------------------- storage
    //  One 64-bit register per write word: 512 x 64 = 32768 flip-flops.
    reg [WR_DATA_W-1:0] wmem [0:N_WORDS-1];

    always @(posedge clk) begin : mem_write
        reg [31:0] idx;
        if (rst) begin
            for (idx = 0; idx < N_WORDS; idx = idx + 1)
                wmem[idx] <= {WR_DATA_W{1'b0}};
        end else if (wr_en && !lock) begin
            wmem[wr_addr] <= wr_data;
        end
    end

    //------------------------------------------------------------- read paths
    //  Readback port, for verifying what the loader wrote.
    assign rd_data = wmem[rd_addr];

    //  Stationary port: every word is wired straight out, no clock and no
    //  address. The generate loop gives each connection constant bounds, so
    //  no part-select offset is ever computed.
    genvar gi;
    generate
        for (gi = 0; gi < N_WORDS; gi = gi + 1) begin : g_flat
            assign w_flat[gi*WR_DATA_W + WR_DATA_W - 1 : gi*WR_DATA_W] = wmem[gi];
        end
    endgenerate

endmodule
