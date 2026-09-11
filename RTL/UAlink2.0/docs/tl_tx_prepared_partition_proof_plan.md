# Explicit mapped proof partitions

Execute alone with executing-plans and TDD. Implements the unresolved conditional step in `tl_tx_prepared_mapping_plan.md`; it does not replace reset/dormant-state or fault obligations.

Inputs: the exact `encoded_step_techmapped/w{8,16}/{gold,gate}_pruned.blif` complete output/next-state networks, their original raw BLIF and hash-bound source artifacts. Preserve all 4,144 public/macro outputs plus 6,254/6,574 encoded next-state bits. No internal arbitrary inputs, changed truth tables or state omissions are permitted.

- [x] Write `verification/tl_tx_prepared/test_proof_partitions.py` with a literal small combinational circuit. Assert exhaustive truth tables of each selected root; reject changed logic, missing roots, duplicate coverage, unknown inputs and undriven live roots. Observe missing implementation failure before adding the helper.
- [x] Implement `proof_partitions.py`: parse the emitted combinational BLIF subset, select output roots, retain the original truth tables in their backwards cones, and independently audit exact input/logic/coverage preservation. Keep the existing driven-cone helper as an additional check. Run ordinary/optimized Python tests.
- [x] Add `run_partitioned_cec.py`: create immutable per-part BLIF and commands, hash original networks and all part artifacts, compare same-named complete outputs with ABC, preserve pass/fail/timeout separately, and record each terminal result immediately. Require a complete partition inventory for any complete conditional result.
- [x] Run actual WIDTH 8/16 complete matrices, inspect difficult or differing partitions, qualify an actual mapped fault, and bind the resulting evidence without claiming reset equivalence prematurely. Update the original mapping plan and checkpoint to the actual terminal/live state.

Commands: `python3 verification/tl_tx_prepared/test_proof_partitions.py` and `python3 verification/tl_tx_prepared/run_partitioned_cec.py --label NEW_LABEL --widths 8 16`. Outputs go to `build/verification/tl_tx_prepared/NEW_LABEL`. Next prove reset/independent dormant payload relation and audit the full mapped equivalence composition before physical timing repair.

Completed with 2,048-output groups (six per width). The smaller 128-output exploration was deliberately terminated after 14 passing WIDTH 8 blocks once the wider grouping proved more efficient; its active block has no claimed result. Added independent reset, actual RTL cursor closure and mapped dormant-payload lemmas, and qualified both reset-D and old-payload-D mutations of original mapped DFQD cells. All final queries are terminal. Full normal/optimized evidence audit passed; 21 new checker tests pass in both modes.
