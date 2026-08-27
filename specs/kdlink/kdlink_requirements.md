# KDLink Requirements

Status: `RELEASE-CANDIDATE`

Release applicability: Overflow `v0.1`. The product release label is recorded in documentation only;
the stable engineering filenames and design-unit names are release-neutral. `KDL_SCHEMA_VERSION = 2`
is the frozen on-wire schema value and is not a product version label.

This document is the acceptance contract for KDLink. A requirement is complete only when its
implementation and the evidence named in `requirements/kdlink_traceability.csv` both exist. Passing
a component test does not imply that the integrated fabric requirement is complete.

## 1. Scope And Evidence Boundary

KDLink ends at synthesizable digital RTL and vendor-neutral digital behavioral models. It includes
the collective engine, reliable link endpoint, PCS, NIC, routing and switch logic, CDC boundaries, and
portable verification infrastructure.

The release excludes analog SerDes implementation, package and PCB design, foundry libraries, hard-macro
timing models, signal-integrity models, and place-and-route artifacts. A local timing run may reference an
externally supplied Liberty file, but that file and its derived proprietary content must not enter the
repository.

Every performance or correctness statement uses one of these evidence labels:

- `ANALYTICAL`: a checked formula or reference-model result;
- `FUNCTIONAL_SIM`: an executable software-model result;
- `RTL_SIM`: a self-checking simulation of the named RTL boundary;
- `FORMAL`: a property proven for the named RTL boundary and parameter set;
- `STA`: a static-timing result with the clock, library, constraints, corner, and top module recorded.

RTL simulation at a 1 GHz logical clock is not evidence of 1 GHz implementation timing or physical line
rate.

## 2. Frozen Protocol Parameters

| Parameter | KDLink value |
| --- | ---: |
| Forward flit | 640 bits |
| Payload per flit | 512 bits |
| Forward header and CRC | 128 bits |
| Reverse-control word | 128 bits |
| Virtual channels | 8 |
| Maximum packet length | 16 flits |
| Packet sequence space | 4096 |
| Slices per bonded port | 2 |
| PCS lanes per slice | 10 |
| PCS block width | 66 bits |
| Nodes in the reference fabric | 32 |
| Switch planes | 8 |
| Collective contexts | 16 |

The `coll_*` four-VC, 96-bit reverse protocol is a compatibility implementation. It is not KDLink
and must not be connected to KDLink through an implicit width or field adapter.

## 3. Link Endpoint Requirements

### KDL-LINK-001: Per-VC ingress isolation

The canonical endpoint shall provide one independently backpressured ingress queue for each of the eight
VCs. A blocked VC shall not prevent an eligible packet on another VC from being transmitted.

### KDL-LINK-002: Packet-aware arbitration

Normal traffic arbitration shall retain ownership from SOP through EOP. It shall support strict priority
for management, replay, and control roles while providing bounded round-robin service to data VCs.

### KDL-LINK-003: Credit correctness

Forward transmission shall occur only when the selected VC has credit. Credit return shall use monotonic
cumulative totals within a link epoch. Stale, overflow, and underflow conditions shall be detected.

### KDL-LINK-004: No reverse combinational admission path

Forward admission shall depend only on registered local state. Reverse control and digital channel models
shall not create a same-cycle combinational ready path into forward transmission.

### KDL-LINK-005: Autonomous link management

The endpoint shall autonomously perform link initialization, initial-credit exchange, keepalive, timeout
detection, link reset, and epoch recovery. User payload shall be admitted only in the operational state.

### KDL-LINK-006: Reliable packet delivery

The endpoint shall retain every unacknowledged packet, autonomously generate NACK on CRC failure, replay
on NACK or timeout using VC6, and release replay state on a matching ACK.

### KDL-LINK-007: Exact-once commit

The receiver shall not expose partial packets. It shall commit complete valid packets atomically and
suppress duplicate retry packets without suppressing the required ACK response.

### KDL-LINK-008: Independent clock domains

Core, forward-PHY, and reverse-control crossings shall use explicit CDC structures. Multi-bit payloads
shall cross through asynchronous FIFOs or an equivalent stable-data handshake.

## 4. Bonded Port Requirements

### KDL-BOND-001: Two-slice full-rate operation

Both healthy slices shall accept and emit one flit per slice per logical cycle after pipeline fill.

### KDL-BOND-002: Packet integrity across slices

A packet shall be assigned to one slice for its complete lifetime. Reorder logic shall preserve the
defined packet order at the bonded receive boundary.

### KDL-BOND-003: Degraded operation and recovery

After a slice failure, new packets shall use the surviving slice. An in-flight packet affected by the
failure shall be replayed and committed exactly once. Recovery shall not reuse stale credit or ACK state.

## 5. NIC, Router, And Fabric Requirements

### KDL-FAB-001: Canonical endpoint integration

The NIC and reference fabric path shall instantiate or connect through the canonical reliable endpoint;
an older replay-only boundary shall not be presented as integrated reliability evidence.

### KDL-FAB-002: Routing and hop limit

Every forwarded packet shall follow the declared deterministic route and decrement a nonzero hop limit.
An exhausted hop limit or illegal destination shall be rejected and reported.

### KDL-FAB-003: VC role isolation

Management, replay, control, escape, and data traffic shall retain their declared VC roles through the
router. Congested data traffic shall not permanently prevent management or replay progress.

### KDL-FAB-004: Deadlock escape

VC0 shall implement the deterministic escape route. The release shall include a machine-checked proof or
exhaustive bounded property demonstrating the absence of a cyclic escape-channel dependency for the
reference topology.

### KDL-FAB-005: Reference topology

The portable environment shall represent a fixed 32-node leaf domain, up to 32 physical card slots,
8 switch planes, and 2 slices per bonded port, with card, plane, and slice fault isolation. Reset shall
retain the legacy 8-card by 4-NPU layout.

### KDL-CARD-001: Supported card profiles

Each configured card shall contain exactly 1, 2, 4, 8, 16, or 32 NPU nodes. One leaf domain may mix these
profiles while retaining a fixed maximum of 32 mapped NPU nodes.

### KDL-CARD-002: Stable and unique node ownership

Each card descriptor shall contain a physical slot, base node, and NPU-count code. The active directory
shall reject duplicate slots, overlapping node ranges, reserved count codes, and ranges beyond node 31.
Unconfigured nodes are legal but shall remain inactive; removing a card shall not renumber other nodes.

### KDL-CARD-003: Atomic directory update

Card configuration shall use separate shadow prepare, descriptor-write, and commit phases. Commit shall
require a quiescent leaf and a newer 16-bit topology epoch. Readers shall observe the complete old or new
directory, never a partial mixture; simultaneous configuration and commit controls shall be rejected.

### KDL-CARD-004: Card-level fault isolation

A mapped node shall be active only when its owning physical slot is present and has completed reset.
Changing one slot state shall affect exactly the nodes owned by that slot and shall preserve plane and
slice isolation below every remaining active node.

### KDL-CARD-005: Legacy layout compatibility

Without a committed directory update, node `n` shall map to slot `n / 4` and local NPU `n % 4`. The node,
plane, slice, PCS, flit, and global endpoint encodings shall not change when another card profile is used.

## 6. Collective Requirements

### KDL-COLL-001: Descriptor-driven execution

Collective execution shall start from the frozen 512-bit descriptor, validate all required fields, assign
one of 16 contexts, and report completion or a defined error.

### KDL-COLL-002: Required operations

The integrated collective path shall support ReduceScatter, AllGather, AllReduce, AllToAll, AllToAllv,
and point-to-point operation for the 32-node reference configuration.

### KDL-COLL-003: Required reduction types

SUM shall support INT32, FP32, FP16, and BF16 on the integrated 512-bit collective datapath. Results shall
match the declared bit-accurate arithmetic model.

### KDL-COLL-004: Pipeline throughput

After pipeline fill and in the absence of downstream backpressure, the reduction datapath shall sustain
an initiation interval of one 512-bit payload flit per cycle.

### KDL-COLL-005: Concurrent contexts

At least two collective contexts shall make observable forward progress under interleaved issue,
backpressure, and one recoverable link-derived context-block indication. A separate link recovery test shall
verify epoch restoration. Packet ownership and completion shall remain context-exact.

## 7. Verification And Release Requirements

### KDL-VER-001: Portable regression

All functional-model and RTL tests shall run through `simulator/kdlink/scripts/run.py` without a PDK,
vendor simulator, analog model, or network dependency.

### KDL-VER-002: Fault and congestion matrix

The RTL regression shall cover credit exhaustion, reverse-word loss, ACK loss, NACK replay, replay
timeout, forward CRC corruption, duplicate packet arrival, active-packet slice loss, lane degradation,
fabric congestion, reset during traffic, and concurrent collectives.

### KDL-VER-003: Coverage gate

The release shall report line, branch, toggle, and user-defined functional coverage for the canonical
canonical integration boundary. The targets are at least 95 percent line, 90 percent branch, and 95 percent
toggle coverage, with every exclusion documented.

### KDL-VER-004: Formal safety gate

Formal properties shall cover FIFO overflow/underflow prevention under the interface assumptions, credit
conservation, packet ownership from SOP to EOP, exact-once commit, duplicate suppression, replay release,
and bounded management/replay service.

### KDL-VER-005: Static RTL gate

Production RTL shall pass the repository lint gate with no latch, multiple-driver, raw gated-clock,
simulation-only construct, or unresolved-width error. CDC assumptions and synchronizer structures shall
be reported separately from functional simulation.

### KDL-VER-006: Timing gate

OpenSTA shall run on registered module partitions using an external Liberty path supplied at execution
time. The report shall state the actual achieved period for each partition. A 1 GHz claim requires
nonnegative setup slack at a 1.000 ns period for every claimed partition; no flat physical-top claim is
permitted without implementation parasitics.

### KDL-VER-007: Reusable verification package and VIP

The repository-owned SystemVerilog verification package shall provide bit-exact encode, decode, and
legality helpers for the supported schema-2, schema-3, and schema-4 headers and control payloads. The
stream VIP shall independently check CRC, capability gating, header and control-payload legality,
valid/ready transfer accounting, packet ownership, flit sequence, and Route Context pairing with the
declared following-packet identity and length. The environment package shall cover all six supported card
profiles and exhaustively round-trip the frozen 512-slice legacy endpoint map. The serial interface shall
remain a vendor-neutral typed digital boundary and shall be compiled and self-checked separately.

### KDL-REL-001: Release evidence

The release shall contain a requirements traceability report, exact tool versions, test results, coverage
summary, formal summary, STA summary, performance statement, known limitations, and a clean-source audit.
Only repository-owned source and redistributable generated reports may be committed.

## 8. Multidomain Extension Requirements

These requirements are frozen as the KDLink v0.3 multidomain contract on the isolated implementation
branch. The complete increment
includes hop-local transport, 2- through 256-domain deterministic routing, global transaction completion,
route-reset recovery, and hierarchical collective orchestration while reusing the released 32-node leaf
data path.

### KDL-MD-001: Packet-scoped route context

A schema-3 Route Context shall describe one following packet on the same ingress and VC. The adapter shall
check the context format, packet sequence, source and destination leaf nodes, logical plane, packet length,
SOP, and EOP before releasing packet ownership.

### KDL-MD-002: Local and remote isolation

Traffic without a Route Context shall remain on the local schema-2 path. A valid remote context and its
following packet shall remain locked to the remote path. A context targeting the local domain shall be
consumed exactly once and only its following packet shall reach the local output.

### KDL-MD-003: Hierarchical address and topology model

The reference model and RTL shall represent an 8-bit domain identifier, a 5-bit leaf-local node identifier,
2-, 4-, 8-, 16-, 32-, 64-, 128-, and 256-domain topology profiles, deterministic radix-8 stage selection,
and failed-egress masking.

### KDL-MD-004: Hop-local reliable integration

Every inter-domain physical hop shall terminate credit, ACK, NACK, replay, timeout, and link-epoch state in
the canonical reliable endpoint. A source gateway shall not release the following packet until the Route
Context has been acknowledged on that hop, so a Route Context replay cannot arrive after its data. Passing
the Route Context adapter test or a testbench-controlled ACK barrier alone does not complete this requirement.

### KDL-MD-005: Global exact-once completion

The source shall retain a global transaction until a destination commit acknowledgement arrives. Gateway
or route soft reset shall allow retransmission without duplicate destination commit. A hard reset that
destroys both the source transaction table and destination history starts a new protocol session and is
outside the exact-once continuity claim.

### KDL-MD-006: Hierarchical collectives

Global ReduceScatter, AllGather, AllReduce, AllToAll, AllToAllv, and point-to-point operations shall use
explicit leaf and inter-domain phases with group-table membership. The released fixed 32-node collective
does not satisfy this requirement by itself. A phase-completion handshake shall not advance until the
connected leaf engine or global transaction engine reports completion.

### KDL-MD-007: Multidomain escape proof

VC0 shall follow an acyclic deterministic `leaf-up -> spine -> leaf-down` route for every supported topology
and failover profile. Adaptive traffic shall not create a dependency from a later escape stage to an earlier
stage.

## 9. Million-Scale Extension Requirements

These requirements define the isolated scale extension. They do not modify the frozen schema-3 contract.

### KDL-SCL-001: Twenty-bit global endpoint address

Schema 4 shall encode a 15-bit leaf-domain identifier and 5-bit local-node identifier, covering 32,768
leaf domains and 1,048,576 global endpoints while rejecting identifiers outside the active topology.

### KDL-SCL-002: Five-stage radix-8 route

The reference model and RTL shall consume one destination-domain radix-8 digit at each of up to five
monotonically ranked stages. Every stage shall validate profile range, active egress, hop budget, packet
ownership, and deterministic escape policy.

### KDL-SCL-003: Schema compatibility

Schema-2 local and schema-3 multidomain traffic shall retain their released layouts and behavior. Schema-4
Route Context and global commit traffic shall be accepted only after capability negotiation and shall not
alias a schema-3 replay or commit identity.

### KDL-SCL-004: Bounded distributed group state

No routing-node interface shall expose a global 32,768-domain bitmap. Each internal group-directory entry
shall expose only an eight-child subtree mask, and each leaf entry only a 32-node mask, together with a
16-bit topology epoch, 21-bit subtree member count, and 20-bit root endpoint.

### KDL-SCL-005: Tree-executed collectives

ReduceScatter, AllGather, AllReduce, AllToAll, AllToAllv, and point-to-point shall execute through bounded
per-node child commands. No controller may require a combinational or sequential scan over every domain in
the global topology before making local progress.

### KDL-SCL-006: Scaled exact-once state

Source transaction and destination commit windows shall be parameterized for five-stage round-trip latency,
preserve exact-once state across route soft reset, reject stale topology epochs, and support SRAM-oriented
implementation without changing the 64-bit global transaction identity.

### KDL-SCL-007: Million-scale evidence

Release evidence shall include exhaustive 20-bit endpoint round trips, exhaustive 32,768-domain route digit
selection, compositional five-stage formal proofs, representative maximum-profile RTL simulation, legacy
regression, critical-module coverage, and three-corner pre-layout STA.

### KDL-SCL-008: Arbitrary active population

The scale deployment shall support every total NPU population from 1 through 1,048,576 using dense global
endpoint ordinals. A one-leaf deployment shall require no inter-domain route. For larger deployments, all
leaves except the last shall contain 32 active nodes; the final leaf shall contain 1 through 32 active nodes.
Unconfigured local nodes and leaf domains shall be rejected by routing and excluded from distributed groups.
Release evidence shall explicitly include totals 2, 3, 33, 78, and 15,132 and adjacent capacity boundaries.

### KDL-SCL-009: Per-tier bandwidth dimensioning

Every active hierarchy tier shall have a machine-readable analytical bandwidth contract covering active
slices, active planes, cross-tier traffic fraction, reduction factor, oversubscription ratio, parallel
bonded-link equivalents, one-equivalent-link failure headroom, reference RTT, and bandwidth-delay-product
storage. Worst-case cross-child traffic without reduction shall be the mandatory dimensioning matrix.
One slice shall represent 64 GB/s per plane per direction and the default two-slice bonded port 128 GB/s.
The 1:1 profile shall preserve offered bandwidth at every tier; any lower-capacity profile shall expose its
oversubscription explicitly. Reference digital RTT values shall not be used as physical signoff latency.

### KDL-SCL-010: Compressed cluster-inference traffic simulation

The functional model shall compile declared prefill and decode workloads into TP, EP, PP, and DP
communication cohorts without creating one object per endpoint, token, or packet. It shall calculate exact
dense-rank crossings for the 32-node leaf and every active radix-8 tier; represent AllReduce, ReduceScatter,
AllGather, AllToAllv, and point-to-point traffic; and consume the selected single- or dual-slice,
active-plane, RTT, and oversubscription capacity contract. The parallel-axis physical order, MoE imbalance,
remote-KV fraction, and compute-network overlap shall remain explicit inputs. Results shall report
per-tier bytes, capacity, mean and peak physical-resource utilization, bottleneck tier, TTFT, decode time
per token, and generated-token throughput while labelling capacity assumptions `ANALYTICAL`. Full-scale functional results
shall not be represented as packet-accurate, RTL-cycle-accurate, or physical-network measurements.

### KDL-SCL-011: Contention, throughput scope, and serving evaluation

The cluster-inference model shall schedule capacity independently by hierarchy tier, group, plane, and
full-duplex direction; preserve logical-VC byte attribution while applying shared physical capacity; and
accept independent per-tier plane, slice, and oversubscription vectors. Utilization shall not be clamped,
and overload shall remain observable. Generated-token throughput shall be reported separately per data-
parallel replica and for the complete cluster. A deterministic multi-request evaluation shall report
latency, TTFT, and queue P50/P95/P99 plus per-tier offered load. Its scheduling approximation and the lack
of packet arbitration, VC priority, measured arrival traces, and physical calibration shall remain explicit.

## 10. Release Decision

KDLink is releasable only when every mandatory row in the traceability matrix is `PASS`, or has a
reviewed waiver that states the affected claim. `PROPOSED`, `PARTIAL`, `NOT_RUN`, and undocumented
exclusions are release-blocking states.
