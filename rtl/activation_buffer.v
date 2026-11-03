//=============================================================================
//  activation_buffer.v -- broadcast activation store for the DCIM tile
//=============================================================================
//  Verilog-2001, synthesizable, no vendor primitives.
//  ANSI-style ports, no functions, no integer types, no default_nettype,
//  no indexed part-selects (no +: or -:).
//
//  Purpose
//  -------
//  Holds N = 64 signed 8-bit activations x[i], i = 0 .. 63, and presents one
//  horizontal bit-slice of them per cycle:
//
//      act_bits[i]  =  x[i][bit_sel]
//
//  This is the broadcast vector. The same 64 bits drive all 64 columns of
//  the compute array in parallel, which is what makes the array 64-wide.
//
//  Dataflow role
//  -------------
//      bit_sel = 0 .. 6 : partial-sum cycle  b, weight contribution 2^b * W
//      bit_sel = 7      : sign cycle,        weight contribution -128 * W
//
//  The buffer stores activations in their natural byte form. The bit-slice is
//  formed combinationally, so there is no transpose state and no per-plane
//  load bookkeeping.
//
//  Load
//  ----
//  One activation per cycle on ld_en/ld_addr/ld_data: 64 cycles per group.
//  Loading is blocked while lock is high, matching the weight array.
//
//  Notes
//  -----
//  * rst is a synchronous clear; it guarantees deterministic contents before
//    the first load and does not run during normal operation.
//  * rd_data is a debug / load-verify port and costs one N:1 byte multiplexer.
//  * Cost of the bit-slice: one DW:1 multiplexer per activation (64 total),
//    roughly 100 LUTs. Negligible against the array itself.
//=============================================================================
`timescale 1ns/1ps

module activation_buffer #(
    parameter N      = 64,
    parameter DW     = 8,
    parameter BW     = 3,
    parameter ADDR_W = 6
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              lock,
    input  wire              ld_en,
    input  wire [ADDR_W-1:0] ld_addr,
    input  wire [DW-1:0]     ld_data,
    input  wire [BW-1:0]     bit_sel,
    input  wire [ADDR_W-1:0] rd_addr,
    output wire [DW-1:0]     rd_data,
    output wire [N-1:0]      act_bits
);

    //---------------------------------------------------------------- storage
    reg [DW-1:0] xmem [0:N-1];

    always @(posedge clk) begin : act_write
        reg [31:0] idx;
        if (rst) begin
            for (idx = 0; idx < N; idx = idx + 1)
                xmem[idx] <= {DW{1'b0}};
        end else if (ld_en && !lock) begin
            xmem[ld_addr] <= ld_data;
        end
    end

    //------------------------------------------------------------- read paths
    assign rd_data = xmem[rd_addr];

    //  Bit-slice: one constant bit position per generated instance, so the
    //  only computed select is the single-bit index bit_sel.
    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_plane
            wire [DW-1:0] xword;
            assign xword      = xmem[gi];
            assign act_bits[gi] = xword[bit_sel];
        end
    endgenerate

endmodule
