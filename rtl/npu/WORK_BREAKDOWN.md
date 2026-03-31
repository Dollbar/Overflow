# NPU RTL Work Breakdown

This file is the allocation index for NPU implementation work. `READY` means the task boundary is clear
enough to begin without inventing an external interface. `HOLD` names the missing decision or evidence.
A task is complete only after its listed documentation, tests, and traceability are updated.

## 1. Work Packages

| ID | Path | Deliverable | Depends on | Current state | Required evidence |
| --- | --- | --- | --- | --- | --- |
| NPU-COM-001 | `common/` | MX numeric packages and arithmetic primitives | NPU core v0.2 contract | VERIFIED: current compute scope | bit-exact RTL_SIM |
| NPU-COM-002 | `common/`, top-level | Performance, fault, clock, and reset types | system management contracts | HOLD: specs | lint + counter/reset tests |
| NPU-CMD-001 | `command/` | Already-decoded internal command sink and NPU event source; no KD-ISA decode or software queue RTL | external decoded-command contract | HOLD: external spec | RTL_SIM backpressure, malformed-internal-record, and reset tests |
| NPU-SCH-001 | `scheduler/` | Local square-GEMM descriptor, dependency, and post issue | NPU core v0.2 contract | VERIFIED: NPU-007 | RTL_SIM + assertions |
| NPU-SCH-002 | `scheduler/` | Pod/global resource scoreboard and independent issue | decoded internal issue and pod contracts | HOLD: specs | RTL_SIM + starvation assertions |
| NPU-TNS-001 | `tensor/` | MXFP4 x MXFP8 PE and exact Tile accumulation | NPU core v0.2 contract | VERIFIED: NPU-010 | bit-exact RTL_SIM |
| NPU-TNS-002 | `tensor/` | 256 x 256 array transport and accumulation | NPU-TNS-001 | VERIFIED: NPU-011 | RTL_SIM continuous issue |
| NPU-TNS-003 | `tensor/`, `compute/` | Local-buffer stream and square-GEMM control | NPU-TNS-002 + local SRAM contract | VERIFIED: NPU-014 | RTL_SIM saturation |
| NPU-TNS-004 | `scheduler/`, `tensor/` | Arbitrary M/N/K, batching, edge masks, and block scheduling | compiler and descriptor vNext contracts | HOLD: specs | bit-exact and boundary RTL_SIM |
| NPU-VEC-001 | `vector/` | Current masked Vector and special-function pipelines | NPU core v0.2 contract | VERIFIED: NPU-008 and NPU-012 | bit-exact RTL_SIM |
| NPU-VEC-002 | `scheduler/`, `vector/` | Independent Vector issue and memory flow | operator and descriptor vNext contracts | HOLD: specs | bit-exact continuous RTL_SIM |
| NPU-SRM-001 | `sram/` | Current local Tensor/Vector storage boundary | NPU core v0.2 contract | VERIFIED: NPU-009 and NPU-014 | RTL_SIM macro contract |
| NPU-SRM-003 | `sram/`, `Library/models/kd28/` | Map NPU SRAM boundaries onto fixed KD28 TDP/SDP cells | KD28 and NPU local SRAM contracts | VERIFIED: NPU-016 | exact macro counts + no inferred memory + synthetic STA |
| NPU-SRM-002 | `sram/` | 16 MiB pod-shared scratchpad and arbitration | NoC/DMA clients | HOLD: client contract | RTL_SIM + starvation assertions |
| NPU-NOC-001 | `noc/` | Credit-based router with deterministic escape VC | routing/packet fields | HOLD: interface spec | FORMAL deadlock obligations |
| NPU-NOC-002 | `noc/` | Proposed 2 x 4 pod mesh integration | NPU-NOC-001 | HOLD: NPU-NOC-001 | RTL_SIM congestion regression |
| NPU-DMA-001 | `dma/` | Descriptor scheduler and scratchpad mover | descriptor fields | HOLD: interface spec | RTL_SIM backpressure |
| NPU-DMA-002 | `dma/` | NPU-side finite RTL HBM transaction adapter; no HBM controller or PHY | HBM RTL contract | HOLD: functional-preview spec is insufficient | FUNCTIONAL_SIM equivalence + RTL_SIM |
| NPU-TOP-001 | `rtl/npu/` | One-pod top-level integration | decoded-command sink, DMA, scratchpad, scheduler contracts | HOLD: specs | RTL_SIM integration |
| NPU-TOP-002 | `rtl/npu/` | Eight-pod NPU top-level integration | topology ADR + NPU-NOC-002 | HOLD: proposed topology | RTL_SIM + CDC/RDC integration |

## 2. Ordered Assignment

1. Reconcile specifications and traceability with the verified v0.2 compute boundary.
2. Record external KD-ISA/ABI dependencies and define only the NPU-owned decoded-command sink, DMA/HBM,
   scratchpad, internal event, and clock/reset contracts.
3. Complete NPU-SRM-003 without changing the current logical SRAM behavior.
4. Implement DMA/HBM movement and pod-shared SRAM arbitration/ECC against approved NPU contracts.
5. Implement the decoded-command sink, pod scoreboard, independent issue, RAS/performance, and CDC/RDC;
   do not implement KD-ISA decode or software queues in this workstream.
6. Integrate and saturate one pod before approving the multi-pod topology and NoC contracts.
7. Implement the router, prove the escape path, then integrate the eight-pod top level.

The controlling authority and stop conditions are recorded in
[`NPU System Closure Plan`](../../docs/architecture/npu_system_closure_plan.md).

## 3. Per-Task Delivery Checklist

- Hand-written RTL and generated sources are separated; generators record inputs and commands.
- Interfaces and parameters cite their authoritative ADR/config/specification.
- Lint is clean or every waiver is reviewed and recorded.
- Directed and randomized tests cover reset, backpressure, boundaries, and errors.
- Applicable assertions, formal properties, CDC/RDC checks, and coverage are included.
- Performance evidence names tensor shape, dtype, logical clock, initiation interval, and evidence level.
- `requirements/traceability.csv` and affected documentation are updated.
- Missing evidence remains `HOLD`; an unexecuted test is never reported as passing.
