# NPU DMA Front End

Owns the NPU-side descriptor scheduler, address generation, scratchpad mover, coalescing requests, QoS tags,
and data credits. `rtl/memory/` owns the abstract HBM transaction machinery and external-memory behavior.
The boundary between these directories must be versioned in `specs/interfaces/`.

The P0 proposal provisions one engine per pod, 16 logical channels, 64 active descriptors, and 4096 x
128-byte in-flight data beats. At 625 GB/s this 512 KiB window covers the declared 800 ns stress latency
(`ANALYTICAL`). Descriptor/address widths, ordering, cancellation, protection, and errors remain `HOLD`.
Acceptance requires stride, gather/scatter, alignment, backpressure, fault, QoS, and saturation RTL tests.

## Implemented NPU Egress

`npu_dma_hbm_egress` is the NPU-owned request boundary from sixteen logical DMA channels to the five
parallel 128-byte HBM request lanes frozen by ADR-0002 and `specs/interfaces/npu_hbm_rtl.md`. Each lane
has an elastic output register, so its payload remains stable under independent backpressure and a retiring
lane can be refilled without a bubble.

The arbiter applies four base QoS classes, round-robin selection within an effective class, and bounded
age promotion. It constructs the twelve-bit HBM tag from the selected four-bit channel and eight-bit local
tag. Pairwise priority and rank calculation are registered so the five-lane allocator can meet the logical
1 GHz generic-cell timing gate. The upstream ready/valid source must hold its complete request and QoS
stable until the actual lane-load handshake.

`npu_dma_hbm_response_router` implements the matching five-lane response retirement leaf. It routes by the
upper tag bits into sixteen independent elastic channel outputs, preserves the order of same-channel
responses accepted across lanes, and passes the local tag, read data, operation type, and status without
reinterpretation. A wrong-partition response is consumed and dropped with a sticky local protocol error.

`npu_dma_hbm_control_buffer` marks intentional high-fanout boundaries. It is transparent RTL and maps to a
generic buffer only in the supplied generic STA techmap. The selected KD28 flow must replace that mapping
with cells from its approved standard-cell library.

`npu_dma_local_tag_allocator` reserves and releases the 256 local identities owned by each of the sixteen
DMA channels. It uses a two-level free-bitmap priority selection, supports one claim and one release per
channel per cycle, detects full-pool claims and unknown releases, and feeds the independently verified
outstanding tracker. A released tag becomes allocatable on the following cycle so the response path does
not cross the free-tag priority tree in one timing stage.

The default HBM-to-compute path stages through SRAM inside the owning pod and does not traverse the global
NoC. Cross-pod DMA and multicast require the future NoC injection/ejection path. Descriptor address
generation, scratchpad movement, translation, NoC packets, fault conversion into the external completion
ABI, and CDC remain separate work packages. These modules do not implement an HBM controller or PHY.
