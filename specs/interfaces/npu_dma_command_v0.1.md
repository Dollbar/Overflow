# NPU Internal DMA Command and Completion v0.1

Status: baselined NPU-internal contract. This is not a KD-ISA encoding, runtime queue record, or IOVA
translation interface.

## 1. Scope and Ownership

One pod DMA consumes already-decoded commands whose HBM address has already been translated to the owning
partition. The NPU mover owns address generation, local resource admission, HBM beat production, SRAM
movement, response accounting, and an internal completion event.

External owners retain KD-ISA encoding and validation, submission and completion queues, IOVA translation,
protection domains, interrupts, cancellation policy, and runtime error/retry semantics. No packed layout in
this specification may be exposed as a software ABI.

## 2. Engine Geometry

| Quantity | v0.1 value |
| --- | ---: |
| DMA engines per logical NPU | 8, one per pod |
| Logical channels per engine | 16 |
| Total command contexts per channel | 4 |
| Executing commands per channel | 1 |
| Maximum queued commands while one executes | 3 |
| Queued or executing commands per engine | 64 |
| HBM beat bytes | 128 |
| HBM partition-local capacity | 24,000,000,000 bytes |
| Pod-local SRAM capacity | 16,777,216 bytes |
| Maximum bytes per command | 16,777,216 bytes |

All DMA RTL in this revision uses one synchronous service clock with active-high synchronous reset and
clear. Any CDC wrapper remains a separate contract.

## 3. Command Record

The authoritative packed type is `npu_dma_pkg::npu_dma_command_t`.

| Field | Width | Rule |
| --- | ---: | --- |
| `version` | 4 | Must equal 1 |
| `operation` | 2 | `0=HBM_TO_SRAM`, `1=SRAM_TO_HBM`; 2 and 3 are reserved |
| `command_id` | 16 | Opaque NPU-local identity returned unchanged on completion |
| `hbm_base_address` | 35 | Owning-partition byte address, 128-byte aligned |
| `sram_base_address` | 24 | Pod SRAM byte address, 128-byte aligned |
| `x_beat_count` | 18 | Contiguous beats per row, nonzero |
| `y_count` | 16 | Rows per plane, nonzero; use one for a linear transfer |
| `z_count` | 16 | Plane count, nonzero; use one for a 1D or 2D transfer |
| `hbm_y_stride` | 35 | Byte distance between HBM row starts, 128-byte aligned |
| `hbm_z_stride` | 35 | Byte distance between HBM plane starts, 128-byte aligned |
| `sram_y_stride` | 24 | Byte distance between SRAM row starts, 128-byte aligned |
| `sram_z_stride` | 24 | Byte distance between SRAM plane starts, 128-byte aligned |
| `qos` | 2 | Passed to the existing four-class HBM request arbiter |

The total beat count is `x_beat_count * y_count * z_count` and must be in the range 1 through 131,072.
The producing NPU adapter must enforce that bound before assertion of `command_valid`. The mover also checks
the version, operation, nonzero counts, alignment, address capacity, and generated-address overflow; a
producer violation returns an internal descriptor or address error and raises a sticky protocol diagnostic.

For X index `x`, Y index `y`, and Z index `z`, generated addresses are:

```text
HBM  = hbm_base_address  + z*hbm_z_stride  + y*hbm_y_stride  + x*128
SRAM = sram_base_address + z*sram_z_stride + y*sram_y_stride + x*128
```

Strides name the byte distance between starts, not padding added after a row or plane. Overlapping rows or
planes are legal because the SRAM is explicitly software-managed. Every generated HBM beat must start at
or below byte 23,999,999,872 and every generated SRAM beat at or below byte 16,777,088.

## 4. Command and Beat Handshakes

Commands, generated beats, SRAM requests, HBM requests, HBM responses, and completions use ready/valid.
While valid is high and ready is low, payload and identity remain stable. An event transfers only on the
rising edge where valid and ready are both high.

One channel does not admit a second executing command until the current command's completion event is
accepted. The queue storage has four entries, while admission limits the combined queued-plus-executing
occupancy to four contexts. Quiesce closes new command admission but continues dequeuing already accepted
commands; the HBM boundary closes only after all accepted commands and movers have drained.

## 5. Data Movement and Completion

For `HBM_TO_SRAM`, the mover emits one HBM read per generated beat. On request acceptance it stores the SRAM
destination and final-beat flag under the returned channel-local tag. A response is consumed only when the
corresponding SRAM write can commit. The command completes after every accepted request has retired and the
final SRAM write has committed.

For `SRAM_TO_HBM`, the mover reads the generated SRAM beat, retains it under backpressure, and emits one HBM
write with all 128 byte enables asserted. The command completes only after every write response retires.

Corrected ECC does not fail a command but is retained in the completion event. Uncorrectable ECC and data
error fail the command after all already accepted work drains. V0.1 does not replay or retry a failed beat.
The mover never releases a tag before the corresponding response is consumed.

## 6. Internal Completion

The authoritative packed type is `npu_dma_pkg::npu_dma_completion_t`.

| Field | Width | Rule |
| --- | ---: | --- |
| `command_id` | 16 | Echoes the accepted command |
| `success` | 1 | One only when the internal error code is `OK` |
| `error_code` | 3 | Internal classification defined by `npu_dma_error_e` |
| `corrected_ecc_seen` | 1 | At least one consumed beat reported corrected ECC |
| `beats_completed` | 18 | Destination-committed beats, maximum 131,072 |

The error classes are `OK`, `DESCRIPTOR`, `ADDRESS`, `HBM_UNCORRECTABLE`, `HBM_DATA`, `SRAM`, and
`INTERNAL`; value seven is reserved. These values are local hardware classifications, not runtime ABI
numbers and not retryability decisions.

## 7. Exclusions

V0.1 excludes partial first/last beats, scatter/gather, indexed movement, multicast, zero-fill,
cancellation, timeout, automatic replay, address translation, protection checks, NoC movement, interrupts,
and runtime queue handling. Later revisions must extend the versioned command rather than reinterpret a
reserved operation.

## 8. Required Evidence

The address generator requires directed and randomized 1D/2D/3D sequence checks, ready/valid stability,
alignment/count/version rejection, HBM and SRAM capacity overflow injection, clear/reset tests,
zero-warning lint, synthesis-readiness, and mapped 1 GHz generic STA.

The complete mover additionally requires randomized bidirectional movement through an HBM BFM and SRAM
scoreboard, all sixteen channels, five-lane saturation where the selected SRAM service permits it, tag
metadata checks, independent HBM/SRAM/completion backpressure, all four response statuses, quiesce/drain,
complete error drain, counter agreement, zero-warning lint, synthesis-readiness, and mapped generic STA.
