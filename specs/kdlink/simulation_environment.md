# KDLink Multi-Board Simulation Environment

Status: `SIM-ENV-V1`. This specification defines the portable digital verification environment below the
KDLink logical-flit boundary and above any analog channel or implementation-specific SerDes macro.

## 1. Scope

The environment represents a fixed 32-NPU leaf domain using up to 32 physical card slots. Each configured
card contains 1, 2, 4, 8, 16, or 32 NPU endpoints, and one leaf may mix card profiles. Reset selects the
legacy eight-card by four-NPU layout. Every NPU exposes eight bonded KDLink ports, each containing two
independent 512-bit slices. The eight ports connect to eight independent 32-port KDSwitch planes on the
baseboard.

The simulation stack contains four explicit layers:

1. Logical flit and collective RTL.
2. Digital PCS with ten 66-bit blocks per slice cycle.
3. Behavioral SerDes channels with training state, propagation latency, lane skew, deterministic error
   injection, lane failure, and per-direction counters.
4. Card-slot and baseboard topology with card presence, reset completion, plane enable, and per-slice
   link state.

The environment does not model analog eye opening, insertion loss, crosstalk, package parasitics, CDR
jitter transfer, equalizer coefficients, connector S-parameters, or a foundry/vendor SerDes macro.

## 2. Configurable Leaf Topology

| Parameter | Value |
| --- | ---: |
| Maximum card slots | 32 |
| Default card slots | 8 |
| Supported NPUs per card | 1, 2, 4, 8, 16, 32 |
| Mixed card profiles | Supported |
| NPU nodes | 32 |
| Switch planes | 8 |
| Slices per bonded port | 2 |
| Slices per NPU | 16 |
| PCS lanes per slice | 10 |
| PCS block width | 66 bits |

A card descriptor is `{slot_id, base_node_id, npu_count_code}`. Count codes 0 through 5 represent 1, 2,
4, 8, 16, and 32 NPUs; codes 6 and 7 are reserved. Descriptors may leave nodes unconfigured but may not
reuse a slot, overlap node ranges, or extend beyond node 31. Node identifiers are stable across card removal
and directory replacement. The reset-compatible mapping is `slot = node / 4`, `local_npu = node % 4`.

The profile-independent endpoint slice index is `node * 16 + plane * 2 + slice`. The active card directory
resolves `{slot, local_npu}` to `node`; the SystemVerilog package's legacy slot-based helper intentionally
retains only the reset mapping. Shadow configuration becomes active atomically at a quiescent boundary and
only with a newer 16-bit topology epoch.

## 3. SerDes Behavioral Contract

Each unidirectional channel accepts one group of ten 66-bit PCS blocks per cycle. It independently delays
and qualifies every lane. A channel has four observable states:

- `DOWN`: administration is disabled or no lane is available.
- `TRAINING`: all required lanes are available and the training timer is running.
- `UP`: all lanes are available and the training timer completed.
- `DEGRADED`: at least one, but not all, lanes are available.

Data may traverse during `TRAINING` so PCS training blocks can reach the far endpoint. Protocol traffic
must not start until `UP`. Lane drop suppresses `valid` for that lane. Corruption flips the PCS sync-header
bits so the receiving PCS must report block error and lose lock. Deterministic BER injection uses an exact
group period, lane, and bit mask; it is a reproducible stress mechanism, not a physical BER prediction.

The channel has no reverse combinational ready path. Link-level flow control remains the responsibility of
KDLink credit, replay, and elastic buffering.

The reverse channel is an independent 128-bit registered path. It transports cumulative credit, ACK,
NACK, and link-management words and never participates in a same-cycle forward admission decision.
`kdlink_reverse_channel_model` provides deterministic propagation, corruption, and drop controls for
this digital contract.

The versioned executable parameters are in
`../../Library/models/kdlink/serdes/serdes.yaml`. Defaults are a 1 GHz logical group clock, three
cycles of base propagation, up to two deterministic skew cycles, and 16 compatibility-model training
cycles. The advanced model separates CDR and block lock, uses an order-preserving elastic queue for added
delay, and reports overflow and retrain counters. Lane `n` in the compatibility model has
`PROPAGATION_CYCLES + n % (MAX_LANE_SKEW_CYCLES + 1)` cycles of synchronous source-to-receiver latency.
Administrative down flushes every lane; lane-down flushes that lane. Drop takes precedence if drop and
corruption are requested together.

At one group per cycle, a slice carries 660 Gbit/s of encoded blocks, 640 Gbit/s of PCS client data, and
512 Gbit/s (64 GB/s) of KDLink payload per direction. One active slice provides 64 GB/s per port and
512 GB/s across eight ports per NPU. Two active slices provide only an analytical 128 GB/s per-port
ceiling. These are digital-model rates, not physical serial-lane claims.

The implied 66 Gbit/s/lane value is a logical serialization equivalent, not the selected physical line
rate. Public AMD GTM parameters support 53.125 and 106.25 Gbit/s PAM4 operating points but exclude the
58-to-76 Gbit/s interval. The selected physical planning profile therefore uses 106.25 Gbit/s PAM4 and an
explicit rate adapter to the 1 GHz logical group clock. The 25.78125 Gbit/s NRZ and 53.125 Gbit/s PAM4
files are alternative capacity profiles, not drop-in 64 GB/s mappings.

## 4. Card and Baseboard Contract

A card is online only when its slot is present and reset completion is asserted. A card owns
`npu_count * 16` slice paths, each independently enabled by SerDes link status. The baseboard additionally
gates every path by plane enable. Removing a card or disabling a plane immediately blocks new ingress
traffic from the affected paths and prevents delivery into the unavailable endpoint.

The generic leaf model composes the synthesizable `kdlink_card_directory` with `kdlink_fabric32` rather
than replacing allocation or routing behavior. The legacy baseboard model remains as a compatibility test.
The hierarchy validates dynamic slot mapping and failure isolation while retaining the real KDSwitch RTL
data path.

## 5. Evidence and Acceptance

`FUNCTIONAL_SIM` must cover mapping, route construction, fault state, and JSON topology validation.
`RTL_SIM` must cover:

- SerDes latency and lane-skew preservation.
- Full-duplex PCS traffic with steady-state one block group per cycle.
- Deterministic corruption, drop, lane-down, and retraining behavior.
- All six homogeneous card profiles and a mixed-profile 32-node directory.
- Atomic directory commit, stale epoch, overlap, reserved-code, and control-collision rejection.
- Legacy eight-card baseboard traffic plus configurable card removal/reset, plane, and slice isolation.
- Two autonomous KDLink endpoints with all eight VCs, asynchronous core clocks, cumulative credit
  recovery, CRC-triggered NACK, replay through VC6, and exact-once commit.

These tests establish digital behavior at the declared clock. They do not establish post-layout frequency,
analog SerDes line rate, signal integrity, or hardware interoperability.
