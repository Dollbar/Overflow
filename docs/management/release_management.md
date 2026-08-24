# Version and Release Management

## 1. Versioning

Repository releases use semantic versioning:

- MAJOR: breaks model artifacts, IR, ISA, ABI, KDLink protocol, or RTL external interfaces.
- MINOR: adds backward-compatible operators, instructions, protocols, or simulator capabilities.
- PATCH: fixes behavior or documentation without changing a versioned interface.

## 2. v0.1 Status

`v0.1.0` is an architecture and repository baseline, not a complete inference implementation. Before
tagging, generate a release checklist whose items are `PASS`, `HOLD`, or `NOT_APPLICABLE`.

## 3. Interface-Version Isolation

The plain-FP8 v0.1 implementation and MX v0.2 implementation live on separate
branches and must be checked out as separate Git worktrees. Do not merge either
feature branch into the other to run comparisons. Generated files remain below
each worktree's own `build/` directories, so lint, simulation, synthesis, and
timing artifacts cannot overwrite the other version.

The v0.2 scheduler accepts descriptor version `2` only. This runtime boundary
complements source-tree isolation: a v0.1 binary descriptor cannot be silently
interpreted with the v0.2 packed layout.

```bash
git fetch origin main
git branch -f main origin/main
git worktree add ../Overflow-npu-fp8-v0.1 feat/npu-gemm-vector-core
git worktree add ../Overflow-npu-mxfp-v0.2 feat/npu-gemm-vector-mxfp-v0.2
git worktree list
```

## 4. Release Evidence

Every release bundle includes:

- Source tag and complete dependency manifests.
- Tool versions, build commands, configuration, and checksums.
- Requirement traceability report.
- Verification summary, failures, waivers, and coverage state.
- Performance results with evidence levels and raw counters.
- Software, simulator, RTL, documentation, and model-license inventory.
- Interface compatibility matrix and known issues.

## 5. Performance Releases

Performance tables identify tensor or token shape, batch, context, logical clocks, dtype, node topology,
recovery configuration, timing boundary, and evidence level. A utilization percentage without numerator,
denominator, and a reproducible raw result is not acceptable.
