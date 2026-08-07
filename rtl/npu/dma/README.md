# NPU DMA Front End

Owns the NPU-side already-decoded command queues, address generation, scratchpad mover, QoS tags, and data
credits. `rtl/memory/` owns the abstract HBM transaction machinery and external-memory behavior. The
boundary between these directories is versioned in `specs/interfaces/`.

The v0.1 implementation provisions one engine per pod, 16 logical channels, 64 total command contexts, and
4096 x 128-byte in-flight data beats. At 625 GB/s this 512 KiB window covers the declared 800 ns stress
latency (`ANALYTICAL`). The internal command and completion widths are frozen; KD-ISA descriptors, IOVA
translation, cancellation, protection, runtime completion ABI, gather/scatter, and partial beats remain
`HOLD`.

## Directory Layout

```text
rtl/npu/dma/
  npu_dma_pkg.sv                    Internal command/completion types
  npu_dma_command_queue.sv          Four-context-per-channel finite queue
  npu_dma_address_generator.sv      Aligned 1D/2D/3D address expansion
  npu_dma_channel_mover.sv          One bidirectional HBM/SRAM mover
  npu_dma_engine.sv                 Sixteen movers plus five-lane boundary
  npu_dma_pod.sv                    DMA engine plus pod-shared SRAM integration
  npu_dma_hbm_*.sv                  HBM egress, response, tracking, and telemetry
  npu_dma_local_tag_allocator.sv    Per-channel 256-tag allocator
  npu_dma_tag_metadata_bank.sv      Outstanding read destination metadata

rtl/npu/sram/
  npu_pod_shared_sram.sv            16 MiB, eight-bank, sixteen-client SRAM
  npu_round_robin_arbiter16.sv      Per-bank client arbitration

specs/interfaces/
  npu_dma_command.md           Internal command and completion contract
  npu_dma_data_path.md         Beat, tag, response, and quiesce contract
  npu_hbm_rtl.md                    Five-lane HBM service contract
  npu_pod_shared_sram.md       Pod SRAM client and mapping contract

docs/adr/
  ADR-0002-npu-hbm-egress-lane-geometry.md
  ADR-0003-npu-local-dma-mover-contract.md

verification/npu/system/
  Makefile                          Portable lint/synth/sim/STA entry points
  tb/                               Self-checking unit and Pod tests
  STA/scripts/                      Generic and Nangate45 mapping scripts
  STA/sdc/                          One-gigahertz production-top constraints

requirements/traceability.csv       NPU-017 through NPU-027 evidence links
```

Generated artifacts stay below `verification/npu/system/build/` (or a caller-provided `BUILD_DIR`) and are
not source-controlled. Makefiles derive the repository root from their own location; no workstation path
is embedded in a source list, constraint, or tool target.

The production integration hierarchy is:

```text
npu_dma_pod
  npu_dma_engine
    16 x npu_dma_command_queue
    16 x npu_dma_channel_mover
    1 x npu_dma_hbm_boundary
  npu_pod_shared_sram
    8 logical banks
    256 x KD28_SRAM_SDP_2048X256 fixed macros
```

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

`npu_dma_hbm_status_monitor` observes only responses consumed by their destination DMA channels. It keeps
independent 64-bit modulo counters for OK, corrected ECC, uncorrectable ECC, and data-error responses, plus
sticky seen bits for the three non-OK classes. The monitor is local telemetry; it does not request replay,
change tag retirement, or define a runtime completion status.

`npu_dma_hbm_boundary` integrates the request egress, response router, allocator, tracker, and one complete
beat buffer per logical channel. A source handshake reserves and returns a tag; egress acceptance records
it as outstanding; response consumption retires it, records its frozen two-bit status, and releases only a
tracker-known identity. Channel buffers use a one-cycle non-fall-through turnover and replicated 32-bit
capture enables. A registered per-channel tag-credit mirror drives admission, egress acceptance is
registered before outstanding allocation, and consumed response tags use a one-cycle retirement pipeline.
These stages preserve five-lane throughput while closing the logical 1 GHz generic-cell gate.

The integrated boundary also provides synchronous lossless quiesce. Quiesce closes new channel admission
while all accepted work drains normally, then reports a settled state after three idle cycles so delayed
telemetry is complete. A reset-cleared outstanding high-watermark records observed pressure. These local
mechanisms do not cancel, replay, time out, or discard a transaction.

`npu_dma_pkg.sv` defines the NPU-owned, already-decoded and translated DMA v0.1 command and internal
completion records. `npu_dma_address_generator.sv` expands their aligned X/Y/Z counts and independent HBM
and SRAM row/plane strides into stable full-beat address pairs. It checks version, operation, count,
alignment, capacity, generated-address overflow, and the 16 MiB command limit without interpreting KD-ISA
or an IOVA.

`npu_dma_channel_mover` implements one bidirectional channel with tag-indexed HBM-read metadata, finite
request/response skid buffers, SRAM backpressure, drain-on-error completion, and stable ready/valid
payloads. `npu_dma_engine` combines sixteen movers, four total command contexts per channel, and the
five-lane HBM boundary. `npu_dma_pod` connects that engine directly to the 16 MiB pod-shared SRAM; this
pod-local path does not consume NoC bandwidth.

The default HBM-to-compute path stages through SRAM inside the owning pod and does not traverse the global
NoC. Cross-pod DMA and multicast require the future NoC injection/ejection path. Translation, NoC packets,
fault conversion into the external completion ABI, and CDC remain separate work packages. These modules
do not implement an HBM controller or PHY.
