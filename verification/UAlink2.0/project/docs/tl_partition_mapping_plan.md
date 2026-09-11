# Partition mapping equivalence implementation plan

Execute independently with writing-plans, executing-plans and erie-verilog-generator.
Goal: prove the actual process-mapped partition block against the current RTL without
changing RTL, using the failed monolithic SAT runs as the starting evidence.
Sources: `docs/tl_credit_reduction_review.md`, the actual `static_reduction` mapping
records, and the original synchronous reset/four-bit cursor contract.

- [x] Bind current RTL, actual mapped Verilog and actual Liberty Boolean/FF model
  hashes before reading them. Build a wrapper comparing the two real instances,
  exposing the actual cursor only as an observation, with no added state inputs.
- [x] Prove WIDTH8/16 reset sets every actual state bit in both designs to zero
  after one edge, from arbitrary binary initial states; audit the shared raw clock.
- [x] Prove reset establishes equal cursor states after one edge from arbitrary
  initial states; prove one-step preservation of this relation under arbitrary
  later inputs/reset; prove all original outputs equal under that established
  relation. Split output cones, not the protocol input space. All three obligations
  are required for the binary sequential equivalence conclusion.
- [x] Use actual mapped netlist mutations to test state, output and reset obligations;
  retain concrete counterexamples, all failures/timeouts and actual exit codes.
- [x] Audit register/clock inventory, every compared output bit, all proof denominators
  and source identity. Update review/status/checkpoint and locally commit. Main clock
  timing, full integrated STA and the full IP Goal remain open.

Execution: `python3 verification/tl_partition_mapping/run.py --widths 8 16`.
Outputs: private `build/verification/tl_partition_mapping/`; default inputs are the
previously measured `tl_control_partition_timing/static_reduction` artifacts.
Next: optimize the remaining source-Control-to-Auth path with proved mapped behavior.

Reset-stage commands (fresh labels; faults must return nonzero):

```sh
python3 verification/tl_partition_mapping/run.py --reset-only --label reset_verified
python3 verification/tl_partition_mapping/run.py --reset-only --fault reset --label reset_bypass
python3 verification/tl_partition_mapping/run.py --reset-only --fault clock --label clock_mutation
python3 verification/tl_partition_mapping/check_evidence.py
```

The reset-only matrix does not discharge induction or original output equivalence.
The WIDTH8 whole relation, cursor-zero subcase, port/state `equiv_simple` and ABC
normalization experiments retain their timeouts. Do not expand a failed cursor
subcase into a claimed exhaustive 16-state proof.

## Staged proof continuation

Use writing-plans and executing-plans independently, as authorized. The full IP
scope and the three sequential-equivalence obligations above remain unchanged.

- [x] Preserve a generic `synth -flatten -noabc` intermediate from the exact
  current source and measured mapping flow. Record hashes before proof use.
- [x] Compare the RTL lowering to the generic intermediate and the intermediate
  to the actual mapped cells. Audit all original outputs and the complete cursor
  state/clock relation at both boundaries; no unexplained state matching or
  unproved internal correspondence may be used as an assumption.
- [x] Test actual mapped transition/output faults against any new proof path.
  An engine that treats latches as combinational boundaries requires an explicit
  checked state correspondence and the already proved reset base.
- [x] Retain every bridge result and timeout, update the review and checkpoint,
  and commit only claims backed by all required proof edges. Do not publish.

Implementation files: extend `verification/tl_partition_mapping/` only after the
private experiments identify a viable exact proof path; retain generated scripts,
intermediate netlists and logs in `build/verification/tl_partition_mapping/`.

Outcome: the WIDTH8 bridge experiments passed CEC, and direct RTL-to-mapped CEC
also proved viable. The final WIDTH8/16 matrix uses the direct path, with checked
dead-alias pruning and no CEC warnings. It compares all 529 original output bits
and all four next-state functions, preserving the original four latches and raw
clock. Combined with the proved reset base, it closes this block's binary mapped
equivalence. See `tl_partition_mapping_review.md` for exact commands, fault
witnesses and exclusions. Main timing, full-top STA and the full IP Goal remain open.
