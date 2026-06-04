# KDLink Simulator

This package contains the portable KDLink simulation sources. It verifies the logical link, bonded
port, digital PCS, behavioral SerDes channels, card slots, baseboard fabric, NIC/CDC boundary, 32-port
switch, 32-node fabric, and collective data path against the synthesizable RTL in `rtl/kdlink/`.

## Directory Layout

```text
simulator/kdlink/
├── manifest.json          # RTL test inventory, dependencies, and pass signatures
├── Makefile               # Short regression entry points
├── pkg/                   # Shared protocol types, pack/unpack, and CRC helpers
├── model/                 # Bit-exact protocol and analytical fabric reference
│   ├── collective_model/  # Shared bit-field and CRC primitives
│   ├── kdlink_model/      # KDLink protocol, PCS, topology, and bonding model
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

The complete manifest contains 54 RTL tests. `JOBS` and `TIMEOUT` are portable Make variables rather than
host-specific settings, for example `make -C simulator/kdlink rtl JOBS=2 TIMEOUT=1800`.

Run one RTL test by its manifest name:

```bash
python3 simulator/kdlink/scripts/run.py --test slice
```

Limit Verilator build parallelism when memory is constrained:

```bash
python3 simulator/kdlink/scripts/run.py --group all --jobs 2
```

## Evidence Boundary

- Model tests produce `FUNCTIONAL_SIM` evidence for packet fields, CRC, PCS transforms, bonding order,
  topology routing, chassis mapping, link state, multidomain route contexts, and analytical capacity
  calculations.
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
- The reusable VIP is dependency-free SystemVerilog: `kdlink_stream_if` supplies valid/ready source
  tasks and modports, while `kdlink_stream_monitor` checks header legality, CRC, flit count, and packet
  completion.
- A declared bandwidth, clock, or latency formula remains `ANALYTICAL` unless the corresponding RTL test
  measures it. Simulation does not establish post-layout frequency or physical SerDes performance.
  The full-duplex result is therefore a logical-interface `RTL_SIM` measurement, not a PHY or STA claim.

The system tests use large, deliberately parallel RTL structures and therefore require substantially more
compile memory and time than the unit tests.

The topology contract is documented in `specs/kdlink/simulation_environment.md`, and the machine-readable
baseline is `simulator/kdlink/config/chassis32.json`.
