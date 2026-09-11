# FIFO prefetch admission selection implementation plan

Execute alone with the writing-plans, test-driven-development and executing-plans workflows, following the existing project layout and authorized local ASIC toolchain.

**Goal:** Shorten the late Header-consume-to-prefetch path without changing any FIFO interface, state, clock, reset, latency, capacity or SRAM transaction.

**Architecture:** Decode available cache reservations from `cnt_cached` and `reg_pending` before the late consume event arrives. The final issue decision combines space already available with space available after a valid consume. All other arithmetic and state updates remain unchanged.

**Tech stack:** Verilog-2001, existing complete-state Yosys/ABC proofs, independent Icarus/Verilator regressions, TSMC 28HPC+ standard cells and OpenSTA. Local dependencies and clock/IO settings remain those in `config/local.json` and the current physical runner.

**Evidence/spec:** `docs/tl_tx_header_visibility_review.md`, `docs/tl_tx_header_visibility_evidence.json`, and the actual FIFO transition equations in `rtl/upli/upli_receive_fifo.v`. Baseline source is `6f10b33539624664cc4231bbb681e7b1d62dc401`; its complete 60-profile matrix already fails the required 640 ps timing gate. Preserve that red performance result and all negative semantic evidence.

## Tasks

- [x] Qualify the existing complete-state proof against an actual isolated FIFO fault that omits `reg_pending` from reservation. Run `run_storage_visibility.py --top fifo --depths 3 --rtl-root FAULT_RTL --label fifo_issue_pending_fault`; require real CEC differences, healthy independent resets and no elaboration/timeout substitute.
- [x] Change only `rtl/upli/upli_receive_fifo.v`: replace the issue reservation arithmetic cone by `space_now || (flag_consume && space_after_consume)`. Use `space_now=(cnt_cached==0)||((cnt_cached==1)&&!reg_pending)` and `space_after_consume=(cnt_cached==1)||((cnt_cached==2)&&!reg_pending)`. Keep count 3 behavior and the actual consume guard; do not assume only reachable count values.
- [x] Run `run_storage_visibility.py --top fifo --depths 1 2 3 5 129 257 --label fifo_issue_fifo` and the actual buffered comparison with `--top buffered --kd28-root PATH --widths 8 16 --depths 1 2 3 --label fifo_issue_buffered`. Expected outputs are immutable snapshots, full-state graphs, reset/CEC logs and complete `results.json` under `build/verification/tl_tx_qualification/`.
- [x] Run strict FIFO lint, six actual SRAM FIFO depths, production unit and 32 actual peer configurations using fresh `fifo_issue_*` labels. If initial checks pass, measure the actual production top with `run_physical.py --lib-root LIB_ROOT --kd28-root PATH --sta STA_PATH --widths 8 16 --label fifo_issue_physical`; preserve its 60-profile results even if setup/hold remain open.
- [x] Independently audit the full physical matrix in ordinary and optimized Python. Compare actual setup, hold, area and FF/macro inventory with `header_visibility_clean_physical`. Reject unsupported or regressing candidates; retain candidate snapshots and restore exact baseline RTL if rejected.
- [x] If adoption is supported, complete all WIDTH 8–16 buffered and ownership checks, actual mapped reset/cursor/dormant/partition/fault correspondence, normal/optimized evidence audits and clean-clone checks before recording adoption. Otherwise document the measured rejection and use its actual critical path to choose the next repair.

The output is a reviewable timing experiment and its semantic/physical evidence. It does not close the broader Endpoint/Switch, digital PHY, protocol, INC, security, management, power or characterized-macro obligations. No generated netlist or proprietary library is published.

Final decision: reject after all 60 measurements and both physical audits. Active RTL restored exactly to 6f10b33; no candidate mapped-equivalence or full-IP claim. WIDTH8 area/setup both regress; WIDTH16 area cost is not justified by its small setup gain.
