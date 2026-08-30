# NPU Pod-to-NoC Attachment v0.1

Status: baselined and RTL-simulation verified logical endpoint contract. Router and cross-Pod client
semantics are externally owned.

## 1. Scope and Ownership

`npu_pod_noc_attachment` is the only admitted synchronous handoff between a Pod packet client and the
separately implemented NoC router. It provides packet-preserving elastic storage, ready/valid
backpressure, packet-aware quiesce, and local endpoint diagnostics.

The attachment does not implement:

- XY, adaptive, source, multicast, or any other routing algorithm;
- virtual-channel assignment, escape-path selection, credits, arbitration, or QoS service;
- packet opcode decoding, remote DMA, SRAM access, completion generation, retry, or timeout;
- NoC clock generation, clock ratio selection, CDC/RDC, link training, or physical wiring; or
- KDLink packet conversion or runtime ABI behavior.

## 2. Logical Channels

One Pod attachment exposes the following full-duplex channels:

| Channel | Lanes per direction | Payload per flit | Purpose |
| --- | ---: | ---: | --- |
| Control | 1 | 128 bits / 16 bytes | Opaque commands, acknowledgements, and future management adapters |
| Data | 2 | 1,024 bits / 128 bytes | Opaque cross-Pod bulk data packets |

Every lane has independent `valid`, `ready`, and packed `flit` signals. The two data lanes may transfer
simultaneously. A packet remains on one logical lane from SOP through EOP; striping, lane selection, and
packet arbitration are not performed by the attachment.

`POD_ID` selects the local identity from zero through seven. The v0.1 lane counts and record widths are
fixed contract values; overriding them to another geometry asserts the local protocol diagnostic.

The `pod_*_tx` ports are produced by future Pod client adapters and consumed by the attachment. The
corresponding `noc_*_tx` ports are consumed by the NoC router. Receive direction ownership is reversed:
the router produces `noc_*_rx`, and future Pod client adapters consume `pod_*_rx`.

## 3. Packed Flit Encoding

Control and data flits use the same least-significant-bit-first layout. Let `P` be payload bits and `B` be
payload bytes:

| Field | Bit range | Meaning |
| --- | --- | --- |
| `payload` | `[P-1:0]` | Opaque client-owned contents |
| `keep` | `[P+B-1:P]` | One valid bit per payload byte |
| `traffic_class` | `[P+B+1:P+B]` | Four abstract service classes; router owns mapping and service |
| `destination_pod` | `[P+B+4:P+B+2]` | Destination Pod 0 through 7 |
| `source_pod` | `[P+B+7:P+B+5]` | Source Pod 0 through 7 |
| `eop` | `[P+B+8]` | Last flit of the packet |
| `sop` | `[P+B+9]` | First flit of the packet |
| `version` | `[P+B+13:P+B+10]` | Attachment protocol version; v0.1 encodes `4'd1` |

The exact widths are therefore 158 bits for a control flit and 1,166 bits for a data flit. SOP and EOP may
both be one for a single-flit packet. Every non-EOP flit has all `keep` bits set; the final flit has at least
one `keep` bit set. Source, destination, traffic class, and version remain constant for the complete packet.

The attachment intentionally defines no opcode or transaction layout inside `payload`. A producer and
consumer may interpret payload only through another versioned adapter contract.

## 4. Handshake and Elasticity

A transfer occurs on a rising clock edge when both `valid` and `ready` are one. The producer holds the
complete packed flit stable while `valid` is one and `ready` is zero. Every direction and lane contains one
registered elastic entry. Once stored, output validity and payload remain stable under sink backpressure.
Simultaneous dequeue and replacement are supported, permitting one flit per lane per cycle after fill when
the sink remains ready.

Ready/valid is the complete Pod-visible flow-control contract. Router-internal credits shall terminate
inside the NoC implementation and shall not be added to this interface.

## 5. Reset, Clear, Quiesce, and Errors

`rst_i` and `clear_i` are synchronous active-high controls. Either discards buffered attachment flits,
packet-progress state, and sticky diagnostics. Neither defines remote recovery; system control shall only
assert them when discarding in-flight traffic is architecturally permitted.

When `quiesce_i` is asserted, a lane does not accept the SOP of a new packet. A packet whose first flit was
already accepted remains admissible through EOP so quiesce cannot strand a packet prefix. `quiesced_o`
asserts only when all transmit and receive elastic entries are empty and no lane is inside a packet.

`protocol_error_o` is sticky until reset or clear. It records an accepted flit with a wrong protocol
version, zero `keep`, partial non-EOP payload, malformed SOP sequence, changing packet metadata, wrong
local source on transmit, or wrong local destination on receive. The attachment forwards such a flit and
reports the error because v0.1 defines no safe drop, retry, or recovery policy.

## 6. NoC-Team Handoff

The NoC implementation shall connect only to the `noc_control_tx_*`, `noc_data_tx_*`,
`noc_control_rx_*`, and `noc_data_rx_*` groups. It may inspect source, destination, traffic class, SOP, and
EOP for routing and service, but shall treat payload as opaque. Any change to flit width, metadata, lane
count, or ready/valid behavior requires a new version of this contract.

The router team remains responsible for VC and credit conservation, deterministic escape behavior,
deadlock proof, topology wiring, congestion tests, and any Pod/NoC CDC wrapper. This endpoint evidence
does not satisfy those router obligations.

## 7. Verification Evidence

The self-checking attachment regression covers control-channel backpressure stability, simultaneous use of
both data lanes, control and data receive delivery, packet-tail admission during quiesce, new-packet
blocking, complete drain, malformed-source forwarding with sticky error, and clear recovery. Verilator
lint is zero-warning and Yosys synthesis-readiness completes for the attachment hierarchy.
