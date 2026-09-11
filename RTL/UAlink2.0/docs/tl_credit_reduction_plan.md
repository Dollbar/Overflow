# Static credit reduction implementation plan

Execute independently with writing-plans, executing-plans, test-driven-development
and erie-verilog-generator in the existing isolated ASIC branch.
Goal: reduce the measured TL credit/partition combinational path without changing
any field decoding, credit semantics, handshake, latency, clock or reset behavior.
Spec: `config/tl_credit_admission_contract.json`, Common2.0 §5.8 and the existing
`docs/tl_control_partition_timing_review.md`. The actual failing five-corner STA
baseline is the performance test to improve; functional expectations remain fixed.

- [x] Preserve original admission source from commit4376b8b under the private
  stage directory and verify its SHA256. Replace variable part-select read/modify
  accumulation with 20 fixed logical slots: each sums eight independently decoded
  field contributions using three balanced levels of six-bit adders. CMD adds1;
  Data adds the decoded full-Beat count. Apply the original validity/reset gate and
  shared slot10+15 merge afterwards; all output/compare expressions remain unchanged.
- [x] Add `verification/tl_credit_reduction/run_equivalence.py`: original and actual
  optimized full admission RTL share the same original external inputs, compare all
  123 output bits for WIDTH8..16 via Yosys SAT, no field/VC/pool legality assumptions.
  Flatten and optimize common decoding across the miter without cutting inputs or
  internal state. Add real wrong-credit mutants to show comparison is effective.
- [x] Run unchanged independent admission and partition vectors under fresh labels.
  Adapt only source mutation anchors in admission fault runner; run real faults,
  strict lint, parameter rejection and generic synthesis. Never substitute compilation
  errors for detected functional faults. Keep original test expectations.
- [x] Run the actual buffered dual peers for both normal/minimum FIFO configurations;
  audit actual source fields, Data/BE/tags, SRAM retirement and FC using the existing
  independent auditor on fresh evidence. Replay baseline healthy fixtures if useful.
- [x] Re-run actual process mapping and five-corner/two-period STA through the existing
  timing runner with a new label; preserve original failing evidence. Record real
  area/path/slack changes and proof status without claiming complete IP signoff.
- [x] Apply artifact quality gate and compatibility tests; update review/status and
  checkpoint, preserve terminal evidence/hashes, remove only terminal compiler outputs,
  locally commit. Full UPLI, perVC, individual oversized transactions, messages,
  complete proofs and integrated tops remain in the unchanged Goal.

Commands: `python3 verification/tl_credit_reduction/run_equivalence.py`,
`python3 verification/tl_credit_admission/run_rtl.py --label static_reduction`,
`python3 verification/tl_control_partition/run_rtl.py --label static_reduction`.
Outputs: private `build/verification/tl_credit_reduction/` and the fresh labels under
the existing stage directories. Timing uses explicit authorized `--lib-root` and
`--sta` through `verification/tl_control_partition_timing/run.py`.
Next: use measured remaining paths to choose further optimization, retaining original
timing budgets and exact protocol semantics.

Actual proof strategy: 20 unconditional six-bit output cones and 3 flags using only
their discharged equality lemma, for each WIDTH8..16 (207 successful SAT queries).
Original whole-vector and mapped-netlist SAT timeouts remain in the evidence.
Reference-period STA10/10 passes; main-frequency and mapped equivalence remain open.
