# Overflow AI Accelerator RTL System

Overflow is an open engineering project that connects model-level accelerator requirements to
synthesizable NPU and KDLink RTL. The repository lower boundary is synthesizable RTL; external HBM,
SerDes, host, and technology behavior is represented by explicitly labeled models and interfaces.

The repository publishes the `1.0.0` source-and-verification baseline at tag `v1.0.0`. Its authoritative
publication decision and validation boundary are recorded in
[`docs/releases/ACCEPTANCE.json`](docs/releases/ACCEPTANCE.json).

## Release Scope

The 1.0 source scope includes:

- MXFP tensor/vector compute RTL, decoded-command routing, DMA, 16 MiB Pod-shared SRAM, and Pod-local
  data movement.
- A two-cluster compute Pod, eight-Pod 2 by 4 array, three-plane NoC, per-Pod CDC, and the integrated
  Pod/NoC top.
- KDLink endpoint, router, collective, scale model, and vendor-neutral digital SerDes models.
- Repository-authored HBM behavior, KD28 SRAM/FIFO models, portable synthetic timing views, testbench
  packages, VIP, lint, formal, simulation, synthesis, and coverage gates.
- Architecture, interface, requirement, ADR, dependency, risk, and release records.

This release does not include model weights, private datasets, a complete compiler/runtime/driver stack,
an end-to-end Kimi-K3 product, analog PHY models, physical design, DFT, or silicon signoff. The 2 PFLOPS,
5 TB/s, 50 token/s, and one-million-endpoint values remain architecture or simulation claims at their
declared evidence levels; they are not measured silicon results. Production private SRAM capacity is not
frozen. Coverage is thresholded where a code-coverage gate exists and is never presented as exhaustive;
the detailed subsystem boundary is recorded in the release scope.

See the complete [release scope](docs/planning/release_scope.md) and
[release notes](docs/releases/RELEASE_NOTES.md).

## Architecture Envelope

| Item | Declared baseline |
| --- | ---: |
| Reference workload | Kimi-K3, 2.8T total and 104B active parameters |
| Forward-looking envelope | 5.6T total and 208B active parameters |
| Weight and activation formats | MXFP4 weights; MXFP8, FP8, and BF16 activations |
| Logical NPU scale | 32 nodes in the system baseline |
| Logical HBM capacity | 192 GB per NPU, 6.144 TB aggregate |
| NPU organization | 8 Pods in a 2 by 4 mesh, 8 HBM partitions, 1 DMA per Pod |
| KDLink injection target | 512 GB/s TX and 512 GB/s RX payload per NPU, analytical |

Configuration values are source-controlled in
[`config/system_baseline.yaml`](config/system_baseline.yaml) and
[`config/npu_arch_proposed.yaml`](config/npu_arch_proposed.yaml). Status fields distinguish frozen
interfaces from proposed product sizing.

## Repository Map

| Directory | Responsibility |
| --- | --- |
| `Library/` | Reusable HBM, SerDes, KD28 models, profiles, and synthetic timing views |
| `specs/` | Model, compiler, ISA, ABI, KDLink, and digital-interface specifications |
| `rtl/` | NPU, KDLink, memory, host, and common synthesizable RTL |
| `simulator/` | HBM, NPU, KDLink, and system functional environments |
| `verification/` | Packages, VIP, self-checking RTL tests, formal, CDC, and coverage |
| `technology/` | Portable timing-view validation and implementation-boundary scripts |
| `requirements/` | Requirement ownership and evidence states |
| `docs/` | Architecture, ADR, planning, management, and release records |
| `config/` | Machine-readable architecture, toolchain, and release configuration |
| `third_party/` | Dependency inventory; external restricted inputs are never stored here |
| `LICENSES/` | Owner-approved official license and exception texts |

Other first-level directories define model, compiler, ISA, runtime, driver, firmware, and deployment
ownership. Some are specification placeholders and are not represented as completed implementations.

## Reproduce the Release

Use a fresh clone on a Linux x86-64 host with Python 3.12, GNU Make, GCC, Verilator, Yosys, OpenSTA, and
`verilator_coverage` available from `PATH`. The exact validated versions, sources, licenses, and checksums
are in [`third_party/dependencies.yaml`](third_party/dependencies.yaml).

A machine with at least 32 GiB of RAM is recommended for the complete RTL regression. Use
`RELEASE_JOBS=1` on smaller hosts or when several generated C++ compilations would otherwise overlap, and
provide swap rather than relying on an OOM kill. The largest validated single Pod lint used about 20 GiB.
The first uncached run is intentionally long: on the validated 24-thread host, the KDLink RTL gate takes
about 45 minutes and its instrumented coverage gate takes about 48 minutes. These figures are planning
guidance, not performance requirements.

```bash
python3 -m venv .release-env
. .release-env/bin/activate
python3 -m pip install --require-hashes -r requirements-build.lock
python3 -m pip install --require-hashes --no-build-isolation -r requirements-dev.lock
make release-preflight
make release-audit
make release-regression RELEASE_JOBS=2
make release-check
```

Expected outputs for the published tree are `RELEASE_REGRESSION_PASS` after all portable engineering gates
and `RELEASE_GATE_PASS` from the clean, licensed release attestation. Generated files stay in ignored
`build/` or `work/` directories. The immutable payload, attestation relationship, and annotated-tag
procedure are documented in [`docs/management/release_management.md`](docs/management/release_management.md).

## Contribution and Evidence Rules

Read [Contributing](CONTRIBUTING.md), [Governance](GOVERNANCE.md), the
[Code of Conduct](CODE_OF_CONDUCT.md), [Security Policy](SECURITY.md), and the repository-wide
[automation rules](AGENTS.md) before changing interfaces. Specifications precede implementations;
versioned protocol values live inside stable, version-neutral engineering files. Evidence is labeled as
`ANALYTICAL`, `FUNCTIONAL_SIM`, `RTL_SIM`, `FORMAL`, or `GENERIC_SYNTH`.
