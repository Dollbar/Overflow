# KDLink-v2 Multi-Board Simulation Environment

Status: `SIM-ENV-V1`. This specification defines the portable digital verification environment below the
KDLink logical-flit boundary and above any analog channel or implementation-specific SerDes macro.

## 1. Scope

The environment represents a 32-NPU chassis as eight card slots with four NPU endpoints per card. Every
NPU exposes eight bonded KDLink ports, each containing two independent 512-bit slices. The eight ports
connect to eight independent 32-port KDSwitch planes on the baseboard.

The simulation stack contains four explicit layers:

1. Logical flit and collective RTL.
2. Digital PCS with ten 66-bit blocks per slice cycle.
3. Behavioral SerDes channels with training state, propagation latency, lane skew, deterministic error
   injection, lane failure, and per-direction counters.
4. Card-slot and baseboard topology with card presence, reset completion, plane enable, and per-slice
   link state.

The environment does not model analog eye opening, insertion loss, crosstalk, package parasitics, CDR
jitter transfer, equalizer coefficients, connector S-parameters, or a foundry/vendor SerDes macro.

## 2. Fixed Topology

| Parameter | Value |
| --- | ---: |
| Card slots | 8 |
| NPUs per card | 4 |
| NPU nodes | 32 |
| Switch planes | 8 |
| Slices per bonded port | 2 |
| Slices per NPU | 16 |
| PCS lanes per slice | 10 |
| PCS block width | 66 bits |

Node `n` belongs to slot `n / 4` and has local card index `n % 4`. Endpoint slice index is
`node * 16 + plane * 2 + slice`. This formula is the single mapping contract shared by the SystemVerilog
package, the Python topology model, and all scoreboards.

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

The versioned executable parameters are in
`../../Library/models/kdlink/serdes/serdes_v0.1.yaml`. Defaults are a 1 GHz logical group clock, three
cycles of base propagation, up to two deterministic skew cycles, and 16 compatibility-model training
cycles. The advanced model separates CDR and block lock, uses an order-preserving elastic queue for added
delay, and reports overflow and retrain counters. Lane `n` in the compatibility model has
`PROPAGATION_CYCLES + n % (MAX_LANE_SKEW_CYCLES + 1)` cycles of synchronous source-to-receiver latency.
Administrative down flushes every lane; lane-down flushes that lane. Drop takes precedence if drop and
corruption are requested together.

At one group per cycle, a slice carries 660 Gbit/s of encoded blocks, 640 Gbit/s of PCS client data, and
512 Gbit/s (64 GB/s) of KDLink payload per direction. The one-active-slice v0.1 baseline is 64 GB/s per
port and 512 GB/s across eight ports per NPU. Two active slices provide only an analytical 128 GB/s per-port
ceiling. These are digital-model rates, not physical serial-lane claims.

The implied 66 Gbit/s/lane value is a logical serialization equivalent, not the selected physical line
rate. Public AMD GTM parameters support 53.125 and 106.25 Gbit/s PAM4 operating points but exclude the
58-to-76 Gbit/s interval. The v0.1 physical planning profile therefore uses 106.25 Gbit/s PAM4 and an
explicit rate adapter to the 1 GHz logical group clock. The 25.78125 Gbit/s NRZ and 53.125 Gbit/s PAM4
files are alternative capacity profiles, not drop-in 64 GB/s mappings.

## 4. Card and Baseboard Contract

A card is online only when its slot is present and reset completion is asserted. Each of its 64 slice paths
is independently enabled by SerDes link status. The baseboard additionally gates every path by plane
enable. Removing a card or disabling a plane immediately blocks new ingress traffic from the affected
paths and prevents delivery into the unavailable endpoint.

The baseboard model wraps the synthesizable `kdlink_v2_fabric32` rather than replacing its allocator or
routing behavior. The hierarchy therefore validates slot mapping and failure isolation while retaining the
real KDSwitch RTL data path.

## 5. Evidence and Acceptance

`FUNCTIONAL_SIM` must cover mapping, route construction, fault state, and JSON topology validation.
`RTL_SIM` must cover:

- SerDes latency and lane-skew preservation.
- Full-duplex PCS traffic with steady-state one block group per cycle.
- Deterministic corruption, drop, lane-down, and retraining behavior.
- Eight-card, 32-node baseboard permutation traffic with all 512 slice paths active.
- Card removal and plane isolation without traffic leakage.

These tests establish digital behavior at the declared clock. They do not establish post-layout frequency,
analog SerDes line rate, signal integrity, or hardware interoperability.
