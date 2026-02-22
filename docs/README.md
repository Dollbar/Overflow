# Documentation Center

This directory contains OwerFlow architecture, planning, management, and ADR documentation. Formal
interface definitions belong in `specs/`; implementation details belong in their subsystem directories.

- `architecture/`: model-to-RTL context, responsibility boundaries, and cross-layer data flow.
- `planning/`: release scope and technical risks.
- `management/`: repository, requirements, versions, and release management.
- `adr/`: architecture decisions requiring multi-owner approval.

Targets in these documents must match `config/system_baseline.yaml`. Resolve conflicts through an ADR
before implementation; subsystems may not silently select different baselines.

The [NPU Subsystem Architecture Proposal](architecture/npu_subsystem_proposal.md) derives an explicitly
`ANALYTICAL`, not-yet-frozen compute, SRAM, NoC, and DMA sizing point from the system baseline.
The [NPU System Closure Plan](architecture/npu_system_closure_plan.md) records the authority order,
current verified compute boundary, specification holds, and gated implementation sequence.
