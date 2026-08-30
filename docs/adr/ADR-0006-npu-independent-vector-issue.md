# ADR-0006: Independent Vector Issue Inside a Compute Cluster

- State: accepted and RTL-simulation verified
- Date: 2026-08-28
- Owners: NPU scheduler, compute integration, Vector interface, and verification

## Context

The Vector engines were previously reachable only as a GEMM post-processing
route. This prevented elementwise and special-function work already resident in
local SRAM from being issued without a synthetic GEMM. One Pod contains two
compute clusters, and each cluster already owns an Activation Buffer, Vector
B/C operand storage, the Vector backend, and external/feedback result paths.
Adding another Vector engine or another local SRAM would duplicate those
resources and create a second storage ABI.

The Pod NoC attachment is owned separately. Independent Vector issue must not
define or depend on NoC routing, credits, virtual channels, or packet payloads.

## Decision

Descriptor version 3 denotes an independent Vector task while preserving the
existing packed descriptor width. `operation=NPU_TASK_VECTOR` is required.
Version 2 remains the GEMM descriptor contract.

An independent task reads Vector A from the existing Activation Buffer in its
Tile-K-major layout. Vector B and C use the existing Vector operand buffers.
The new frontend decodes MXFP4/MXFP8 A data to the existing sixteen-element
FP32 Vector request shape. A fair per-physical-row arbiter merges that stream
with GEMM post-processing traffic before the unchanged Vector backend.

The Activation Buffer read port is shared with the GEMM executor through a
two-client round-robin arbiter. The executor now holds its Activation request
and address until `ready`; only an accepted Activation request launches the
matching Weight read and advances wave metadata. Under continuous two-client
contention, grants alternate, so either client waits for at most one competing
grant. Result streams retain their existing external or feedback destinations.

`npu_post_command_t.standalone` distinguishes completion contexts whose data
does not traverse the GEMM post-dispatch input. For those contexts, completion
from the shared Vector backend is the dispatch proof. GEMM post-processing
continues to require its existing accepted-beat count.

## Alternatives Considered

- A synthetic identity GEMM was rejected because it consumes Tensor capacity,
  changes numerical behavior, and cannot represent a true independent issue
  path.
- A second Vector backend and private A SRAM were rejected because they
  duplicate arithmetic and memory while fragmenting the local data layout.
- Extending the NoC was rejected because local Vector issue needs no network
  behavior and the NoC implementation has a separate owner.
- Independently handshaking Activation and Weight reads was rejected because
  it would require an additional response join buffer. Acceptance of the
  shared Activation read instead launches the uncontended Weight read in the
  same cycle, preserving the existing A/W response-pair contract.

## Consequences

Independent Vector tasks now execute without a GEMM command, Tensor A/B feeder
command, or GEMM result command. They reuse all existing arithmetic, operand,
output, feedback, tag, status, and Pod boundaries. Continuous simultaneous
GEMM and standalone Vector reads receive alternating SRAM grants. A lone GEMM
client retains one accepted Activation/Weight pair per cycle.

The implementation adds only cluster-local interfaces. It does not modify the
NoC attachment or define cross-Pod Vector operands.
