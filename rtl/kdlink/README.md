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
