# NPU System Closure Plan

Status: controlled implementation plan. This document does not freeze fields that remain `PROPOSED` or
`HOLD` in their owning ADR or specification.

## 1. Authority Order

NPU implementation decisions use the following precedence. A lower item cannot override a higher item.

1. `config/system_baseline.yaml` defines the accepted system envelope.
2. Accepted ADRs define cross-owner architecture decisions.
3. Versioned documents under `specs/` define externally consumed interfaces and numerical behavior.
4. `requirements/traceability.csv` records required evidence and current requirement state.
5. Architecture proposals and implementation READMEs guide work only inside the boundaries above.

Conflicts stop implementation until an ADR and every affected specification are updated. RTL must not
turn a proposal parameter into a de facto external contract.

## 2. Current Verified Boundary

The current `npu_square_gemm_system` is a post-transfer compute-cluster boundary, not a complete NPU. It
accepts versioned local descriptors and data already placed in local SRAM. Requirements NPU-007 through
NPU-015 record the verified MX-only square-GEMM, Vector, feedback, local-buffer, and mapped-PE timing
evidence. The authoritative compute contract is `specs/interfaces/npu_gemm_vector_core.md`.

The following system functions remain outside that verified boundary. KD-ISA and the software ABI are
external dependencies of this NPU RTL workstream, not NPU RTL deliverables:

- externally owned KD-ISA encoding/decoding, runtime queues, completion ABI, interrupts, and cancellation;
- DMA descriptors, finite RTL HBM transactions, address protection, and error recovery;
- pod-shared SRAM, multi-client arbitration, ECC policy, and software ownership transitions;
- independent Vector dispatch and general M/N/K or block-matrix scheduling;
- pod/global scheduling, multi-pod NoC, KDLink attachment, and memory attachment;
- clock/reset-domain contracts, CDC/RDC policy, power control, and system-level RAS.

## 3. Conformance Matrix

| Area | Current authority | State | Allowed next action | RTL gate |
| --- | --- | --- | --- | --- |
| MX Tensor/Vector compute | NPU core v0.2 contract; NPU-007..015 | `VERIFIED` in declared scope | Preserve behavior and extend only through a versioned contract | Existing bit-exact and continuous-flow regressions |
| KD28 SRAM/FIFO models | KD28 SRAM/FIFO v0.1 contract | `RTL_SIM`; synthetic technology collateral | Bind logical NPU 1W/1R banks through explicit adapters | Macro-count, no residual inferred memory, three-corner synthetic STA |
| KD-ISA and software ABI | External ISA, compiler, runtime, driver, and firmware owners | `EXTERNAL / HOLD` | External owners publish versioned command and queue/completion contracts; NPU consumes an already-decoded internal command | External encode/decode and software compatibility evidence; NPU sink backpressure tests |
| DMA and HBM RTL | ADR-0002 and NPU HBM RTL beat contract; NPU-017..018 | Request egress and response-routing leaves `VERIFIED`; mover `HOLD` | Implement outstanding-tag tracking, address generation, translation boundary, and scratchpad movement without changing the frozen beat fields | Functional-model equivalence plus RTL backpressure/saturation |
| Scratchpad system | Capacity targets are proposed; local compute stores are verified | Mixed | Specify clients, arbitration, ownership, ECC, and reset before pod-shared RTL | Collision, starvation, ECC injection, capacity, and bandwidth tests |
| Independent Vector/general Tensor issue | Existing ABI supports square GEMM with optional Vector post-processing | `HOLD` outside v0.2 | Version compiler/operator and descriptor contracts | Bit-exact, edge-mask, arbitrary M/N/K, and independent issue tests |
| Eight-pod organization | NPU P0 sizing proposal | `PROPOSED` | Create an ADR after workload/locality evidence | Checked sizing and one-pod evidence before replication |
| NoC | NPU P0 sizing proposal | `HOLD` for packet/link contract | Freeze packet, VC, credit, routing, reset, and error rules | Router RTL_SIM, congestion regression, and formal deadlock proof |
| Clock/reset/CDC | Logical compute clocks only | `HOLD` | Define domain relationships and reset sequencing | CDC/RDC analysis and reset recovery tests |

## 4. Ordered Delivery

### Phase A: Specification closure

1. Keep the current compute contract unchanged and reconcile implementation status documents.
2. Record KD-ISA and queue/completion ABI documents as external inputs. The NPU workstream does not
   define their encoding or implement their frontend.
3. Define the NPU-owned side of a versioned single-pod boundary covering an already-decoded command
   sink, remaining DMA descriptors/scratchpad clients, internal completion/error events, and clocks/resets.
   Proposed values remain explicitly marked until approved through an ADR.
4. Add requirement IDs and compatibility tests before externally visible RTL is written.

The unresolved cross-owner choices and recommended approval order are maintained in
[`NPU External Command Dependencies and DMA Approval Packet`](npu_command_dma_approval_packet.md).

### Phase B: Storage closure

1. Bind the current logical local-buffer 1W/1R contract to banked KD28 SDP cells.
2. Keep data and scale storage explicit, record depth/width tiling, and prohibit inferred memory after
   synthesis mapping.
3. Add arbitration and ECC only after their interface and fault semantics are approved.

### Phase C: One-pod closure

1. Complete outstanding-tag tracking, the finite DMA mover, and translation boundary against the approved
   beat contract. The five-lane request egress and response-routing leaves are verified by NPU-017 and
   NPU-018.
2. Implement the decoded-command sink, internal completion aggregation, resource scoreboard, and
   independent compute issue. Do not implement KD-ISA decode or runtime queue logic in this workstream.
3. Integrate one pod and prove reset, backpressure, faults, and sustained local data flow.

### Phase D: Multi-pod closure

1. Approve the pod-count/topology ADR using one-pod measurements and compiler locality traces.
2. Implement the router and escape VC, then prove protocol deadlock freedom.
3. Integrate the mesh, global scheduler, memory/KDLink adapters, CDC, telemetry, and system regression.

## 5. Stop Conditions

Implementation stops rather than guessing when a field is consumed outside its owning module and lacks a
versioned specification, when a proposed parameter conflicts with the system baseline, or when required
evidence cannot distinguish a behavioral model from synthesizable RTL. No analytical clock or bandwidth
claim may be reported as implementation timing or sustained RTL throughput.
