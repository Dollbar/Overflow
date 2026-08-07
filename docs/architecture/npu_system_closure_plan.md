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
shell replicates eight such Pods with fixed HBM affinity. The joint system closes every attachment-to-CDC,
CDC-to-Mesh, Mesh-to-CDC, and CDC-to-attachment transport connection across eight independent Pod clocks.

The following system functions remain outside that verified boundary. KD-ISA and the software ABI are
external dependencies of this NPU RTL workstream, not NPU RTL deliverables:

- externally owned KD-ISA encoding/decoding, runtime queues, completion ABI, interrupts, and cancellation;
- host-visible DMA descriptors, address protection, and runtime error recovery (the internal DMA and finite
  RTL HBM paths are verified);
- additional compute/NoC shared-SRAM clients, ECC policy, and software ownership transitions (the DMA-only
  shared SRAM is verified);
- general M/N/K or block-matrix scheduling (cluster-local independent Vector issue is closed by ADR-0006);
- opaque-payload adapters for remote DMA/SRAM/collectives, global scheduling, KDLink attachment, and
  physical memory attachment;
- command/HBM/KDLink CDC/RDC policy, physical Pod/NoC CDC signoff, power control, and system-level RAS.

## 3. Conformance Matrix

| Area | Current authority | State | Allowed next action | RTL gate |
| --- | --- | --- | --- | --- |
| MX Tensor/Vector compute | NPU core v0.2 contract; NPU-007..015 | `VERIFIED` in declared scope | Preserve behavior and extend only through a versioned contract | Existing bit-exact and continuous-flow regressions |
| KD28 SRAM/FIFO models | KD28 SRAM/FIFO v0.1 contract | `RTL_SIM`; synthetic technology collateral | Bind logical NPU 1W/1R banks through explicit adapters | Macro-count, no residual inferred memory, three-corner synthetic STA |
| KD-ISA and software ABI | External ISA, compiler, runtime, driver, and firmware owners | `EXTERNAL / HOLD`; NPU decoded sink `VERIFIED` by NPU-034 | External owners publish queue/encoding/cancellation contracts and translate into decoded-command v0.1 | External compatibility evidence; existing NPU gateway regression |
| DMA and HBM RTL | ADR-0002/0003, NPU HBM and DMA command/data-path contracts; NPU-017..027 | Sixteen-channel mover, request/response boundary, status, quiesce, and DMA-to-SRAM Pod path `VERIFIED` | Preserve the internal contract; add IOVA/protection and host-visible adapters only through new versioned contracts | RTL backpressure/saturation, Pod round trip, and exact SRAM mapping |
| Scratchpad system | Pod-shared SRAM v0.1 plus inherited local compute stores | DMA-only Pod client and KD28 mapping `VERIFIED`; compute/NoC clients and ECC `HOLD` | Preserve the DMA client; specify each additional client and ECC behavior before admission | Collision, starvation, capacity, mapping, and future ECC injection tests |
| Independent Vector/general Tensor issue | ADR-0006 and NPU-033 close cluster-local independent Vector version 3; GEMM remains version 2 | Independent Vector `VERIFIED`; general Tensor `HOLD` | Preserve Vector v3; version M/N/K and block scheduling separately | Real-SRAM PASS end-to-end RTL_SIM, 104-combination operation/source/route scheduler matrix, all-operation numeric Vector RTL_SIM; future arbitrary M/N/K tests |
| Eight-pod organization | ADR-0004 plus array/system v0.1 | Structural shell and HBM affinity `VERIFIED` by NPU-035/036 | Preserve fixed geometry and opaque packet clients | Production-geometry concurrent Pod suite plus joint multi-clock regression |
| NoC | ADR-0005/0008, attachment/router/CDC contracts | Attachment, VC/credit routers, 2x4 Mesh, CDC, and joint transport `VERIFIED LOGIC` | Preserve contracts; define packet semantics only in versioned client adapters | Router congestion/all-pairs RTL_SIM, bounded formal deadlock proof, CDC ratios, coverage, and joint 64+512 route matrix |
| Clock/reset/CDC | NoC CDC and system v0.1 contracts | Pod/NoC path `VERIFIED LOGIC`; physical signoff and other crossings `HOLD` | Preserve independent reset release and drain; close implementation CDC/RDC with selected tools | Eight distinct Pod-clock reset/quiesce recovery plus future commercial CDC/RDC signoff |

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
2. Preserve the implemented router, escape VC, CDC, formal deadlock evidence, and joint transport test.
3. System owners integrate versioned packet clients, global scheduler, memory/KDLink adapters, and
   physical CDC/timing/power/RAS closure through the frozen NPU boundaries.

## 5. Stop Conditions

Implementation stops rather than guessing when a field is consumed outside its owning module and lacks a
versioned specification, when a proposed parameter conflicts with the system baseline, or when required
evidence cannot distinguish a behavioral model from synthesizable RTL. No analytical clock or bandwidth
claim may be reported as implementation timing or sustained RTL throughput.

## 6. Reproducible NPU-Owned RTL Gate

Run `make npu-pod-noc-release` from the repository root for the layered Pod, NoC, joint transport, and
repository gate. `make npu-owned-rtl-test` remains the NPU-owned compute/Pod-only gate. It executes compute lint/reference/functional and
peak-flow regressions, DMA/shared-SRAM integration lint/synthesis/simulation, decoded-command VIP tests,
single-Pod tests, real-hierarchy lint, production-geometry four-seed eight-Pod simulation, and the Pod
code/functional coverage gates. Neither target claims technology-specific physical timing, P&R, power,
DFT, or commercial CDC/RDC signoff; those gates require selected implementation inputs.
