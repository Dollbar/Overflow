# Independent TL transmit class selection plan

Execute independently with the already loaded writing-plans, test-driven-development,
executing-plans and erie-verilog-generator workflows. Local ASIC tool selection persists.

Goal: choose eligible Request/Response prepared-Control sources independently and
route their separate Data/BE sources through the actual half-Flit packer. Preserve
old-tail ownership when the next header changes class. This does not finish physical
Tx queues, per-VC scheduling, oversized transactions or the complete dual-IP goal.

Spec: private Common 2.0 §9.1 requires Request/Response independence under flow
control; §5.1.1–5.1.2 define ordered Data tenure and swapped tail; §5.7/§5.8 govern
catch budgets and credit eligibility. Only the existing confirmed field profile applies.

Interface: `tl_tx_channels` has two prepared Control/tag streams and two ordered
Data/BE sources (lane 0=Request, lane 1=Response). It drives the existing actual
packer/credit port. Sources retain entries until the corresponding real wire-taken
acknowledgement. Three state functions are separate: preferred header class, held
header class under stalled output, and active Data tenure owner.

- [x] Test reference selection before RTL: blocked Request permits Response and
  vice versa, payload shortage cannot block the other class, and budget-only blocked
  heads can trigger a NOP without hiding an eligible other class.
- [x] Test old owner A tail + new owner B header acknowledgement on one real Flit;
  following Data comes from B. Test stalled choice against arrivals in the other class.
- [x] Implement Python reference and Verilog-2001 class qualification/mux/owner state;
  no speculative source consumption, new wire format or additional clock/reset domain.
- [x] Actual unit traces with reset, both classes, Auth, shared pool, credit/budget
  waits, source gaps and fairness; retain missing/failed tests and real mutations.
- [x] Actual dual packer/port/Rx SRAM/FC integration with independently indexed class
  sources. Full-drain traffic plus Request-blocked and Response-blocked cases must
  show the opposite class completing without acknowledging the blocked input.
- [x] Independent wire/source/SRAM/credit audit, lint, synthesis and clock checks;
  mandatory artifact gate and separately reported global skill selftest status.
- [x] Regress existing modules in a clean export; save source-hashed evidence and
  local commit; keep oversized handling, real Tx buffering and full proofs/STA open.

Files: `model/tl/tx_channels.py`, `rtl/tl/tl_tx_channels.v`,
`verification/tl_tx_channels/`, contract/review/checkpoint under config/docs.
Commands: `python3 verification/tl_tx_channels/test_model.py`,
`python3 verification/tl_tx_channels/run_rtl.py`,
`python3 verification/tl_tx_channels/run_peers.py --kd28-root /authorized/Overflow`.
Outputs: `build/verification/tl_tx_channels/`; next capacity-aware UPLI and real Tx queues.
