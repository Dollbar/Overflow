# NPU Already-Decoded Command and Completion v0.1

Status: baselined NPU-internal contract. This is not KD-ISA or a software ABI.

## Scope

The contract joins a trusted decoder/translation boundary to one managed Pod. It carries already-decoded
Task, Pod-local transfer, or DMA records. It does not define queue memory, doorbells, instruction encoding,
virtual-address translation, cancellation, interrupts, retry, or runtime-visible completion layout.

## Command Record

`npu_decoded_command_t` is a 372-bit packed record:

| Bits | Field | Meaning |
| --- | --- | --- |
| `[371:368]` | `version` | `4'd1` |
| `[367:366]` | `command_class` | Task `0`, local `1`, DMA `2`; `3` is invalid |
| `[365:350]` | `request_id` | Must equal the selected leaf record ID |
| `[349:347]` | `pod_id` | Destination Pod `0..7` |
| `[346]` | `target_valid` | Task affinity valid; mandatory for local and DMA |
| `[345:342]` | `target` | Cluster for Task/local or DMA channel |
| `[341:0]` | `payload` | Zero-extended leaf record |

Task payloads accept GEMM descriptor version 2 and independent-Vector descriptor version 3. Local payloads
use Pod local-transfer version 1. DMA payloads use DMA command version 1. A gateway rejects a wrong envelope
version, reserved class, wrong Pod, out-of-range target, mismatched request ID, or unsupported leaf version.

## Completion Record

`npu_unified_completion_t` is a 66-bit packed record:

| Bits | Field | Meaning |
| --- | --- | --- |
| `[65:64]` | `source` | Task `0`, local `1`, DMA `2`, command-validation `3` |
| `[63:48]` | `request_id` | Original leaf or rejected-envelope request ID |
| `[47:45]` | `pod_id` | Producing Pod |
| `[44:41]` | `target` | Producing cluster/channel or rejected target |
| `[40]` | `success` | One only for successful leaf completion |
| `[39:32]` | `code` | Zero on success; source-specific error otherwise |
| `[31:0]` | `detail` | Task tag in `[7:0]`; DMA beat count in `[17:0]`, corrected ECC in `[31]` |

## Flow Control and Quiesce

A transfer occurs on a rising edge with `valid && ready`. Producers hold all payload bits stable while
stalled. Valid commands are forwarded without an implicit acceptance queue. Invalid commands use a
one-entry error slot. Completion arbitration captures one leaf response into a stable one-entry output
buffer. Selection rotates after every leaf capture, preventing permanent starvation.

`quiesce_i` blocks new commands. Buffered error and unified completions remain deliverable. Reset and clear
synchronously discard gateway-local buffered state and clear counters and sticky diagnostics.

## Ownership Boundary

The queue/ISA owner supplies one decoded command to the matching Pod lane. Multi-Pod distribution and clock
crossing are outside this contract. The NPU owns validation, leaf dispatch, completion aggregation, counters,
and the malformed-command indication.
