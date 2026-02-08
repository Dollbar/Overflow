# NPU RTL

This directory owns the synthesizable NPU implementation and its implementation-facing documentation.
The authoritative system context remains in `docs/architecture/`; cross-subsystem interfaces remain in
`specs/`. No README in this tree freezes an external protocol by itself.

## Implementation Map

| Path | Responsibility |
| --- | --- |
| `common/` | NPU-local numeric packages and reusable arithmetic/control primitives |
| `command/` | KD-ISA command intake, validation, dispatch, and completion |
| `scheduler/` | Dependency tracking, pod selection, and tile issue |
| `tensor/` | MX processing element, Tile reduction/accumulation, and 256 x 256 GEMM array |
| `vector/` | Vector ALU, reductions, special functions, and vector-engine groups |
| `sram/` | Local Tensor/Vector buffers, FIFO wrappers, and physical SRAM boundary |
| `compute/` | Tensor/Vector integration, result routing, feedback, and system top levels |
| `noc/` | Pod-local and inter-pod on-chip network |
| `dma/` | NPU-side DMA descriptor and data-movement front end |

Read [Architecture](ARCHITECTURE.md) before changing module boundaries and use
[Work Breakdown](WORK_BREAKDOWN.md) to assign implementation tasks. The analytical sizing source is
[`config/npu_arch_proposed.yaml`](../../config/npu_arch_proposed.yaml).

The tensor geometry is baselined by
[`ADR-0001`](../../docs/adr/ADR-0001-npu-tensor-array-geometry.md) as 256 x 256 at a declared logical
1 GHz tensor clock. This is `ANALYTICAL`; it is not a measured or synthesized frequency result.
