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

The managed one-Pod path now adds an already-decoded Task/local/DMA gateway, unified completion stream,
two-cluster scoreboard, DMA/shared-SRAM/local-loader integration, and independent Vector issue. The 2 by 4
shell replicates eight such Pods with fixed HBM affinity and verified router-independent attachments.

The following system functions remain outside that verified boundary. KD-ISA and the software ABI are
external dependencies of this NPU RTL workstream, not NPU RTL deliverables:

- externally owned KD-ISA encoding/decoding, runtime queues, completion ABI, interrupts, and cancellation;
- host-visible DMA descriptors, address protection, and runtime error recovery (the internal DMA and finite
  RTL HBM paths are verified);
- additional compute/NoC shared-SRAM clients, ECC policy, and software ownership transitions (the DMA-only
  shared SRAM is verified);
- general M/N/K or block-matrix scheduling (cluster-local independent Vector issue is closed by ADR-0006);
- global scheduling, NoC router/mesh behavior, KDLink attachment, and physical memory attachment;
- clock/reset-domain contracts, CDC/RDC policy, power control, and system-level RAS.

## 3. Conformance Matrix

| Area | Current authority | State | Allowed next action | RTL gate |
| --- | --- | --- | --- | --- |
| MX Tensor/Vector compute | NPU core v0.2 contract; NPU-007..015 | `VERIFIED` in declared scope | Preserve behavior and extend only through a versioned contract | Existing bit-exact and continuous-flow regressions |
| KD28 SRAM/FIFO models | KD28 SRAM/FIFO v0.1 contract | `RTL_SIM`; synthetic technology collateral | Bind logical NPU 1W/1R banks through explicit adapters | Macro-count, no residual inferred memory, three-corner synthetic STA |
| KD-ISA and software ABI | External ISA, compiler, runtime, driver, and firmware owners | `EXTERNAL / HOLD`; NPU decoded sink `VERIFIED` by NPU-034 | External owners publish queue/encoding/cancellation contracts and translate into decoded-command v0.1 | External compatibility evidence; existing NPU gateway regression |
| DMA and HBM RTL | ADR-0002/0003, NPU HBM and DMA command/data-path contracts; NPU-017..027 | Sixteen-channel mover, request/response boundary, status, quiesce, and DMA-to-SRAM Pod path `VERIFIED` | Preserve the internal contract; add IOVA/protection and host-visible adapters only through new versioned contracts | RTL backpressure/saturation, Pod round trip, and exact SRAM mapping |
| Scratchpad system | Pod-shared SRAM v0.1 plus inherited local compute stores | DMA-only Pod client and KD28 mapping `VERIFIED`; compute/NoC clients and ECC `HOLD` | Preserve the DMA client; specify each additional client and ECC behavior before admission | Collision, starvation, capacity, mapping, and future ECC injection tests |
| Independent Vector/general Tensor issue | ADR-0006 and NPU-033 close cluster-local independent Vector version 3; GEMM remains version 2 | Independent Vector `VERIFIED`; general Tensor `HOLD` | Preserve Vector v3; version M/N/K and block scheduling separately | Real-SRAM PASS end-to-end RTL_SIM, 104-combination operation/source/route scheduler matrix, all-operation numeric Vector RTL_SIM; future arbitrary M/N/K tests |
| Eight-pod organization | ADR-0004 plus array v0.1 | Structural shell and HBM affinity `VERIFIED LEAF` by NPU-035 | Preserve fixed geometry; integrate external router only through attachment v0.1 | Production-geometry concurrent eight-Pod RTL_SIM including all 16 local loaders, four HBM seeds, mandatory 84-bit functional matrix, ready/valid SVA, measured code-coverage gate, structural lint, and separate real-module one-Pod lint |
| NoC | ADR-0005 attachment v0.1 | Pod attachment `VERIFIED`; router/mesh `EXTERNAL / HOLD` | NoC owner implements VC credit routing CDC and proof obligations | Router RTL_SIM congestion regression and formal deadlock proof |
| Clock/reset/CDC | Logical compute clocks only | `HOLD` | Define domain relationships and reset sequencing | CDC/RDC analysis and reset recovery tests |

## 4. Ordered Delivery

### Phase A: Specification closure

1. Keep the current compute contract unchanged and reconcile implementation status documents.
2. Record KD-ISA and queue/completion ABI documents as external inputs. The NPU workstream does not
   define their encoding or implement their frontend.
3. Preserve the versioned NPU-internal command, completion, DMA, and DMA-only shared-SRAM boundaries.
   Define additional scratchpad clients, the external completion adapter, and cross-domain clocks/resets
   only through their owning contracts.
4. Add requirement IDs and compatibility tests before externally visible RTL is written.

The unresolved cross-owner choices and recommended approval order are maintained in
[`NPU External Command Dependencies and DMA Approval Packet`](npu_command_dma_approval_packet.md).

### Phase B: Storage closure

1. Bind the current logical local-buffer 1W/1R contract to banked KD28 SDP cells.
2. Keep data and scale storage explicit, record depth/width tiling, and prohibit inferred memory after
   synthesis mapping.
3. Add arbitration and ECC only after their interface and fault semantics are approved.

### Phase C: One-pod closure

1. Preserve the completed finite DMA mover against the approved internal command and beat contracts. The
   five-lane request egress, response routing, tag allocation/lifetime, status, DMA-only shared SRAM, and Pod
   round trip are verified; IOVA/protection and physical HBM attachment remain separate integration work.
2. Preserve the verified decoded-command sink, internal completion aggregation, resource scoreboard, and
   independent Vector issue. Do not implement KD-ISA decode or runtime queue logic in this workstream.
3. Preserve the verified managed one-Pod reset, backpressure, malformed-command, DMA/local-transfer, and
   completion regressions.

### Phase D: Multi-pod closure

1. Preserve the accepted Pod-count/topology ADR and verified eight-Pod structural shell.
2. The external NoC owner implements the router and escape VC and proves protocol deadlock freedom.
3. System owners integrate the router, global scheduler, memory/KDLink adapters, CDC, telemetry, and
   system regression through the frozen NPU boundaries.

## 5. Stop Conditions

Implementation stops rather than guessing when a field is consumed outside its owning module and lacks a
versioned specification, when a proposed parameter conflicts with the system baseline, or when required
evidence cannot distinguish a behavioral model from synthesizable RTL. No analytical clock or bandwidth
claim may be reported as implementation timing or sustained RTL throughput.

## 6. Reproducible NPU-Owned RTL Gate

Run `make npu-owned-rtl-test` from the repository root. It executes compute lint/reference/functional and
peak-flow regressions, DMA/shared-SRAM integration lint/synthesis/simulation, decoded-command VIP tests,
single-Pod tests, real-hierarchy lint, production-geometry four-seed eight-Pod simulation, and the Pod
code/functional coverage gates. The target deliberately
does not claim or run externally owned NoC router/deadlock/CDC verification or technology-specific physical
signoff; those gates require the contracts and implementation inputs listed above.
