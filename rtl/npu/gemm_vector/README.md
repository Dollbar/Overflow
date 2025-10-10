# GEMM and Vector Core Path

This directory is a source-only extraction of the Transformer NPU compute path
from the `Transform` RTL project. It contains synthesizable SystemVerilog plus
the small behavioral SRAM/FIFO wrappers required by the RTL hierarchy. It does
not contain testbenches, generated build output, timing collateral, papers,
model data, or DMA/HBM logic.

## Boundary

The integration boundary is `npu_square_gemm_system`. External logic writes a
descriptor and already-migrated tensor words into local buffers, then submits
the descriptor by slot index. The core owns descriptor issue, local tensor
buffer reads, GEMM execution, result routing, vector operand reads, and
feedback quantization. HBM, DMA, host queues, and physical SRAM macros remain
outside this source-only block.

## Main hierarchy

```text
npu_square_gemm_system
├── npu_input_scheduler / npu_descriptor_buffer
├── npu_square_gemm_executor
│   └── GEMM_65536
│       └── 16 x 16 TILE_FP8_16_NOC tiles
│           ├── 256 PE_FP8 per tile
│           └── per-tile NoC router and fixed-point K accumulator
├── npu_gemm_post_scheduler / npu_gemm_result_fifo
├── npu_gemm_vector_coupler16
│   └── 16 independent vector_engine16 instances
└── npu_gemm_feedback_writer16
```

`GEMM_65536` is the full 16 x 16 tile array (256 tiles, 65,536 PE cells).
Each tile consumes a 128-bit A row beat and a 128-bit B column beat. A and B
are propagated across the direct tile links; routed traffic uses the 160-bit
local NoC flit and a dual-VC XY router. A tile result is a 512-bit beat
(sixteen FP32 values). The K-accumulation path retains exact fixed-point
partial sums and performs the final FP32 conversion once at the result
boundary.

`npu_gemm_vector_coupler16` keeps command and result metadata together with the
payload. Each physical row has an independent request/result path, so the
default 16-row configuration accepts sixteen 512-bit vectors, or 256 FP32
elements, per cycle at the GEMM-to-vector boundary. Results carry `job_id`,
`tag`, row, segment, and `last` metadata through the post scheduler.

`vector_engine16` contains seven independent operator pipelines: elementwise
ALU, GEMM epilogue, reduction, softmax, LayerNorm/RMSNorm, GELU, and SiLU.
The engine has operation-specific result FIFOs and a fair output selector;
different operation latencies may therefore return out of issue order while
retaining the descriptor tag.

## Numeric and command ABI

- FP8 formats are selected per task through `fp8_pkg::fp8_format_e` (E4M3 or
  E5M2); rounding is carried in the descriptor.
- `npu_scheduler_pkg::npu_task_descriptor_t` contains the job/event fields,
  square matrix and tile parameters, local A/B/output buffer identifiers and
  offsets, vector operation/control, optional B/C vector operands, and the
  feedback route.
- All descriptor and command widths are derived with `$bits(...)` in
  `npu_scheduler_pkg`; do not duplicate those widths in integration RTL.
- A post-result beat is 512 bits of FP32 data plus invalid and identity fields
  (`job_id`, `tag`, row, segment, `last`).

## Source-only lint

From this directory, the following command performs an independent Verilator
lint of the complete system hierarchy. The four packages are listed first so
that package types are available before dependent modules.

```sh
verilator --lint-only --language 1800-2017 -Wall \
  --top-module npu_square_gemm_system \
  fp8_pkg.sv vector_pkg.sv npu_scheduler_pkg.sv tile_noc_pkg.sv \
  $(find . -maxdepth 1 -type f \( -name '*.sv' -o -name '*.v' \) \
      ! -name 'fp8_pkg.sv' ! -name 'vector_pkg.sv' \
      ! -name 'npu_scheduler_pkg.sv' ! -name 'tile_noc_pkg.sv' | sort)
```

The command is a structural/lint gate only; it is not a claim of FPGA timing
closure or foundry signoff. Functional regressions and waveform collateral
remain in the original development tree and are intentionally excluded here.

## Integration notes

1. Compile the package files before modules that use their packed structs.
2. Connect the local-buffer write interfaces at `npu_square_gemm_system`; do
   not bypass them by adding external memory ports to the extracted RTL.
3. Keep `ARRAY_DIM=16` for the validated full-array configuration. Smaller
   parameter values are useful for bring-up but are not equivalent to the
   16 x 16 throughput configuration.
4. Preserve the ready/valid contract on all three post routes (external,
   vector, and feedback). Metadata must advance only with its payload.
