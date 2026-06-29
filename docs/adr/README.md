# Architecture Decision Records

Name ADRs `ADR-XXXX-english-title.md`. Each ADR includes context, decision, alternatives, consequences,
state, owners, and date. Initial ADRs cover the 32-node logical topology, abstract memory capacity, KDLink
logical ports and PCS, compiler IR, and simulator timing model.

## Current NPU Decisions

- [`ADR-0001`](ADR-0001-npu-tensor-array-geometry.md) fixes the logical Tensor Array geometry and declared
  calculation clock.
- [`ADR-0002`](ADR-0002-npu-hbm-egress-lane-geometry.md) derives the five-lane per-pod NPU HBM egress
  geometry from the baselined partition bandwidth and beat size.
- [`ADR-0003`](ADR-0003-npu-local-dma-mover-contract.md) fixes the NPU-owned, already-translated local DMA
  command and HBM-to-SRAM completion boundary without defining KD-ISA or runtime ABI fields.
- [`ADR-0004`](ADR-0004-npu-pod-organization.md) fixes the eight-Pod 2 by 4 organization, two compute
  clusters per Pod, and one-to-one local HBM affinity while leaving NoC fields and production private-SRAM
  capacity open.
- [`ADR-0005`](ADR-0005-npu-pod-noc-attachment.md) freezes the router-independent Pod/NoC ready-valid
  attachment while leaving VC, credit, routing, CDC, and packet payload semantics to their owning teams.
- [`ADR-0006`](ADR-0006-npu-independent-vector-issue.md) enables cluster-local independent Vector issue by
  reusing the Activation and Vector operand buffers plus the existing Vector backend, without changing NoC.
- [`ADR-0007`](ADR-0007-npu-decoded-command-gateway.md) freezes the NPU-internal already-decoded
  Task/local/DMA envelope, validation rules, and unified completion gateway without defining KD-ISA.
- [`ADR-0008`](ADR-0008-npu-noc-router-mesh.md) fixes the deterministic 2 by 4 Router baseline, internal
  virtual-channel credit contract, bounded packets, CDC profile, and formal proof obligations while
  leaving cross-Pod payload semantics opaque.
