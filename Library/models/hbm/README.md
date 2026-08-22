# HBM Simulation Model

This package provides a sparse, versioned HBM transaction model for architecture simulation and
controller-independent verification. It can represent hundreds of gigabytes without allocating the
declared capacity. The stable Python entry points are `HBMConfig`, `HBMModel`, `HBMRequest`,
`HBMResponse`, `HBMAddress`, `HBMEvent`, and `HBMStats`.

`rtl/overflow_hbm_beat_bfm.sv` is the HDL-facing companion. Its ready/valid port transfers one aligned
128-byte beat per accepted request and supports partition, address, tag, byte enable, response
backpressure, sparse storage, bandwidth tokens, ordered latency, and correctable/uncorrectable response
injection. A 4,096-byte transaction is represented by up to 32 consecutive beats; burst assembly remains
the controller-adapter responsibility. The BFM has one ingress beat port, so it is for functional RTL
integration and backpressure checking, not proof of the 625-byte/cycle partition target.

## Parameter Sets

| File or profile | Intended use | Evidence boundary |
| --- | --- | --- |
| `hbm_v0.1.yaml`, `nominal` | Overflow 8 x 24 GB, 5 TB/s logical baseline | `FUNCTIONAL_SIM` baseline |
| `hbm_v0.1.yaml`, `stress` | Fixed 800-cycle response latency | Configured stress scenario |
| `hbm_v0.1.yaml`, `banked_nominal` | FR-FCFS, bank/row timing, staggered refresh | Transaction-level timing abstraction |
| `hbm_v0.1.yaml`, `banked_stress` | FIFO, one issue/cycle, longer refresh and latency | Contention stress abstraction |
| `profiles/hbm3e_24gb_public_reference.yaml` | One public 24 GB HBM3E placement | Capacity/bandwidth `ANALYTICAL` floor |
| `profiles/hbm3e_36gb_public_reference.yaml` | One public 36 GB HBM3E placement | Capacity/bandwidth `ANALYTICAL` floor |

The public reference files use Micron's published HBM3E capacity, channel count, pseudo-channel count,
pin-rate, and bandwidth statements. They intentionally do not invent proprietary command timing. Values
for row size, bank organization below pseudo-channel level, latency, and refresh are labeled simulation
assumptions and remain configurable.

## Modeled Behavior

- Partition-local capacity, independent queues, outstanding limits, and disabled-partition backpressure.
- 128-byte aligned reads and writes up to 4,096 bytes, including byte write enables and caller QoS.
- Sparse zero-filled storage with ordered completion inside each partition.
- A shared read-plus-write token bucket that enforces sustained payload bandwidth.
- Address decoding into channel, pseudo-channel, bank group, bank, row, and column.
- Optional FIFO or first-ready/first-come-first-served scheduling with row-hit, row-miss, and row-conflict
  accounting.
- Optional activation, precharge, minimum row-active, column spacing, read/write turnaround, and refresh
  delays.
- Manual or periodic refresh, partition enable/disable, deterministic transient or persistent bit faults,
  per-beat correction limits, and explicit response status.
- Bounded event history and counters for throughput, backpressure, row behavior, refresh, turnaround, and
  ECC outcomes.

The banked scheduler is a transaction-level abstraction. One accepted transaction consumes its full byte
budget and uses the first beat for command locality; it is not a JEDEC command bus or a DRAMSim-class
per-burst command trace.

## Python Use

```bash
PYTHONPATH=Library/models/hbm .venv/bin/python - <<'PY'
from hbm_model import HBMConfig, HBMModel

cfg = HBMConfig.from_yaml(
    "Library/models/hbm/hbm_v0.1.yaml",
    profile="banked_nominal",
)
hbm = HBMModel(cfg)
hbm.submit_write(0, 0, bytes([0x5a]) * 128, tag=1)
hbm.inject_bit_errors(0, 0, [0], persistent=False)
hbm.submit_read(0, 0, 128, tag=2)
hbm.run_until_idle()
for response in hbm.drain_responses():
    print(response.tag, response.status, response.corrected_bits)
PY
```

`submit_read` and `submit_write` return `False` only for capacity backpressure or a disabled partition.
Malformed requests raise `ValueError`. `request_refresh(partition)` schedules a refresh when refresh is
enabled. `inject_bit_errors` accepts bit offsets relative to the supplied byte address; transient faults
are consumed on the first read, while persistent faults remain until `clear_faults`.

For an RTL simulator, compile `hbm_bfm.f` from the repository root and instantiate
`overflow_hbm_beat_bfm`. Response status encoding is `0=OK`, `1=ECC_CORRECTED`, and
`2=ECC_UNCORRECTABLE`. Expected output is a ready/valid response for every accepted beat; reads of
unwritten locations return zero.

## Validation

Run `make hbm-model` from the repository root. The target executes 27 Python model cases and then compiles
and runs `simulator/memory/tb/tb_overflow_hbm_beat_bfm.sv` with Verilator. Expected terminal signatures
are `[FUNCTIONAL_SIM PASS] hbm_model` and `[RTL_SIM PASS] hbm_beat_bfm`; generated logs are under
`simulator/memory/work/`. Integrators should next bind the beat BFM to their controller adapter and add
adapter-specific burst, reset, and backpressure tests.

## Physical Boundary

This package does not model HBM command pins, AXI timing, PHY training, DBI, lane repair, temperature,
power, package parasitics, exact JEDEC timing bins, or vendor controller queues. Those require the selected
controller and legally redistributable vendor collateral. The corresponding front-end-only Liberty cells
are under `Library/timing/interfaces/`; they are not HBM array timing views.

The normative transaction contract is
[`specs/interfaces/hbm_transaction.md`](../../../specs/interfaces/hbm_transaction.md).
