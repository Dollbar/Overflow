# NPU System RTL Verification

This directory owns self-checking RTL tests for NPU integration blocks outside the frozen Tensor/Vector
compute leaf. Production sources remain under `rtl/npu/`; this tree contains testbenches and generated
build output only.

Run the DMA HBM request/response lint, synthesis-readiness, and simulation gate from the repository root:

```sh
make npu-system-test
```

The request test drives all sixteen DMA channels and checks five-beat-per-cycle issue, random independent
HBM lane backpressure, stalled-payload stability, tag/data scoreboarding, simultaneous retire/refill, QoS
age promotion, counters, and reset-visible empty state. The response test checks five simultaneous
same-channel responses, five-lane acceptance, random independent destination stalls, stable output payload,
per-channel ordering, no loss/duplication, malformed-partition drop, sticky error, counters, and drain. The
tag-tracker test exhaustively fills and drains all 4,096 identities, checks same-cycle retirement/reuse,
injects duplicate and unknown events, and runs a randomized bitmap and telemetry scoreboard.
The local-tag allocator test exhaustively claims and releases the same identity space, checks full-pool
failure, release/reclaim turnover, unknown release, and a randomized free-bitmap scoreboard.
The status-monitor test drives all four frozen response classes across sixteen simultaneous commit inputs,
checks randomized per-class accumulation, sticky non-OK observations, pipeline drain, and reset clearing.
The integrated-boundary test submits 1,536 mixed read/write beats across all sixteen channels, randomizes
five request lanes and sixteen response consumers independently, loops ordered HBM responses back through
the router, checks every tag and payload field, validates all four delivered-status counters, quiesces and
drains during active traffic, resumes admission, checks the outstanding high-watermark, and requires
complete final drain.

The DMA address-generator test checks ready/valid-stable linear, two-dimensional, three-dimensional, and
overlapping-stride sequences plus malformed version, alignment, capacity-overflow, completion-backpressure,
clear, and reset behavior against the versioned NPU-local DMA command contract.

The channel-mover test covers both transfer directions, tag metadata, HBM and SRAM stalls, completion
backpressure, and error drain. The engine test exercises all sixteen movers, four total contexts per
channel, five-lane issue, quiesce, and completion routing. The shared-SRAM and Pod tests cover bank
conflicts, read-before-write behavior, end-to-end HBM/SRAM round trips, and exact synthesis mapping to 256
`KD28_SRAM_SDP_2048X256` macros.

Run the mapped generic pre-layout STA gate with a readable Liberty path supplied by the caller:

```sh
make npu-system-sta LIBERTY=/path/to/standard_cells.lib
```

The checked Nangate45 adapter can be selected without a workstation-specific path:

```sh
make npu-system-sta \
  LIBERTY=/path/to/NangateOpenCellLibrary_typical.lib \
  CELL_MAP=verification/npu/system/STA/scripts/nangate45_cells_map.v \
  ABC_CONSTR=verification/npu/system/STA/scripts/abc_nangate45.constr \
  DRIVING_CELL=BUF_X1 DRIVING_PIN=Z
```

No repository target contains a workstation-specific Liberty path. The gate constrains all eight production
tops at 1.000 ns with 0.030 ns uncertainty, 0.050 ns input/output delays, and 0.005 pF output load. It fails
on setup, max slew, max capacitance, or max fanout violations. Passing evidence is `GENERIC_SYNTH`; it is
not HBM controller bandwidth, post-layout closure, or KD28 foundry signoff.
