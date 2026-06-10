# KDLink SerDes Simulation Models

This directory provides two model levels for the ten-lane, 66-bit-block KDLink digital PCS/PMA boundary.
All models are vendor-neutral and redistributable.

## Model Levels

| Source | Purpose |
| --- | --- |
| `kdlink_v2_serdes_channel_model.sv` | Stable compatibility model for existing KDLink tests |
| `kdlink_v2_serdes_link_model.sv` | Stable two-direction compatibility wrapper |
| `kdlink_v2_serdes_lane_full_model.sv` | Lane state, locks, elastic delay, deterministic jitter/errors, burst faults, overflow, counters |
| `kdlink_v2_serdes_channel_full_model.sv` | Parameterized lane array, aggregate state and telemetry |
| `kdlink_v2_serdes_link_full_model.sv` | Independently controlled full-duplex advanced link |
| `kdlink_v2_serdes_profile_pkg.sv` | Compile-time rate and encoding constants |

The advanced lane state sequence is `DOWN -> CDR_LOCK -> BLOCK_LOCK -> READY`. Signal loss, receiver-not-
ready, or forced lock loss flushes the lane's elastic queue and requires reacquisition. The channel reports
`DOWN`, `TRAINING`, `UP`, or `DEGRADED` from the aggregate lane states.

## Fault and Timing Controls

- Static propagation and deterministic per-lane skew.
- Optional periodic extra queue delay. The elastic FIFO preserves order; if it fills, the incoming block
  is dropped and counted.
- Explicit block drop and corruption, deterministic every-N-block corruption, and configurable burst
  corruption. Drop takes precedence over corruption.
- Per-lane signal detect, receiver ready, forced loss of lock, CDR lock, block lock, ready, delivered,
  dropped, corrupted, overflow, and retrain accounting.
- Independent A-to-B and B-to-A fault controls in the advanced full-duplex wrapper.

The corruption mask defaults to both 64b/66b header bits, making PCS block-lock loss observable. Jitter is
a digital queue-delay abstraction, not random phase noise. Periodic and burst errors are deterministic so
tests can reproduce them exactly.

## Rate Profiles

| Profile | Line mode | Parallel block capacity | KDLink use |
| --- | --- | ---: | --- |
| `profiles/serdes_25g_nrz.yaml` | 25.78125 Gbit/s NRZ | 390.625 M 66-bit blocks/s/lane | Lower-rate reference |
| `profiles/serdes_53g_pam4.yaml` | 53.125 Gbit/s PAM4 | 804.924 M blocks/s/lane | Cannot directly sustain 1 GHz groups |
| `profiles/serdes_106g_pam4_rate_adapted.yaml` | 106.25 Gbit/s PAM4 | 1.609848 G blocks/s/lane | Selected capacity point with rate adaptation |

The logical KDLink interface offers ten 66-bit blocks per 1 GHz group cycle. That equals a 66 Gbit/s
serial equivalent per lane, 660 Gbit/s encoded per slice, 640 Gbit/s PCS client data, and 64 GB/s of
512-bit KDLink payload per direction. This is an `ANALYTICAL` logical rate only.

It must not be mapped directly to a 66 Gbit/s GTM mode. AMD DS956 identifies the PAM4 interval above
58 Gbit/s and below 76 Gbit/s as unavailable. The selected public reference is therefore 106.25 Gbit/s
PAM4 with a digital rate adapter. At 106.25 Gbit/s the physical capacity is about 1.609848 billion 66-bit
blocks/s/lane, so the 1 GHz logical group interface uses about 62.12 percent of that capacity. The line-
rate parameters are metadata and validation guards; the behavioral model clock remains `clk_i`.

## Instantiation

Compile the profile package before the advanced models, then instantiate either the channel or link:

```systemverilog
kdlink_v2_serdes_channel_full_model #(
    .LANES(10),
    .LINE_RATE_KBPS(106250000),
    .MODULATION_BITS_PER_SYMBOL(2),
    .PROPAGATION_CYCLES(3),
    .MAX_LANE_SKEW_CYCLES(2),
    .CDR_LOCK_CYCLES(16),
    .BLOCK_LOCK_CYCLES(16)
) u_serdes_channel (/* named ports */);
```

The machine-readable logical baseline is [`serdes_v0.1.yaml`](serdes_v0.1.yaml). The profile YAML files
contain the exact parameter values and primary-source URLs.

Use `serdes_compat.f` for the stable existing channel/link pair or `serdes_full.f` for the advanced lane,
channel, and full-duplex hierarchy. Both file lists are rooted at the repository root. The advanced
full-duplex wrapper exposes separate administration, signal-detect, receiver-ready, forced-lock-loss,
periodic-error, and explicit fault controls for each direction.

## Validation

Run `make -C simulator/kdlink model` to validate the YAML schema, logical-rate derivations,
physical-profile capacity, and RTL default parameters. Run `make -C simulator/kdlink rtl` for the
complete 61-test manifest. Expected signatures
include `[FUNCTIONAL_SIM PASS] kdlink_model`, `[RTL_SIM PASS] serdes_full_lane`,
`[RTL_SIM PASS] serdes_full_link`, and the final `[RTL_SIM PASS] 61 test(s)`. Generated logs are under
`simulator/kdlink/work/`. Integrators should next add board/device-specific channel and vendor-transceiver
tests without treating these digital models as electrical compliance evidence.

## Physical Boundary

These models do not implement PLL/CDR phase behavior, TX FIR, RX CTLE/DFE, adaptation algorithms, PAM4
levels, random/deterministic jitter distributions, insertion loss, crosstalk, S-parameters, eye masks,
FEC, IBIS-AMI, package/board behavior, or vendor transceiver calibration. Electrical and BER compliance
requires the selected device, package, board channel, vendor wizard configuration, and licensed analog
models. The Liberty files under `Library/timing/interfaces/` cover only the front-end digital boundary.
