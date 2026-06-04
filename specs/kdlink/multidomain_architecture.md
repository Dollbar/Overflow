# KDLink Multidomain Architecture

Status: `FROZEN` as the KDLink v0.3 multidomain architecture and implementation baseline.

The v0.3 freeze fixes the 8-bit domain identifier, 5-bit leaf-node identifier, 256-domain group bitmap,
one-to-three-stage radix-8 route, schema-3 Route Context, message-type-9 global commit, sixteen direct-mapped
source and destination transaction slots, and four physical group entries. Increasing any of those frozen
limits is a subsequent protocol/architecture change rather than an in-place v0.3 parameter adjustment.

This document defines hierarchical KDLink transport, scalable routing, global completion, and collective
orchestration. It preserves the released 32-node leaf domain and does not change the 640-bit forward flit,
128-bit reverse word, eight virtual channels, two-slice bonded port, PCS block geometry, or SerDes boundary.

## 1. Isolation And Compatibility

Development occurs on the dedicated `feat/kdlink-multidomain` branch and its dedicated Git worktree.
Existing release and NPU development worktrees are not implementation inputs and must remain unchanged.
Engineering filenames and design-unit names remain release-neutral.

Local traffic uses the released schema value 2. Hierarchical route-context traffic uses schema value 3.
A link that did not negotiate schema 3 must reject route-context traffic while continuing to support
local schema-2 traffic.

## 2. Addressing

A global endpoint address is the concatenation of an 8-bit domain identifier and a 5-bit leaf-local node
identifier. The architectural address space is therefore 256 domains with up to 32 nodes per domain.
Implementation evidence must separately state the number of instantiated and tested domains.

The model and RTL validate 2-, 4-, 8-, 16-, 32-, 64-, 128-, and 256-domain profiles. A fixed radix-8 stage
uses one level through 8 domains, two levels through 64 domains, and three levels through 256 domains. The
13-bit endpoint encoding therefore covers the tested architectural maximum of 8192 endpoints.

## 3. Route Context Payload

A route context is a one-flit packet with schema value 3, message type 8, SOP and EOP asserted, a complete
64-byte payload, and the normal flit CRC. A committed route context applies to exactly the next packet on
the same ingress stream and virtual channel.

| Payload bits | Field | Rule |
| --- | --- | --- |
| `[7:0]` | `source_domain` | Source domain identifier |
| `[15:8]` | `destination_domain` | Destination domain identifier |
| `[20:16]` | `source_node` | Source leaf-local node |
| `[25:21]` | `destination_node` | Destination leaf-local node |
| `[33:26]` | `topology_epoch` | Route-table generation |
| `[41:34]` | `domain_hop_limit` | Must be nonzero |
| `[44:42]` | `logical_plane` | One of eight KDLink planes |
| `[46:45]` | `slice_mask` | At least one bonded slice enabled |
| `[49:47]` | `route_policy` | Zero is deterministic escape; other values are reserved in this increment |
| `[54:50]` | `packet_flit_count` | Integer from 1 through 16 |
| `[66:55]` | `expected_packet_sequence` | Must match the following packet SOP |
| `[130:67]` | `global_transaction_id` | End-to-end transaction identity |
| `[162:131]` | `group_id` | Global group or zero for point-to-point traffic |
| `[165:163]` | `logical_vc` | Original VC0 through VC5; preserved when link replay remaps the header to VC6 |
| `[511:166]` | `reserved` | Must be zero |

The route context and following packet must not be interleaved with another packet. The first data flit
must assert SOP and match `expected_packet_sequence`. EOP must occur on the declared final flit. A malformed
route context is consumed, reported, and not forwarded. A packet-pairing fault is reported on the handshake
that exposes it; this increment does not provide end-to-end rollback for data already accepted downstream.

The header VC carries the physical-hop service class. On the initial transmission it must equal
`logical_vc`; on a replay transmission the reliable endpoint sets header VC6 while leaving `logical_vc`
unchanged. The gateway therefore validates packet pairing against `logical_vc`, while accepting VC6 only
when the retry flag is also asserted.

## 4. Gateway Behavior

When `destination_domain` equals the local domain, the gateway consumes the route context and directs the
following packet to the local output. When it differs, the gateway forwards the route context and following
packet to the remote output. Packet ownership remains locked until EOP.

The direct two-domain profile forwards a context whose hop limit is nonzero and the destination gateway
consumes it. The compact four/eight-domain profile may use `kdlink_spine_router`; larger profiles compose
`kdlink_route_stage` instances. Each stage selects one destination-domain radix-8 digit, decrements
`domain_hop_limit`, locks the following packet through EOP, and rejects inactive, out-of-range,
non-deterministic, or exhausted routes. The downstream reliable endpoint regenerates the forward CRC.

All ACK, NACK, credit, replay, keepalive, and link-epoch state remains local to one physical hop. The global
transaction layer is independent: it retains the source operation until a message-type-9 destination commit
arrives, and it retransmits after timeout or route soft reset without re-exposing a duplicate destination
delivery.

The Route Context and following data are separate reliable packets. `kdlink_route_pair_tx` therefore holds
the data until the canonical endpoint returns the matching Route Context ACK to the core domain through an
asynchronous FIFO. Unrelated ACK identities do not release the barrier. A new downstream physical hop
clears the upstream retry flag, restores the payload-carried logical VC, and lets its own reliable endpoint
own any later VC6 replay.

The focused single-slice system test injects CRC failures into both context and data. The bonded system test
uses two independent route-pair controllers, two logical reliable slices, four PCS instances, two existing
ten-lane SerDes link models, and two reverse channels. Across 20 modeled lanes it injects one context fault
and one data fault, observes NACK-driven VC6 replay, and requires one exact local commit per slice.

## 5. Routing And Deadlock

VC0 retains the deterministic escape role. VC6 remains link-local replay and VC7 remains management. The
gateway uses packet store-and-forward at reliable-link boundaries so that an accepted upstream packet is
committed before requesting a downstream hop. A route never transitions from a later radix-8 level back to
an earlier level. The formal properties prove destination-exclusive output, deterministic route policy,
hop decrement, and monotonic `leaf-up -> route-stage[0..2] -> leaf-down` dependencies through 256 domains.

## 6. Global Completion And Collectives

The source transaction table has 16 direct-mapped replay slots selected by transaction ID bits `[3:0]`.
An occupied collision is backpressured. The destination keeps a matching 16-slot commit history across
route soft reset. A first commit produces one local-delivery event and a global ACK; a replay produces only
the ACK. The default replay-grace interval is 4095 cycles at both ends. A same-slot different identity is
blocked during that interval, including while an earlier commit is still in the destination input pipeline;
an identical back-to-back arrival is accepted and acknowledged without duplicate delivery. A hard reset
that destroys both tables starts a new protocol session.

The global ACK is encoded as a schema-2, message-type-9, single-flit 64-byte control packet on VC5 for an
initial send or VC6 with the retry flag for link replay. Reserved commit status value 3 is rejected. This
extension is accepted only when the reliable endpoint's multidomain extension parameter is enabled; default
baseline instances continue to reject it.

The group table contains four independently generated entries, each carrying a topology epoch, 256-domain
member bitmap, member count, and root domain. A three-phase configuration pipeline samples the request,
registers the contract decision, then commits or rejects it. It validates the exact bitmap popcount, root
membership, physical index, and unique group/epoch key. The hierarchical controller supports ReduceScatter,
AllGather, AllReduce, AllToAll, AllToAllv, and point-to-point. Each descriptor advances monotonically through
leaf prepare, one or more inter-domain member commands, leaf finish, and complete. `command_ready_i` is a
completion-qualified handshake from the existing leaf engine or per-destination global transaction engine.

## 7. Complete-Increment Acceptance

The complete multidomain increment is accepted only when all of the following pass:

- route-context encode/decode and validation in the Python reference model;
- bit-exact RTL codec tests with complementary mutable fields and invalid reserved-field injection;
- 2- through 256-domain functional route construction and exhaustive 256-domain RTL digit selection;
- route masking and deterministic uplink selection;
- RTL local bypass, remote context forwarding, destination context consumption, and packet locking;
- malformed context, wrong packet sequence, early EOP, late EOP, and nested-context rejection;
- production context-before-data ACK ordering for single-slice and bonded paths;
- direct controller tests for unrelated ACK rejection, multi-flit ordering, replay normalization, and reset recovery;
- spine and radix-8 stage destination selection, hop decrement, backpressure, packet lock, single-stage
  profile selection, and malformed-data recovery at intermediate and terminal packet boundaries;
- global commit codec legality, all sixteen source slots, lost global ACK, route-reset replay, back-to-back
  duplicate suppression, protected same-slot collision, and source release;
- schema-2 message-type-9 global commit transport through the production endpoint, PCS, and ten-lane SerDes
  model from destination back to source;
- all six group-table-driven hierarchical phase sequences across a sparse 256-domain group, randomized
  configurations, exact-count/root/key/index rejection, invalidation, and illegal-state recovery;
- bounded formal properties for ACK ordering, global exact-once behavior, membership, and escape dependencies;
- three-corner partition STA using the matching HBM/SerDes interface Liberty view at every corner;
- regression of the released KDLink functional model and applicable RTL/static gates.

`route_context_reliable` requires one injected CRC failure and one VC6 replay for both the Route Context
and its following data packet, exactly-once local delivery, and a ten-lane PCS/SerDes transport.
`multidomain_bonded` closes both logical slices and 20 modeled lanes. Neither test claims analog SerDes,
package, PCB, or post-layout behavior.
