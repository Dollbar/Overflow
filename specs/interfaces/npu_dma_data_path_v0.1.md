# NPU DMA Internal Data Path v0.1

Status: controlled NPU-internal contract. The already-translated local DMA command, mover, and pod-shared
SRAM client are baselined; address-translation and NoC packet fields remain `HOLD`.

## 1. Scope

This contract separates the NPU-owned DMA data path from the externally owned KD-ISA and runtime ABI.
The NPU consumes an already-decoded internal DMA descriptor and produces an internal completion event.
It does not decode KD-ISA, read host submission queues, write runtime completion queues, or assign ABI
error encodings.

The currently admitted RTL scope is the finite HBM beat boundary, local-tag allocation, outstanding-tag
lifetime checking, the already-translated DMA v0.1 command, X/Y/Z address generation, sixteen channel
movers, and their pod-local integration with the fixed KD28-backed shared SRAM.

## 2. Local and NoC Paths

The default data path is pod-local:

```text
local HBM partition <-> pod DMA <-> pod/shared or tile staging SRAM <-> Tensor/Vector
```

The local HBM partition is directly attached to its owning pod DMA. Data destined for compute is written
into software-managed SRAM and becomes visible through an explicit producer-consumer ownership/barrier
transition. Tensor and Vector engines read SRAM; they do not consume an unbuffered HBM response stream.
The pod-local path uses a local SRAM client arbiter or crossbar and does not traverse the global pod NoC.

The NoC is required only when the source or destination is outside the owning pod, or when an approved
operation explicitly requests cross-pod distribution:

```text
source pod DMA/SRAM -> NoC injection -> pod mesh -> destination ejection -> destination SRAM
```

The NoC owns routing, virtual-channel selection, credits, congestion backpressure, packet ordering, and
deadlock avoidance after injection. The DMA owns beat generation, source/destination bounds, reservation
of destination resources, and completion accounting before and after that boundary. No remote mover RTL
may be implemented until the NoC flit, VC, credit, reset, and error contract is versioned.

The architecture proposal requires at least 80 percent pod-local HBM traffic because the proposed mesh
cannot redistribute the complete 5 TB/s NPU HBM stream. That locality ratio remains `ANALYTICAL` and is
not an RTL guarantee.

## 3. Local-Tag Allocation

Each pod DMA has sixteen logical channels. Each channel owns 256 eight-bit local tags, producing the
twelve-bit HBM identity `{channel[3:0], local_tag[7:0]}` frozen by ADR-0002.

`npu_dma_local_tag_allocator` exposes one claim and one release opportunity per channel per service-clock
cycle. `allocation_request_i` is a commit pulse, not an unconstrained ready/valid level; the producer must
assert it only while `allocation_available_o` is high and must capture `allocation_local_tag_o` on the
same edge as `allocation_grant_o`. A successful claim immediately reserves the selected lowest-numbered
free tag. Requesting while no tag is available produces `allocation_failure_o` and is a producer protocol
error.

A release is committed only after the matching HBM response has been consumed by the destination DMA
channel. Releasing a free tag produces `unknown_release_o`. A released tag enters the free pool on the
following cycle; after the one-cycle full-pool turnover, release and allocation can continue every cycle.
The sticky local protocol-error diagnostic is asserted one cycle after the first allocation failure or
unknown release.

The allocator reserves a tag when a channel beat buffer is created. The independent outstanding tracker
records that tag only when the HBM request egress actually accepts the beat, then retires it when the
response is consumed. Integration must preserve both stages:

```text
beat-buffer claim -> allocator reservation -> HBM egress acceptance -> tracker allocation
HBM response consumption -> tracker retirement -> allocator release
```

Cancellation and reset-abort reclamation remain `HOLD`; until that contract is approved, an admitted beat
buffer may not silently discard a reserved tag.

## 4. Integrated Beat Boundary

`npu_dma_hbm_boundary` is the admitted integration top between sixteen already-decoded channel beat
producers and the frozen five-lane HBM service. Each producer supplies the frozen write, partition-local
address, write-data, byte-enable, and QoS fields without a tag. On `channel_request_valid_i &&
channel_request_ready_o`, the boundary reserves a local tag, returns that tag on
`channel_request_local_tag_o`, and captures the complete beat in a one-entry channel buffer.

The channel buffer is deliberately non-fall-through: a channel dequeued into the egress becomes ready for
its next beat on the following cycle. This removes the egress arbitration return path from the tag-claim
and 1,199-bit buffer-capture path. Sixteen channel buffers feeding five HBM lanes preserve the aggregate
five-beat-per-cycle saturation target even though one channel cannot dequeue and refill on the same edge.
Capture enables are replicated in 32-bit groups for timing and capacitance control.

The boundary connects the lifetime stages as follows:

- channel input acceptance reserves a tag and captures the beat;
- egress acceptance is registered for one cycle before the independent outstanding tracker claim;
- HBM response delivery captures its tag into a one-cycle retirement pipeline before tracker retirement;
- only a tracker-known retirement releases the allocator entry.

An unknown response is still consumed through the finite response boundary and raises the sticky local
protocol diagnostic, but it cannot release an allocator entry. `busy_o` remains asserted while a channel
buffer, egress lane, response buffer, or tracked HBM request is occupied. The integration top does not
generate addresses, access SRAM, interpret completion status, or select a NoC route.

The integrated status monitor observes the same response-consumption pulse used for retirement. It counts
the frozen `OK`, `ECC_CORRECTED`, `ECC_UNCORRECTABLE`, and `DATA_ERROR` values independently in 64-bit
modulo counters and latches local seen bits for the three non-OK classes. Aggregate counters lag the commit
by two service-clock cycles and sticky observations lag by one cycle. These outputs are diagnostic
telemetry only: status never changes retirement or allocator release, and this revision defines no replay,
retryability, interrupt, completion record, or ABI error conversion.

The boundary also supports lossless local quiesce. Assertion closes all sixteen channel admission points
without modifying requests already accepted. Buffered and outstanding work continues to retirement, and
`quiesced_o` asserts after three consecutive idle service-clock cycles so the two-cycle count/status
telemetry pipelines have settled. Deassertion re-enables ordinary allocation-based admission. The
outstanding high-watermark records the maximum delayed aggregate count since reset. Neither mechanism
cancels work, frees an unretired tag, imposes a timeout, or defines reset-abort recovery.

## 5. Remaining Holds

The following are not defined by this revision or the referenced DMA command contract:

- KD-ISA descriptor packing, IOVA width, protection domain, chaining, and runtime completion identity;
- compute and NoC shared-SRAM client arbitration, ECC, and ownership-transition fields;
- partial-beat, scatter/gather, indexed, multicast, and zero-fill address-generator fields;
- scatter-gather, indexed gather/scatter, multicast, and zero-fill command encodings;
- NoC packet, virtual-channel, credit, ordering, retry, and reset behavior; and
- runtime status, cancellation, interrupt, timeout, and recovery semantics.

These fields require their producing contract, this consuming contract, compatibility tests, and updated
traceability before a command extension, compute adapter, or remote-path RTL is admitted.

## 6. Required Evidence

The local-tag allocator requires zero-warning lint, synthesis-readiness, exhaustive allocation of all
4,096 identities, full-pool failure injection, release/reclaim turnover, unknown-release injection,
randomized free-bitmap scoreboarding, complete drain, and mapped 1 GHz generic STA with no setup, slew,
capacitance, or fanout violation. Generic-cell evidence is not KD28 signoff.

The integrated boundary additionally requires a sixteen-channel mixed read/write regression with five
independently backpressured request lanes, ordered HBM response generation, independently stalled channel
consumers, full tag, address, data, byte-enable, and status scoreboarding, telemetry checks, complete drain,
and mapped 1 GHz generic STA. The regression must demonstrate aggregate request issue without relying on
same-cycle channel-buffer dequeue/refill.

The response-status monitor additionally requires all four status classes in directed and randomized
sixteen-channel commit traffic, exact counter checks after pipeline drain, sticky-bit and reset checks,
zero-warning lint, synthesis-readiness, and the same mapped 1 GHz generic STA gate.

The integrated boundary must also be quiesced during active randomized traffic, prove that admission stops
while accepted traffic drains without loss, hold the settled indication until control deassertion, resume
to full completion, and compare the reported outstanding high-watermark against an independent scoreboard.
