# Documentation Center

This directory contains OwerFlow architecture, planning, management, and ADR documentation. Formal
interface definitions belong in `specs/`; implementation details belong in their subsystem directories.

- `architecture/`: model-to-RTL context, responsibility boundaries, and cross-layer data flow.
- `planning/`: release scope and technical risks.
- `management/`: repository, requirements, versions, and release management.
- `adr/`: architecture decisions requiring multi-owner approval.

Targets in these documents must match `config/system_baseline.yaml`. Resolve conflicts through an ADR
before implementation; subsystems may not silently select different baselines.
