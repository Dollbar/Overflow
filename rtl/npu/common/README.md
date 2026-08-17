# NPU Common RTL

Owns NPU-local parameter packages, internal types, counters, arbiters, and reusable control that are not
already provided by `rtl/common/`. NPU-COM-001 may encode the ADR-0001 tensor geometry and derived counts.
It must not freeze an external command, memory, KDLink, reset, or error field.

Deliverables: parameter/type package, elaboration-time consistency assertions, performance counters, lint,
and parameter-boundary unit tests. External-interface types remain `HOLD` until their `specs/` owners act.
