# NPU Scheduler RTL

Owns command dependency tracking, resource scoreboards, pod selection, tile issue, barrier handling, and
forward-progress counters. It consumes validated internal commands and produces tensor, vector, DMA, and
collective issue records.

The local descriptor scheduler is verified for the frozen GEMM version-2 and
independent-Vector version-3 records. Policies are deterministic under equal
priority; runtime/compiler scheduling policy remains outside this RTL directory.

The local path owns the versioned descriptor buffer, dependency checks,
fixed-origin active-array derivation, atomic issue FIFOs, and post-result
scheduling. A standalone Vector task emits only Vector and post commands; GEMM
continues to emit its Tensor feeder/result commands. Tensor and Vector
datapaths remain in their owning directories.
