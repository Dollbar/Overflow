# NPU GEMM/Vector Core Digital Interface v0.1

Status: versioned RTL integration contract. Numerical and throughput claims require the evidence named in
the verification section.

## 1. Boundary

The integration top is `npu_square_gemm_system`. Its upstream boundary starts after external transfer logic
has placed descriptors, A/B tensor beats, and optional vector operands in local input buffers. HBM, DMA,
host queues, foundry SRAM implementation, and physical design are outside this contract.

The core owns descriptor commit, task issue, local-buffer reads, GEMM execution, result collection,
post-route selection, vector processing, and FP32-to-FP8 feedback. All ports are synchronous to `clk_i`.
`rst_i` and `clear_i` are active-high synchronous controls. A transfer occurs only when both `valid` and
`ready` are high at a rising edge.

## 2. Descriptor Commit Protocol

Descriptor storage is random-access so software or an upstream queue manager can prepare independent slots.
Writing a slot does not make it visible to scheduling. A subsequent submit of the same index atomically
commits the complete descriptor.

| Channel | Payload | Behavior |
| --- | --- | --- |
| descriptor write | slot index and `npu_task_descriptor_t` | Stores or replaces one uncommitted slot |
| descriptor submit | slot index | Makes a previously written slot available to the scheduler |
| status | `npu_task_status_t` | Reports completion or a protocol-level task error |

Submitting an unwritten slot raises the sticky `protocol_error_o`. Reset or clear discards written but
unsubmitted descriptors and any descriptor currently held at the task output.

The scheduler does not validate compiler-owned matrix size, Tile placement, buffer alignment, or operation
legality. The compiler must provide non-overlapping Tile regions, square matrices, valid local-buffer
addresses, and supported enum encodings.

## 3. Packed Descriptor ABI

The authoritative type is `npu_scheduler_pkg::npu_task_descriptor_t`; consumers must derive its width with
`$bits(...)`. In v0.1 the packed width is 349 bits and the first declared field is the most significant.

| Bits | Field | Purpose |
| --- | --- | --- |
| `[348:345]` | `version` | Descriptor ABI version |
| `[344:342]` | `operation` | Top-level task operation |
| `[341:326]` | `job_id` | Software-visible task identity |
| `[325]`, `[324:317]` | wait-event valid and ID | Optional issue dependency |
| `[316]`, `[315:308]` | signal-event valid and ID | Optional completion event |
| `[307:304]`, `[303:300]` | Tile anchor X and Y | Compiler-selected array origin |
| `[299:284]` | `matrix_size` | Square matrix dimension in elements |
| `[283:279]` | `tile_span` | Active Tile span on each dimension |
| `[278:263]` | `k_blocks` | Number of 16-element K blocks |
| `[262:259]`, `[258:227]` | activation buffer ID and offset | Local A operand location |
| `[226:223]`, `[222:191]` | weight buffer ID and offset | Local B operand location |
| `[190:187]`, `[186:155]` | output buffer ID and offset | Destination location |
| `[154]`, `[153]` | activation and weight FP8 formats | E4M3 or E5M2 selection |
| `[152:151]` | rounding | FP8 rounding mode |
| `[150:149]` | post route | External, vector, or GEMM feedback |
| `[148:107]` | vector control | Lane mask, operation, sources, epilogue, and norm controls |
| `[106:103]`, `[102:71]` | vector-B buffer ID and offset | Optional vector operand B |
| `[70:67]`, `[66:35]` | vector-C buffer ID and offset | Optional bias/residual operand C |
| `[34:3]` | vector scalar | Scalar operand or epsilon |
| `[2]` | feedback operand | Selects the GEMM feedback operand |
| `[1]` | feedback transpose | Enables feedback layout transposition |
| `[0]` | output format | FP32 or FP8 result selection |

The nested vector-control tag is not a software task identity. The input scheduler allocates the hardware
tag used to match in-flight commands, result beats, post-processing, and completion.

## 4. Tensor and Vector Input Buffers

Each accepted tensor write carries one 128-bit beat, equal to sixteen FP8 elements. The write selects A or
B storage, a local buffer ID, a physical bank, and a beat offset. With the production `ARRAY_DIM=16`, the
executor reads sixteen banks in parallel and presents sixteen 128-bit A beats and sixteen 128-bit B beats
per active array cycle. The scalar external write port is a buffer-fill interface, not the aggregate GEMM
issue bandwidth.

Optional vector B and C operands use independent local stores. One accepted vector-operand write carries a
512-bit beat, equal to sixteen FP32 elements, plus buffer, bank, and offset selection.

Storage depth, banking, and compiler layout must agree. This contract does not define an external-memory
address or permit direct HBM access from the core.

## 5. Result and Post-Route Protocol

`npu_post_result_beat_t` is 574 bits:

| Field | Width | Meaning |
| --- | ---: | --- |
| `data` | 512 | Sixteen FP32 result elements |
| `invalid` | 16 | Per-element invalid flags |
| `job_id` | 16 | Software task identity |
| `tag` | 8 | Hardware in-flight identity |
| `row` | 16 | Matrix row coordinate |
| `segment` | 5 | Sixteen-element segment within the row |
| `last` | 1 | Final beat of the task |

The post scheduler selects exactly one descriptor-requested route: external output, vector processing, or
GEMM feedback. The production boundary has sixteen independently handshaken result channels. Payload and
all metadata are atomic and must remain stable while `valid=1` and `ready=0`.

The vector path instantiates one `vector_engine16` per physical row, so sixteen channels can consume 256
FP32 elements per cycle when all channels are ready. Individual operators may complete out of issue order;
the hardware tag preserves identity through their result FIFOs.

## 6. SRAM Replacement Contract

Production RTL only declares `SRAM_32_32`, `SRAM_32_64`, and `SRAM_32_128` replacement points. Each is a
32-word true-dual-port memory with full-word writes and registered read data/valid. A read request accepted
before a rising edge produces valid read data after that edge. Reset clears read-valid state but does not
require memory contents to be cleared.

Same-address accesses involving a write on both ports are outside this contract. The selected macro adapter
must match the declaration's width, depth, port behavior, Liberty, LEF, and physical views. The behavioral
model under `verification/` is simulation-only and must never enter synthesis source lists.

## 7. Verification

The authoritative commands are:

```bash
make -C verification/npu/gemm_vector lint
make -C verification/npu/gemm_vector test
make -C verification/npu/gemm_vector waves
```

`tb_descriptor_path` checks atomic write/submit, output hold, slot reuse, clear/reset, and unwritten-slot
errors. `tb_npu_input_scheduler` checks event bypass, atomic command fanout, tag completion, and continuous
issue. `tb_vector_engine16` checks all seven operator pipelines, mixed-latency tag matching, collision
capture, backpressure, and recovery. `tb_sram_macro_contract` checks all three SRAM widths and registered
dual-port reads. Passing these tests is `RTL_SIM` evidence for the tested configurations, not physical
timing, CDC, synthesis, or full-model evidence.
