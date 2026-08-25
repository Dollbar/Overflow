# ADR-0003: NPU Local DMA Mover Contract

- State: accepted
- Owners: NPU architecture and DMA implementation
- Date: 2026-08-25
- Evidence: `ANALYTICAL`

## Context

ADR-0002 fixes the per-pod HBM beat boundary, but it deliberately does not define how a multi-beat DMA
operation is represented or how data reaches software-managed SRAM. The NPU workstream owns that mover,
while KD-ISA encoding, runtime queues, IOVA translation, protection, and externally visible completion
records belong to other owners.

The proposed architecture assigns one DMA engine to each of eight pods. Each engine has sixteen logical
channels, 4,096 HBM beat identities, and a 16 MiB pod-shared SRAM target. A useful production boundary must
support finite commands and complete only after data reaches its destination, rather than treating HBM
request acceptance as operation completion.

## Decision

The NPU local mover consumes a versioned, already-decoded and already-translated internal command. The HBM
address is a 35-bit partition-local byte address and the SRAM address is a 24-bit byte address within one
16 MiB pod-local space. Neither address is an IOVA or a system-physical address.

DMA v0.1 supports full 128-byte beats for HBM-to-SRAM and SRAM-to-HBM movement. One set of X, Y, and Z
counts plus independent HBM and SRAM row/plane strides represents linear, two-dimensional, and
three-dimensional transfers. Unused dimensions have count one. Every base and stride is 128-byte aligned,
all counts are nonzero, and one command moves no more than 16 MiB.

Each of the sixteen channels owns four total command contexts: at most one executing command and up to
three additional queued commands, yielding 64 active or queued descriptors per pod engine. Channels feed
the five-lane HBM boundary from ADR-0002. HBM read responses commit only when their data is accepted by the
SRAM write port. HBM write operations complete only when every matching write response retires. Tag-indexed
metadata retains the SRAM address and final-beat marker while a request is outstanding; the single executing
context in each channel retains the command identity.

The mover emits an NPU-internal completion event with command identity, success, an internal error class,
completed-beat count, and corrected-ECC observation. This event is consumed by a future NPU integration
adapter and is not a runtime completion record or stable software encoding.

## Alternatives

- Carry KD-ISA descriptors directly into the mover: rejected because that crosses the external ISA owner
  boundary and couples hardware movement to an unapproved binary encoding.
- Carry a 52-bit IOVA into the HBM beat boundary: rejected because translation and protection precede the
  partition-local interface.
- Stream HBM responses directly into Tensor or Vector: rejected because the architecture requires explicit
  software-managed SRAM ownership and barrier transitions.
- Complete a command when its final HBM request is accepted: rejected because response faults and SRAM
  destination backpressure would not be accounted for.
- Route pod-local movement through the NoC: rejected because it consumes scarce bisection bandwidth and is
  unnecessary for the owning HBM partition and SRAM.

## Consequences

The local mover can be implemented and verified without defining KD-ISA, host queues, IOVA page tables, or
NoC packet fields. A translation adapter must reject or translate external addresses before producing this
internal command. The v0.1 full-beat rule requires software or a later edge-byte extension for unaligned
transfers.

Scatter/gather, indexed movement, multicast, zero-fill, cancellation, timeout, replay, and cross-pod paths
require later versioned contracts. They are not inferred from the X/Y/Z representation. Generic-cell
synthesis and STA establish implementation readiness only; KD28 signoff requires selected macro and
standard-cell views.
