# NPU RTL

This directory owns the synthesizable NPU implementation and its implementation-facing documentation.
The authoritative system context remains in `docs/architecture/`; cross-subsystem interfaces remain in
`specs/`. No README in this tree freezes an external protocol by itself.

## Implementation Map

| Path | Responsibility |
| --- | --- |
| `common/` | NPU-local parameters, types, counters, and reusable control |
| `command/` | KD-ISA command intake, validation, dispatch, and completion |
| `scheduler/` | Dependency tracking, pod selection, and tile issue |
| `tensor/` | 256 x 256 tensor array and tile wrapper |
| `vector/` | Vector ALU, reductions, mask handling, and special functions |
| `sram/` | Tile-private and pod-shared scratchpad integration |
| `noc/` | Pod-local and inter-pod on-chip network |
| `dma/` | NPU-side DMA descriptor and data-movement front end |

Read [Architecture](ARCHITECTURE.md) before changing module boundaries and use
[Work Breakdown](WORK_BREAKDOWN.md) to assign implementation tasks. The analytical sizing source is
[`config/npu_arch_proposed.yaml`](../../config/npu_arch_proposed.yaml).

The tensor geometry is baselined by
[`ADR-0001`](../../docs/adr/ADR-0001-npu-tensor-array-geometry.md) as 256 x 256 at a declared logical
1 GHz tensor clock. This is `ANALYTICAL`; it is not a measured or synthesized frequency result.
