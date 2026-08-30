# NPU GEMM/Vector Core Digital Interface — MX Revision v0.2

Status: implementation contract for the MX-only compute path. This document
supersedes v0.1 for new integrations. The v0.1 document remains historical and
does not define a compatible descriptor encoding.

## 1. Boundary and Numeric Formats

The integration boundary remains `npu_square_gemm_system`: descriptors and
local-buffer tensor words have already been transferred into the core boundary.
HBM, DMA, host queues, and physical SRAM implementations are outside this
contract.

The public tensor formats are exclusively:

| Encoding | Tensor format | Element encoding | Shared scale |
| ---: | --- | --- | --- |
| `0` | MXFP4 E2M1 | sign, 2-bit exponent, 1-bit fraction | E8M0 |
| `1` | MXFP8 E4M3FN | sign, 4-bit exponent, 3-bit fraction | E8M0 |
| `2` | reserved | rejected at descriptor ingress; deterministic NaN at a numeric boundary | E8M0 |
| `3` | reserved | rejected at descriptor ingress; deterministic NaN at a numeric boundary | E8M0 |

Plain FP4 and plain FP8 are not public v0.2 tensor formats. IEEE FP32 remains
the internal Vector arithmetic and architectural GEMM result format; it is not
an input tensor encoding.

Every MX block contains exactly 32 elements. An E8M0 scale byte `S` represents
the exact power of two `2^(S-127)` for `S=0x00..0xfe`; `S=0xff` is NaN. The
compiler guarantees 32-element K alignment, nonzero `k_blocks`, valid matrix bounds,
and one common combined A-plus-B scale exponent for every product contributing
to an output dot product. Hardware does not check scale compatibility or add
redundant legality and busy checks for those compiler-owned properties.

## 2. Local Tensor Storage

The physical tensor data word is 128 bits. Offsets are byte addresses relative
to a selected local buffer and must address the start of a physical word.

### MXFP8

One physical word stores sixteen consecutive 8-bit elements. Two consecutive
words form one 32-element MX block and carry the same E8M0 scale. The ingress
writer supplies the scale with each word; repeating it removes a second scale
read from the banked SRAM critical path.

### MXFP4

One physical word stores one complete 32-element block. Elements 0 through 15
occupy nibbles `data[4*i +: 4]`; elements 16 through 31 occupy nibbles
`data[64 + 4*i +: 4]`. The local buffer expands the selected half into sixteen
8-bit lane containers before the Tile boundary. Bits `[7:4]` of each expanded
container are zero.

The executor addresses the Tile-friendly physical layout as follows, where
`slice` is a 16-element K slice and `stream` identifies the local row/column
within a Tile:

```text
MXFP8 physical_word = slice * 16 + stream
MXFP4 physical_word = floor(slice / 2) * 16 + stream
MXFP4 half          = slice mod 2
```

Activation and weight buffers use the same packing. Each accepted physical-word
write carries `data[127:0]` and `scale[7:0]`. The production implementation must
bind data and scale arrays to matching SRAM macro adapters; behavioral arrays are
verification-only.

The production defaults are four logical IDs, sixteen banks, and 8192 physical
words per bank. Each independently addressed Tensor-A, Tensor-B, Vector-B, or
Vector-C data store therefore has
`4 * 16 * 8192 * 16 bytes = 8 MiB` capacity. Scale arrays are distinct metadata
SRAMs and do not consume this declared 8 MiB data capacity. The executor's
two-entry A/B pair FIFO is only an elasticity stage; it is deliberately not the
8 MiB tensor store.

## 3. GEMM Numerical Contract

`k_blocks` counts 32-element MX blocks. The executor expands it to two
16-element Tile injection slices while preserving matrix coordinates.

For every output element, the Tile-reduction Tensor path:

1. decodes E2M1 or E4M3FN elements without rounding;
2. uses each PE only to emit one exact product per compute cycle;
3. reduces sixteen products per K slice through a pipelined Tile adder tree into
   signed 70-bit Q32;
4. sign-extends each Tile sum into one of sixteen signed 85-bit Q32 long-K
   accumulators (there is no 85-bit accumulator inside a PE);
5. accumulates as many as `256*4096 = 2^20` products without intermediate
   rounding under the compiler-guaranteed common combined scale; and
6. applies that scale and converts to IEEE FP32 exactly once, at matrix-result
   submission, using round-to-nearest, ties-to-even (RNE).

The 85-bit bound is the v0.2 contract, not an unbounded accumulator. It depends
on the compiler keeping the combined A-plus-B E8M0 exponent constant across the
complete dot product; hardware consumes the supplied exponent but does not
detect a violation. E8M0 NaN and E4M3FN NaN propagate to canonical FP32 NaN.
MXFP8 has no infinity encoding in v0.2.

The production array remains 16 by 16 Tiles with 256 exact-product PEs per Tile.
Each Tile has two 16-cycle operand banks. In steady state one bank accepts the
next atomic A/B beat while the other drives all 256 PEs, and the selectors swap
without an inter-bank bubble. The
direct A and B links carry one 128-bit expanded lane beat, a 2-bit MX format, an
8-bit E8M0 scale, and existing identity/control metadata. A enters only at the
west boundary and propagates east; B enters only at the north boundary and
propagates south. The GEMM path has no Tile packet router or alternate
injection path.

The array interface is dense. For an active 256-by-256, K=256 command, the
executor supplies 256 A elements and 256 B elements on every one of 256
consecutive cycles. `GEMM_65536` delays complete 16-lane Tile groups according
to Tile row/column before the direct links. It does not skew individual PE
operands. This preserves numerical alignment without an executor-side issue
bubble or extending the command read count beyond K.

## 4. Descriptor ABI

The descriptor `version` field is `2`. The scheduler rejects every other
version with `NPU_TASK_ERROR_VERSION` before allocating a context or emitting
any command. `activation_format` and `weight_format`
are 2-bit `mxfp_format_e` values. Vector B and C operands have independent
2-bit MX format fields because bias, residual, and affine tensors need not match
the GEMM activation encoding. Encodings `2` and `3` are rejected with
`NPU_TASK_ERROR_FORMAT`. RNE is the only v0.2 rounding policy; there is no
descriptor, command, Tile-link, or MX-quantizer rounding field.

The v0.2 packed descriptor is 342 bits and `npu_post_result_t` is 586 bits.
Package constants derived through `$bits(...)` remain authoritative; integration
logic must not duplicate those widths in RTL. Writing a descriptor slot still
does not issue it. A subsequent submit of the same slot atomically commits the
descriptor.

`matrix_size` is the only matrix-geometry control. Hardware derives
`ceil(matrix_size/16)` and activates that origin-anchored physical prefix. The
descriptor has no `tile_anchor_x`, `tile_anchor_y`, or `tile_span`; software
cannot place a GEMM in an arbitrary Tile subarray, and the executor does not
perform block-matrix scheduling.

`output_mx_format` independently selects MXFP4 E2M1 or MXFP8 E4M3FN for Vector,
external, and feedback quantization. The scheduler copies this
single field into every downstream command and overrides duplicate Vector
epilogue format controls so one descriptor cannot request inconsistent output
encodings.

`vector_result_route` independently chooses external delivery or feedback
storage after Vector execution. Vector-to-feedback commands keep the Vector
arithmetic response in FP32 and perform the required 32-element MX quantization
at the feedback storage boundary; Vector-to-external commands may emit FP32 or
self-describing MX beats directly.

The scheduler allocates the hardware tag and copies all MX format fields into the
GEMM, buffer-read, Vector, result, and post-route commands. The compiler remains
responsible for format consistency and block alignment.

Independent Vector issue is a compatible reinterpretation of this same packed
descriptor width. It requires `version=3` and `operation=NPU_TASK_VECTOR`;
GEMM remains `version=2`. The scheduler emits only Vector and post commands for
version 3. Vector A reuses the Activation Buffer's Tile-K-major layout, while B
and C retain the existing Vector operand stores. The detailed layout,
arbitration, and completion contract is defined in
[`npu_independent_vector.md`](npu_independent_vector.md).

## 5. Vector and Post Routes

The Vector arithmetic pipelines remain 16-lane IEEE FP32 pipelines. MX support
is implemented at their storage boundaries:

```text
local MX operand + E8M0 scale -> MX decode -> 16 FP32 Vector lanes
two adjacent FP32 result beats -> 32-element MX quantizer -> local/output MX block
```

Vector B and C local stores use the same 128-bit MX packing and scale convention
as Tensor storage. A Vector command identifies their formats. GEMM-to-Vector
traffic remains 512-bit FP32 because GEMM has already performed its one final
matrix conversion after exact cross-block accumulation.

An independent Vector frontend also decodes local MX A data into this same
FP32 request boundary. A fair per-row arbiter merges independent and GEMM-post
sources; it does not modify any Vector arithmetic pipeline.

At the `vector_engine16` response boundary, each accepted 16-lane request still
produces one response with its original `tag`, lane mask, and `last`. For MXFP8,
the two responses forming a block each carry sixteen encoded bytes and the same
scale. For MXFP4, each response carries sixteen nibbles in `mx_vector[63:0]`,
with `mx_vector[127:64]=0`; concatenating the second low half after the first
low half yields the packed 128-bit storage word. The compiler emits compatible
format controls for both beats and does not terminate a block after its first
beat. Both beats are quantized with RNE.

Feedback and MX external storage quantization operate on 32 elements, not on an
isolated 16-lane beat. The quantizer selects one E8M0 scale for the pair, emits
two coordinate-preserving result beats for every format, and preserves
`job_id`, `tag`, row, segment, and `last` ordering. Each MXFP8 beat carries one
16-byte half; each MXFP4 beat carries one 8-byte half in `data[63:0]`, and the
feedback store packs the adjacent halves into one 128-bit physical word. No
route may silently emit plain FP8/FP4.

Every post-result beat is self-describing. In addition to its 512-bit data
plane and identity fields it carries `payload_kind`, `mx_format`, and the E8M0
`mx_scale`. FP32 GEMM beats set `payload_kind=FP32_VECTOR`; MX Vector and
external beats set `payload_kind=MX_VECTOR` and repeat the same scale on the two
responses belonging to one 32-element block. These fields advance atomically
with data under backpressure.

Feedback does not transpose the result in v0.2. Result row `r` maps to
`bank=floor(r/16)` and `stream=r mod 16`; adjacent result segments form one
block. The physical write address is `(slice*16+stream)*16` bytes for MXFP8 and
`(floor(slice/2)*16+stream)*16` bytes for MXFP4. This layout allows a feedback
matrix to be consumed directly as the next GEMM activation input.

Both direct GEMM feedback and Vector-result feedback use this same writer and
storage layout. Arbitration occurs only if software illegally overlaps the two
destinations; a single selected route retains the full sixteen-channel input
rate and bubble-free bank drain.

## 6. Throughput and Backpressure

At `ARRAY_DIM=16`, the aggregate GEMM-to-Vector boundary remains sixteen
independent 512-bit channels: 256 FP32 elements per cycle. MX decoding and
quantization are replicated per physical row so a single row cannot block the
other fifteen. Command switching may consume one descriptor every cycle when
real FIFO/context credit exists. The design may backpressure only on actual
storage or downstream credit exhaustion; no single-request busy interlock is
part of the v0.2 protocol.

After the initial two-beat block fill, the external MX formatter emits sixteen
result beats every cycle while `ready` remains asserted. It emits the previous
block's second beat in the same cycle that it accepts the next block's first
beat, so block pairing introduces no steady-state bubble.

At a declared 1 GHz clock, a continuously occupied 65,536-PE array performs
65,536 multiply-accumulates per cycle. Counting a multiply and an add as two
operations gives an `ANALYTICAL` dense peak of 131.072 TOPS. The dense-input
RTL regression proves the issue pattern and arithmetic results; it is not a
full-array post-layout timing or power claim.

## 7. Verification Evidence

The authoritative targets are:

```bash
make -C verification/npu/compute lint
make -C verification/npu/compute test
make -C verification/npu/compute waves
```

Required v0.2 regressions cover both MX formats, reserved-format rejection,
descriptor-version rejection, E8M0 boundary values and NaN, subnormal elements,
exact 32-element block reduction, 85-bit matrix
accumulation through `2^20` products, one final FP32 rounding, packed MXFP4
halves, MXFP8 scale sharing, descriptor-to-Tile scale propagation, Vector
operand decode, paired feedback quantization, continuous commands, reset/clear
recovery, real-credit backpressure, the `K=4096` Tile path, and the complete
fixed-origin 16-by-16 Tile array at its
256-cycle dense A/B input boundary and 256-FP32-per-cycle result boundary. The
buffer-stream regression also elaborates the 8 MiB A/B configuration and
checks both K=256 and K=4096 continuous traffic over the real local-buffer read
path into the executor. A resource-bounded K=8192 heterogeneous regression
adds 16,384 dense input cycles and 4,194,304 checked A/B lane pairs across the
external and feedback routes; it uses production buffers, schedulers,
transport, formatter, and feedback logic with verification GEMM/Vector
arithmetic models. The parameterized GiB regression repeats those K=8192
external/feedback tasks 128 times per route, checks 2,097,152 full-rate cycles,
536,870,912 A/B lane pairs, and exactly 1,073,741,824 operand bytes. Once an
input or result burst starts, a missing cycle or partial lane-valid mask is a
test failure. `make test` also requires the mapped `PE_FP8` and complete
16-channel external MX formatter setup checks to pass at TSMC28 HPC+ SSG
0.72 V/125 C with a 1.000 ns clock. RTL simulation remains `RTL_SIM`; the
timing result is pre-layout STA
evidence and is not CTS/parasitic, CDC, physical-array, or signoff evidence.
