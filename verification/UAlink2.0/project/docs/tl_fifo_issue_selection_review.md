# FIFO prefetch reservation selection experiment

This timing candidate is rejected after all 60 physical measurements and identical normal/optimized Python audits. The entire active RTL tree has been restored byte-for-byte to `6f10b33539624664cc4231bbb681e7b1d62dc401`, the fully qualified [header visibility baseline](tl_tx_header_visibility_review.md). Candidate sources and all evidence remain retained. Full candidate mapped correspondence was not completed or claimed; the full dual-IP Goal remains active.

The actual baseline critical path traverses Header qualification and opposite-class FIFO consumption before updating unread count. `upli_receive_fifo` now computes cache space from the current cached count and pending SRAM result before the consume decision arrives. `flag_issue` selects existing space or space released by an actual consume. It no longer feeds consume through the reservation subtract/add/compare cone. Ports, parameters, all state and all other transition equations remain unchanged, including invalid count-3 behavior.

## Completed semantic evidence

- The pre-change fault that ignores a pending SRAM result is detected in six complete-state FIFO comparisons. Independent resets remain healthy. The runner's nonzero exit and `complete=false` correctly report inequivalence, not a tool failure.
- The final expression's missing-pending and missing-consume faults each produce six additional real CEC differences, with unchanged reset behavior.
- FIFO default and raw/remasked behavior passes all 36 configurations: data widths 8/32/512, depths 1/2/3/5/129/257, with 72 independent reset proofs against the frozen `6839cac` reference. The proof observes every actual FF transition and output, without constraining cached count to reachable values.
- Six actual SRAM FIFO depth regressions and 36 production unit configurations pass. All 32 production peer configurations pass independent wire/queue/partition/capture audits. Ordinary and optimized Python wire evidence agrees; all 128 trace files are byte-identical to the adopted header-visibility baseline.
- Strict Verilator lint passes. Independent static RTL lint with the confirmed `i_clk` input reports no errors or advisories.

Complete buffered composition passes all six WIDTH 8/16 × depth 1/2/3 configurations and 12 independent reset queries. All 27 production ownership configurations pass 35 assertions each; normal and optimized Python independently audit the actual graphs and induction logs and produce identical results. The candidate does not yet have the additional 21 middle-width buffered comparisons or complete actual mapped correspondence required for adoption.

A first workspace `make test rtl-smoke prepared-tx-smoke` invocation completed model/tool tests but stopped when `rtl-smoke` refused to overwrite an existing `tl_publish/sim/final` directory. The clean source-only clone at `161ed37248c08d3f7f5e12c63515d9b365adafb0` subsequently passes all three Make targets, with a clean worktree. Both the original label collision and successful rerun log remain retained. Completed semantic evidence hashes are in `docs/tl_fifo_issue_selection_evidence.json`.

The complete physical matrix uses unchanged actual standard-cell libraries, synthetic SRAM views, periods and IO budgets. WIDTH 8 area is 45,184.860 µm², worst setup −1.809450 ns; WIDTH 16 area is 47,284.650 µm², worst setup −1.823450 ns. Against the adopted baseline, WIDTH 8 area increases 0.880% and setup worsens 3.065 ps; WIDTH 16 area increases 3.685% for only 11.215 ps setup improvement. Both retain the same 6,254/6,574 FFs and 64 macro interfaces. Main 640 ps timing remains 0/30 closed, reference 6.4 ns remains 26/30, and worst hold remains −0.008036 ns. The measured tradeoff does not justify adopting this candidate.

Actual WIDTH 8 mapped Q aliases bind the worst path from Request Header FIFO `reg_head[123]` to Response Header FIFO `cnt_unread[1]`, through the real header-taken and issue signals. The path-pair run prepared actual graphs; its strict same-encoding check rejected the known cursor encoding difference, so it is not a complete mapped proof. The physical audits completed before restoring any RTL, and `fifo_issue_restoration.json` binds both source identities and the final audit/result hashes. Historical candidate evidence is no longer asserted to apply to current source.

## Reproduction and next gate

The exact candidate is `rtl/upli/upli_receive_fifo.v`, SHA-256 `3348d06961770df6da9e10e44077624e6b160312254b72bdc5a9240fe7ff3b06`. Run the commands in the [implementation plan](tl_fifo_issue_selection_plan.md) with fresh labels. Candidate artifacts use `fifo_issue_*` under `build/verification/{tl_tx_qualification,tl_tx_prepared,tl_tx_buffered,tl_control_partition}`. Fault-source folders retain exact before/after expressions and both source hashes; proof runs freeze the actual mutated RTL. No faulty file replaces production RTL.

The next isolated experiment examines direct fixed-account matching in credit admission; see [its plan](tl_credit_slot_selection_plan.md). It must establish complete functional correspondence and actual physical benefit independently. This rejected experiment does not establish full protocol, real SRAM timing, layout, power or complete Endpoint/Switch signoff.
