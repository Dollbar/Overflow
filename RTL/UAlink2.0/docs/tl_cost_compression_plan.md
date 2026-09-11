# Prepared Control cost compression implementation plan

Execute alone using executing-plans, TDD and the existing RTL review workflow.

**Goal:** reduce the measured account/cursor-to-cost selection delay while preserving all state, public ports, capture latency and simultaneous retirement/replacement.

**Architecture:** retain the current metadata registers and account matching. Replace repeated carry-propagating prefix sums with fixed-width carry-save compression followed by one final carry-propagating addition per prefix. Actual contributions are at most seven Data credits per field; six-bit modulo arithmetic exactly matches the existing six-bit prefix costs for every input, without needing a protocol constraint. Share compressor nodes where their inputs coincide.

**Stack/spec:** Verilog-2001, Yosys/ABC, Icarus, Verilator, authorized TSMC28/OpenSTA. Contract and previous measurements: `docs/tl_prepared_partition_plan.md`, `docs/tl_selection_reduction_review.md`. Current baseline `3127705b9aca1051d0915b9b8be51e41216968eb`, RTL SHA `0e58dd764016974129329bd1c9c6cc7d854c19ff8cb4bb1e7529b52ef1190dc0`. No new wire-protocol interpretation.

- [x] Add an independent SAT harness extracting the actual compressor assignments; test absence before implementation, prove each prefix against direct modular summation, and verify an actual carry fault yields a counterexample.
- [x] Stage the candidate under `build/verification/tl_cost_compression/candidate`; keep production unchanged while measuring. No functions, tasks, extra clocks or state; retain Chinese explanatory comments.
- [x] Prove complete public outputs and actual next-state at WIDTH 8/16 using existing state-graph/CEC tooling, and run independent oracle vectors.
- [x] Measure two widths, five corners and both unchanged periods. Inspect actual critical paths and area; reject candidates that do not improve the intended constraint.
- [x] If useful, complete WIDTH 8–16, actual peers, current mapped equivalence and reset/capture proof before adoption. Otherwise retain measured rejection and record the next architectural direction. Keep full-top STA and complete dual-IP scope open.
- [x] Audit source identities and retained evidence, update status/checkpoint, commit locally. Do not publish private inputs or new work.

Files: new `verification/tl_prepared_partition/run_cost_lemma.py` is the arithmetic proof and negative-control entry; existing `run_selection_equivalence.py`, `run_mapped_cec.py`, `run_rtl.py`, `run_timing.py` supply whole-module evidence. Each runner documents command and output paths. This phase's decision is measured progress toward the unchanged 640 ps target; a useful pilot is not a full-IP completion claim.
