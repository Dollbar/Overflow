# NPU RTL Work Breakdown

This file is the allocation index for NPU implementation work. `READY` means the task boundary is clear
enough to begin without inventing an external interface. `HOLD` names the missing decision or evidence.
A task is complete only after its listed documentation, tests, and traceability are updated.

## 1. Work Packages

| ID | Path | Deliverable | Depends on | Start state | Required evidence |
| --- | --- | --- | --- | --- | --- |
| NPU-COM-001 | `common/` | Local parameter/type package and performance counters | ADR-0001 | READY | lint + unit tests |
| NPU-CMD-001 | `command/` | Command intake, validation, dispatch, completion | KD-ISA and queue fields | HOLD: specs | FUNCTIONAL_SIM then RTL_SIM |
| NPU-SCH-001 | `scheduler/` | Dependency scoreboard and pod/tile issue | command contract | HOLD: NPU-CMD-001 | RTL_SIM + assertions |
| NPU-TNS-001 | `tensor/` | MXFP4 x MXFP8 PE numerical reference and RTL | dtype semantics | HOLD: model spec | bit-exact RTL_SIM |
| NPU-TNS-002 | `tensor/` | 256 x 256 array transport and accumulation | NPU-TNS-001 | READY for structural work | RTL_SIM continuous issue |
| NPU-TNS-003 | `tensor/` | Tensor tile wrapper, SRAM streams, counters | NPU-TNS-002 + SRAM ports | HOLD: SRAM contract | RTL_SIM saturation |
| NPU-VEC-001 | `vector/` | Masked vector ALU and reductions | operator manifest | HOLD: model/compiler input | bit-exact RTL_SIM |
| NPU-VEC-002 | `vector/` | exp2, reciprocal, reciprocal-sqrt pipelines | error bounds | HOLD: numerical spec | bit-exact RTL_SIM |
| NPU-SRM-001 | `sram/` | 8 MiB banked tile scratchpad wrapper | local port contract | READY for banking study | RTL_SIM + ECC tests |
| NPU-SRM-002 | `sram/` | 16 MiB pod-shared scratchpad and arbitration | NoC/DMA clients | HOLD: client contract | RTL_SIM + starvation assertions |
| NPU-NOC-001 | `noc/` | Credit-based router with deterministic escape VC | routing/packet fields | HOLD: interface spec | FORMAL deadlock obligations |
| NPU-NOC-002 | `noc/` | Proposed 2 x 4 pod mesh integration | NPU-NOC-001 | HOLD: NPU-NOC-001 | RTL_SIM congestion regression |
| NPU-DMA-001 | `dma/` | Descriptor scheduler and scratchpad mover | descriptor fields | HOLD: interface spec | RTL_SIM backpressure |
| NPU-DMA-002 | `dma/`, `../memory/` | Abstract HBM transaction adapter | memory contract | HOLD: interface spec | FUNCTIONAL_SIM + RTL_SIM |
| NPU-TOP-001 | `rtl/npu/` | One-pod then eight-pod top-level integration | all leaf packages | HOLD: leaf blocks | RTL_SIM integration |

## 2. Recommended Parallel Assignment

The first parallel wave can assign NPU-COM-001, NPU-TNS-002 structural transport, NPU-SRM-001 banking
study, and the missing model/interface specifications. Numerical PE implementation must wait for MXFP4
block-scale and rounding semantics. Router and DMA RTL must wait for packet and descriptor fields.

The second wave integrates PE semantics into the array, freezes scratchpad client ports, implements vector
operators from the manifest, and begins router/DMA leaf verification. The third wave builds one pod; the
fourth wave builds the eight-pod mesh and cross-subsystem adapters.

## 3. Per-Task Delivery Checklist

- Hand-written RTL and generated sources are separated; generators record inputs and commands.
- Interfaces and parameters cite their authoritative ADR/config/specification.
- Lint is clean or every waiver is reviewed and recorded.
- Directed and randomized tests cover reset, backpressure, boundaries, and errors.
- Applicable assertions, formal properties, CDC/RDC checks, and coverage are included.
- Performance evidence names tensor shape, dtype, logical clock, initiation interval, and evidence level.
- `requirements/traceability.csv` and affected documentation are updated.
- Missing evidence remains `HOLD`; an unexecuted test is never reported as passing.
