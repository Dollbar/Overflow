# TL whole-tenure admission implementation plan

Execute independently in this session with executing-plans and test-driven-development.

Goal: prevent a credit-eligible header from entering the wire when its remaining
Data tenure cannot finish from the credits already available to the sole transmitter.
This is a local scheduling policy, not a new wire requirement or a complete solution
for transactions larger than the peer's total capacity.

Spec: private Common 2.0 §5.1.1–5.1.2 (inferred sequencing, Control-only FC),
§5.8 (64-byte Data credits, inherited class/VC/Pool, shared Data Pool), §9.1
(outbound flow-controlled requests/responses wait until eligible). The confirmed
tenure decoder profile remains the scope; unresolved field encodings remain rejected.

Architecture: a combinational `tl_credit_admission` decodes all new CMD/Data
requirements, combines only shared Data Pool slots, and compares them with current
physical credit counters. `tl_credit_admitted_port` gates the existing actual port's
send input at Control boundaries. The sole transmitter retains exclusive access to
its ledger during a tenure, so future Data credits remain available without charging
them twice. No extra clock/reset or physical ready wire is introduced.

Files: `model/tl/credit_admission.py`, `rtl/tl/tl_credit_admission.v`,
`rtl/tl/tl_credit_admitted_port.v`, `verification/tl_credit_admission/`,
`verification/tl_receive_credit/run_rtl.py`, and this plan/review/checkpoint.

- [x] Extend real dual SRAM regression with two consecutive three-beat transactions,
  two CMD credits and four Data credits on the same VC. Run legacy port first;
  require a real mid-tenure timeout with both FIFO consumers active.
- [x] Test reference requirements from hand-derived field fixtures (all five supported
  kinds, all positions, shared and separate pools, BE excluded). Observe missing-model
  failure, implement reference, then run normal and optimized Python.
- [x] Test combinational RTL requirements/allow/wait/shortfall against independently
  generated semantic fixtures, including unavailable, oversized, malformed and FC cases.
  Implement RTL after the failure; preserve all diagnostic artifacts.
- [x] Integrate actual wrapper. Re-run the failing dual-port fixture with the same
  workload/capacities, plus WIDTH 8/16, Auth 0/1, shared 0/1, link delay 1/3.
  Require full payload/ownership/credit conservation and finite drain.
- [x] Re-run original mixed-traffic matrix through the new wrapper. Preserve the
  one-credit oversized counterexample; report capacity shortfall rather than declare
  it fixed. Do not increase its credits or remove its multi-beat transactions.
- [x] Strict lint, negative gate/requirement mutations, appropriate legacy regression,
  skill artifact gate/selftest; record any failed environmental gate explicitly.
- [x] Review proofs/limits and save source-hashed evidence and local commit. Online
  capacity induction, capacity-aware packing/UPLI policy, full proof and process STA
  remain mandatory next work in the unchanged full-IP goal.

Commands: `python3 verification/tl_credit_admission/test_model.py`,
`python3 verification/tl_credit_admission/run_rtl.py`, and
`python3 verification/tl_receive_credit/run_rtl.py --kd28-root /authorized/Overflow
--label pressure_admitted --traffic-pressure --admission`.
Outputs: `build/verification/tl_credit_admission/` and fresh labeled subdirectories
under `build/verification/tl_receive_credit/`. Next: examine every failure before
claiming this local policy closes any observed stall.
