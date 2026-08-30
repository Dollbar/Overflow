# ADR-0008: NPU NoC Router and Mesh Baseline

- State: accepted
- Owners: NPU NoC, Pod integration, verification, and system clock/reset
- Date: 2026-08-30
- Evidence: `ANALYTICAL`

## Context

ADR-0004 fixes eight Pods in a 2 by 4 logical placement, and ADR-0005 fixes the router-independent Pod
attachment. The remaining NoC implementation choices must be narrow enough to permit independently
verified Router and Mesh RTL without changing the Pod flit boundary or inventing cross-Pod DMA payload
semantics.

The attachment supplies one full-duplex 128-bit control payload lane and two full-duplex 1,024-bit data
payload lanes per Pod. Each data payload lane can carry one 128-byte shared-SRAM or DMA beat without width
conversion. A proposed 2 GHz logical NoC clock gives 512 GB/s of data payload per directed Pod link and
1.024 TB/s across the two-edge middle bisection. These rates are analytical logical-clock calculations,
not physical timing evidence.

## Decision

The first complete NoC implementation contains eight coordinate-aware routers connected as a 2 by 4
mesh. Pod identity is `row * 4 + column`. There are six horizontal and four vertical bidirectional links.
Every router implements Local, West, East, North, and South logical ports; nonexistent boundary directions
are tied inactive and any attempted route through them raises a sticky protocol diagnostic.

Control and data use independent fabrics. The control fabric has one physical lane. The data fabric has
two independent physical lanes, and a packet remains on its admitted lane from SOP through EOP. Each data
lane has four virtual channels selected by the existing two-bit traffic class. VC0 is the deterministic
escape class; VC1 carries demand/read-response traffic, VC2 carries writeback/prefetch traffic, and VC3
carries collective/KDLink traffic. The initial implementation routes every VC with horizontal-first
deterministic XY. Adaptive routing remains held until an ordering contract and comparative congestion
evidence exist.

Cardinal Router links use internal VC identity and per-VC credit-return pulses. These signals terminate
inside the NoC and do not change ADR-0005. Each data input VC has eight flit entries. The control fabric
uses four entries per input. Credit state is initialized only by a common link reset, decremented on each
transmitted flit, and incremented on each returned credit. Underflow, overflow, receive-while-full, invalid
VC, and boundary-route attempts set sticky diagnostics.

Output arbitration is packet locked. A selected input retains its output until its EOP transfers. New
packets use round-robin arbitration, with an age threshold of 64 eligible arbitration opportunities to
prevent starvation. Data packets are limited to 32 flits, matching the 4 KiB coalesced DMA limit. Control
packets are limited to four flits. An overlength packet is diagnosed and drained through EOP rather than
silently dropped.

The Pod and NoC logical clocks remain separate assumptions. When the Pod attachment and Router use
different clocks, a wrapper uses independently reset-aware Gray-pointer asynchronous FIFOs: eight entries
for control and sixteen entries for each data lane in each direction. Physical 2 GHz closure, reset-tree
implementation, and macro choice remain separate gates.

## Alternatives

- Start with adaptive minimal routing: rejected for the first implementation because the current flit has
  no reorder sequence and no approved endpoint reorder buffer.
- Expose Router credits at the Pod boundary: rejected by ADR-0005 because it couples Pod clients to a
  Router microarchitecture.
- Use one shared control/data Crossbar: rejected because the 1,166-bit data flit would increase control
  latency and physical cost without a protocol benefit.
- Allow unlimited wormhole packets: rejected because a malformed or oversized producer could retain an
  output indefinitely.
- Route local HBM traffic through the Mesh: rejected by ADR-0004; only explicitly nonlocal traffic enters
  the NoC.

## Consequences

Router, credit, deterministic route, arbitration, Mesh wiring, CDC, and telemetry RTL may proceed against
stable fields. Remote DMA, remote SRAM, multicast, retry, timeout, and software-visible completion payloads
remain opaque and require their own accepted client-adapter contract before end-to-end cross-Pod movement
is claimed.

The deterministic implementation must provide `RTL_SIM` no-loss/no-duplication evidence and `FORMAL`
escape-channel and credit-conservation evidence. Generic synthesis may report structure and area proxies,
but cannot promote the proposed 2 GHz logical clock to a physical frequency claim.
