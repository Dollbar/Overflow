# KDLink Million-Scale Architecture

Status: `RELEASE CANDIDATE` for the KDLink v0.4 implementation branch. This document does not alter the frozen
KDLink v0.3 schema-3 contract.

## 1. Capacity And Compatibility

The implementation retains the released 32-endpoint leaf domain and extends the domain identifier from
8 bits to 15 bits under a new schema value of 4. The resulting 20-bit global endpoint address supports
32,768 leaf domains and 1,048,576 endpoints. A deployment may contain any total population from 1 through
1,048,576 NPU endpoints. A single-leaf deployment performs no inter-domain routing; deployments with two
through 32,768 active leaves use the radix-8 hierarchy. Identifiers outside the active population are invalid.

Every leaf retains exactly 32 logical NPU node identifiers but may pack them into 1, 2, 4, 8, 16, or 32
NPUs per physical card, including mixed profiles. A full million-endpoint system therefore contains from
32,768 physical 32-NPU cards through 1,048,576 physical single-NPU cards. Card packing does not consume
global address bits and does not change the five-stage route.

The reference deployment mapping is dense: global ordinal `n` maps to domain `n / 32` and local node
`n % 32`. The active leaf count is `ceil(total_npus / 32)`. Every leaf except the last is full; the last
leaf carries between 1 and 32 active nodes and its remaining logical node identifiers stay inactive. The
partial leaf is packed from supported physical card profiles without changing addressing. Representative
irregular totals are therefore:

| Total NPUs | Active leaves | Active NPUs in final leaf | Final-leaf member mask |
| ---: | ---: | ---: | ---: |
| 2 | 1 | 2 | `0x00000003` |
| 3 | 1 | 3 | `0x00000007` |
| 33 | 2 | 1 | `0x00000001` |
| 78 | 3 | 14 | `0x00003fff` |
| 15,132 | 473 | 28 | `0x0fffffff` |

| Homogeneous NPUs per card | Cards per full leaf | Cards at 32,768 full leaves |
| ---: | ---: | ---: |
| 1 | 32 | 1,048,576 |
| 2 | 16 | 524,288 |
| 4 | 8 | 262,144 |
| 8 | 4 | 131,072 |
| 16 | 2 | 65,536 |
| 32 | 1 | 32,768 |

Schema 2 remains the local baseline. Schema 3 remains the bit-exact 8-bit-domain multidomain format.
Schema 4 carries the scale format and must be rejected by a peer that did not negotiate scale capability.
The 640-bit forward flit, 128-bit reverse word, eight virtual channels, two bonded slices, PCS geometry,
and digital SerDes boundary remain unchanged.

## 2. Five-Stage Radix-8 Route

A maximum-size destination domain is decomposed into five radix-8 digits. Stage zero consumes bits
`[14:12]`, stage one `[11:9]`, stage two `[8:6]`, stage three `[5:3]`, and stage four `[2:0]`. Smaller
profiles use the least number of digits able to represent `domain_count - 1`. Each stage validates the
active-domain range, selects one active egress, decrements the hop budget, and locks the following packet
through EOP. The deterministic escape dependency rank increases monotonically with stage index.

The supported capacity points are 8, 64, 512, 4,096, and 32,768 domains, corresponding to 256, 2,048,
16,384, 131,072, and 1,048,576 leaf endpoints. Partial profiles between those capacity points use the same
digit mapping and reject unused high identifiers.

### 2.1 Per-Tier Bandwidth Contract

Reachability does not imply a nonblocking physical fabric. One 512-bit slice at the declared 1 GHz logical
clock carries 64 GB/s per direction. The default bonded port has two active slices and therefore carries
128 GB/s per plane per direction; eight active planes provide 1,024 GB/s per NPU per direction. Degraded
single-slice operation is 64 GB/s per plane and 512 GB/s per NPU per direction.

The mandatory dimensioning traffic is worst-case cross-child traffic with no assumed locality or reduction.
The nonblocking profile uses 1:1 capacity at every tier. An optional balanced planning example uses
oversubscription ratios 1:1, 2:1, 4:1, 8:1, and 16:1 from the leaf-adjacent tier upward. Those ratios are
explicit performance limits, not hidden implementation details. The maximum-size reference results are:

| Leaf-up tier | Leaves/group | NPUs/group | Offered per plane/direction | Offered across 8 planes | 1:1 bonded-link equivalents/plane | Balanced example links/plane |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 8 | 256 | 32.768 TB/s | 262.144 TB/s | 256 | 256 |
| 2 | 64 | 2,048 | 262.144 TB/s | 2.097152 PB/s | 2,048 | 1,024 |
| 3 | 512 | 16,384 | 2.097152 PB/s | 16.777216 PB/s | 16,384 | 4,096 |
| 4 | 4,096 | 131,072 | 16.777216 PB/s | 134.217728 PB/s | 131,072 | 16,384 |
| 5 | 32,768 | 1,048,576 | 134.217728 PB/s | 1.073741824 EB/s | 1,048,576 | 65,536 |

A bonded-link equivalent is 128 GB/s per plane per direction. The table describes distributed aggregate
switch capacity inside each hierarchy group; it is not the rate of one physical cable or one monolithic
root switch. Each group installs one additional bonded-link equivalent per plane for N+1 capacity after
one equivalent-link failure. A real topology may distribute these equivalents across Clos stages, switch
ASICs, cables, and parallel lanes, but the sum must meet the selected contract.

Plane loss and slice loss are separate degraded modes. Losing one slice halves each surviving bonded-link
equivalent to 64 GB/s without changing the number of logical routes. Losing one adaptive plane reduces
aggregate bandwidth by one eighth while the per-plane contract stays unchanged; plane zero remains the
mandatory deterministic escape path. N+1 link headroom does not substitute for plane-failure redundancy.

Traffic locality and in-network reduction may lower the offered load only through explicit
`cross_tier_fraction` and `reduction_factor` inputs. AllToAll, AllToAllv, and adversarial external P2P use
the mandatory worst-case values of one. An idealized reduced collective may use a larger reduction factor
for analytical planning, but it is not an RTL bandwidth claim until the corresponding aggregation data
path and traffic regression exist.

The digital planning RTT is 14, 24, 34, 44, and 54 cycles for tiers one through five. It uses the repository
SerDes compatibility latency, registered reverse control, one route/control allowance per tier, and a fixed
endpoint-turnaround allowance. At 1 GHz and 128 GB/s, this requires 1,792, 3,072, 4,352, 5,632, and 6,912
bytes of BDP storage per bonded-link equivalent. Physical deployments must replace these reference RTTs
with measured cable, retimer, switch, clock-crossing, and recovery latency before sizing production buffers.

### 2.2 Cluster-Inference Traffic Simulation

The maximum-scale simulator does not instantiate one RTL endpoint or packet object for every NPU. It
compiles a declared inference workload into bounded prefill and decode communication cohorts, then services
those cohorts through one leaf resource class and each active radix-8 hierarchy tier. At the maximum
population there are 32,768 leaf groups plus 4,096, 512, 64, 8, and 1 groups from tiers one through five.
Only active communication cohorts and sparse physical resource keys are retained in the event state. At
maximum scale, all 37,449 groups, eight planes, and two directions bound that state to 599,184 keys; no
per-endpoint, per-token, or per-packet objects are created.

The workload declares TP, EP, PP, and DP dimensions and an explicit fastest-to-slowest physical axis order.
The dense rank mapper counts every member of each regular communication group to calculate exact boundary
crossings. A tensor group packed inside one leaf therefore contributes no interdomain traffic, while the
same expert group placed as the slowest-changing axis may cross all five tiers. This distinction is
mandatory: endpoint reachability alone is not a traffic distribution.

AllReduce, ReduceScatter, and AllGather use ring traffic-volume and round-count contracts. AllToAllv uses
directed uniform-peer traffic with an explicit peak imbalance factor. Pipeline traffic uses adjacent-rank
point-to-point transfers. Prefill and decode carry independent payload sizes and repetition counts; remote
KV traffic and compute-network overlap are optional explicit inputs. The simulator applies payload capacity
only once: the 64 GB/s single-slice value already accounts for the logical flit and PCS encoding boundary.

The event resources are keyed independently by hierarchy tier, physical group, plane, and full-duplex
direction. Traffic is mapped onto exact source-side group distributions and striped evenly over the selected
planes. Logical VC2 collective, VC3 AllToAllv, and VC4 point-to-point bytes are accounted separately while
sharing the same physical service resource. The model does not yet implement VC priority, packet arbitration,
or uneven per-plane hashing. Active plane count, active slice count, and oversubscription may be configured
independently at each tier, so a leaf-only dual-slice experiment cannot silently double upper-tier capacity.

Each single-cluster-batch result reports bytes propagated into every tier, distributed group capacity,
unclamped mean and peak physical-resource utilization, overload state, queue/service contribution,
bottleneck tier, TTFT, decode time per generated token, throughput per DP replica, and total cluster
throughput. The retained `generated_tokens_per_second` compatibility field means throughput per DP replica.
It shall not be interpreted as cluster total throughput.

The optional serving evaluation schedules deterministic arrivals using an explicitly labelled
`FCFS_CLUSTER_BATCH` approximation. It reuses physical resources across requests and reports latency, TTFT,
and maximum-resource-queue P50/P95/P99 together with per-tier offered load. It reserves a complete request's
dependency-ordered traffic before scheduling the next request and is therefore neither a request-stage
interleaving model nor a packet/cycle simulator. This conservative scheduling policy is suitable for
saturation and local-upgrade screening; production serving claims require trace-driven arrival, packet-level
arbitration, measured compute distributions, topology-calibrated RTT, and hardware switch capacities.
For a zero-interval burst the steady-state offered load is undefined and is emitted as JSON `null`; the
corresponding tier is still marked overloaded when it carries traffic.

Execution is `FUNCTIONAL_SIM`, while link rate, switch capacity, RTT, compute latency, arrival distribution,
and workload values retain `ANALYTICAL` evidence. The supplied dense, distributed-MoE, degraded irregular-
population, and serving-burst JSON files are planning examples, not measured model or hardware performance
claims.

The current 20-bit endpoint format covers one million single-NPU cards or fewer multi-NPU cards. One million
cards containing more than one NPU exceed this format and require a later schema, address-width, and route-
depth extension; the inference simulator shall reject that population rather than aggregate it silently.

## 3. Schema-4 Route Context

Schema-4 message-type-8 Route Context remains a single 64-byte payload packet. Its mutable fields are:

| Payload bits | Field | Rule |
| --- | --- | --- |
| `[14:0]` | `source_domain` | 15-bit source leaf domain |
| `[29:15]` | `destination_domain` | Must be below the active domain count |
| `[34:30]` | `source_node` | Source node 0 through 31 |
| `[39:35]` | `destination_node` | Destination node 0 through 31 |
| `[55:40]` | `topology_epoch` | 16-bit committed topology generation |
| `[63:56]` | `domain_hop_limit` | Nonzero and sufficient for the remaining stages |
| `[66:64]` | `logical_plane` | One of eight physical/logical planes |
| `[68:67]` | `slice_mask` | At least one bonded slice enabled |
| `[71:69]` | `route_policy` | Zero is deterministic escape |
| `[76:72]` | `packet_flit_count` | Integer from 1 through 16 |
| `[88:77]` | `expected_packet_sequence` | Following packet SOP sequence |
| `[152:89]` | `global_transaction_id` | End-to-end transaction identity |
| `[184:153]` | `group_id` | Group identifier or zero for point-to-point |
| `[187:185]` | `logical_vc` | Original VC0 through VC5 |
| `[190:188]` | `route_depth` | Integer from 1 through 5 |
| `[511:191]` | `reserved` | Must be zero |

Schema-4 message-type-9 global commit carries 15-bit source/destination domains, 5-bit source/destination
nodes, a 16-bit topology epoch, a 64-bit transaction identifier, and a two-bit status. Schema-3 and
schema-4 identities must never alias in a replay or commit-history table.

## 4. Distributed Group State

No hardware interface may expose a 32,768-bit domain membership bitmap. Each internal hierarchy node
stores an eight-bit child-subtree mask for each resident group. Each leaf stores a 32-bit local-node mask.
Every entry also carries the 32-bit group identifier, 16-bit topology epoch, 21-bit subtree member count,
and 20-bit root endpoint. Group configuration uses prepare and commit generations so readers observe either
the old complete tree or the new complete tree.

ReduceScatter, AllGather, and AllReduce operate as tree reductions and broadcasts. AllToAll and AllToAllv
are scheduled by destination prefix so a controller emits at most eight child commands per hierarchy node.
Point-to-point retains ordinary unicast routing.

## 5. Reliability And Failure Contract

Hop-local credit, ACK, NACK, replay, keepalive, and link epoch remain terminated at every physical link.
End-to-end source transactions and destination commit history are parameterized for the five-stage RTT and
may be inferred or mapped as SRAM. A route soft reset preserves exact-once state and moves outstanding
transactions to a committed newer topology epoch. A hard reset of both endpoints begins a new session.

Plane zero is the deterministic escape plane. Planes one through seven may select another active path but
may only fall back toward the escape dependency order. A packet must never transition from a later escape
rank to an earlier rank.

## 6. Evidence Required For Release

- Exhaustive encode/decode of all 1,048,576 global endpoint addresses.
- Exhaustive digit selection for all 32,768 destination domains and every active route depth.
- RTL tests for schema compatibility, packet lock, failed egress, hop exhaustion, partial profiles, and
  five-stage forwarding.
- Compositional formal proof of destination digit selection and monotonic escape rank for stages zero
  through four.
- Distributed-directory tests for sparse, full, single-member, invalid, prepared, committed, and stale
  group generations.
- Exact-once tests across ACK loss, CRC replay, route reset, plane failure, and transaction-window collision.
- Regression of every released model, RTL, lint, CDC, formal, coverage, and applicable STA gate.
- Three-corner pre-layout STA for new critical partitions using repository interface Liberty plus
  caller-supplied licensed standard-cell Liberty.
- Exhaustive homogeneous and mixed card-directory mapping, atomic update, card fault isolation, and
  legacy eight-card by four-NPU compatibility.
- Directed 2-, 3-, 33-, 78-, and 15,132-NPU tests plus adjacent 32/64/radix boundaries, checking dense
  address continuity, partial final-leaf masks, inactive-address rejection, routing, and group membership.
- Per-tier analytical bandwidth tests for single- and dual-slice operation, 1:1 and explicit oversubscribed
  profiles, cross-tier traffic and reduction factors, N+1 capacity, irregular populations, and RTT-derived BDP.

Million-scale support is a compositional system-capacity claim. It does not require or imply a monolithic
RTL instance containing one million endpoint modules, analog SerDes signoff, package signoff, or PCB timing.
