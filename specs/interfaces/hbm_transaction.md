# Abstract HBM Transaction Contract v0.1

Status: functional-preview baseline

## Boundary

The v0.1 HBM boundary is a vendor-neutral transaction service between future DMA logic and an external
memory environment. It is not an AXI, JEDEC HBM, controller DFI, or PHY pin contract. A later RTL adapter
must map this contract to a selected controller without changing software-visible address semantics.

## Request

| Field | v0.1 rule |
| --- | --- |
| `partition` | Explicit integer in `[0, 7]` |
| `address` | Partition-local byte address, aligned to 128 bytes |
| `length` | Positive multiple of 128 bytes, at most 4,096 bytes |
| `tag` | Caller-owned completion identifier |
| `write_data` | Exactly `length` bytes for a write; absent for a read |
| `byte_enable` | Optional one-byte mask entry per write byte; every entry is `0` or `1` |
| `qos` | Non-negative priority used by the optional FR-FCFS scheduler |

Requests may be accepted independently by each partition until its outstanding limit is reached. A
rejected request has no side effect and must be retried by the caller.

## Response

A response returns the partition, address, tag, operation type, completion cycle, status, corrected-bit
count, and read data. Write responses carry no data. Requests accepted by one partition complete in issue
order in v0.1; different partitions may progress independently. Unwritten addresses read as zero in the
portable sparse model. Status is `OK`, `ECC_CORRECTED`, `ECC_UNCORRECTABLE`, or `DATA_ERROR`.

## Clock, Latency, and Bandwidth Semantics

The model clock is an explicit logical 1 GHz clock, so one model cycle is 1 ns. Latency is measured from
the cycle in which a request consumes bandwidth tokens and is issued, not from the earlier API acceptance
call. Queueing behind older requests or waiting for tokens adds to observed acceptance-to-response time.

Each partition has one shared read-plus-write payload budget of 625 bytes per logical cycle. Reads and
writes consume the same tokens; the target is not 625 GB/s read plus another 625 GB/s write. The integer
token bucket permits 128-byte-aligned transactions while preserving the long-run byte rate. It is capped
at one maximum-size transaction, so an idle partition may accumulate a burst credit of at most 4,096
bytes.

The `nominal` and `stress` profiles use fixed service latency and FIFO issue. The `banked_nominal` and
`banked_stress` profiles additionally decode channel, pseudo-channel, bank group, bank, row, and column;
track open rows; apply activation, precharge, minimum-active, column-spacing, direction-turnaround, and
refresh delays; and expose row/refresh counters. This remains a transaction-level timing abstraction. A
multi-beat request uses its first beat for locality and is not expanded into JEDEC commands.

The decimal-unit derivation is:

| Quantity | Formula | v0.1 value |
| --- | --- | ---: |
| Logical cycle | `1e9 / logical_clock_hz` | 1 ns |
| Capacity per NPU | `8 * 24,000,000,000` | 192,000,000,000 bytes (192 GB) |
| Payload rate per partition | `625 B/cycle * 1e9 cycle/s` | 625,000,000,000 B/s (625 GB/s) |
| Aggregate payload rate | `8 * 625 GB/s` | 5,000 GB/s (5 TB/s) |
| Nominal issue-to-completion latency | `500 cycles * 1 ns` | 500 ns |
| Stress issue-to-completion latency | `800 cycles * 1 ns` | 800 ns |

The aggregate rate is the sum of independent partitions under balanced traffic. A hot partition remains
limited to 625 GB/s even if other partitions are idle.

## Baseline Parameters

- Eight partitions and 24,000,000,000 logical bytes per partition.
- 1,000,000,000 Hz logical model clock.
- 128-byte transaction beat.
- 4,096-byte maximum transaction.
- 625 payload bytes per partition per 1 ns logical cycle.
- 500-cycle nominal and 800-cycle stress round-trip latency.
- 4,096 outstanding transactions per partition.

The executable configuration is `../../Library/models/hbm/hbm_v0.1.yaml`. These are logical
architecture parameters with `FUNCTIONAL_SIM` evidence, not physical HBM timing or PPA claims.

## Executable API

`HBMConfig.from_yaml(path)` loads the nominal profile and validates geometry, timing, scheduling, ECC,
capacity, and alignment. `stress`, `banked_nominal`, and `banked_stress` select versioned overrides.
`HBMModel.submit_read` and `submit_write` return `False` for outstanding-limit backpressure or a disabled
partition; malformed transactions raise `ValueError`. Advance time with `tick()` or `run_until_idle()`,
then consume ordered completions with `pop_response()` or `drain_responses()`.

`decode_address()` exposes the configured channel-through-row mapping. `set_partition_enabled()` and
`request_refresh()` control availability. `inject_bit_errors()` installs transient or persistent bit
faults, and `clear_faults()` removes them. ECC correction is evaluated independently for every configured
beat. `drain_events()` returns the bounded event trace.

Counters distinguish accepted read/write bytes, combined payload, issued/completed requests,
backpressure, row hits/misses/conflicts, refresh blocking, read/write turnarounds, and ECC outcomes.
Counter values and tags are unbounded Python integers in the portable model; an RTL adapter must define
finite widths before it becomes a frozen interface.

## Exclusions

This contract intentionally excludes AXI channel timing, atomics, coherence, virtual-to-physical
translation, thermal throttling, power state, exact JEDEC command traces, proprietary timing bins,
controller microarchitecture, command/address pins, PHY behavior, package parasitics, and signal
integrity. The provided bank, refresh, and ECC behavior is configurable verification behavior, not a
replacement for a selected vendor controller or JEDEC-aware model.
