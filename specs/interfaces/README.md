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
- [`npu_pod_boundary.md`](npu_pod_boundary.md) defines the controlled single-pod admission
  boundary, inherited compute/SRAM contracts, verified internal command/DMA/completion paths, and explicit
  holds for their externally owned ISA/ABI, NoC-router, protection, and clock-domain portions.
- [`hbm_transaction.md`](hbm_transaction.md) defines the vendor-neutral logical HBM transaction and
  backpressure boundary used by the portable system model.
- [`npu_hbm_rtl.md`](npu_hbm_rtl.md) freezes the finite five-lane per-pod NPU HBM beat interface, its
  NPU-local DMA arbitration contract, the 4,096-identity tag-lifetime tracker behavior, and delivered-beat
  status telemetry plus lossless local quiesce.
- [`npu_dma_data_path.md`](npu_dma_data_path.md) defines the admitted local-tag allocator and
  integrated beat boundary, and separates the pod-local HBM/SRAM path from the held cross-pod NoC mover
  path.
- [`npu_dma_command.md`](npu_dma_command.md) freezes the already-decoded and translated local DMA
  command, 1D/2D/3D address generation, HBM-to-SRAM movement, and internal completion contract.
- [`npu_pod_shared_sram.md`](npu_pod_shared_sram.md) defines the 16 MiB, eight-bank, sixteen-client
  pod-local DMA scratchpad and its fixed KD28 SDP macro mapping.
- [`npu_pod_local_transfer.md`](npu_pod_local_transfer.md) defines the compatibility path that
  reads paired data/scale beats from Pod-shared SRAM and writes one to eight banks of a compute cluster.
- [`npu_compute_pod.md`](npu_compute_pod.md) defines the complete single-clock two-cluster Pod,
  its task/completion path, DMA/loader shared-SRAM integration, result streams, and quiesce boundary.
- [`npu_pod_noc_attachment.md`](npu_pod_noc_attachment.md) defines the synchronous one-control-
  lane and two-data-lane ready-valid attachment handed to the external NoC router team without exposing
  router VC, credit, routing, or CDC implementation.
- [`npu_decoded_command.md`](npu_decoded_command.md) defines the NPU-internal decoded
  Task/local/DMA envelope, validation errors, and unified completion stream without defining KD-ISA.
- [`npu_2x4_pod_array.md`](npu_2x4_pod_array.md) defines eight managed Pods, fixed HBM affinity,
  per-Pod clocks, and the array-level handoff to the externally owned NoC router.
- [`npu_2x4_pod_noc_system.md`](npu_2x4_pod_noc_system.md) integrates the fixed Pod array with the
  multi-clock 2x4 NoC and freezes reset, quiesce, status, and opaque packet-client boundaries.
- [`npu_noc_router.md`](npu_noc_router.md) defines the deterministic 2 by 4 Router and Mesh port geometry,
  internal virtual-channel credits, buffering, arbitration, ordering, quiesce, telemetry, and verification
  obligations without changing the Pod flit format.
- [`npu_noc_cdc.md`](npu_noc_cdc.md) defines the Gray-pointer FIFO boundary between Pod and NoC clocks,
  including padding, depths, reset participation, drain behavior, and CDC evidence.
- [`kd28_sram_fifo.md`](kd28_sram_fifo.md) defines the portable KD28 SRAM mapping cells,
  collision semantics, synthetic timing boundary, and parameterized FIFO wrapper contract.

## Historical Contracts

The earlier plain-FP8 ABI remains available from the v0.1 release history and its isolated worktree. It is
not compatible with the current MX descriptors or tensor storage.
