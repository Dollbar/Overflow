# ADR-0004: NPU Pod Organization and Local Memory Affinity

- State: accepted
- Owners: NPU architecture, compute, DMA, and physical planning
- Date: 2026-08-27
- Evidence: `ANALYTICAL`

## Context

The verified compute core contains one 256 by 256 Tensor array, its Vector path, schedulers, and local
stores. The verified DMA Pod contains one sixteen-channel DMA engine and one 16 MiB shared SRAM. A stable
integration hierarchy is required before those blocks can be connected without accidentally routing local
HBM traffic through an undefined NoC or treating the exploratory private-memory sizing as a production
capacity commitment.

The system capacity target already divides one logical NPU into eight 24 GB HBM partitions. ADR-0002
defines five 128-byte logical HBM lanes per Pod, and ADR-0003 defines the local HBM-to-shared-SRAM mover.

## Decision

One NPU contains eight Pods arranged as two rows by four columns. Each Pod contains two identical compute
clusters, where one cluster is one `npu_square_gemm_system` instance and therefore contains one Tensor
array and its associated Vector path. The full NPU consequently contains sixteen Tensor arrays.

Each Pod owns one DMA engine, one 16 MiB shared SRAM, and an affinity to exactly one of the eight HBM
partitions. The HBM controller and PHY remain outside `npu_compute_pod`; the Pod retains the five-lane
vendor-neutral request/response boundary. Traffic between a Pod, its shared SRAM, and its owning HBM
partition never enters the inter-Pod mesh.

The logical placement is:

```text
HBM0  HBM1  HBM2  HBM3
  |     |     |     |
 P0----P1----P2----P3
 |     |     |     |
 P4----P5----P6----P7
  |     |     |     |
HBM4  HBM5  HBM6  HBM7
```

Top and bottom rows may be mirrored during physical implementation. The diagram fixes affinity and
logical neighborhood, not bump coordinates, stack orientation, or controller placement.

The v0.1 bring-up profile uses one synchronous clock/reset/clear domain around existing blocks. NoC,
HBM-controller, management, or KDLink clock crossings require their own later contracts.

The existing 8 MiB-per-store compute parameters are retained only as a compatibility verification
profile. They imply approximately 49.129 MiB of private storage per compute cluster and approximately
114.258 MiB total storage per Pod after adding the 16 MiB shared SRAM. This ADR deliberately does not
freeze that approximately 914 MiB NPU-wide implementation as the production SRAM capacity. Private SRAM
capacity, scale packing, buffering depth, and macro selection require a separate capacity decision.

## Alternatives

- One compute cluster per Pod: rejected because it provides only eight of the sixteen accepted Tensor
  arrays.
- Four or eight compute clusters behind fewer DMA engines: rejected because it reduces HBM locality and
  enlarges the shared-SRAM arbitration domain.
- Route local HBM traffic through the mesh: rejected because it consumes bisection bandwidth without a
  data-ownership benefit.
- Place all eight HBM partitions on one side: not selected as the logical floorplan because it lengthens
  half of the affinity paths; a physical package study may still choose another orientation while
  preserving the one-to-one mapping.

## Consequences

Pod-local scheduling and shared-to-private movement can proceed before the NoC packet format is frozen.
The two-cluster wrapper must expose local loader, descriptor, result, completion, HBM, quiesce, and
diagnostic boundaries without inventing KD-ISA or runtime ABI fields.

The 2 by 4 topology is now an architectural baseline. ADR-0005 subsequently freezes the router-independent
Pod attachment, and NPU-035 implements the eight-Pod structural top with one attachment and one same-ID HBM
partition per Pod. Router RTL, virtual channels, credits, routing, cross-domain integration, reset policy,
and deadlock proof remain owned by the NoC workstream. Physical HBM implementation and production
private-memory capacity also remain separate approval gates.
