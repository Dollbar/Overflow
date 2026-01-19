# KDLink Verification Gates

This directory owns release-facing static and dynamic verification for KDLink. Portable functional and
RTL simulations remain under `simulator/kdlink`; this directory adds coverage aggregation, bounded formal
properties, structural lint and CDC audits, partitioned OpenSTA, and release evidence generation.

Generated compiler objects, raw coverage databases, synthesized netlists, and solver work directories are
written below a `work/` directory and are ignored by Git. Only concise, redistributable summaries belong in
the repository.

## Gates

| Directory | Gate |
| --- | --- |
| `coverage/` | Source-level line, branch, expression, and control-toggle coverage |
| `formal/` | Bounded safety and progress properties using Yosys SAT |
| `cdc/` | Structural clock/reset-domain crossing audit |
| `sta/` | Multi-corner registered-partition timing plus HBM/SerDes interface-Liberty validation |
| `scripts/` | Reproducible orchestration and report generation |

The release target is a 1.000 ns clock period for each explicitly reported partition. RTL simulation with
a 1 ns testbench clock is not accepted as timing evidence.
