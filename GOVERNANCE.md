# Project Governance

## Decision Authority

| Decision | Required approvers |
| --- | --- |
| Workload envelope, logical node count, or performance SLA | System Architecture Owner |
| Breaking model-schema or compiler-IR change | Model and Compiler owners |
| Breaking ISA or ABI change | Compiler, Runtime, Firmware, and RTL owners |
| KDLink protocol, PCS, routing, or collective change | Fabric and Verification owners |
| RTL external-interface change | RTL, Simulator, and Verification owners |
| Release status | Release Manager and all blocking owners |

## Architecture Decision Records

A change affecting two or more subsystems, adding a dependency, or changing a versioned external interface
requires an ADR. ADRs use `docs/adr/ADR-XXXX-title.md` and one of the states proposed, accepted,
superseded, or rejected.

## Release Discipline

Internal stages use gate identifiers and are not released as completed products. Public releases require
a machine-readable acceptance report. Any open blocking criterion keeps the release status at `HOLD`.
