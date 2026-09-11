# TL transmit half-Flit packing implementation plan

Execute independently using writing-plans, test-driven-development and executing-plans.
The existing erie-verilog-generator gates apply to all new RTL. Local ASIC tools and
external KD28 SRAM models remain the confirmed environment.

Goal: construct actual Flits from independent prepared-Control, Data/BE and FC
sources, so an ineligible next Control cannot block retirement of the previous tail.
This advances the full dual-IP goal; it does not finish oversized transactions,
Request/Response queue arbitration, unconfirmed encodings, authentication cryptography,
DL/PHY integration or process STA.

Spec: private Common 2.0 §5.1.1/5.1.2 (Control placement, swapped tail, AuthTags),
§5.7 (packing/source-rate limits), §5.8 (credit FC). Reuse the confirmed tenure profile.

Interface: `tl_tx_packer` consumes one prepared Control queue, one ordered 32-byte
Data/BE queue exposing up to two entries, a matching AuthTags entry, and the actual
FC publisher candidate. It reads the real transmit pending count, current physical
credit counters, and transmit catch-buffer budget. Its outputs feed the real
`tl_credit_admitted_port`. Only that port's actual taken event acknowledges sources.

- [x] Preserve a failing old-tail/new-header test: pending=1, eligible old tail,
  insufficient next-header credit; require NOP lower plus old tail upper, zero
  header consumption and one Data/BE consumption.
- [x] Python reference first; literal tests cover FC+tail, Auth prohibition on
  tail+header, completion FC waiting for the tail, two-data packing, independent
  source consumption, explicit NOP to recover catch budget, and FC/header fairness.
- [x] Implement Verilog-2001 mux/control with native actual-taken handshake.
  Remember the selected source under output backpressure, while sources hold their
  own queue entries until acknowledgement. Data tenure never accepts an FC field.
- [x] Compare actual RTL with reference vectors including stalls, source arrivals
  during stalls, reset and maximum pending count. Preserve failed runs.
- [x] Connect actual packer, admitted port and receiving SRAM/FC publisher in a
  dual-port test with independent prepared-Control/Data streams. Check actual
  wire and stored words, source consumption, FC credit conservation and finite drain.
- [x] Fault injection, strict lint, generic synthesis/clock review and mandatory
  artifact/selftest gates; retain any unavailable external gate as unavailable.
- [x] Audit final source identity, update full-goal checkpoint/review, commit locally.

Commands: `python3 verification/tl_tx_packer/test_model.py`,
`python3 verification/tl_tx_packer/run_rtl.py`, and
`python3 verification/tl_tx_packer/run_peers.py --kd28-root /authorized/Overflow`.
Outputs: fresh directories in `build/verification/tl_tx_packer/`; next address
capacity-aware UPLI policy and independent Request/Response queue selection.
