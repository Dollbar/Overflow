# NPU Scheduler RTL

Owns command dependency tracking, resource scoreboards, pod selection, tile issue, barrier handling, and
forward-progress counters. It consumes validated internal commands and produces tensor, vector, DMA, and
collective issue records.

NPU-SCH-001 remains `HOLD` on the internal command and resource contracts. Policies must be deterministic
under equal priority and must include starvation assertions. Runtime/compiler scheduling policy remains
outside this RTL directory.

The local square-GEMM path owns the versioned descriptor buffer, dependency checks, fixed-origin active-array
derivation, issue FIFO, and post-result scheduling. Tensor and Vector datapaths remain in their owning directories.
