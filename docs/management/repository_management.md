# Repository Management

## 1. Monorepo Policy

The v0.x program uses a monorepo so model, compiler, runtime, simulator, RTL, verification, and deployment
interfaces can be reviewed in one change. Splitting repositories requires an ADR showing a concrete
build-scale or access-control need.

## 2. Directory Ownership

- Every first-level directory has an English `README.md` defining responsibility, inputs, outputs, and exclusions.
- Cross-layer contracts are defined only in `specs/`; subsystems link to them rather than copying them.
- Tests belong in `verification/` or an explicit subsystem `tests/` directory.
- Local host paths, credentials, and developer settings use ignored `*.local.yaml` files.
- The repository lower boundary remains synthesizable RTL and behavioral external-interface models.

## 3. Branches and Merges

- `main` remains buildable and auditable.
- Branches use `feature/<issue>-<name>`, `fix/<issue>-<name>`, or `docs/<issue>-<name>`.
- Do not maintain permanent organization branches.
- Pull requests require an implementation owner and an affected-consumer owner.
- Model schema, IR, ISA, ABI, KDLink, and RTL interface changes require the corresponding architecture owner.

## 4. File Classes

| Class | Stored in Git | Rule |
| --- | --- | --- |
| Hand-written source or specification | Yes | Reviewable and owned |
| Small deterministic generated file | Optional | Generator and verification command included |
| Build cache, waveform, or intermediate netlist | No | CI artifact only |
| Model weight or dataset | No | Manifest and authorized acquisition flow only |
| Redistributable third-party source | Optional | Version, license, and checksum required |
| Non-redistributable dependency | No | Manifest only |

## 5. Large Files

Files above 10 MB require justification; files above 50 MB do not enter normal Git objects by default.
Reproducible binaries are not kept in source control merely for convenience.

## 6. Compatibility Matrix

Releases record this tuple:

```text
model_adapter_version
compiler_ir_version
compiler_version
isa_version
runtime_driver_abi
firmware_version
rtl_interface_version
kdlink_protocol_version
simulator_model_version
```

Any unlisted combination is unverified.
