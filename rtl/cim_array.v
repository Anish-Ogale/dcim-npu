//=============================================================================
//  cim_array.v -- 64 x 64 digital CIM compute fabric
//=============================================================================
//  Verilog-2001, synthesizable, no vendor primitives.
//  ANSI-style ports, no functions, no integer types, no default_nettype,
//  no indexed part-selects (no +: or -:).
//
//  Function
//  --------
//  For one activation bit plane, produce all 64 column partial sums:
//
//      p_sum[j] = SUM(i = 0 .. 63) act_bits[i] ? W[i][j] : 0
//
//  This is P[b][j] from the specification, with b implied by act_bits.
//  The array is purely combinational: it holds no state of its own.
//
//  Why this is compute-in-memory and not a MAC array
//  -------------------------------------------------
//  The weight for cell (i,j) is a dedicated register that is wired straight
//  into this fabric and never addressed, moved or reloaded during a dot
//  product. There is no weight read port, no address generation and no
//  weight bus traffic while computing. The only signals crossing into the
//  array per cycle are 64 activation bits.
//
//  Multiplication is eliminated: act_bits[i] is 0 or 1, so each "product"
//  is a select between W[i][j] and 0. One AND gate per weight, 4096 total.
//  The only real arithmetic is the reduction, which is one adder tree per
//  column.
//
//  Structure
//  ---------
//  Per column j:
//      row gates  : 64 x AND        (act_bits[i] ? W[i][j] : 0)
//      adder tree : 64 -> 1, 14-bit output
//
//  64 columns run concurrently, so one activation plane produces 64 partial
//  sums in one cycle. Two's-complement weighting (2^b, and -2^7 for the sign
//  bit) is NOT done here; that belongs to the accumulator bank.
//
//  Widths
//  ------
//      PW = DW + LW = 8 + 6 = 14 bits per partial sum.
//      Exact range [-8192, +8128]; see adder_tree.v for the derivation.
//
//  Cost
//  ----
//      4096 AND gates + 64 adder trees (4032 adders).
//      This is the dominant logic block of the whole design.
//
//  Timing
//  ------
//  Combinational path per cycle: act_bits -> row gate -> 6 adder levels ->
//  p_sum. Pipelining this path is a Phase 3 experiment; the module boundary
//  is designed so a register stage can be inserted without touching the
//  accumulator or the memory.
//=============================================================================
`timescale 1ns/1ps

module cim_array #(
    parameter ROWS = 64,
    parameter COLS = 64,
    parameter DW   = 8,
    parameter LW   = 6,
    parameter PW   = DW + LW
)(
    input  wire [ROWS*COLS*DW-1:0] w_flat,
    input  wire [ROWS-1:0]         act_bits,
    output wire [COLS*PW-1:0]      p_sum
);

    genvar gi;
    genvar gj;

    generate

        //----------------------------------------------------- one column
        for (gj = 0; gj < COLS; gj = gj + 1) begin : g_col

            //  64 gated weights for this column, packed little-end first:
            //  slot i holds  W[i][j]  if act_bits[i] else 0.
            wire [ROWS*DW-1:0] gated;

            for (gi = 0; gi < ROWS; gi = gi + 1) begin : g_row

                wire [DW-1:0] wval;

                //  W[i][j] lives at bit offset (i*COLS + j)*DW in w_flat.
                //  Bounds are elaboration-time constants (genvars).
                assign wval = w_flat[(gi*COLS + gj)*DW + DW - 1
                                     : (gi*COLS + gj)*DW];

                //  The multiply: select the weight or zero.
                assign gated[gi*DW + DW - 1 : gi*DW] =
                            act_bits[gi] ? wval : {DW{1'b0}};

            end

            //  Reduce the 64 selected weights to one signed partial sum.
            adder_tree #(
                .N(ROWS), .W(DW), .LW(LW)
            ) u_tree (
                .din  (gated),
                .dout (p_sum[gj*PW + PW - 1 : gj*PW])
            );

        end

    endgenerate

endmodule
