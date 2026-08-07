# NPU External Command Dependencies and DMA Approval Packet

Status: `PROPOSED` decision packet. No value in this document is an implementation contract until the
listed ADR and producing specifications are accepted.

## 0. Ownership Boundary

This packet records dependencies; it does not assign all of them to the NPU RTL workstream.

- KD-ISA encoding, decoding, assembler/disassembler behavior, and command validation belong to the
  external KD-ISA owner.
- Submission/completion queue layout, doorbells, interrupts, and recovery ABI belong to the runtime,
  driver, and firmware owners.
- The NPU consumes a versioned, already-decoded internal command record. It owns only the ready/valid
  sink, internal resource checks, issue, and completion-event production after that boundary.
- The NPU owns the DMA mover, NPU-side finite HBM transaction adapter, scratchpad controller,
  scheduler/scoreboard, Pod integration, and its internal diagnostics. The NoC router, system-visible RAS
  mapping, and any cross-domain wrappers remain with their separately identified owners.
- The HBM controller, PHY, and physical memory model are outside this workstream. The RTL HBM
  specification is the jointly approved interface contract used by the NPU-side adapter.

## 1. Audit Result

The repository currently has no KD-ISA encoding or runtime command/completion queue ABI. It now has a
versioned NPU-internal decoded-command gateway and unified completion, DMA command contract, finite RTL HBM
transaction contract, DMA mover, DMA-to-Pod-SRAM integration, managed Pod, and eight-Pod structural shell.
The owning `isa/`, `specs/isa/`, `specs/abi/`, `runtime/`, `drivers/`, `firmware/`, and `rtl/memory/` paths
still contain scope READMEs only.

The portable HBM model and beat BFM provide verification behavior, not production field authority. Their
testbench address, tag, queue-depth, and latency parameters must not be copied into RTL interfaces.

## 2. External Inputs Reserved for Host-Visible Integration

The recommendations below describe properties the future host-visible integration boundary needs. They are
not prerequisites for the current post-DMA compute ISA or NPU-internal DMA implementation, and they are not
an authorization for this workstream to define KD-ISA or ABI behavior.

| Decision | Existing constraint | Requested v0.1 direction | Required external-owner output |
| --- | --- | --- | --- |
| KD-ISA command version | System baseline selects KD-ISA; compute descriptor version is 2 | Define a KD-ISA major/minor header and carry the existing 342-bit compute descriptor through an aligned command record without changing its packed layout | `specs/isa/kd_isa.md` plus encoder/decoder tests |
| Command queue ownership | Runtime, driver, and firmware are all in scope | Host-owned submission ring, device-owned completion ring, monotonic producer/consumer indices, and an explicit doorbell; no implicit polling side effects | `specs/abi/npu_queue.md` plus runtime/firmware compatibility test |
| Ordering | Current compute submit is atomic by slot index | Preserve command-record atomicity; define whether different queues order independently and which barrier establishes scratchpad visibility | ISA and ABI memory-order sections |
| Cancellation/reset | No external semantics exist | Cancellation affects only commands not yet issued; reset completion for accepted work must be explicit rather than silently dropped | ISA exception and ABI recovery sections |
| Completion/error | Local compute status is not a runtime ABI | Define success, malformed command, access, DMA, poison, ECC, timeout, cancelled, and reset outcomes with retryability | Versioned completion record and error table |
| Privilege/protection | System proposal mentions future IOVA/protection domains | Keep protection-domain and address-translation fields versioned; do not expose raw local SRAM macro addresses | ISA/ABI and memory-interface ownership agreement |

## 3. DMA/HBM Decisions and Remaining Inputs

ADR-0002 and `specs/interfaces/npu_hbm_rtl.md` now close the NPU-side five-lane beat geometry, 35-bit
partition-local address, twelve-bit tag, status, ordering, and four-class age-promoted request arbitration.
They do not close the upstream DMA descriptor, IOVA translation, cancellation, or runtime fault ABI.

| Decision | Existing constraint | Recommended v0.1 direction | Required owner output |
| --- | --- | --- | --- |
| External address | 192 GB per logical NPU is baselined; 52-bit IOVA is proposed | Use a parameterized IOVA field in DMA descriptors and freeze its v0.1 width only through the ADR; translate to partition plus partition-local byte address before the HBM boundary | ADR plus DMA descriptor spec |
| HBM partition | Functional-preview contract uses partitions 0 through 7 | Retain an explicit partition field if the eight-partition organization is approved; otherwise keep partition selection behind the memory adapter | Topology/memory ADR |
| Data beat | Functional-preview contract requires 128-byte alignment | Closed: five parallel 1024-bit lanes with 128 byte enables per pod | ADR-0002 and `specs/interfaces/npu_hbm_rtl.md` |
| Transaction length | Functional-preview maximum is 4096 bytes | Closed at the HBM boundary as tagged single beats; a DMA operation emits a sequence of beats | NPU HBM RTL beat contract; DMA descriptor remains open |
| Outstanding identity | Tags are caller-owned but unbounded in the model; 4096 beats per engine is proposed | Closed: twelve-bit tag composed from four-bit channel and eight-bit local identity; no reuse before retirement | ADR-0002 and NPU HBM RTL beat contract |
| Completion ordering | Functional model completes in issue order per partition | Closed: preserve per-partition request order; response lane number carries no identity; the verified NPU leaf routes by tag and preserves same-channel retirement order across the five lanes | NPU HBM RTL beat contract and NPU-018 regression |
| Status | Model has OK, corrected ECC, uncorrectable ECC, and data error | Closed at beat boundary with two-bit status; runtime retryability remains external | NPU HBM RTL beat contract and external completion ABI |
| DMA operations | P0 proposes linear, strided, gather/scatter, multicast, and zero-fill | Stage v0.1 as linear plus strided transfer first; admit gather/scatter and multicast only with compiler/runtime descriptors and bounds rules | DMA descriptor and compiler contracts |
| QoS/starvation | Four classes and age promotion are proposed | Closed for NPU request egress: class priority, round-robin ties, and 256-cycle promotion interval | NPU HBM RTL beat contract plus NPU-017 regression |

The beat-interface leaves, local-tag allocator, outstanding-tag lifetime tracker, sixteen-channel mover,
address generator, Pod-shared SRAM, and integrated Pod boundary are implemented and verified. The allocator
reserves and releases all 4,096 beat identities; the tracker detects duplicate allocation and unknown
retirement; and the local monitor counts consumed responses across all four frozen status classes. The
remaining external integration gate covers IOVA translation, protection, cancellation reclamation, and
conversion of internal completion events into the externally owned ABI. The verified quiesce path stops new
admission and drains accepted work, but deliberately does not define cancellation, timeout, abrupt-reset
reclamation, or replay.

## 4. External Inputs Required Before General Compute Issue

The GEMM v0.2 descriptor supports one fixed-origin square GEMM followed optionally by Vector
post-processing. ADR-0006 additionally authorizes the NPU-internal version-3 independent Vector
interpretation at the same packed width. Neither record defines a host-visible command nor authorizes
arbitrary M/N/K scheduling.

Before general Tensor issue or an external command adapter enters RTL, the compiler/operator owners shall define:

- independent M, N, and K dimensions, batch count, strides, and edge masks;
- block/subarray placement or an explicit decision to keep fixed-origin execution;
- the mapping from any external Vector command into the frozen internal source/destination layout and operator controls;
- attention, MoE, transpose, gather, and KV-cache lowering responsibilities; and
- compatibility behavior for the existing descriptor version 2.

The requested external-owner approach remains a new command record that references the existing internal
GEMM v2, Vector v3, and DMA records. Reinterpreting spare or reserved v2 GEMM bits is prohibited; Vector v3
is selected explicitly by its version and operation fields.

## 5. Clock and Reset Decisions

The only admitted synchronous boundary is the current compute-local `clk_i`, `rst_i`, and `clear_i`.
Logical 1 GHz Tensor and HBM clocks are system/model assumptions; the proposed 2 GHz NoC clock is not
approved implementation timing.

Before a system wrapper makes any Pod boundary cross domains, an interface specification shall define:

- command-management, compute/SRAM, HBM-service, NoC, and KDLink clock relationships;
- asynchronous assertion and domain-synchronous reset deassertion;
- reset propagation and in-flight request retirement or abort behavior;
- CDC primitive ownership, maximum payload delay, and Gray-pointer bus-skew constraints; and
- RDC behavior for independently reset producer and consumer domains.

## 6. Recommended Approval Order

1. NPU owners may implement and verify the internal DMA command, mover, HBM beat, and DMA-only shared-SRAM
   contracts independently of host-visible KD-ISA and queue ABI work.
2. Memory and NPU owners jointly approve any future address translation, protection, and physical HBM
   attachment fields before those fields enter RTL.
3. External owners publish KD-ISA and queue/completion ABI specifications in parallel; integration adds an
   adapter only after both sides are versioned.
4. NPU owners approve additional compute/NoC shared-SRAM clients and ECC behavior before exposing them.
5. External compiler/ISA owners approve general Tensor and the host-visible mapping to independent Vector;
   the NPU consumes only their decoded internal issue records.
6. Affected owners approve clock/reset relationships before constructing a multi-clock system wrapper.

Each approval updates its owner-controlled ADR or specification, the NPU consuming specification,
compatibility tests, and traceability rows in the same change. These gates apply to the corresponding
externally visible adapter or new client; they do not retroactively block the versioned NPU-internal DMA
datapath. No KD-ISA frontend RTL is part of this workstream.
