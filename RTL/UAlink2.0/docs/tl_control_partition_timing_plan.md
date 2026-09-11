# Control partition process timing implementation plan

Execute independently using writing-plans and executing-plans in the existing
isolated ASIC branch. Goal: establish actual standard-cell mapping and five-corner
prelayout timing for `tl_control_partition`, WIDTH 8 and 16, without changing RTL.
Specification: `config/tl_control_partition_contract.json`,
`docs/tl_control_partition_review.md` and the existing digital budgets in
`scripts/sta_burst_sender.tcl`. This is a block baseline; complete Tx/Rx tops and
physical implementation remain separate outstanding tasks.

- [x] Extend `scripts/check_sta_report.py` with the explicit `control_partition`
  profile, first add tests accepting its declared completion and rejecting a
  wrong profile, missing completion and negative slack. Run
  `python3 -m unittest verification.tools.test_sta_report` before and after the change.
- [x] Create `scripts/map_tl_control_partition.tcl`: read the four existing RTL
  dependencies, WIDTH from explicit environment, flatten and map with authorized
  SSG 0.81V 125C Liberty, existing 5 fF ABC drive/load and 350 ps optimization
  objective. Produce mapped Verilog/JSON and area JSON; reject unresolved cells.
- [x] Create `scripts/sta_tl_control_partition.tcl`: one ideal i_clk, periods
  0.640/6.400 ns, setup/hold uncertainty 0.032/0.010 ns, input max/min
  0.128/0.020 ns, output max/min 0.128/-0.020 ns, transition 0.050 ns,
  output load 0.005 pF. No exceptions, case analysis or parasitic estimates.
- [x] Create `scripts/equiv_tl_control_partition.tcl`: compare original RTL
  against actual Liberty Boolean/FF mapped definitions, reset convergence and
  binary temporal induction with actual cursor state and all original outputs.
  Reject unknown cells; preserve timeout/failure instead of claiming proof.
- [x] Create `verification/tl_control_partition_timing/run.py` accepting explicit
  `--lib-root` and `--sta`, refusing an existing output directory. For each width,
  execute mapping, equivalence and TT/SSG hot/SSG cold/FFG hot/FFG cold STA at both
  periods. Save exact commands, statuses, source/library/netlist SHA256 and logs;
  independently apply the report gate even if the STA process exits zero.
- [x] Audit real mapped clock/storage and mapping/proof/report results, record
  actual violations and worst paths in review/status/checkpoint. Rehash evidence,
  run existing report-tool regression and diff checks, commit this stage locally.

Execution: `python3 verification/tl_control_partition_timing/run.py --lib-root
/authorized/NLDM --sta /installed/opensta/bin/sta`. Outputs are private under
`build/verification/tl_control_partition_timing/`; dependencies are never copied
to canonical source. Next: optimize measured paths with equivalence and unchanged
budgets, then time the complete integrated Tx/Rx tops. No physical signoff claim.

Measured baseline and audit are complete with recorded failures: 6/20 STA gates pass;
reset-convergence mapping proofs time out, induction is not reached, and the
optional structured WIDTH8 proof also times out. Timing/equivalence and Goal remain open.
