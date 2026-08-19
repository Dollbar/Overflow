# Verification

Contains cross-layer golden models, testbenches, assertions, formal properties, CDC/RDC, coverage, fault
injection, performance regression, and release audit. Tests map to IDs in `requirements/traceability.csv`.

Large waveforms and intermediate netlists are CI artifacts rather than Git sources.

## Environments

- [`npu/gemm_vector/`](npu/gemm_vector/) contains the reusable SystemVerilog package, VIP, behavioral
  boundary models, deterministic references, self-checking tests, and Make workflow for the GEMM/vector
  compute path.
