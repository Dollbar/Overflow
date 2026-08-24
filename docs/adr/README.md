# Architecture Decision Records

Name ADRs `ADR-XXXX-english-title.md`. Each ADR includes context, decision, alternatives, consequences,
state, owners, and date. Initial ADRs cover the 32-node logical topology, abstract memory capacity, KDLink
logical ports and PCS, compiler IR, and simulator timing model.

## Current NPU Decisions

- [`ADR-0001`](ADR-0001-npu-tensor-array-geometry.md) fixes the logical Tensor Array geometry and declared
  calculation clock.
- [`ADR-0002`](ADR-0002-npu-hbm-egress-lane-geometry.md) derives the five-lane per-pod NPU HBM egress
  geometry from the baselined partition bandwidth and beat size.
