# ADR-0002: NPU HBM Egress Lane Geometry

- State: accepted
- Owners: NPU architecture and model-to-RTL integration
- Date: 2026-08-25
- Evidence: `ANALYTICAL`

## Context

The system baseline assigns each logical NPU 192 GB of abstract HBM capacity and 5 TB/s aggregate
read-plus-write payload bandwidth at a logical 1 GHz HBM clock. The functional HBM contract divides that
capacity and bandwidth across eight independent 24 GB partitions and uses aligned 128-byte beats. The NPU
architecture assigns one partition to each of eight pods.

A single 128-byte ready/valid lane can transfer at most 128 GB/s at 1 GHz and therefore cannot represent
the 625 GB/s payload target of one partition. The existing single-lane HBM beat BFM remains useful for
functional tests but is not the production NPU egress geometry.

## Decision

Each pod exposes five parallel 128-byte request lanes and five parallel 128-byte response lanes in the
logical 1 GHz HBM service domain. Five lanes provide 640 bytes/cycle, or 640 GB/s raw payload capacity.
The memory service limits long-run accepted payload to 625 bytes/cycle per partition, leaving 2.4 percent
lane headroom for the integer beat granularity.

The NPU contains sixteen logical DMA channels per pod. A deterministic NPU-side arbiter maps those channels
onto the five request lanes. Four QoS classes are retained, and bounded age promotion prevents a
continuously requesting lower class from starving. QoS affects selection before the HBM boundary and is
not a memory-controller pin.

The finite HBM beat tag is twelve bits. Its default NPU construction is a four-bit DMA channel index plus
an eight-bit channel-local tag, providing 4,096 simultaneously distinct beat identities per pod. A tag
cannot be reused before its response is consumed.

The HBM service address is a 35-bit partition-local byte address. A 52-bit IOVA, protection domain, or
system address is translated before this boundary. Every request address is aligned to 128 bytes and must
remain below 24,000,000,000 bytes.

## Alternatives

- One 1024-bit lane: rejected because it provides only 128 GB/s at the declared logical clock.
- Four 1024-bit lanes: rejected because 512 GB/s is below the partition target.
- One 5,000-bit aggregate interface: rejected because it obscures beat identity, byte enables, and
  independent backpressure.
- A 3,072-bit 2 GHz NoC attachment: retained as a separate future clock-domain boundary. It is not the
  logical 1 GHz HBM service interface selected here.
- A controller-specific AXI or HBM pin interface: rejected for this repository boundary.

## Consequences

Eight balanced pods have 5.12 TB/s of raw lane capacity. The accepted payload claim remains 5 TB/s because
the memory service enforces 625 GB/s per partition and read plus write share that budget.

The NPU must provide multi-lane arbitration, stable ready/valid payloads under backpressure, response-tag
retirement, and CDC buffering if a producer is outside the HBM service clock domain. The memory owner may
adapt the five logical lanes to any controller interface without changing the NPU-visible fields.

This ADR does not approve an HBM controller, PHY, JEDEC command path, physical clock, IOVA translation
scheme, DMA descriptor ABI, cancellation policy, or sustained workload bandwidth claim.
