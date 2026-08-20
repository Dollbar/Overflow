# OwerFlow Open AI Accelerator RTL System

OwerFlow is an open engineering project spanning model adaptation, compilers, instruction sets, runtime
software, NPU digital logic, and the KDLink scale-up fabric. It targets Kimi-K3 and future sparse MoE
models at roughly twice its scale. The project is organized as one verifiable path from model semantics to
synthesizable RTL rather than a collection of disconnected components.

The repository lower boundary is synthesizable RTL plus behavioral models for external memory, host, and
link environments. Work below that boundary is not part of OwerFlow. The current `v0.1` release is an
architecture and repository baseline; it does not claim a complete compiler, complete RTL, or full-model
performance.

## 1. System Targets

The OwerFlow design envelope is named `OF-5P6T`:

| Item | v0.1 baseline |
| --- | ---: |
| Reference model | Kimi-K3: 2.8T total, 104B active parameters |
| Forward-looking envelope | 5.6T total, 208B active parameters |
| Weight format | MXFP4 or equivalent 4-bit block-scaled format |
| Activation formats | MXFP8, FP8, BF16 |
| Simulated scale | Up to 32 logical NPU nodes |
| Logical HBM capacity | 192 GB per NPU, 6.144 TB aggregate |
| Compute target | 2 PFLOPS-equivalent per NPU under declared model assumptions |
| Logical HBM target | 5 TB/s per NPU |
| KDLink injection target | 512 GB/s TX + 512 GB/s RX payload per NPU |
| Model context | 1M-token compatibility, 2M-token capacity stress mode |
| Service scope | Inference first; training is outside the project boundary |

Targets are architectural assumptions until supported by the stated evidence. Performance reports must
label analytical results, functional simulation, RTL simulation, formal results, and generic synthesis
separately.

## 2. System Context

```text
Kimi-K3 / future model artifacts
              |
              v
Model adapter -> compiler/sharding -> KD-ISA executable
                                         |
                                         v
                            Serving runtime / driver
                                         |
                                         v
       +--------------------------------------------------+
       | NPU RTL: command, tensor, vector, SRAM/NoC/HBM  |
       |                         + KDLink NIC/collective  |
       +--------------------------------------------------+
                                         |
                          KDLink router and KDSwitch RTL
                                         |
                          32-node behavioral environment
```

See [System Context and Responsibility Boundaries](docs/architecture/system_context.md) for the detailed
scope definition.

## 3. Repository Map

| Directory | Responsibility |
| --- | --- |
| `Library/` | Reusable HBM and digital SerDes behavioral models and parameter profiles |
| `specs/` | Model, compiler, ISA, ABI, KDLink, and digital-interface specifications |
| `models/` | Model manifests, operator lists, weight sharding, and numerical references |
| `compiler/` | Graph import, IR, optimization, partitioning, scheduling, and code generation |
| `isa/` | KD-ISA encoding, assembler, disassembler, and conformance tests |
| `runtime/` | Serving, execution queues, KV cache, and multi-device scheduling |
| `drivers/` | Driver interfaces and user-space device access |
| `firmware/` | Management firmware, command processing, and KDLink control |
| `rtl/` | NPU, KDLink, memory, host, and common synthesizable RTL |
| `simulator/` | ISA, NPU, memory, KDLink, and 32-node behavioral simulation |
| `verification/` | Golden models, RTL simulation, formal checks, CDC, and coverage |
| `deployment/` | Serving images, containers, logical cluster configuration, and operations |
| `third_party/` | Redistributable software and RTL dependency manifests |
| `requirements/` | Requirement ownership, verification method, and evidence state |
| `docs/` | Architecture, planning, management, and ADR documents |
| `config/` | Machine-readable architecture and protocol baselines |
| `scripts/` | Reproducible repository, model, compiler, simulator, and RTL tooling |
| `ci/` | Automated formatting, test, simulation, and release gates |
| `LICENSES/` | Software, RTL, documentation, and model license boundaries |

## 4. v0.1 Deliverables

`v0.1` includes:

- The OF-5P6T workload and logical-capacity baseline.
- A model-to-RTL context boundary and cross-layer interface ownership.
- Repository, branch, version, review, and release rules.
- Initial requirement-to-artifact-to-test traceability.
- Placeholder areas with clear ownership for specifications and implementations.

See [v0.1 Scope](docs/planning/v0.1_scope.md) for exit criteria.

## 5. Core Engineering Rules

1. Project documentation and README files are written in English.
2. Specifications precede implementations; each cross-directory interface has one versioned source of truth.
3. Generated artifacts are reproducible from committed sources and commands.
4. Model weights and non-redistributable dependencies do not enter the repository.
5. Logical clocks and bandwidths are assumptions unless a cited test establishes the stated evidence level.
6. Internal gates are risk controls and are not presented as completed product releases.

Read [Contributing](CONTRIBUTING.md), [Governance](GOVERNANCE.md), and
[Repository Management](docs/management/repository_management.md) before contributing.

Run the repository gate:

```bash
python3 -m pip install -r requirements-dev.txt
make check
```
