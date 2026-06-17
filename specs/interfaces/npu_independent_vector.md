# NPU Independent Vector Issue Contract

Status: implemented and RTL-simulation verified cluster-local contract.

## Descriptor and Admission

Independent Vector tasks use the existing `npu_task_descriptor_t` packed width
with these interpretations:

| Field | Required meaning |
| --- | --- |
| `version` | `NPU_VECTOR_TASK_DESCRIPTOR_VERSION` (`3`) |
| `operation` | `NPU_TASK_VECTOR` |
| `matrix_size` | square logical tensor dimension, `1..ARRAY_DIM*16` |
| `activation_*` | Vector A buffer, byte base offset, and MX format |
| `vector_b_*`, `vector_c_*` | existing optional Vector B/C operands |
| `vector_control` | unchanged Vector operation and lane controls |
| `vector_result_route` | external result or Activation feedback |
| `output_*` | unchanged FP32/MX output selection |

The scheduler emits one Vector command and one post command atomically. It does
not emit GEMM, Activation-feeder, Weight-feeder, or GEMM-result commands. An
unsupported version, operation, format, or matrix dimension is rejected before
context allocation.

## Vector A Storage Layout

Vector A reuses the existing banked Activation Buffer. Logical row `r` maps to
`bank=floor(r/16)` and `local_row=r mod 16`. Let
`segment=0..ceil(matrix_size/16)-1`.

```text
MXFP8 word = base + 16 * (segment * 16 + local_row)
MXFP4 word = base + 16 * (floor(segment / 2) * 16 + local_row)
MXFP4 half = segment mod 2
```

Offsets are byte addresses. This is the same Tile-K-major image used by GEMM
activation reads and feedback writes; no repacking step or additional SRAM is
introduced. All physical banks are read together. Rows beyond `matrix_size`
and elements beyond the final segment are suppressed with valid/invalid masks.

The SRAM arbiter applies two-client round-robin service to GEMM and standalone
Vector reads. Both clients hold valid and address until ready. When both remain
asserted, grants alternate; therefore either request is accepted after at most
one competing grant. A GEMM Weight read is launched only when its corresponding
Activation read is accepted, keeping A/W responses paired without another join
buffer. With no Vector request, GEMM retains one accepted pair per cycle.

## Backend, Results, and Completion

MXFP4 E2M1 or MXFP8 E4M3FN A elements and E8M0 scales are decoded to FP32, then
sent through the unchanged `vector_engine16` operator selected by
`vector_control.operation`. B/C reads, arithmetic, result formatting, feedback,
tags, and status reuse the existing GEMM/Vector backend.

GEMM-post and standalone sources are arbitrated independently per physical row.
Each accepted output keeps result and post-command metadata atomic under
backpressure. A source that loses contention retains its payload; preference
toggles after a contested transfer.

For `NPU_PAYLOAD_FP32_VECTOR`, `mx_format` and `mx_scale` are canonical zero and
must not be interpreted as the input format. They are meaningful only for
`NPU_PAYLOAD_MX_VECTOR`.

The shared Vector backend emits one completion after exactly
`matrix_size*ceil(matrix_size/16)` accepted result beats. The standalone bit in
the post command permits the post scheduler to accept that backend completion
without waiting for GEMM-dispatch accounting. The normal tag-matched task
status and event behavior is unchanged.

## Verification

The authoritative directed regression is:

```bash
make -C verification/npu/compute lint-independent-vector
make -C verification/npu/compute sim-independent-vector JOBS=4
make -C verification/npu/compute sim-activation-fairness JOBS=4
make -C verification/npu/compute sim-buffer-stream-stall JOBS=4
```

It writes address-distinct MXFP8 segments through the production local-buffer
write port, submits a version-3 task, applies independent result backpressure,
and checks 36 beats for `matrix_size=18`, numerical values, coordinates, tail
masks, last, tag/status completion, quiet GEMM/feedback outputs, and protocol
diagnostics. Existing scheduler, descriptor, GEMM-to-Vector coupler, System,
and Pod regressions remain required compatibility gates. The fairness test
holds both SRAM clients continuously active and checks alternating grants and
response ownership. The stalled-buffer test withholds every other Activation
grant and verifies that all 256 GEMM A/W pairs remain aligned and numerically
correct.
