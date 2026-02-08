# Vector RTL

Owns masked elementwise arithmetic, conversions, reductions, comparisons, and special-function pipelines
used by attention, normalization, routing, and tensor epilogues. The P0 proposal provisions a 2048-bit
datapath per tile and 16 special-function lanes, but these remain `PROPOSED`.

The checked-in core implements sixteen independent 16-lane channels with tagged mixed-latency completion.
Its MX boundary supports MXFP4 E2M1 and MXFP8 E4M3FN with one E8M0 scale per 32 elements. Per-operator
bit-exact `RTL_SIM` does not constitute a full-model result.
