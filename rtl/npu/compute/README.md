# NPU Compute Integration RTL

This directory owns only the integration boundary between the independently
organized Tensor, Vector, scheduler, and local-buffer RTL. Numeric primitives
are in `../common/`, the GEMM array is in `../tensor/`, vector engines are in
`../vector/`, descriptor/issue logic is in `../scheduler/`, and storage
adapters are in `../sram/`. It contains no behavioral models, testbenches,
generated output, timing collateral, DMA, or HBM logic.

## Boundary

The integration boundary is `npu_square_gemm_system`. External logic writes a
descriptor and already-migrated tensor words into local buffers, then submits
the descriptor by slot index. The core owns descriptor issue, local tensor
buffer reads, GEMM execution, result routing, vector operand reads, and
feedback quantization. HBM, DMA, host queues, and physical SRAM macros remain
outside this source-only block.

`../sram/sram_macro_blackbox.sv` is declaration-only. `SRAM_32_32`, `SRAM_32_64`,
`SRAM_32_128`, `npu_local_sram_1w1r_macro`, and
`npu_feedback_block_store_macro` are replacement points for selected
foundry/compiler SRAM views. Their contracts use synchronous requests and
one-cycle read-valid/read-data behavior. No storage array is inferred by the
production NPU RTL for those instances, and no `SYNTHESIS` conditional selects
a technology macro.

## Main hierarchy

```text
npu_square_gemm_system
├── npu_input_scheduler / npu_descriptor_buffer
├── npu_square_gemm_executor
│   └── GEMM_65536
│       └── 16 x 16 TILE_FP8_16_FIFO tiles
│           ├── two 16-cycle A/B operand banks
│           ├── 256 exact-product PE_FP8 per tile
│           ├── sixteen Tile reduction trees and 85-bit K accumulators
│           └── direct A-right/B-down links
├── npu_gemm_post_scheduler / npu_post_output_formatter16
├── npu_gemm_vector_coupler16
│   └── 16 independent vector_engine16 instances
└── npu_gemm_feedback_writer16
```

`GEMM_65536` is the full 16 x 16 tile array (256 tiles, 65,536 PE cells).
Each tile consumes a 128-bit A row beat and a 128-bit B column beat. A and B
enter only at the west/north array boundaries and propagate east/south through
registered direct links. There is no Tile-level packet router, alternate
injection port, or programmable subarray placement. A tile result is a 512-bit
beat (sixteen FP32 values). A PE only forwards its operands and emits one exact
MX product; it does not retain matrix state. Four 4-input reducers followed by
one 4-input reducer form each of the sixteen Tile column sums. Only those
sixteen lanes enter signed 85-bit Q32 long-K accumulators, and final FP32
conversion occurs once at the result boundary. This bound covers up to `2^20`
products per output under the compiler contract that every product in the dot
product has one common combined A-plus-B E8M0 exponent.

The production local-buffer defaults are four logical buffer IDs, sixteen
banks, and 8192 128-bit words per bank. Consequently each Tensor-A,
Tensor-B, Vector-B, and Vector-C data store is 8 MiB. Scale SRAMs are separate
metadata stores and are not counted in those 8 MiB data capacities. The
executor reads one word from every active bank on every K cycle and presents
all 256 A lanes plus all 256 B lanes at the `GEMM_65536` boundary for 256
consecutive cycles in the K=256 full-array case. Each Tile alternates two
16-cycle operand banks, loading one while all 256 multipliers consume the
other. `gemm_boundary_skew` delays complete 16-lane Tile-row/Tile-column groups
at the array boundary; operands inside a group remain atomic, so there is no
per-PE lane skew and no loss of boundary issue bandwidth.

`npu_gemm_vector_coupler16` keeps command and result metadata together with the
payload. Each physical row has an independent request/result path, so the
default 16-row configuration accepts sixteen 512-bit vectors, or 256 FP32
elements, per cycle at the GEMM-to-vector boundary. Results carry `job_id`,
`tag`, row, segment, and `last` metadata through the post scheduler.

`vector_engine16` contains seven independent operator pipelines: elementwise
ALU, GEMM epilogue, reduction, softmax, LayerNorm/RMSNorm, GELU, and SiLU.
The engine has operation-specific result FIFOs and a fair output selector;
different operation latencies may therefore return out of issue order while
retaining the descriptor tag. An MX epilogue pairs adjacent 16-lane FP32 beats,
selects one E8M0 scale from all 32 values, and then emits the two tagged response
beats continuously after pair formation.

## Numeric and command ABI

- Public tensor formats are MXFP4 E2M1 and MXFP8 E4M3FN. Every
  block has 32 elements and one E8M0 scale; plain FP4/FP8 is not a v0.2 input
  or output mode. Internal FP8-named helpers are implementation utilities only.
- RNE is the only v0.2 rounding policy. No public descriptor, command, Tile
  link, or MX quantizer transports a rounding selector.
- Descriptor version `2` is enforced at scheduler ingress. Older descriptors
  and reserved MX format encodings are rejected before any GEMM command issues.
- `npu_scheduler_pkg::npu_task_descriptor_t` contains the job/event fields,
  square matrix size, local A/B/output buffer identifiers and
  offsets, vector operation/control, optional B/C vector operands, and the
  feedback route.
- `matrix_size` selects the origin-anchored active prefix; hardware derives
  `ceil(matrix_size/16)` active physical rows/columns internally. The ABI has
  no Tile anchor/span fields and does not schedule block-matrix subregions.
- All descriptor and command widths are derived with `$bits(...)` in
  `npu_scheduler_pkg`; do not duplicate those widths in integration RTL.
- `output_mx_format` is the single descriptor source for Vector, external, and
  feedback MX encoding.
- `vector_result_route` selects external delivery or re-quantized activation
  feedback after Vector execution.
- A post-result beat contains a 512-bit data plane, `payload_kind`, MX format,
  E8M0 scale, invalid bits, and identity fields (`job_id`, `tag`, row, segment,
  `last`). FP32 and MX payloads therefore use one atomic ready/valid ABI.

## Source-only lint

Use the verification Makefile as the authoritative source list and command
interface. It compiles packages first and combines a resource-bounded 2x2
system-connection lint with independent zero-warning production PE and full
256-PE Tile lint targets.

```sh
make -C ../../../verification/npu/compute lint
```

For a lint-only source check, keep `sram_macro_blackbox.sv` in the command.
For synthesis or gate-level simulation, replace it with the exact generated
macro adapter and matching Liberty/LEF/GDS views for the selected SRAM
configuration. The behavioral SRAM models intentionally removed from this
tree must not be used as a substitute for that macro binding.

The command is a structural/lint gate only; it is not a claim of FPGA timing
closure or foundry signoff. Reusable functional regressions, reference models,
VIP, and waveform collateral are kept outside production RTL under
`verification/npu/compute/`.

## Verification

From the repository root, run:

```sh
make npu-compute-lint
make npu-compute-test
make npu-compute-waves
```

The verification environment substitutes its generic registered-read SRAM
model for the declaration-only macro boundary. It never compiles that model
in a synthesis source list. Tool executables resolve from `PATH`; the timing
gate requires a caller-supplied `LIBERTY_SSG`, so no developer-home or PDK-root
path is stored in this open-source tree.

## Integration notes

1. Compile the package files before modules that use their packed structs.
2. Connect the local-buffer write interfaces at `npu_square_gemm_system`; do
   not bypass them by adding external memory ports to the extracted RTL.
3. Keep `ARRAY_DIM=16` for the intended full-array configuration. Smaller
   parameter values are useful for bring-up but are not equivalent to the
   16 x 16 throughput configuration. The full-array regression verifies all
   65,536 PE results, 256 consecutive full-width A/B input cycles, and the
   256-FP32-per-cycle result boundary.
4. Preserve the ready/valid contract on all three post routes (external,
   vector, and feedback). Metadata must advance only with its payload.
   The 16-channel MX external formatter and Vector coupler both sustain sixteen
   result beats, or 256 elements, per cycle after pipeline fill. The external
   formatter uses elastic scale-reduction, scale-application, and encoding
   stages so this throughput is retained under backpressure while closing the
   mapped TSMC28 SSG 1 GHz setup gate.
5. The v0.2 feedback layout is non-transposed: result row `r` maps to
   `bank=r/16` and `stream=r%16`. Adjacent result segments form the 32-element
   MX block used directly as a later activation tensor.
6. Schedule only dot products whose A-plus-B E8M0 exponent is common across K.
   The sixteen Tile-level 85-bit accumulators rely on this compiler-owned
   invariant and do not perform a runtime scale-consistency check.
