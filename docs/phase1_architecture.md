# Phase 1 — Architectural Foundation (locked decisions)

## 1. Target datapath

| Item | Decision |
|---|---|
| Dataflow | Weight stationary, activations broadcast |
| Tile | 64 rows (inputs) x 64 columns (output neurons) |
| Weight element | `W[i][j]`, signed 8-bit two's complement |
| Activation | `x[i]`, signed 8-bit two's complement |
| Bit-serial on | activation bits `x[i][b]`, b = 0..7 |
| Rows evaluated per bit-cycle | 64 (all) |
| Bit-cycles per 64-element dot product | 8 |
| Accumulator (tile) | signed 24-bit |
| Layer accumulator (cross-group) | signed 32-bit |

## 2. Arithmetic widths (worst-case, verified)

| Quantity | Bound | Bits needed | Implemented |
|---|---|---|---|
| Weight | -128 .. 127 | 8 | 8 |
| Activation | -128 .. 127 | 8 | 8 |
| Single product | -16384 .. 16256 | 15 | — |
| Partial sum P[b] = sum of 64 gated weights | -8192 .. 8128 | 14 | **15** (1 guard) |
| Tile dot product (64 terms) | -1048576 .. 1040384 | 22 | **24** (spec) |
| Layer sum (784 terms, 13 groups) | -12845056 .. 12746752 | 25 | **32** |

24 bits is sufficient for one 64-element dot product but **not** for the full
784-input layer sum; the cross-group accumulation must be 32-bit.

## 3. Two's-complement bit-serial formulation

For activation `x` and weight `W`:

```
x*W = SUM_{b=0..6} 2^b * x[b] * W  -  128 * x[7] * W
```

Cycle b evaluates `P[b][j] = SUM_i x[i][b] * W[i][j]` for all 64 j in parallel
(each term is `W` or `0`, so multiplication is a gated select). Cycle 7
subtracts `P[7] << 7` instead of adding it.

## 4. Memory organization

Weights are register-resident and combinationally visible to the array, so no
weight address is generated during compute. Weight load is a single write port.

```
flat bit offset of W[i][j]  =  i*512 + j*8
write word address          =  i*8 + g      (g = group of 8 adjacent columns)
```

512 words x 64 bits = 4 KB. The same 512x64 geometry maps directly onto an
SRAM/BRAM macro when the memory-resident variant is built, so the loader and
`ROWS_PER_CYCLE` consumer do not change.

## 5. Fixed-point convention (hardware and Python must match)

```
y[j] = sat8( (acc[j] + 2^(SH-1)) >>> SH )   // SH-bit arithmetic shift, round half up
a[j] = relu_q( y[j] )                        // max(0, y)
```

Bias is signed 24-bit, sign-extended into the 32-bit layer accumulator.
