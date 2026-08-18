# KDLink Simulator

This package contains the portable KDLink-v2 simulation sources. It verifies the logical link, bonded
port, digital PCS, NIC/CDC boundary, 32-port switch, 32-node fabric, and collective data path against the
synthesizable RTL in `rtl/kdlink/`.

## Directory Layout

```text
simulator/kdlink/
├── manifest.json          # RTL test inventory, dependencies, and pass signatures
├── Makefile               # Short regression entry points
├── pkg/                   # Shared protocol types, pack/unpack, and CRC helpers
├── model/                 # Bit-exact protocol and analytical fabric reference
│   ├── collective_model/  # Shared bit-field and CRC primitives
│   ├── kdlink_model/      # KDLink protocol, PCS, topology, and bonding model
│   └── tests/             # Functional-model tests
├── scripts/run.py         # Portable Verilator and pytest runner
├── vip/                   # Stream interface, source BFM, and passive checker
└── tb/
    ├── unit/              # Codec, replay, scheduler, deskew, and tensor-bank tests
    ├── subsystem/         # Bonded port, PCS, NIC, CDC, switch, and reverse control
    └── system/            # 32-node fabric, direct traffic, and collective tests
```

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
or an analog SerDes model because the tested boundary is the digital PHY streaming interface.

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
  topology routing, and analytical capacity calculations.
- SystemVerilog testbenches produce `RTL_SIM` evidence only after the compiled RTL emits the exact pass
  signature recorded in `manifest.json`.
- The reusable VIP is dependency-free SystemVerilog: `kdlink_v2_stream_if` supplies valid/ready source
  tasks and modports, while `kdlink_v2_stream_monitor` checks header legality, CRC, flit count, and packet
  completion.
- A declared bandwidth, clock, or latency formula remains `ANALYTICAL` unless the corresponding RTL test
  measures it. Simulation does not establish post-layout frequency or physical SerDes performance.

The system tests use large, deliberately parallel RTL structures and therefore require substantially more
compile memory and time than the unit tests.
