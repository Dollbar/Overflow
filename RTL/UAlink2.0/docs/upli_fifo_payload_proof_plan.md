# Independent FIFO payload proof plan

Execute alone while the frozen transmit candidate's physical jobs continue. Use the existing local ASIC toolchain and authorized KD28 dependency root; no production RTL changes are required.

**Goal:** Prove that the actual `upli_receive_fifo` preserves accepted-word order and exact occupancy, does not expose stale pre-reset data as valid, and makes a retained nonempty queue readable within a bounded number of cycles.

**Boundary:** Instantiate the authorized parameterized `kd28_sram_sdp_model` with a common clock, full byte write mask, registered read-before-write behavior and arbitrary initial memory/read data. This proves the controller under that explicit synchronous SRAM contract. Fixed 256×32 bank mapping, physical SRAM timing, complete TL payload assembly and final Endpoint/Switch correctness remain separate obligations.

- [x] Add `verification/upli_fifo_payload/run_formal.py`. Snapshot actual FIFO and SRAM sources, elaborate the real composition, retain every state/memory cell, and add only output observations. Reject any transformation that changes original inputs, outputs, cells, nets or state.
- [x] Construct an independent shift-queue reference driven by external write proposals, capacity and actual consumer handshakes. Relate its valid words to actual cache head/tail, registered pending SRAM data and unread SRAM addresses. Assert exact count, address bounds, pointer relation, write behavior, payload equality and bounded empty-cache wait. Initial synchronous reset is the only environment assumption; do not initialize SRAM or require input stability during stalls.
- [x] Demonstrate real failures for incorrect captured payload and omitted pending reservation. Require an actual reset-reachable counterexample, not merely failed induction or timeout. Then prove the healthy controller with unbounded induction at depths 1/2/3/5, initially data width 8, and expand to 32/512 bits and both invalid-output profiles as supported by actual results.
- [x] Independently audit exact observations, source/model identity, reference transitions, asserted relationships, assumptions and SAT base/step logs. Retain all failures and record exact proven parameter coverage; do not infer unsupported configurations or macro signoff.

Command: `python3 verification/upli_fifo_payload/run_formal.py --kd28-root PATH --label NEW --depths 1 2 3 5 --widths 8`, with optional `--fault head|reservation` for real source mutations. Outputs are immutable sources, complete graphs, properties, proof logs, witnesses and `results.json` under `build/verification/upli_fifo_payload/NEW`. The next step is integrating the payload invariant with actual bank mapping and higher-level TL ownership/assembly proofs.

Completed: 24 configurations, 20 whole-word and 32 slice inductions, two concrete SAT fault replays, twelve auditor tests and byte-identical normal/optimized aggregate evidence. Four whole-word timeouts remain recorded; complete bit slicing supplies the corresponding proofs without weakening assumptions. Fixed bank mapping and complete TL payload remain next obligations.
