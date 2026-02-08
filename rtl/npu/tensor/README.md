# Tensor RTL

Owns the MXFP4-by-MXFP8 processing element, FP32 accumulation path, 256 x 256 transport array, tensor tile
wrapper, operand-scale delivery, drain path, and utilization counters.

The production implementation keeps exact products in each PE, performs reduction in the Tile, and keeps
the signed long-K accumulator at the Tile result boundary. It contains no GEMM tile-level packet router and
no programmable block-matrix placement path.

ADR-0001 fixes the logical geometry at 256 x 256 and declares a 1 GHz analytical tensor clock. One array
therefore contains 65,536 MAC lanes and has an analytical peak of 131.072 TOPS-equivalent. Sixteen arrays
produce 2.097152 PFLOPS-equivalent. These values are not `RTL_SIM` or implementation-frequency evidence.

The MXFP4 E2M1/MXFP8 E4M3FN block-scale and RNE production semantics are defined by
`specs/interfaces/npu_gemm_vector_core.md`. Acceptance includes bit-exact PE vectors, array fill/drain
boundaries, continuous initiation interval, stalls, reset, and counters.
