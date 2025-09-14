# Version and Release Management

## 1. Versioning

Repository releases use semantic versioning:

- MAJOR: breaks model artifacts, IR, ISA, ABI, KDLink protocol, or RTL external interfaces.
- MINOR: adds backward-compatible operators, instructions, protocols, or simulator capabilities.
- PATCH: fixes behavior or documentation without changing a versioned interface.

## 2. v0.1 Status

`v0.1.0` is an architecture and repository baseline, not a complete inference implementation. Before
tagging, generate a release checklist whose items are `PASS`, `HOLD`, or `NOT_APPLICABLE`.

## 3. Release Evidence

Every release bundle includes:

- Source tag and complete dependency manifests.
- Tool versions, build commands, configuration, and checksums.
- Requirement traceability report.
- Verification summary, failures, waivers, and coverage state.
- Performance results with evidence levels and raw counters.
- Software, simulator, RTL, documentation, and model-license inventory.
- Interface compatibility matrix and known issues.

## 4. Performance Releases

Performance tables identify tensor or token shape, batch, context, logical clocks, dtype, node topology,
recovery configuration, timing boundary, and evidence level. A utilization percentage without numerator,
denominator, and a reproducible raw result is not acceptable.
