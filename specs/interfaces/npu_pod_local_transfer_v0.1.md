# NPU Pod Shared-to-Private Local Transfer v0.1

Status: baselined NPU-internal compatibility contract.

## 1. Scope

This interface moves an already-resident pair of 128-byte data and scale beats from one Pod-shared SRAM
into the current 128-bit write boundary of one compute cluster. It is an internal ownership-transition
adapter, not a DMA descriptor, KD-ISA encoding, runtime ABI, NoC packet, or coherence mechanism.

One Pod instantiates one loader per compute cluster. Arbitration that assigns the two loader clients to
the shared SRAM belongs to the Pod wrapper. V0.1 intentionally favors compatibility and verification over
the final bandwidth target; a wider double-buffered loader requires a later revision of the compute-local
SRAM write boundary.

## 2. Command

The packed command is 114 bits and contains fields in the order declared by
`npu_pod_local_transfer_t`:

| Field | Width | Meaning |
| --- | ---: | --- |
| `version` | 4 | Must equal 1 |
| `transfer_id` | 16 | NPU-internal completion identity |
| `target` | 2 | Tensor activation, Tensor weight, Vector B, or Vector C |
| `buffer_id` | 4 | Existing compute-local buffer identifier; v0.1 accepts 0 through 3 |
| `bank_start` | 4 | First of sixteen compute-local banks |
| `local_offset` | 32 | Common byte offset written in every selected bank; 16-byte aligned |
| `data_sram_address` | 24 | Aligned Pod-shared SRAM data-beat address |
| `scale_sram_address` | 24 | Aligned Pod-shared SRAM scale-beat address |
| `word_count` | 4 | Number of consecutive banks, 1 through 8 |

`bank_start + word_count` must not exceed sixteen. Both shared addresses are 128-byte aligned and select a
complete beat inside the 16 MiB Pod SRAM. The local offset must select one of the current 8,192 128-bit
words per buffer and bank.

## 3. Data Mapping

The loader reads the data beat first and the scale beat second. Word `n` maps data bits
`[128*n +: 128]` to local bank `bank_start + n` at the same `buffer_id` and `local_offset`.

For Tensor targets, scale bits `[128*n +: 128]` accompany word `n`. For Vector targets, only scale bits
`[8*n +: 8]` accompany word `n`; the remainder of the scale beat is reserved and ignored. V0.1 emits at
most one 128-bit local write per cycle, so one valid command takes at least two shared-SRAM reads plus
`word_count` local-write cycles.

## 4. Ready/Valid, Completion, and Quiesce

All command, shared-SRAM, local-write, and completion channels use ready/valid. Payload remains stable
while valid is asserted without ready. Only one command is active in a loader. An accepted command drains
to completion even if `quiesce_i` is asserted; quiesce blocks new command admission and is reported settled
only when the loader is idle.

The 20-bit completion contains `transfer_id`, `success`, and a three-bit internal error class. Malformed
commands complete unsuccessfully without issuing a shared-SRAM request and set sticky local
`protocol_error_o`. These error values are diagnostics and are not software-visible status encodings.

Reset or clear removes active protocol state and valid outputs but does not modify SRAM contents. The Pod
owner must quiesce traffic before clear when lossless completion is required.

## 5. Required Evidence

Required evidence includes zero-warning lint, synthesis-readiness checks, Tensor and Vector mapping,
shared request and local write backpressure, completion stability, invalid version/count/bank/alignment/
range checks, reset, clear, and drain-on-quiesce behavior.
