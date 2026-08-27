# KDLink Simulator

This package contains the portable KDLink simulation sources. It verifies the logical link, bonded
port, digital PCS, behavioral SerDes channels, configurable card slots, baseboard fabric, NIC/CDC boundary, 32-port
switch, 32-node fabric, and collective data path against the synthesizable RTL in `rtl/kdlink/`.

## Directory Layout

```text
simulator/kdlink/
├── manifest.json          # RTL test inventory, dependencies, and pass signatures
├── Makefile               # Short regression entry points
├── pkg/                   # Shared protocol types, pack/unpack, and CRC helpers
├── model/                 # Bit-exact protocol and analytical fabric reference
│   ├── collective_model/  # Shared bit-field and CRC primitives
│   ├── kdlink_model/      # Protocol, topology, bandwidth, and cluster-inference models
│   ├── system/             # Card-slot and baseboard behavioral wrappers
│   └── tests/             # Functional-model tests
├── config/                # Stable chassis and channel configurations
├── scripts/run.py         # Portable Verilator and pytest runner
├── vip/                   # Stream interface, source BFM, and passive checker
└── tb/
    ├── unit/              # Codec, replay, scheduler, deskew, and tensor-bank tests
    ├── subsystem/         # Bonded port, PCS, NIC, CDC, switch, and reverse control
    └── system/            # 32-node fabric, baseboard, direct traffic, and collective tests
```

Reusable digital SerDes sources are repository dependencies under
`Library/models/kdlink/serdes/`; the test manifest references them by repository-relative path.

All generated files are written to the git-ignored `simulator/kdlink/work/` directory. No waveform, log, binary, timing library,
process design kit, or local tool path is part of this package.

## Requirements

- Python 3.10 or newer
- Verilator 5.x for `RTL_SIM`
- pytest for `FUNCTIONAL_SIM`
- A C++ compiler and GNU Make, as required by Verilator

Install repository development dependencies with:

```bash
python3 -m pip install -r requirements-dev.txt
```

The runner discovers `verilator` from `PATH`. It does not require Vivado, a technology library, OpenSTA,
or an analog SerDes model because the tested boundary is the digital PCS/PMA streaming interface.
`config/kdlink_toolchain.json` records the supported and validated open-tool versions, and
`make kdlink-preflight` validates tools, repository dependencies, path containment, and host-path hygiene.

The SerDes model is intentionally vendor-neutral. It models ten 66-bit lanes, deterministic propagation
latency, lane skew, training state, lane availability, corruption/drop injection, and repeatable BER
events. It does not model analog equalization, CDR, eye diagrams, package loss, or vendor macro behavior.

## Running Tests

From the repository root:

```bash
make -C simulator/kdlink list
make -C simulator/kdlink model
make -C simulator/kdlink unit
make -C simulator/kdlink subsystem
make -C simulator/kdlink system
make -C simulator/kdlink all
```

The complete manifest contains 61 RTL tests. `JOBS` and `TIMEOUT` are portable Make variables rather than
host-specific settings, for example `make -C simulator/kdlink rtl JOBS=2 TIMEOUT=1800`.

Run one RTL test by its manifest name:

```bash
python3 simulator/kdlink/scripts/run.py --test slice
```

Limit Verilator build parallelism when memory is constrained:

```bash
python3 simulator/kdlink/scripts/run.py --group all --jobs 2
```

Report the analytical per-tier bandwidth, link-equivalent, failure-headroom, and BDP contract for one
deployment. The default is the worst-case 1:1 nonblocking profile with both slices active:

```bash
python3 simulator/kdlink/scripts/report_bandwidth.py 15132 --profile nonblocking
python3 simulator/kdlink/scripts/report_bandwidth.py 1048576 --profile balanced --json
python3 simulator/kdlink/scripts/report_bandwidth.py 15132 --profile balanced \
  --cross-tier-fractions 1,0.5,0.25,0.125,0.0625 \
  --reduction-factors 1,1,1,1,1
```

Run compressed cluster-inference simulation. The example inputs are explicitly analytical planning
workloads; the current baseline uses one active slice. Uniform overrides use `--active-slices 2` or
`--active-planes 7`. Six-entry leaf-through-T5 vectors allow local changes without silently modifying
unrelated tiers:

```bash
python3 simulator/kdlink/scripts/run_cluster_inference.py \
  simulator/kdlink/config/inference_dense.json
python3 simulator/kdlink/scripts/run_cluster_inference.py \
  simulator/kdlink/config/inference_moe.json --json
python3 simulator/kdlink/scripts/run_cluster_inference.py \
  simulator/kdlink/config/inference_failure.json --active-slices 2
python3 simulator/kdlink/scripts/run_cluster_inference.py \
  simulator/kdlink/config/inference_moe.json \
  --slices-by-tier 2,1,1,1,1,1 --planes-by-tier 8,8,8,8,8,8
python3 simulator/kdlink/scripts/run_cluster_inference.py \
  simulator/kdlink/config/inference_serving.json
```

`--oversubscription-by-tier` accepts five T1-through-T5 ratios. `--requests` and
`--arrival-interval-us` override the serving section and produce deterministic FCFS cluster-batch P50/P95/P99
latency, TTFT, queue, throughput, and offered-load metrics. Single-run throughput is explicitly emitted both
per DP replica and for the whole cluster; the compatibility `generated_tokens_per_second` JSON field remains
the per-DP-replica value. Utilization is not clipped at one, so offered-load overload remains visible.

The optional `--output simulator/kdlink/work/<name>.json` writes a generated report below the ignored work
directory. A maximum-scale run retains compressed communication cohorts and sparse
tier/group/plane/direction resources; it does not create one Python or RTL object per NPU, token, or packet.

## Evidence Boundary

- Model tests produce `FUNCTIONAL_SIM` evidence for packet fields, CRC, PCS transforms, bonding order,
  topology routing, homogeneous and mixed card-directory mapping, link state, multidomain route contexts,
  analytical capacity calculations, per-tier bandwidth/oversubscription/N+1/BDP dimensioning, exact
  TP/EP/PP/DP hierarchy crossings, independent tier/group/plane/direction contention, logical-VC byte
  attribution, per-tier capacity policy, and compressed dense/MoE cluster-inference traffic propagation with
  deterministic serving-tail evaluation.
- SystemVerilog testbenches produce `RTL_SIM` evidence only after the compiled RTL emits the exact pass
  signature recorded in `manifest.json`. The added `serdes_pcs_link` test covers full-duplex PCS traffic
  through a skewed channel; `baseboard32` covers eight cards, 32 nodes, card removal, plane isolation,
  and per-slice link isolation. `multiboard_e2e` composes packetizer/CRC, PCS, SerDes, depacketizer,
  NACK, and the RTL replay buffer for an exact-once retry path. `endpoint_credit_recovery` connects two
  reliable endpoints across asynchronous collective and PHY clocks and checks credit exhaustion, cumulative
  credit recovery, retry, exact commits, and control-VC progress. `four_node_full_duplex` drives 1,024
  continuous 512-bit payload flits per node through a four-node ring and requires II=1, zero data-path
  bubbles, 64 GB/s in each direction, and 128 GB/s aggregate at a 1 GHz logical simulation clock.
  `reduction_dtype_ii1` drives a 4,096-flit mixed INT32/FP32/FP16/BF16 stream through the 512-bit SUM
  pipeline and requires bit-exact lane results, aligned metadata, and zero output bubbles.
  `route_context_codec` toggles every mutable Route Context field, checks bit-exact round trips, and rejects
  unsupported policy, length, logical-VC, and reserved-bit encodings. `route_pair_tx` directly checks the
  synthesizable ACK barrier with complementary identities, unrelated ACKs, multi-flit ordering, hop-local
  retry/VC normalization, and reset recovery. `domain_adapter` checks local schema-2 bypass, schema-3
  Route Context forwarding and destination consumption, packet ownership under backpressure, and malformed
  context/packet rejection for the direct two-domain profile.
  `route_context_reliable` connects two optional-schema reliable endpoints through two PCS instances,
  ten lanes of the repository-provided digital SerDes link model, and the independent reverse channel. It
  injects CRC faults into both the Route Context and its following data packet, requires NACK-driven VC6
  replay, exercises the synthesizable Route Context ACK barrier, checks exactly-once local delivery using
  the preserved logical VC, and returns a schema-2 message-type-9 commit through the opposite endpoint,
  PCS, and ten-lane SerDes link to release the source transaction. `multidomain_bonded` extends the forward
  transport to two route-pair controllers, two
  logical slices, four PCS instances, two repository-provided SerDes links totaling 20 lanes, independent
  reverse channels, context and data fault injection, and one exact commit per slice. `spine_router`
  exhaustively covers all destinations in the four-domain and eight-domain profiles, including hop
  decrement, packet lock, backpressure stability, and exhausted-route rejection.
  `route_stage_scale` exhaustively checks all 256 destination domains across a real top/middle/leaf cascade,
  packet lengths 1 through 16, VC6 replay, and end-to-end backpressure. `route_stage_profiles` adds the one-
  and two-stage profiles plus malformed-packet recovery. `global_commit_window`, `global_commit_codec`, and
  `global_transaction_stress` cover back-to-back duplicates, protected direct-map collisions, legal and
  reserved status encoding, and all sixteen slots. `global_recovery` drops the first destination commit ACK,
  applies a route soft reset, retransmits under a new topology epoch, and requires exactly one destination
  delivery plus source release. `hierarchical_collective` checks all six operations, 128 randomized valid
  configurations, invalid count/root/key/index cases, invalidation, command stability under backpressure,
  and illegal-state recovery.
  `reliable_endpoint_e2e` is the canonical KDLink reliability closure: two autonomous 8-VC endpoints
  run on independent core clocks, cross registered CDC FIFOs, exchange forward traffic through two PCS
  instances and the full-duplex digital SerDes model, and return 128-bit ACK/NACK/credit traffic through
  an independent delayed reverse-channel model. The test covers credit exhaustion and cumulative recovery,
  an injected forward CRC fault, autonomous NACK, VC6 replay, exact-once commit, duplicate suppression,
  and replay-window release in both directions.
  `card_directory` exhaustively checks 1/2/4/8/16/32-NPU homogeneous layouts, a mixed layout, atomic
  shadow commit, epoch and descriptor rejection, card isolation, control-phase collision recovery, and
  2/3/1/14/28-node partial leaves corresponding to 2/3/33/78/15,132 total-NPU deployments.
  `card_profiles` composes that directory with the real 32-node fabric and checks card removal/reset plus
  plane and slice isolation without changing the logical node or wire encodings.
  `scale_route_codec` checks the 2-, 3-, and 473-leaf route profiles used by 33-, 78-, and 15,132-NPU
  deployments, including the first inactive domain. `distributed_collective` checks that the matching
  partial-leaf masks survive directory commit and remain unchanged through collective command issue.
- The reusable VIP is dependency-free SystemVerilog. `kdlink_tb_pkg` supplies bit-exact schema-2/3/4
  header, Route Context, and Global Commit codecs plus capability-aware legality helpers;
  `kdlink_stream_if` supplies valid/ready source tasks and modports. `kdlink_stream_monitor` checks CRC,
  capability gates, control-payload legality, packet ownership, flit sequence, completion, and Route
  Context pairing with the declared following-packet identity and length. Extension acceptance is disabled
  by default and enabled explicitly through monitor parameters. `vip_stream` self-checks backpressure,
  normal and corrupted traffic, both extension schemas, malformed reserved fields, multi-flit traffic, and
  sequence-error recovery. `env_pkg` exhaustively round-trips all 512 legacy endpoint slices and checks all
  six 1/2/4/8/16/32-NPU card codes; `serial_if` separately checks the vendor-neutral digital lane boundary.
- A declared bandwidth, clock, or latency formula remains `ANALYTICAL` unless the corresponding RTL test
  measures it. Simulation does not establish post-layout frequency or physical SerDes performance.
  The full-duplex result is therefore a logical-interface `RTL_SIM` measurement, not a PHY or STA claim.

The system tests use large, deliberately parallel RTL structures and therefore require substantially more
compile memory and time than the unit tests.

The topology contract is documented in `specs/kdlink/simulation_environment.md`, and the machine-readable
baseline is `simulator/kdlink/config/chassis32.json`.
