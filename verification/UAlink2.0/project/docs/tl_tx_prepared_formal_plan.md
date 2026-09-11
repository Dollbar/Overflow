# Prepared transmit ownership proof plan

Execute alone using the existing writing-plans/executing-plans and RTL review workflow.

Goal: establish unbounded source-group and actual header-queue conservation in the production `tl_tx_prepared` composition. Contract: `docs/tl_tx_prepared_plan.md`, `docs/tl_tx_buffered_plan.md`; starting commit `d482965e32276e12cad8d5f0e59f9c352741d32b`.

The proof elaborates the actual complete RTL hierarchy and authorized SRAM mapping. It adds observation ports to existing state without altering RTL logic or state. Each actual SRAM read output becomes an unconstrained formal input: this overapproximates memory values and does not establish payload integrity or macro timing. No internal control cut or stable-configuration assumption is permitted for these conservation properties. The sole environment assumption is an initial synchronous reset.

- [x] Add `verification/tl_tx_prepared/run_formal.py`: snapshot sources, elaborate WIDTH and queue-depth matrix, inventory original FF/macro clocks, replace only macro output drivers, add independent balances and observation assertions.
- [x] Demonstrate an actual production tag-gating mutation fails with a SAT counterexample; compilation failure or timeout is not a detection.
- [x] Prove each lane's captured-minus-queued balance equals its actual owned bit and is in 0..1; prove enqueued-minus-consumed balance equals actual FIFO count and is in 0..HEADER_DEPTH. Check FIFO unread/cache/pending conservation, atomic tags, queue event wiring and synchronous reset cancellation.
- [x] Run every WIDTH 8..16 and HEADER_DEPTH 1/2/3, retaining complete proof logs and any failed induction attempts. Exercise reset and queue event mutations to qualify the checker. Also produce actual simultaneous-replacement/full-queue/reset witnesses and exclude capture without tags.
- [x] Audit source identity, exact transformation boundary and proof completion; record remaining full payload formal/STA and full dual-IP obligations, then commit locally without push.

Command: `python3 verification/tl_tx_prepared/run_formal.py --kd28-root PATH --label ownership --widths 8 16 --depths 1 2 3`. Outputs: source snapshots, original and observed JSON graphs, generated `properties.sv`, Yosys scripts/logs, witnesses and `results.json` in `build/verification/tl_tx_prepared/LABEL`. Next: full payload/temporal correspondence and actual combined-top process mapping/STA.
