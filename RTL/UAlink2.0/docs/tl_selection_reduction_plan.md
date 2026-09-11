# Prepared Control selection reduction plan

Execute alone with writing-plans/executing-plans/TDD and the existing RTL review workflow. No publication; the full dual-IP Goal and 640 ps requirement remain unchanged.

**Goal:** shorten the measured cursor/credit-selection-to-AuthTags path without changing the one-slot capture/retirement interface, one-cycle initial latency or sustained group replacement throughput.

**Architecture:** compare the current longest-fit priority selection against parallel eligibility reductions. For each retained Control sector, the longest fit includes it iff some fit boundary ends at or after that sector. For each output tag, the selected prefix has more than that tag index iff some fit prefix does; the actual prefix counts are monotone and bounded by eight. Preserve full selection of public end/field count and all raw metadata semantics. Consider a one-hot highest-fit encoder if measured timing identifies it as useful.

**Baseline:** immutable commit `8bf4afcd54eaec3bc4ac35811fd6266b4ba86e61`, production RTL hash `def8d202e6394d755485a191fb7f42ba93ec8ef3af28ca061f3f37e4bace7f78`. Contract: `docs/tl_prepared_partition_plan.md`; actual mapped reference review: `docs/tl_prepared_mapping_review.md`. No wire format or protocol decisions change.

- [x] Write exhaustive local selection tests before implementation, covering all application-start masks, cursors, fit vectors and output tag slots, including empty and inconsistent fit patterns; count overflow must not be assumed away.
- [x] Implement and prove the reduced selection equations in a staged candidate. Keep production unchanged during initial measurement. Every authored Verilog code line retains its Chinese explanatory comment.
- [x] Compare every public output and all actual next-state equations against the immutable baseline across WIDTH 8–16; preserve clock/state inventories and failures.
- [x] Run the unchanged independent streaming oracle at all nine widths, actual mutation checks and actual dual SRAM/credit peers. Maintain simultaneous replacement and holding behavior.
- [x] Map the actual candidate and measure all five corners at 0.640/6.400 ns using the existing authorized TSMC28 constraints. Verify the candidate's actual mapped correspondence. Decide adoption using measured timing/area, not source-level expectations.
- [x] Adopt only a verified useful candidate, update source-bound status/review, commit locally and retain evidence. Full-top integration and the remaining protocol/IP requirements stay open.

Runner docstrings provide execution commands and artifact locations. If reduction alone does not close 640 ps, retain the measured deficit and proceed toward deeper path partitioning rather than changing the target.
