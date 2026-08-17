# RTL

This directory contains synthesizable digital logic:

- `npu/`: command, tensor, vector, scalar-assist, attention, MoE, and on-chip NoC.
- `kdlink/`: NIC, reliable link, PCS, router, switch, and collective.
- `memory/`: SRAM-facing control, DMA, abstract HBM transactions, ECC, and QoS.
- `host/`: command queues, interrupts, and host-facing transaction logic.
- `common/`: reusable FIFO, arbitration, CDC, reset, and utility blocks.

Every RTL block requires a versioned specification, lint, directed and randomized tests, and applicable
formal or CDC evidence. Performance claims state their logical clock assumption and evidence level.
