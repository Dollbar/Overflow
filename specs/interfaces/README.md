# Digital External-Interface Specifications

Contains revision-controlled digital contracts at the RTL boundary: memory transactions, host command queues,
interrupts, clocks and resets, KDLink encoded-block streams, and behavioral-model controls. Implementations
and tests must not depend on behavior absent from these contracts.

## Current Contracts

- [`npu_gemm_vector_core.md`](npu_gemm_vector_core.md) defines the current MX-only post-transfer
  descriptor, local tensor-buffer, vector-operand, result-route, feedback, and SRAM replacement boundary
  for the GEMM/vector core.
- [`npu_independent_vector.md`](npu_independent_vector.md) defines descriptor version 3, Activation Buffer
  layout reuse, shared-backend arbitration, and completion semantics for cluster-local Vector tasks.
- [`npu_pod_boundary_v0.1.md`](npu_pod_boundary_v0.1.md) defines the controlled single-pod admission
  boundary, inherited compute/SRAM contracts, verified internal command/DMA/completion paths, and explicit
  holds for their externally owned ISA/ABI, NoC-router, protection, and clock-domain portions.
- [`hbm_transaction.md`](hbm_transaction.md) defines the vendor-neutral logical HBM transaction and
  backpressure boundary used by the portable system model.
- [`npu_hbm_rtl.md`](npu_hbm_rtl.md) freezes the finite five-lane per-pod NPU HBM beat interface, its
  NPU-local DMA arbitration contract, the 4,096-identity tag-lifetime tracker behavior, and delivered-beat
  status telemetry plus lossless local quiesce.
- [`npu_dma_data_path_v0.1.md`](npu_dma_data_path_v0.1.md) defines the admitted local-tag allocator and
  integrated beat boundary, and separates the pod-local HBM/SRAM path from the held cross-pod NoC mover
  path.
- [`npu_dma_command_v0.1.md`](npu_dma_command_v0.1.md) freezes the already-decoded and translated local DMA
  command, 1D/2D/3D address generation, HBM-to-SRAM movement, and internal completion contract.
- [`npu_pod_shared_sram_v0.1.md`](npu_pod_shared_sram_v0.1.md) defines the 16 MiB, eight-bank, sixteen-client
  pod-local DMA scratchpad and its fixed KD28 SDP macro mapping.
- [`npu_pod_local_transfer_v0.1.md`](npu_pod_local_transfer_v0.1.md) defines the compatibility path that
  reads paired data/scale beats from Pod-shared SRAM and writes one to eight banks of a compute cluster.
- [`npu_compute_pod_v0.1.md`](npu_compute_pod_v0.1.md) defines the complete single-clock two-cluster Pod,
  its task/completion path, DMA/loader shared-SRAM integration, result streams, and quiesce boundary.
- [`npu_pod_noc_attachment_v0.1.md`](npu_pod_noc_attachment_v0.1.md) defines the synchronous one-control-
  lane and two-data-lane ready-valid attachment handed to the external NoC router team without exposing
  router VC, credit, routing, or CDC implementation.
- [`npu_decoded_command_v0.1.md`](npu_decoded_command_v0.1.md) defines the NPU-internal decoded
  Task/local/DMA envelope, validation errors, and unified completion stream without defining KD-ISA.
- [`npu_2x4_pod_array_v0.1.md`](npu_2x4_pod_array_v0.1.md) defines eight managed Pods, fixed HBM affinity,
  per-Pod clocks, and the array-level handoff to the externally owned NoC router.
- [`kd28_sram_fifo_v0.1.md`](kd28_sram_fifo_v0.1.md) defines the portable KD28 SRAM mapping cells,
  collision semantics, synthetic timing boundary, and parameterized FIFO wrapper contract.

## Historical Contracts

The earlier plain-FP8 ABI remains available from the v0.1 release history and its isolated worktree. It is
not compatible with the current MX descriptors or tensor storage.
