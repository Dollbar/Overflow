# NPU HBM RTL Beat Interface v0.1

Status: NPU-side implementation contract. The memory-controller and PHY implementation remain outside
`rtl/npu/`.

## 1. Boundary

This contract connects one pod's NPU DMA egress to one abstract HBM partition service. It is a finite,
synthesizable ready/valid interface derived from ADR-0002 and the abstract HBM transaction contract. It is
not AXI, DFI, a JEDEC command interface, or a physical HBM pin contract.

The interface runs in the logical 1 GHz HBM service domain. A producer in another clock domain uses an
explicit asynchronous FIFO before this boundary. Reset is active-high and synchronous to the service
clock. Reset may be asserted only after the owning system reset sequence has quiesced or discarded all
in-flight DMA work.

## 2. Geometry

| Quantity | v0.1 value |
| --- | ---: |
| Partitions per logical NPU | 8 |
| HBM partition per pod | 1 |
| Request lanes per pod | 5 |
| Response lanes per pod | 5 |
| Payload bytes per lane | 128 |
| Raw bytes per pod cycle | 640 |
| Accepted long-run bytes per pod cycle | 625 shared by reads and writes |
| Partition-local capacity | 24,000,000,000 bytes |

Lane capacity is an `ANALYTICAL` interface property. It is not measured controller bandwidth. For
requests accepted in the same cycle, lane zero precedes lane one and so on in partition issue order.

## 3. Request Channel

Every request lane uses ready/valid. While `valid=1` and `ready=0`, every payload field remains stable.
A request is accepted only on `valid && ready`.

| Field | Width | Rule |
| --- | ---: | --- |
| `write` | 1 | `0` reads one beat; `1` writes one beat |
| `partition` | 3 | Integer 0 through 7; fixed by the owning pod in the default integration |
| `address` | 35 | Partition-local byte address, 128-byte aligned |
| `tag` | 12 | Unique among all accepted requests that have not retired |
| `write_data` | 1024 | One complete write beat; ignored for reads |
| `byte_enable` | 128 | One active-high enable per write byte; ignored for reads |

The default NPU tag layout is `{dma_channel[3:0], channel_local_tag[7:0]}`. Integration logic derives
widths from package or module parameters and must not duplicate them as unrelated literals.

Malformed partition, address, or tag reuse is a producer protocol error. Production NPU logic must not
send such a request to the memory service.

## 4. Response Channel

Every response lane uses ready/valid and remains stable under backpressure. A response retires its tag
only on `valid && ready`.

| Field | Width | Rule |
| --- | ---: | --- |
| `write` | 1 | Echoes the accepted operation |
| `partition` | 3 | Echoes the accepted partition |
| `tag` | 12 | Matches exactly one outstanding request |
| `read_data` | 1024 | Read beat; zero for a successful write response |
| `status` | 2 | `0=OK`, `1=ECC_CORRECTED`, `2=ECC_UNCORRECTABLE`, `3=DATA_ERROR` |

Responses preserve request order within one partition. Different partitions progress independently. The
NPU uses the tag for channel routing and must not infer completion identity from a response lane number.

The NPU response router contains one elastic register per HBM lane and one elastic register per logical
DMA channel. The upper tag bits select the DMA channel and the lower tag bits are delivered unchanged as
the channel-local tag. If several lanes target one channel, the oldest buffered response is delivered
first; lane zero is oldest for responses accepted in the same cycle. Unrelated channels may retire
independently.

A response carrying a partition other than the owning pod's configured partition is accepted and
dropped, increments the dropped-response counter, and sets the sticky local `protocol_error_o` diagnostic.
This diagnostic is not a runtime ABI status. The response router reports retirement events; tag lifetime
is enforced by the separate DMA transaction tracker described below.

## 5. NPU Request Arbitration

One pod has sixteen logical DMA channels. The NPU request egress accepts at most one beat per channel per
cycle and fills any request lane that is empty or retiring in that cycle.

Each request carries a two-bit NPU-local QoS class. Class three is selected before class two, class two
before class one, and class one before class zero. Within the same effective class, selection is
round-robin. A continuously blocked request is promoted by one class after every 256 eligible arbitration
cycles, saturating at class three. Acceptance clears its age.

QoS and age do not cross the HBM beat boundary. They select which request occupies an egress lane. Once a
request is buffered in a lane, later priority changes cannot replace it.

The implementation may pipeline request observation, pairwise priority comparison, rank counting, and
grant selection. The channel producer must therefore obey the ready/valid rule and keep valid plus every
payload/QoS field stable until `request_ready_o` completes the transfer. `request_ready_o` means that the
request was loaded into one physical HBM lane; speculative queue admission is prohibited at this boundary.
Pipelining may delay an eligible request but must not reduce the five-beat-per-cycle saturated issue rate.

## 6. Local-Tag Allocation and Outstanding Tracking

The local-tag allocator reserves one of 256 identities owned by each logical DMA channel before a beat is
placed in a channel beat buffer. The allocator accepts one claim and one release opportunity per channel
per cycle. A tag is released only after its response is consumed. Released tags become visible to the
allocator on the following cycle, avoiding a combinational response-to-allocation priority path while
preserving one claim and one release per channel per cycle after initial turnover. Detailed claim/release
semantics are defined in `npu_dma_data_path_v0.1.md`.

The NPU DMA tag tracker implements the ADR-0002 identity space as sixteen independent sets of 256
channel-local tags. An allocation is committed only after the corresponding request is accepted by the
HBM request egress. A retirement is committed only after a response is consumed by its destination DMA
channel. The tracker accepts one allocation and one retirement event per logical channel per cycle, which
is greater than the five request and five response events available at the external beat boundary.

Allocation of an already-outstanding tag is rejected and emits a one-cycle duplicate-allocation pulse.
Retirement of a tag that is not outstanding emits a one-cycle unknown-retirement pulse. Retiring and
reallocating the same tag in the same cycle is legal and leaves that tag outstanding. `empty_o` and
`full_o` are derived from the authoritative 4,096-bit state. The aggregate outstanding-count telemetry
lags accepted state changes by two service-clock cycles; it is not an admission-control input. The sticky
protocol-error diagnostic lags the first error event by one service-clock cycle.

The tracker records lifetime but does not choose channel-local tag numbers, define descriptor fields,
perform address translation, or convert beat status into the runtime completion ABI. Its 512-byte state
is implemented as a concurrent bitmap with grouped write-enable buffering. Mapping it onto the current
minimum 256-by-32 KD28 true-dual-port macro would waste 31 of 32 bits per entry and require a synchronous
read-modify-write schedule that cannot preserve the required per-channel allocation-plus-retirement
throughput.

## 7. Ordering, Faults, and Exclusions

Reads and writes share request lanes and the 625-byte/cycle long-run service budget. No implicit coherence,
barrier, atomic operation, retry, cancellation, or address translation exists at this boundary. A status
other than `OK` is reported to the owning DMA operation; automatic replay requires a future versioned
fault-policy contract.

This revision excludes burst headers, gather/scatter descriptors, protection domains, interrupt or runtime
completion ABI, HBM controller timing, and PHY behavior. Multi-beat DMA operations are sequences of tagged
single-beat transfers.

## 8. Required Evidence

The NPU request egress requires:

- zero-warning lint for the production source list;
- self-checking reset, five-lane saturation, simultaneous refill/retire, and randomized backpressure tests;
- payload-stability checks for every stalled lane;
- no-loss/no-duplication tag and data scoreboarding;
- bounded starvation evidence for age promotion; and
- an explicit `ANALYTICAL` label on 640 GB/s raw and 625 GB/s accepted-bandwidth calculations.

The NPU response router additionally requires:

- five simultaneous responses targeting one channel to retire in contract order;
- five-lane-per-cycle acceptance with independent channel-output backpressure;
- stable output payload while a destination channel is stalled;
- no-loss, no-duplication, per-channel ordering, malformed-partition drop, and sticky-error checks; and
- accepted, delivered, dropped, and backpressure counter checks after pipeline drain.

Both leaves require an automated mapped pre-layout STA gate at the logical 1 GHz target. The generic gate
uses a 1.000 ns period, 0.030 ns clock uncertainty, 0.050 ns input/output delays, and 0.005 pF output load,
and fails on negative setup slack or any max slew, capacitance, or fanout violation. Generic-cell evidence
does not constitute KD28 signoff; selected KD28 standard-cell Liberty views, RC corners, clock-tree
assumptions, and post-route parasitics are required for that claim.

The outstanding-tag tracker additionally requires exhaustive fill and drain of all 4,096 identities,
duplicate-allocation and unknown-retirement injection, same-cycle retirement and reuse, randomized
bitmap scoreboarding, telemetry-pipeline checks, zero-warning lint and synthesis-readiness, and the same
mapped 1 GHz generic STA gate.

The local-tag allocator requires the corresponding exhaustive claim/drain, full-pool failure,
release/reclaim turnover, unknown-release, randomized free-bitmap, and mapped 1 GHz generic STA evidence.
