# Registered Control mapped equivalence plan

Execute alone using writing-plans/executing-plans/TDD. No publication. The complete dual-IP Goal and 640 ps timing requirement remain unchanged.

**Goal:** prove all 531 original public output bits of the registered Control module equivalent to its actual TSMC28 mapped netlists at WIDTH 8/16 after reset.

**Architecture:** load the exact STA netlists with the recorded real Liberty Boolean/sequential models. Inventory all surviving FFs, original positive clocks, semantic register aliases and next-state D equations. Check the complete interface before adding observations. Establish unconditional empty reset and relation-preserving output/next-state theorems. Initial unreset payloads on both machines are independent; equality is required only while owned. Constants and merged register aliases require explicit verified correspondence, never silent omission.

**Inputs:** current `rtl/tl/tl_prepared_partition.v` and decode/tenure dependencies; `build/verification/tl_prepared_partition/timing/results.json` and its WIDTH 8/16 mapped netlists; operator-authorized external Liberty identified there. Prior RTL reference theorem: `docs/tl_prepared_equivalence_review.md`.

- [x] Write structural observation tests before implementation: real FF coverage, original clock, alias/constants, wrong D/Q wiring, unsupported state or undriven logic must be caught.
- [x] Add a source/library-bound preparation and proof runner under `verification/tl_prepared_partition/`, keeping all actual outputs/state and isolated result directories under `build/verification/tl_prepared_mapping/`.
- [x] Inspect actual optimized RTL/mapped state correspondence; list any removed or merged semantic bits and prove required state restrictions rather than assuming them.
- [x] Prove arbitrary-state reset, empty-state outputs/capture, owned-state complete outputs and next-state correspondence at both mapped widths. Timeouts remain open; decompose only using explicit proved relations.
- [x] Mutate actual mapped clock/reset/captured state/output paths and require rejection or actual SAT/CEC counterexamples. Audit raw logs, mappings, complete denominators and source identity in normal and optimized Python.
- [x] Document the composition and limits, update status/checkpoint, commit locally and hash retained evidence. Preserve failures and remove only terminal caches/binaries.

Each runner must document its execution command and generated artifacts. Completion of this module proof does not complete STA, mapped full-top integration, protocol certification or the full Goal.

Result: WIDTH 8/16 composed mapped equivalence, actual mapped negatives, full oracle replay and both audit modes passed. See `docs/tl_prepared_mapping_review.md`. Full IP scope and 640 ps closure remain open.
