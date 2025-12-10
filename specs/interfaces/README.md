# Digital External-Interface Specifications

Contains versioned digital contracts at the RTL boundary: memory transactions, host command queues,
interrupts, clocks and resets, KDLink encoded-block streams, and behavioral-model controls. Implementations
and tests must not depend on behavior absent from these contracts.

## Current Contracts

- [`npu_gemm_vector_core_v0.1.md`](npu_gemm_vector_core_v0.1.md) defines the post-transfer descriptor,
  local tensor-buffer, vector-operand, result-route, and SRAM replacement boundary for the GEMM/vector core.
