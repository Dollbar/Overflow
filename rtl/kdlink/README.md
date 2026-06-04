# KDLink RTL

This directory contains the synthesizable KDLink logical link, reliable endpoints, NICs, multi-port
routers, KDSwitch, collectives, and AllToAllv data paths.

KDLink is the canonical wire protocol. It uses a 640-bit forward flit, eight virtual channels, and a
128-bit reverse-control word. `kdlink_reliable_endpoint` is the canonical endpoint boundary. It
integrates:

- asynchronous core-to-PHY and PHY-to-core FIFOs;
- cumulative credit accounting for all eight VCs;
- CRC-protected reverse ACK, NACK, and credit messages;
- packet replay with retry remapping to VC6;
- autonomous CRC-failure NACK generation;
- atomic packet commit and exact-once duplicate suppression.

Files beginning with `coll_` implement the earlier four-rank Collective protocol. That protocol has four
VCs and a 96-bit reverse word. It remains available for compatibility tests, but it is not wire-compatible
with KDLink and must not be connected through an implicit width adapter.

The RTL boundary ends at logical PCS-facing streams. No process library, analog SerDes macro, PCB model,
or physical implementation artifact is required by this directory.

The isolated hierarchical implementation adds Route Context encoding, domain adaptation, context/data
pair ordering, deterministic radix-8 route stages, global transaction retention, destination commit
tracking, a four-entry 256-domain group table, and hierarchical collective control.
It keeps schema-2 local traffic on the released leaf path and binds one schema-3 Route Context to exactly
one following local or remote packet. `kdlink_reliable_endpoint` and its bonded wrapper expose an
`ALLOW_ROUTE_CONTEXT` parameter that defaults to zero, preserving baseline instances. When enabled, a
schema-3 context participates in CRC, NACK, VC6 replay, ACK, credit, and exact-once receive commit; its
payload retains the original logical VC because the replay header uses physical VC6.

The endpoint exports ACK identity events to the core clock through an asynchronous FIFO. The route-pair
controller uses those events as a production context-before-data barrier. The validated transport evidence
covers a single slice with faults on both packets and a bonded path with four PCS instances, two ten-lane
SerDes links, and faults split across the two logical slices. The single-slice composition also transports a
schema-2 message-type-9 global commit back through the opposite endpoint, PCS, and ten-lane SerDes link,
then decodes it and releases the source transaction slot. `kdlink_spine_router` preserves the compact
4/8-domain profile, while `kdlink_route_stage` composes one, two, or three radix-8 stages for every frozen
profile through 256 domains with hop decrement and packet locking.

`kdlink_global_transaction_source` retains up to 16 outstanding transactions, retransmits after timeout or
route soft reset, and releases a slot only after a message-type-9 destination commit. The low four transaction
ID bits select the replay-window slot; an occupied collision is backpressured. The matching destination
tracker preserves its 16-slot history across route soft reset, suppresses a replayed local delivery, and
re-emits the global commit. `REPLAY_GRACE_CYCLES` defaults to 4095 at both ends; a different identity mapped
to the same direct slot is backpressured until that interval expires, while an identical back-to-back replay
is acknowledged without a second delivery.

`kdlink_group_table` stores four concurrently configured group generations, each with a 256-domain member
bitmap. Configuration uses registered sample, contract-decision, and commit phases; `config_ready_o` remains
low until the prior request is committed or rejected. The contract requires an in-range physical slot,
an exact nonzero bitmap popcount, a root contained in the bitmap, and a unique `(group_id, topology_epoch)`
key. `kdlink_hierarchical_collective_ctrl` emits explicit leaf-prepare, inter-domain, leaf-finish, and
complete phases for all six operations. Its `command_ready_i` is completion-qualified: the connected leaf
engine or per-destination global transaction engine asserts it only after that phase is complete.
