# NPU Single-Pod Digital Boundary v0.1

Status: controlled integration boundary. Only items marked `BASELINED` or `INHERITED` are implementation
contracts. Items marked `PROPOSED` or `HOLD` are not admissible as externally visible RTL fields.

## 1. Scope and Authority

This document defines the admission boundary for integrating one NPU pod around the existing MX-only
compute cluster. It prevents command, DMA, scratchpad, completion, and clock/reset placeholders from
escaping into production RTL before their owning specifications are approved.

The authority order is:

1. `config/system_baseline.yaml`;
2. accepted ADRs;
3. the producing cross-layer specification;
4. this boundary document;
5. implementation-local documentation.

The existing compute behavior is inherited from `npu_gemm_vector_core.md`. The logical HBM behavior is
inherited only at the functional-model level from `hbm_transaction.md`. This document does not convert the
NPU P0 sizing proposal into an interface contract.

## 2. Single-Pod Composition

The intended integration unit contains the following ownership regions:

```text
npu_pod
  decoded_command_sink        # BASELINED: NPU-internal v0.1 sink
  pod_scheduler               # local policy after command validation
  compute_cluster[0..1]       # BASELINED organization; cluster block VERIFIED
  tile_private_sram[]         # current local compute stores are INHERITED
  pod_shared_sram             # BASELINED: DMA-only client contract
  dma_frontend                # BASELINED: NPU-internal command and data path
  memory_attachment           # BASELINED: logical RTL HBM request/response
  noc_attachment              # BASELINED: router-independent ready-valid handoff
  completion_aggregator       # BASELINED: NPU-internal v0.1 completion
```

One `npu_square_gemm_system` instance is the verified compute-cluster implementation. ADR-0004 baselines
two identical instances per Pod and eight Pods in a 2 by 4 logical placement. The complete single-Pod
wrapper is verified by NPU-031. The managed command wrapper is verified by NPU-034, and fixed eight-Pod
structural replication is verified at leaf-integration level by NPU-035. These counts remain internal
rather than ABI fields.

## 3. Channel Admission Matrix

| Channel | Producer | Consumer | State | Authority and restriction |
| --- | --- | --- | --- | --- |
| Local task descriptor write/submit | integration logic | compute cluster | `INHERITED` | NPU core v0.2 packed descriptor and atomic submit rules |
| Tensor and Vector local writes | integration logic | compute-local SRAM | `INHERITED` | 128-bit physical words, MX packing, scale rules, and local byte offsets from NPU core v0.2 |
| Compute post-result streams | compute cluster | integration logic | `INHERITED` | Atomic result/metadata ready-valid contract from NPU core v0.2 |
| Compute event/status | compute cluster | integration logic | `INHERITED` | Local event/tag/status semantics only; not a runtime completion ABI |
| Physical local SRAM cells | SRAM adapter | compute-local SRAM controller | `INHERITED` | Registered 1W/1R behavior; explicit adapter required; no inferred production storage |
| KD-ISA command queue | firmware/runtime | external KD-ISA frontend | `EXTERNAL / HOLD` | Encoding, ordering, cancellation, privilege, and malformed-command behavior are not NPU RTL deliverables and require external `specs/isa/` and `specs/abi/` contracts |
| Decoded internal command | external KD-ISA frontend | NPU decoded-command sink | `BASELINED / VERIFIED` | ADR-0007 and `npu_decoded_command_v0.1.md` freeze the versioned 372-bit Task/local/DMA envelope; source-side KD-ISA decoding remains external |
| NPU internal completion event | compute/scheduler/DMA | external ABI adapter | `BASELINED / VERIFIED` | ADR-0007 freezes the 66-bit request-correlated internal completion; runtime queue layout, interrupt and retry policy remain external |
| Runtime completion queue/interrupt | external ABI adapter | firmware/runtime | `EXTERNAL / HOLD` | Queue layout, ordering, interrupt moderation, retry, and reset behavior are externally owned and require `specs/abi/` |
| Internal DMA descriptor | NPU-local scheduler/adapter | DMA frontend | `BASELINED / VERIFIED` | `npu_dma_command_v0.1.md` freezes the internal linear/strided command used by the mover; KD-ISA packing, IOVA, protection, chaining, and cancellation remain external or held |
| HBM RTL request lanes | DMA frontend | memory attachment | `BASELINED` | ADR-0002 and `npu_hbm_rtl.md` freeze five 128-byte lanes, finite address/tag fields, stable backpressure, ordering, and reset |
| HBM RTL response retirement | memory attachment | DMA frontend | `BASELINED / VERIFIED LEAF` | Five-lane elastic capture, ordered tag routing, malformed-partition drop, and sixteen channel outputs are verified by NPU-018 |
| HBM response status telemetry | DMA response consumers | local diagnostics | `BASELINED / VERIFIED LEAF` | Four frozen beat-status counters and three non-OK sticky observations are verified by NPU-022; retry and runtime ABI conversion remain held |
| DMA lossless quiesce | local reset/maintenance sequencing | DMA beat admission | `BASELINED / VERIFIED LEAF` | NPU-023 closes new admission and drains accepted beats before a settled indication; cancellation, timeout, abrupt reset, and ABI behavior remain held |
| DMA local-tag allocation and lifetime | DMA beat buffers and response consumers | HBM egress and DMA scheduler | `BASELINED / VERIFIED LEAF` | ADR-0002 tag geometry plus NPU DMA data-path contract; allocator and tracker are verified by NPU-019..020; cancellation reclamation remains held |
| Integrated DMA HBM beat boundary | decoded beat producers | memory attachment and decoded response consumers | `BASELINED / VERIFIED LEAF` | Sixteen channel buffers integrate allocation, egress, routing, retirement, and tag reclamation under NPU-021; descriptor and SRAM-client semantics remain held |
| Pod-shared SRAM DMA client request | DMA | shared SRAM | `BASELINED / VERIFIED` | `npu_pod_shared_sram_v0.1.md` freezes sixteen DMA clients, eight banks, full-beat writes, independent round-robin read/write arbitration, and ready-valid backpressure; compute/NoC clients and ECC remain held |
| Pod shared-to-private transfer | Pod loader | compute-local SRAM writes | `BASELINED / VERIFIED LEAF` | `npu_pod_local_transfer_v0.1.md` freezes paired full-beat reads and one-to-eight 128-bit Tensor/Vector writes; wider production loading remains a later revision |
| Complete two-cluster Pod | task/DMA/local-transfer producers | compute/result/HBM consumers | `BASELINED / VERIFIED` | `npu_compute_pod_v0.1.md` freezes the single-clock composition, task/status matching, DMA/loader SRAM sharing, result flattening, and lossless quiesce boundary |
| Pod/NoC logical attachment | pod packet clients | pod router | `BASELINED / VERIFIED LEAF` | ADR-0005 and `npu_pod_noc_attachment_v0.1.md` freeze ready-valid, one 128-bit control lane, two 1,024-bit data lanes, endpoint metadata, quiesce, and diagnostics |
| Fixed 2 by 4 Pod array | per-Pod command/HBM/packet lanes | NPU integration | `BASELINED / VERIFIED LEAF` | `npu_2x4_pod_array_v0.1.md` freezes eight managed Pods, same-ID HBM affinity, per-Pod clock/reset inputs, and eight router-independent attachments; it contains no router or CDC behavior |
| NoC router/credit/VC implementation | pod attachment | inter-pod mesh | `EXTERNAL / HOLD` | NoC owner retains VC mapping, credits, routing, arbitration, ordering, faults, deadlock proof, telemetry, and CDC |
| KDLink injection/ejection | pod | KDLink adapter | `HOLD` | Must use a versioned logical packet adapter; implicit width conversion is prohibited |

## 4. Baselined System Invariants

The following constraints apply to every future pod contract:

- The management ISA is RV64 and the accelerator command ISA is KD-ISA.
- The NPU is an explicitly managed, non-coherent accelerator. Software/compiler ownership and barriers
  control scratchpad visibility; hardware cache coherence must not be introduced implicitly.
- One logical NPU exposes 192 GB of abstract HBM capacity and a 5 TB/s aggregate read-plus-write payload
  target. These are system targets, not an RTL port-width or frequency claim.
- MXFP4 weights and MXFP8 activations are required workload formats. The existing v0.2 compute path is
  MX-only and RNE-only; FP8/BF16 issue rates remain outside that implementation contract.
- The accepted Tensor geometry is 256 by 256 at a declared logical 1 GHz clock. This does not establish
  implementation timing for a pod, SRAM, DMA, or NoC boundary.
- External behavior required by RTL must have a versioned digital contract and a portable behavioral
  model; proprietary implementation details must not leak into ISA or ABI semantics.

## 5. Local SRAM Adapter Contract

The current `npu_local_sram_1w1r_macro` boundary may be implemented before the wider pod contracts because
its behavior is already contained inside the verified compute boundary.

An admitted KD28 adapter shall:

1. implement one synchronous write port and one independent synchronous read port;
2. return read-valid and read-data one cycle after an accepted read;
3. preserve the logical address and data widths through explicit depth banking and width tiling;
4. define same-address read/write behavior as the selected KD28 SDP contract;
5. contain no inferred storage in the synthesis source list;
6. keep data and scale storage as explicit logical arrays; and
7. provide exact macro-count and three-corner synthetic timing evidence.

The adapter is synthetic front-end collateral until replaced by one selected foundry/compiler release. It
does not authorize a physical area, power, or signoff timing claim.

## 6. Clock, Reset, and Error Admission

The existing compute cluster has one synchronous `clk_i`, `rst_i`, and `clear_i` boundary. A wrapper may
remain in that same domain without creating a new external clock contract.

The admitted Pod/NoC attachment is synchronous to its supplied clock. Any command, HBM, NoC, KDLink, or
management clock crossing remains `HOLD`. Before such RTL is admitted,
the owning contract shall define clock relationships, synchronizer or FIFO ownership, reset assertion and
deassertion, in-flight transaction handling, timeout behavior, and CDC/RDC evidence.

Error handling shall be sticky only when the owning contract explicitly requires it. Local
`protocol_error_o` signals are diagnostic implementation outputs and must not be treated as stable runtime
status codes. Completion, retryability, poison, corrected ECC, uncorrectable ECC, access, timeout, and
cancellation outcomes require versioned ABI encodings before they cross the pod boundary.

## 7. RTL Admission Gates

The following work is admitted now:

- KD28 mapping for the inherited local SRAM 1W/1R boundary;
- verification-only adapters that translate the existing compute ports without changing semantics;
- assertions and counters that do not escape the current compute contract;
- the frozen HBM request egress and response-routing leaves, without descriptor, translation, or ABI
  semantics; and
- local-tag allocation, outstanding-lifetime, status telemetry, lossless quiesce, and integrated
  beat-boundary leaves using only the frozen ADR-0002 geometry and HBM beat fields; and
- NPU consuming-specification and functional-model work for the decoded-command sink, DMA,
  and NoC channels;
- the versioned NPU-internal linear/strided DMA mover and DMA-only Pod-shared SRAM client; and
- the single-clock DMA Pod integration without KD-ISA decode, IOVA translation, or runtime queues.
- the two-cluster Pod-local scoreboard and shared-to-private compatibility loaders under ADR-0004.
- the synchronous router-independent Pod/NoC ready-valid attachment under ADR-0005.
- cluster-local independent Vector descriptor version 3 under ADR-0006, with no host-visible or NoC fields.
- the versioned NPU-internal decoded-command gateway and unified completion aggregator under ADR-0007;
- the managed one-Pod wrapper joining command, DMA, shared SRAM, Tensor, Vector, and completion paths; and
- fixed 2 by 4 structural replication with one HBM partition and one NoC attachment per Pod.

The following work is blocked:

- production KD-ISA decode, host command queue, or runtime completion-queue RTL, which is outside this
  NPU workstream;
- host-visible DMA descriptors, address translation, protection, cancellation reclamation, and runtime
  fault conversion;
- NoC pod-shared SRAM clients or ECC response fields;
- general M/N/K descriptor encodings and any host-visible independent-Vector encoding;
- multi-clock Pod/NoC integration and router/mesh logic before the NoC owner closes VC, credit, routing,
  CDC, reset, and deadlock contracts.

Blocked work becomes admissible only after the producing specification, consuming specification,
compatibility tests, and affected traceability entries are updated together.

## 8. Conformance Evidence

A single-pod change shall record:

- the exact authority for every external field and parameter;
- lint and self-checking reset/backpressure/error tests;
- synthesis evidence distinguishing inferred storage from explicit macros;
- CDC/RDC results for every introduced clock or reset crossing;
- evidence labels from the allowed system policy; and
- an updated `requirements/traceability.csv` entry before claiming implementation or verification status.
