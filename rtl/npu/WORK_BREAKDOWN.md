# NPU RTL Work Breakdown

This file is the allocation index for NPU implementation work. `READY` means the task boundary is clear
enough to begin without inventing an external interface. `HOLD` names the missing decision or evidence.
A task is complete only after its listed documentation, tests, and traceability are updated.

## 1. Work Packages

| ID | Path | Deliverable | Depends on | Current state | Required evidence |
| --- | --- | --- | --- | --- | --- |
| NPU-COM-001 | `common/` | MX numeric packages and arithmetic primitives | NPU core v0.2 contract | VERIFIED: current compute scope | bit-exact RTL_SIM |
| NPU-COM-002 | `common/`, top-level | Performance, fault, clock, and reset types | system management contracts | HOLD: specs | lint + counter/reset tests |
| NPU-CMD-001 | `command/` | Already-decoded internal command sink and unified completion source; no KD-ISA decode or software queue RTL | ADR-0007 + decoded-command v0.1 | VERIFIED: NPU-034 | lint + synthesis readiness + routing/backpressure/malformed/reset/completion RTL_SIM |
| NPU-SCH-001 | `scheduler/` | Local square-GEMM descriptor, dependency, and post issue | NPU core v0.2 contract | VERIFIED: NPU-007 | RTL_SIM + assertions |
| NPU-SCH-002 | `pod/` | Pod-local two-cluster resource scoreboard and independent issue | ADR-0004 internal allocation contract | VERIFIED LEAF: NPU-030 | RTL_SIM + backpressure and retirement checks |
| NPU-TNS-001 | `tensor/` | MXFP4 x MXFP8 PE and exact Tile accumulation | NPU core v0.2 contract | VERIFIED: NPU-010 | bit-exact RTL_SIM |
| NPU-TNS-002 | `tensor/` | 256 x 256 array transport and accumulation | NPU-TNS-001 | VERIFIED: NPU-011 | RTL_SIM continuous issue |
| NPU-TNS-003 | `tensor/`, `compute/` | Local-buffer stream and square-GEMM control | NPU-TNS-002 + local SRAM contract | VERIFIED: NPU-014 | RTL_SIM saturation |
| NPU-TNS-004 | `scheduler/`, `tensor/` | Arbitrary M/N/K, batching, edge masks, and block scheduling | compiler and descriptor vNext contracts | HOLD: specs | bit-exact and boundary RTL_SIM |
| NPU-VEC-001 | `vector/` | Current masked Vector and special-function pipelines | NPU core v0.2 contract | VERIFIED: NPU-008 and NPU-012 | bit-exact RTL_SIM |
| NPU-VEC-002 | `scheduler/`, `compute/`, `vector/`, `sram/` | Independent Vector issue and local memory flow | ADR-0006 + independent Vector contract | VERIFIED: NPU-033 | real-SRAM-path RTL_SIM + 104-combination operation/source/route scheduler matrix + all-operation Vector numeric RTL_SIM + bounded round-robin service, stalled A/W pairing, backpressure, layout, completion, and compatibility checks |
| NPU-SRM-001 | `sram/` | Current local Tensor/Vector storage boundary | NPU core v0.2 contract | VERIFIED: NPU-009 and NPU-014 | RTL_SIM macro contract |
| NPU-SRM-003 | `sram/`, `Library/models/kd28/` | Map NPU SRAM boundaries onto fixed KD28 TDP/SDP cells | KD28 and NPU local SRAM contracts | VERIFIED: NPU-016 | exact macro counts + no inferred memory + synthetic STA |
| NPU-SRM-002 | `sram/` | 16 MiB pod-shared scratchpad and sixteen-client DMA arbitration | NPU pod-shared SRAM v0.1 contract | VERIFIED: NPU-026 | RTL_SIM + exact KD28 macro mapping |
| NPU-DMA-001 | `dma/` | Finite command queues, address generation, and scratchpad movers | NPU-local DMA command and SRAM client contracts | VERIFIED: NPU-024..025 | RTL_SIM backpressure and generic STA |
| NPU-DMA-002 | `dma/` | NPU-side HBM response retirement and finite DMA mover; no HBM controller or PHY | NPU HBM RTL beat and DMA command contracts | VERIFIED: NPU-018..025 | RTL_SIM + generic STA |
| NPU-DMA-003 | `dma/` | Sixteen-channel QoS/age arbiter and five-lane elastic HBM request egress | ADR-0002 and NPU HBM RTL beat contract | VERIFIED: NPU-017 | zero-warning lint + no-loss saturation/backpressure RTL_SIM |
| NPU-DMA-004 | `dma/` | Five-lane HBM response buffering, ordered tag routing, and sixteen-channel elastic retirement | ADR-0002 and NPU HBM RTL beat contract | VERIFIED: NPU-018 | zero-warning lint + no-loss/order/error RTL_SIM + generic 1 GHz STA |
| NPU-NOC-000 | `pod/` | Router-independent Pod/NoC logical attachment with opaque packet payloads | ADR-0005 + Pod/NoC v0.1 | VERIFIED LEAF: NPU-032 | zero-warning lint + synthesis readiness + backpressure/quiesce RTL_SIM |
| NPU-NOC-001 | `noc/` | Credit-based router with deterministic escape VC | ADR-0005 attachment + NoC-owner routing contract | EXTERNAL OWNER / HOLD: router contract | FORMAL deadlock and credit obligations |
| NPU-NOC-002 | `noc/` | Proposed 2 x 4 pod mesh integration | NPU-NOC-001 | EXTERNAL OWNER / HOLD: NPU-NOC-001 | RTL_SIM congestion regression |
| NPU-POD-001 | `pod/` | Shared-to-private compatibility loader for two compute clusters | Pod local-transfer v0.1 | VERIFIED LEAF: NPU-029 | RTL_SIM mapping and backpressure |
| NPU-TOP-001 | `rtl/npu/pod/` | One-pod top-level integration | ADR-0004, DMA, scratchpad, loader, compute contracts | VERIFIED: NPU-031 | RTL_SIM integration + real-hierarchy lint |
| NPU-TOP-002 | `rtl/npu/` | Eight-Pod structural shell, HBM affinity, and NoC-owner handoff | ADR-0004/0005/0007 + array v0.1 | VERIFIED LEAF: NPU-035; router/CDC external | production-geometry eight-Pod concurrent RTL_SIM + all 16 local loaders + four-seed HBM pressure + 84-bit functional-coverage hard gate + code-coverage baseline + ready/valid SVA + structural lint; separate real-module one-Pod lint at reduced Tensor dimension; router congestion/formal evidence external |

## 2. Ordered Assignment

1. Reconcile specifications and traceability with the verified v0.2 compute boundary.
2. Preserve external KD-ISA/ABI dependencies and the verified NPU-owned decoded-command, completion,
   DMA/HBM, scratchpad, and internal event contracts; clock/reset crossings remain separately gated.
3. Complete NPU-SRM-003 without changing the current logical SRAM behavior.
4. Preserve the verified DMA/HBM response retirement, movement, DMA-only shared-SRAM arbitration, and
   exact macro mapping; ECC awaits a characterized storage and fault contract.
5. Preserve the verified decoded-command sink, Pod scoreboard, independent Vector issue, managed Pod, and
   eight-Pod shell. RAS register mapping and CDC/RDC await their owning system contracts.
6. The NoC owner implements and proves the router/escape path against the frozen attachment; the system
   owner adds any cross-domain and global integration outside this workstream.

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
