//=============================================================================
//  adder_tree.v -- balanced reduction tree for one output column
//=============================================================================
//  Verilog-2001, synthesizable, no vendor primitives.
//  ANSI-style ports, no functions, no integer types, no default_nettype,
//  no indexed part-selects (no +: or -:).
//
//  Function
//  --------
//      dout = SUM(i = 0 .. N-1) din[i]
//
//  din carries N signed two's-complement values of W bits, packed little-end
//  first: din[i] occupies din[i*W + W-1 : i*W].
//  dout is the exact sum in two's complement, W+LW bits wide.
//
//  Why a tree
//  ----------
//  A linear chain of N-1 adders has a carry path proportional to N. A
//  balanced tree has depth log2(N) and depth-proportional delay, which is
//  what makes 64 inputs summable in one clock at 100+ MHz.
//
//      level 0 : 64 values, W   bits
//      level 1 : 32 values, W+1 bits
//      level 2 : 16 values, W+2 bits
//      level 3 :  8 values, W+3 bits
//      level 4 :  4 values, W+4 bits
//      level 5 :  2 values, W+5 bits
//      level 6 :  1 value,  W+6 bits
//
//  Each level widens by exactly one bit, because the sum of two k-bit signed
//  values is representable in k+1 bits. Widening up front instead of at the
//  end would waste area on every adder in the tree.
//
//  Width arithmetic in Verilog
//  ---------------------------
//  The result width of '+' is max(operand widths), NOT width+1. Each level
//  therefore sign-extends both operands explicitly by one bit before adding.
//  This is the classic expression-sizing trap and is the reason the level
//  code looks repetitive.
//
//  Exactness
//  ---------
//  With W=8, N=64 and all products in [-128, 127], the sum lies in
//  [-8192, 8128], which fits W+6 = 14 bits with no truncation and no
//  headroom. The tree is exact; no guard bit is added.
//
//  Generality
//  ----------
//  The level structure is written out for N = 64 (LW = 6). Supporting a
//  different N means adding or removing levels; there is no recursive
//  generate in Verilog-2001. N must equal 2**LW.
//=============================================================================
`timescale 1ns/1ps

module adder_tree #(
    parameter N  = 64,
    parameter W  = 8,
    parameter LW = 6
)(
    input  wire [N*W-1:0]  din,
    output wire [W+LW-1:0] dout
);

    //------------------------------------------------------- level widths
    localparam W1 = W + 1;
    localparam W2 = W + 2;
    localparam W3 = W + 3;
    localparam W4 = W + 4;
    localparam W5 = W + 5;

    //------------------------------------------------------ level registers
    wire [W-1:0]  l0 [0:63];
    wire [W1-1:0] l1 [0:31];
    wire [W2-1:0] l2 [0:15];
    wire [W3-1:0] l3 [0:7];
    wire [W4-1:0] l4 [0:3];
    wire [W5-1:0] l5 [0:1];

    genvar i;
    generate

        //--------------------------------------------------------- level 0
        for (i = 0; i < 64; i = i + 1) begin : g_l0
            assign l0[i] = din[i*W + W - 1 : i*W];
        end

        //--------------------------------------------------------- level 1
        for (i = 0; i < 32; i = i + 1) begin : g_l1
            wire [W1-1:0] a;
            wire [W1-1:0] b;
            assign a    = {l0[2*i][W-1], l0[2*i]};
            assign b    = {l0[2*i+1][W-1], l0[2*i+1]};
            assign l1[i] = a + b;
        end

        //--------------------------------------------------------- level 2
        for (i = 0; i < 16; i = i + 1) begin : g_l2
            wire [W2-1:0] a;
            wire [W2-1:0] b;
            assign a    = {l1[2*i][W1-1], l1[2*i]};
            assign b    = {l1[2*i+1][W1-1], l1[2*i+1]};
            assign l2[i] = a + b;
        end

        //--------------------------------------------------------- level 3
        for (i = 0; i < 8; i = i + 1) begin : g_l3
            wire [W3-1:0] a;
            wire [W3-1:0] b;
            assign a    = {l2[2*i][W2-1], l2[2*i]};
            assign b    = {l2[2*i+1][W2-1], l2[2*i+1]};
            assign l3[i] = a + b;
        end

        //--------------------------------------------------------- level 4
        for (i = 0; i < 4; i = i + 1) begin : g_l4
            wire [W4-1:0] a;
            wire [W4-1:0] b;
            assign a    = {l3[2*i][W3-1], l3[2*i]};
            assign b    = {l3[2*i+1][W3-1], l3[2*i+1]};
            assign l4[i] = a + b;
        end

        //--------------------------------------------------------- level 5
        for (i = 0; i < 2; i = i + 1) begin : g_l5
            wire [W5-1:0] a;
            wire [W5-1:0] b;
            assign a    = {l4[2*i][W4-1], l4[2*i]};
            assign b    = {l4[2*i+1][W4-1], l4[2*i+1]};
            assign l5[i] = a + b;
        end

        //--------------------------------------------------------- level 6
        wire [W+LW-1:0] a6;
        wire [W+LW-1:0] b6;
        assign a6   = {l5[0][W5-1], l5[0]};
        assign b6   = {l5[1][W5-1], l5[1]};
        assign dout = a6 + b6;

    endgenerate

endmodule
