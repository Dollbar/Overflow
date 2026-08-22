# Digital External-Interface Specifications

Contains revision-controlled digital contracts at the RTL boundary: memory transactions, host command queues,
interrupts, clocks and resets, KDLink encoded-block streams, and behavioral-model controls. Implementations
and tests must not depend on behavior absent from these contracts.

## Current Contracts

- [`npu_gemm_vector_core.md`](npu_gemm_vector_core.md) defines the post-transfer descriptor,
  local tensor-buffer, vector-operand, result-route, and SRAM replacement boundary for the GEMM/vector core.
- [`hbm_transaction.md`](hbm_transaction.md) defines the vendor-neutral logical HBM transaction and
  backpressure boundary used by the portable system model.
