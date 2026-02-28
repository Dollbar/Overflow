# Digital External-Interface Specifications

Contains revision-controlled digital contracts at the RTL boundary: memory transactions, host command queues,
interrupts, clocks and resets, KDLink encoded-block streams, and behavioral-model controls. Implementations
and tests must not depend on behavior absent from these contracts.

## Current Contracts

- [`npu_gemm_vector_core.md`](npu_gemm_vector_core.md) defines the current MX-only post-transfer
  descriptor, local tensor-buffer, vector-operand, result-route, feedback, and SRAM replacement boundary
  for the GEMM/vector core.
- [`npu_pod_boundary_v0.1.md`](npu_pod_boundary_v0.1.md) defines the controlled single-pod admission
  boundary, inherited compute/SRAM contracts, and explicit holds for command, DMA, completion, NoC, and
  clock/reset fields.
- [`hbm_transaction.md`](hbm_transaction.md) defines the vendor-neutral logical HBM transaction and
  backpressure boundary used by the portable system model.
- [`kd28_sram_fifo_v0.1.md`](kd28_sram_fifo_v0.1.md) defines the portable KD28 SRAM mapping cells,
  collision semantics, synthetic timing boundary, and parameterized FIFO wrapper contract.

## Historical Contracts

The earlier plain-FP8 ABI remains available from the v0.1 release history and its isolated worktree. It is
not compatible with the current MX descriptors or tensor storage.
