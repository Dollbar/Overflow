# ADR-0005: NPU Pod-to-NoC Logical Attachment

- State: accepted
- Owners: NPU Pod integration and NoC interface consumers
- Date: 2026-08-28
- Evidence: `RTL_SIM`

## Context

ADR-0004 freezes eight Pods in a 2 by 4 placement but deliberately leaves router implementation to the
NoC workstream. Pod integration still needs a stable handoff that prevents DMA, compute, and SRAM details
from leaking into router RTL and prevents router-specific VC or credit choices from leaking back into the
Pod.

The P0 sizing proposal already identifies two 1,024-bit data lanes per direction, one 128-bit control
flit, four traffic classes, and three-bit Pod identities. The local HBM and shared-SRAM beat are also 128
bytes, so the proposed data-flit width avoids an implicit width converter at the logical boundary.

## Decision

The synchronous Pod/NoC v0.1 attachment contains one full-duplex 128-bit control channel and two
independent full-duplex 1,024-bit data channels. Every channel uses ready/valid and one packet-aware
elastic register in each direction. A common 14-bit metadata suffix above byte-valid and payload fields
carries protocol version, start/end markers, source Pod, destination Pod, and a two-bit traffic class.

Payload content is opaque to the attachment. Packet opcodes, transaction identifiers, remote DMA
semantics, multicast, retry, and completion formats belong to separately versioned client adapters. The
NoC owns virtual-channel mapping, credits, routing, arbitration, QoS service, deadlock avoidance, hop
state, congestion, and router telemetry. None of those fields appear at the Pod boundary.

V0.1 is synchronous to the supplied attachment clock. It does not freeze 1 GHz versus 2 GHz operation and
does not implement CDC. A future system wrapper shall place an independently verified async FIFO or other
approved CDC adapter between clock domains when the Pod and router clocks differ.

## Alternatives

- Expose router credits and VC numbers to the Pod: rejected because it couples Pod clients to an
  implementation owned by the NoC team.
- Reuse the HBM request interface for cross-Pod traffic: rejected because HBM tags, status, and local
  partition affinity are not a general packet contract.
- Freeze remote-DMA opcodes now: rejected because ownership, reservation, completion, and failure
  semantics are not yet approved.
- Make the attachment a transparent combinational wire: rejected because it would create an uncontrolled
  timing and backpressure path across the Pod/router ownership boundary.

## Consequences

The NoC team can implement and verify a router against stable `noc_*` ready/valid channels without
depending on Pod internals. Future Pod client adapters can connect to the corresponding `pod_*` channels
without changing the router interface. Cross-Pod movement is not functional until those client adapters
and the router are supplied; the attachment alone makes no routing, bandwidth, clock, or deadlock claim.
