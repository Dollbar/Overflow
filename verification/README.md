# Verification

Contains cross-layer golden models, testbenches, assertions, formal properties, CDC/RDC, coverage, fault
injection, performance regression, and release audit. Tests map to IDs in `requirements/traceability.csv`.

Large waveforms and intermediate netlists are CI artifacts rather than Git sources.

## Environments

- [`npu/compute/`](npu/compute/) contains the reusable SystemVerilog package, VIP, behavioral
  boundary models, deterministic references, self-checking tests, and Make workflow for the GEMM/vector
  compute path.
- [`kd28/`](kd28/) contains the self-checking Verilator regression and generic black-box link check for
  reusable KD28 SRAM cells and parameterized FIFO wrappers.
