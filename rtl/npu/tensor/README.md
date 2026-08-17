# Tensor RTL

Owns the MXFP4-by-MXFP8 processing element, FP32 accumulation path, 256 x 256 transport array, tensor tile
wrapper, operand-scale delivery, drain path, and utilization counters.

ADR-0001 fixes the logical geometry at 256 x 256 and declares a 1 GHz analytical tensor clock. One array
therefore contains 65,536 MAC lanes and has an analytical peak of 131.072 TOPS-equivalent. Sixteen arrays
produce 2.097152 PFLOPS-equivalent. These values are not `RTL_SIM` or implementation-frequency evidence.

NPU-TNS-002 structural transport may begin. NPU-TNS-001 arithmetic remains `HOLD` until MXFP4 block scale,
rounding, saturation, NaN/Inf, denormal, and exception semantics are authoritative. Acceptance includes
bit-exact PE vectors, array fill/drain boundaries, continuous initiation interval, stalls, reset, and counters.
