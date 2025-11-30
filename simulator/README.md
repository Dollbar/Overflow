# System Simulator

The simulator covers KD-ISA, NPU kernels, HBM, KDLink, and the 32-node fabric. It provides functional and
cycle/bandwidth-estimation modes to validate partitioning, deadlock freedom, capacity, and tokens/s before
RTL and hardware are complete.

## Available Packages

| Package | Scope | Evidence |
| --- | --- | --- |
| [`kdlink/`](kdlink/) | KDLink protocol model and self-checking RTL regressions | `FUNCTIONAL_SIM`, `RTL_SIM` |

Generated KDLink binaries, logs, and caches belong under `simulator/kdlink/work/` and are not source
artifacts. Each future simulator package must similarly isolate generated files in its own ignored work
directory.
