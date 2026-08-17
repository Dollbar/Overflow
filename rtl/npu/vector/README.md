# Vector RTL

Owns masked elementwise arithmetic, conversions, reductions, comparisons, and special-function pipelines
used by attention, normalization, routing, and tensor epilogues. The P0 proposal provisions a 2048-bit
datapath per tile and 16 special-function lanes, but these remain `PROPOSED`.

NPU-VEC-001 and NPU-VEC-002 are `HOLD` until the model/compiler operator manifest provides dtype, accuracy,
rounding, reduction-order, and throughput demand. Acceptance is per-operator bit-exact `RTL_SIM`; it does
not constitute a full-model result.
