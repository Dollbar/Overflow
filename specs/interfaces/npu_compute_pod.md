# NPU Complete Compute Pod v0.1

Status: baselined and RTL-simulation verified NPU-internal integration contract.

## 1. Composition

One `npu_compute_pod` contains exactly:

- two `npu_square_gemm_system` compute clusters;
- one two-cluster allocation and completion scoreboard;
- two shared-to-private local loaders, one per compute cluster;
- one sixteen-channel `npu_dma_engine`;
- one 16 MiB, eight-bank `npu_pod_shared_sram`; and
- two fair DMA/loader read multiplexers on shared-SRAM client slots zero and one.

The Pod exposes the five-lane logical HBM interface from ADR-0002. It does not contain an HBM controller,
PHY, KD-ISA decoder, runtime queue, NoC router, or KDLink adapter. Those boundaries remain externally owned
or held.

ADR-0005 defines `npu_pod_noc_attachment` as a separately verified sibling boundary for future Pod packet
clients. It is not wired into `npu_compute_pod` v0.1 because remote-DMA and other cross-Pod payload
semantics are not yet approved; this preserves the completed local Pod behavior while giving the NoC team
a stable logical handoff.

## 2. Task Dispatch and Completion

The Pod task input carries one already-decoded `npu_task_descriptor_t`, an optional preferred-cluster bit,
and ready/valid. With no preference, allocation is round-robin across free clusters. With a preference, the
command waits until that cluster is free.

V0.1 reserves at most one Pod-level task per compute cluster. After allocation, the Pod writes the complete
descriptor to local descriptor slot zero and submits that slot atomically. Reusing slot zero is safe because
the compute descriptor buffer copies the descriptor into its task queue on submit. The Pod accepts another
task only after the preceding descriptor has completed the write/submit sequence.

The full `npu_task_status_t` returned by a compute cluster is matched against its reserved job identifier,
buffered in a two-entry completion FIFO, and returned with the selected cluster index. Completion remains
stable under backpressure. Duplicate active job identifiers are diagnosed but still carry distinct cluster
identity and retire independently.

## 3. Shared SRAM Integration

All sixteen DMA write clients connect directly to the sixteen shared-SRAM write clients. DMA read clients
two through fifteen also connect directly. DMA read client zero shares SRAM client zero with loader zero;
DMA read client one shares SRAM client one with loader one.

Each two-source read multiplexer permits one outstanding request, records its owner until response
consumption, preserves payload under response backpressure, supports same-cycle response retirement and
next-request admission, and alternates priority after every accepted request. Loader traffic therefore does
not change the frozen sixteen-client physical SRAM interface or the DMA channel count.

Local-loader commands and mappings follow `npu_pod_local_transfer.md`. Tensor and Vector local writes
connect only to the loader associated with the same compute cluster.

## 4. Result, Event, and HBM Boundaries

Each compute cluster retains all existing GEMM external, Vector, and feedback result streams. The Pod
flattens the two clusters into `2 * ARRAY_DIM` independent ready/valid result channels without adding
cross-cluster arbitration. Event set and clear inputs also remain independent per cluster.

Each cluster also accepts the independent Vector descriptor contract. Vector A
reuses that cluster's private Activation Buffer; Vector B/C and result paths are
unchanged. This is entirely cluster-local and does not add a Pod-shared SRAM or
NoC request path.

DMA commands, completions, telemetry, tag lifetimes, and HBM request/response behavior are inherited from
the NPU DMA v0.1 contracts. `PARTITION_ID` fixes one Pod's local HBM affinity; local DMA and loader traffic
never traverses a NoC.

## 5. Clock, Reset, Quiesce, and Errors

V0.1 uses one synchronous clock plus synchronous active-high reset and clear for every contained block.
Reset and clear discard control validity but do not clear SRAM contents. Any future multi-clock wrapper
requires a separate CDC/RDC contract.

Quiesce blocks new task, local-loader, and DMA admission while accepted work drains. `quiesced_o` asserts
only after the scoreboard and completion FIFO, both loaders, DMA boundary, compute clusters, shared SRAM,
and read multiplexers are idle. Lossless maintenance therefore also requires downstream consumers to
accept pending task, local-loader, and DMA completions.

`protocol_error_o` combines scoreboard identity faults, compute and loader diagnostics, DMA faults,
shared-SRAM request errors, and read-multiplexer response-ownership errors. It is a local sticky diagnostic,
not a software ABI status.

## 6. Evidence and Limitations

The complete-Pod regression verifies two-cluster task selection and status return, HBM-to-DMA-to-shared-
SRAM writes, shared-SRAM-to-loader-to-Tensor/Vector movement, completion backpressure, and clean quiesce.
A separate arbitration regression verifies simultaneous DMA/loader requests, response ownership,
backpressure, same-cycle turnover, and round-robin priority. The real compute, DMA, loader, KD28 shared-SRAM,
and Pod hierarchy passes zero-warning Verilator elaboration with the compute array reduced to `ARRAY_DIM=2`;
the production 256 by 256 compute block and exact 256-macro shared SRAM retain their existing independent
regressions.

The independent-Vector System regression additionally verifies a version-3
task over the real local SRAM model and Vector engines with address-distinct
segments, result backpressure, and tag-matched completion. The complete-Pod
stub regression and real-hierarchy lint remain compatibility gates.

This evidence does not close physical timing, production private-SRAM capacity, NoC router behavior,
cross-Pod client behavior, CDC/RDC,
HBM controller/PHY behavior, or sustained workload bandwidth. Those claims remain separate gates.
