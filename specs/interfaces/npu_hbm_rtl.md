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

## 5. NPU Request Arbitration

One pod has sixteen logical DMA channels. The NPU request egress accepts at most one beat per channel per
cycle and fills any request lane that is empty or retiring in that cycle.

Each request carries a two-bit NPU-local QoS class. Class three is selected before class two, class two
before class one, and class one before class zero. Within the same effective class, selection is
round-robin. A continuously blocked request is promoted by one class after every 256 eligible arbitration
cycles, saturating at class three. Acceptance clears its age.

QoS and age do not cross the HBM beat boundary. They select which request occupies an egress lane. Once a
request is buffered in a lane, later priority changes cannot replace it.

## 6. Ordering, Faults, and Exclusions

Reads and writes share request lanes and the 625-byte/cycle long-run service budget. No implicit coherence,
barrier, atomic operation, retry, cancellation, or address translation exists at this boundary. A status
other than `OK` is reported to the owning DMA operation; automatic replay requires a future versioned
fault-policy contract.

This revision excludes burst headers, gather/scatter descriptors, protection domains, interrupt or runtime
completion ABI, HBM controller timing, and PHY behavior. Multi-beat DMA operations are sequences of tagged
single-beat transfers.

## 7. Required Evidence

The NPU request egress requires:

- zero-warning lint for the production source list;
- self-checking reset, five-lane saturation, simultaneous refill/retire, and randomized backpressure tests;
- payload-stability checks for every stalled lane;
- no-loss/no-duplication tag and data scoreboarding;
- bounded starvation evidence for age promotion; and
- an explicit `ANALYTICAL` label on 640 GB/s raw and 625 GB/s accepted-bandwidth calculations.
