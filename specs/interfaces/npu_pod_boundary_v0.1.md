# NPU Single-Pod Digital Boundary v0.1

Status: controlled pre-RTL boundary. Only items marked `BASELINED` or `INHERITED` are implementation
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
  decoded_command_sink        # HOLD: NPU sink; source contract externally owned
  pod_scheduler               # local policy after command validation
  compute_cluster[]           # one verified cluster; replication is PROPOSED
  tile_private_sram[]         # current local compute stores are INHERITED
  pod_shared_sram             # HOLD: client and ownership contract
  dma_frontend                # HOLD: finite descriptor and transaction fields
  memory_attachment           # HOLD: RTL HBM request/response contract
  noc_attachment              # HOLD: packet and credit contract
  completion_ras              # HOLD: NPU events; runtime ABI externally owned
```

One `npu_square_gemm_system` instance is the only currently verified compute cluster. A second cluster per
pod and the eight-pod organization remain `PROPOSED`; neither may be hard-coded into an external ABI.

## 3. Channel Admission Matrix

| Channel | Producer | Consumer | State | Authority and restriction |
| --- | --- | --- | --- | --- |
| Local task descriptor write/submit | integration logic | compute cluster | `INHERITED` | NPU core v0.2 packed descriptor and atomic submit rules |
| Tensor and Vector local writes | integration logic | compute-local SRAM | `INHERITED` | 128-bit physical words, MX packing, scale rules, and local byte offsets from NPU core v0.2 |
| Compute post-result streams | compute cluster | integration logic | `INHERITED` | Atomic result/metadata ready-valid contract from NPU core v0.2 |
| Compute event/status | compute cluster | integration logic | `INHERITED` | Local event/tag/status semantics only; not a runtime completion ABI |
| Physical local SRAM cells | SRAM adapter | compute-local SRAM controller | `INHERITED` | Registered 1W/1R behavior; explicit adapter required; no inferred production storage |
| KD-ISA command queue | firmware/runtime | external KD-ISA frontend | `EXTERNAL / HOLD` | Encoding, ordering, cancellation, privilege, and malformed-command behavior are not NPU RTL deliverables and require external `specs/isa/` and `specs/abi/` contracts |
| Decoded internal command | external KD-ISA frontend | NPU decoded-command sink | `HOLD` | Version, opcode class, resource intent, payload reference, ordering token, and error handoff require a jointly consumed interface contract |
| NPU internal completion event | compute/scheduler/DMA | external ABI adapter | `HOLD` | Event identity, outcome, retryability, ordering token, and reset handoff require a jointly consumed interface contract |
| Runtime completion queue/interrupt | external ABI adapter | firmware/runtime | `EXTERNAL / HOLD` | Queue layout, ordering, interrupt moderation, retry, and reset behavior are externally owned and require `specs/abi/` |
| Internal DMA descriptor | decoded-command sink/scheduler | DMA frontend | `HOLD` | Transfer type, finite widths, chaining, protection, cancellation, and fault fields are not frozen |
| HBM RTL request lanes | DMA frontend | memory attachment | `BASELINED` | ADR-0002 and `npu_hbm_rtl.md` freeze five 128-byte lanes, finite address/tag fields, stable backpressure, ordering, and reset |
| HBM RTL response retirement | memory attachment | DMA frontend | `BASELINED / VERIFIED LEAF` | Five-lane elastic capture, ordered tag routing, malformed-partition drop, and sixteen channel outputs are verified by NPU-018; outstanding-tag lifetime and runtime fault propagation remain part of the held DMA mover contract |
| Pod-shared SRAM client request | DMA/compute/NoC | shared SRAM | `HOLD` | Arbitration, ownership, ECC, byte enables, ordering, and starvation policy are not frozen |
| NoC packet/credit link | pod clients | pod router | `HOLD` | Flit, VC, routing, credit, ordering, fault, and reset fields require a NoC contract |
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

Any command, HBM, NoC, KDLink, or management clock crossing remains `HOLD`. Before such RTL is admitted,
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
- NPU consuming-specification and functional-model work for the decoded-command sink, DMA,
  shared-SRAM, and NoC channels.

The following work is blocked:

- production KD-ISA decode, host command queue, or runtime completion-queue RTL, which is outside this
  NPU workstream;
- DMA descriptors, address translation, outstanding-tag allocation/release, runtime fault conversion, and
  scratchpad movement beyond the frozen HBM beat interface;
- pod-shared SRAM arbitration or ECC response fields exposed to clients;
- independent Vector or general M/N/K descriptor encodings;
- multi-clock pod integration, NoC links, or eight-pod replication.

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
