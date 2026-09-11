# Parallel Control partition selection plan

Continue the full Endpoint/Controller and Switch IP Goal independently. This
stage targets the measured Control/Auth output path; it is not full-top closure.
Baseline is commit e34ea20, with main setup −1.159129 ns at WIDTH8 and −1.116678 ns
at WIDTH16 under unchanged 0.640 ns budgets. The actual timing reports are the
failing performance test; original RTL and independent vectors remain the
behavioral contract. No changes to protocol encodings or handshake are planned.

- [x] Preserve baseline source and timing identities under local ignored
  `build/verification/tl_partition_select/`.
- [x] Construct a private candidate with parallel highest-fit selection and
  per-sector inclusion, preserving all ten outputs and four next-state bits.
  Preserve invalid-input and arbitrary-cursor binary behavior as well as reset.
- [x] Run unchanged unit vectors and full named-state RTL CEC; investigate any
  mismatch before measurements or adoption.
- [x] Measure actual mapping and all five process corners at both periods with
  the existing mapper, libraries and constraints. Retain regressions and failures.
- [x] Adopt only an improvement with strict lint, actual mapped CEC/reset/faults,
  independent actual dual-peer normal/minimum configurations and trace comparison.
  If the candidate does not improve, retain the result and current production RTL.
- [x] Update status, review and next actions; commit locally. Do not push this
  continuation. Main-period and complete integrated-IP requirements remain open.

Use `verification/tl_control_partition/run_rtl.py --label <fresh> --replace <file>`
and `verification/tl_prefix_cost/run_equivalence.py --candidate <file> --label
<fresh> --widths 8 16`, followed by `run_timing.py --candidate <file> --label <fresh>
--lib-root <authorized> --sta <installed>`. Each runner writes complete inputs and
actual results beneath local build paths. Formal comparison uses the preserved
1bc57c1 original, already proven equivalent to e34ea20. After an adopted change,
recheck integrated use and continue the full IP plan.

Measured refinement: the full parallel selector is equivalent at WIDTH8/16 but
regresses setup to −1.247491/−1.294584 ns, despite smaller area. Retain it as a
rejected timing experiment. A sector-only variant separates that change from the
winner encoding. The actual critical path also passes through global tenure-error
zeroing before credit accumulation. Test a third candidate using a default-on
`ZERO_ON_ERROR` parameter in `tl_control_tenure`: only the partitioner's internal
masked-cost instance computes descriptors in parallel with errors; its existing
`masked_status == 0` acceptance gate remains mandatory. All other instances retain
the original default. Full reference/gate dependency snapshots are required for
proof, since this candidate changes a dependency. Neither speculative descriptors
nor any error field may become an accepted transaction.

Completed: two equivalent selector candidates rejected by actual STA; the parallel
tenure candidate was adopted only after nine-width RTL and two-width mapped CEC,
reset/actual faults, tenure default/parallel contracts, 32 peer configurations with
96 identical traces, 72 functional faults, artifact and clean-export checks.
Main period remains failing. Next follow the measured AuthTags paths and full IP plan.
