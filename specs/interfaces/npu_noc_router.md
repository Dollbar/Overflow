# NPU NoC Router and Mesh Interface

Status: implementation baseline. Pod payload semantics remain opaque.

## 1. Geometry and Port Numbering

One logical NPU contains eight Routers in two rows and four columns. Coordinates and identities are:

```text
(0,0) P0 -- (1,0) P1 -- (2,0) P2 -- (3,0) P3
   |             |             |             |
(0,1) P4 -- (1,1) P5 -- (2,1) P6 -- (3,1) P7
```

`pod_id = row * 4 + column`. Router ports use the stable indices Local=0, West=1, East=2, North=3, and
South=4. A generic Router exposes all five ports; the Mesh ties nonexistent boundary directions inactive.

## 2. Logical Fabrics

The control and data fabrics are independent. Both consume and produce the exact packed flits defined by
`npu_pod_noc_attachment_v0.1.md`.

| Fabric | Physical lanes per direction | Payload bits | Packed flit bits | Internal VCs |
| --- | ---: | ---: | ---: | ---: |
| Control | 1 | 128 | 158 | 1 |
| Data | 2 | 1,024 | 1,166 | 4 per lane |

Data traffic class maps to the same-numbered VC. A packet remains on one physical lane and one VC from SOP
through EOP. The Router does not inspect or alter payload or `keep`.

## 3. Routing

All admitted traffic uses deterministic horizontal-first XY routing:

1. route East while `destination_column > local_column`;
2. route West while `destination_column < local_column`;
3. route South while columns match and `destination_row > local_row`;
4. route North while columns match and `destination_row < local_row`; or
5. eject Local when both coordinates match.

VC0 is the mandatory escape VC. The first implementation also applies XY to VC1 through VC3. Adaptive
selection is not admitted until a later contract defines ordering and proves that every dependency can
transition to the escape subnetwork without introducing a cycle.

## 4. Cardinal Credit Contract

Each directed cardinal lane carries `valid`, packed `flit`, and internal VC identity. A valid flit consumes
one destination input-VC entry on the receiving edge. The receiver returns one credit pulse for that VC
when the buffered flit leaves the input FIFO.

The sender initializes every cardinal output VC to the configured destination FIFO depth after the common
link reset. It transmits only when the selected VC credit count is nonzero. Credit and flit transfer may
occur in the same cycle. Credit underflow, credit overflow, invalid VC, or a received flit with no free
entry is a sticky protocol error.

Credits never cross the Pod attachment. The Local port converts Pod ready/valid admission into input FIFO
availability and converts Router ejection into Pod ready/valid backpressure.

## 5. Buffering and Arbitration

Data input depth is eight flits per port, lane, and VC. Control input depth is four flits per port. FIFO
heads expose route metadata only after admission; storage remains stable until the granted transfer.

Each output lane grants one input VC. A grant that transfers SOP without EOP locks the output to the same
input VC until EOP transfers. New packets use round-robin priority. An eligible packet waiting through 64
arbitration opportunities receives age priority over non-aged packets. Ties retain round-robin order.

Data packets contain at most 32 flits and control packets contain at most four flits. Overlength, missing
SOP, repeated SOP, changing source/destination/traffic class, and invalid destination are diagnosed. Once a
packet is admitted, Router recovery drains it through EOP; the v0.1 Router does not retry or synthesize a
completion.

## 6. Ordering, Reset, and Quiesce

The deterministic Router preserves order for packets admitted on the same physical lane and VC with the
same source, destination, and traffic class. No ordering is promised across lanes, VCs, or traffic classes.

Reset and clear discard Router buffers, packet locks, credit accounting, counters, and sticky diagnostics.
All endpoints on one cardinal link participate in the same reset event. Reset during active traffic is a
system-level destructive operation.

Quiesce prevents admission of a new Local-port SOP. Packets already admitted and all transit traffic
continue through EOP. A Router is quiesced only when every input FIFO is empty, every output lock is idle,
and all cardinal output credits have returned to their reset value.

## 7. Performance and Telemetry

At the proposed 2 GHz logical clock, each 1,024-bit payload lane represents 256 GB/s and a two-lane directed
edge represents 512 GB/s. The two-edge middle bisection represents 1.024 TB/s per direction. These are
`ANALYTICAL` values until cycle-level regressions measure achieved utilization.

Each Router records per-port accepted and transmitted flits, packets, blocked cycles, maximum arbitration
wait, credit-low watermark, invalid-route events, and protocol errors. Saturation acceptance targets are
95 percent of theoretical payload rate for one long flow and 90 percent across the middle bisection.

## 8. Verification Obligations

Verification covers all 56 directed Pod pairs, four data VCs, both data lanes, packet lengths 1, 2, 31,
and 32, all legal turns, cardinal boundaries, simultaneous credit return/transmit, control/data coexistence,
sink backpressure, hotspot, incast, transpose, bisection, uniform-random, quiesce, clear, and error recovery.

Formal evidence covers FIFO bounds, credit conservation, one-hot output grants, packet-lock ownership, no
spontaneous flit creation, and acyclic VC0 channel dependencies under recorded endpoint-fairness assumptions.
