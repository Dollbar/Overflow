# Actual FIFO payload proof under a synchronous SRAM contract

This work connects the unchanged production `upli_receive_fifo` to the authorized parameterized `kd28_sram_sdp_model` and checks it against an independent shift queue. The only environment assumption is an initial synchronous reset. Subsequent writes, input changes during stalls, reads and resets are arbitrary. Actual SRAM memory and registered read data are not initialized by the harness.

The reference accepts an external write proposal only when its own count is below capacity; admission does not depend on the DUT's ready output. Reads follow the actual valid/ready consumer handshake. Assertions bind exact occupancy, write behavior, circular addresses, cache/pending/unread ownership and every valid payload to the reference. The head, tail, pending registered SRAM value and unread circular memory region jointly represent the independent queue. Address bounds and no simultaneous enabled same-address read/write are proved assertions, not assumptions. A retained nonempty queue must become readable within the checked two-cycle empty-cache wait; reset cancels the obligation.

## Actual composition and observations

The SRAM uses a common write/read clock, full byte masks, a registered read and read-before-write behavior. Original graphs contain all actual memory and cache state. The observation transform adds output ports only and is checked by removing those ports and requiring exact graph equality. No cell, state, original input or original output is changed by observation. All state clocks must be the actual positive input clock; SRAM words must be independent state bits and have no initial values.

Two initial harness failures are retained. At non-power-of-two depth, Yosys memory mapping left invalid-address mux leaves undriven; `opt_expr -undriven` now expresses them as undefined values, without zero-filling or assuming address legality. At depth one, unused address wires were optimized away; the composition now preserves those actual address wires with `keep` so the same address assertions remain checked.

## Proof strategy and retained failures

The requested matrix is data width 8/32/512 × logical depth 1/2/3/5 × invalid-output zero/raw, totaling 24 configurations. Each has 20–25 assertions. Twenty whole-word induction proofs complete directly. Larger 512-bit depth-3/5 whole-word queries exceed the 180-second resource limit; these runs remain failures/timeouts, never counted as passes.

For those four configurations, contiguous 64-bit reference payload slices reduce the SAT cone. Each query still instantiates the complete actual observed FIFO/SRAM and retains every control assertion, the initial reset assumption and the original external inputs. Only the independent reference payload width and compared payload slices change. Eight slices cover bits 0–511 exactly; the checker rejects gaps, overlaps, wrong configuration/source graphs and weakened obligations. This method proves all payload bits, not a representative bit or low-word sample.

The final aggregate audit now passes all 24 configurations: 20 whole-word inductions plus 32 slice inductions for the four remaining configurations. Normal and optimized Python produce byte-identical evidence. An intentionally early audit rejected the incomplete last configuration; that failure is retained. Scope and artifact hashes are recorded in `docs/upli_fifo_payload_proof_evidence.json`.

## Real faults and checker qualification

Actual FIFO source mutations invert the captured head word or omit pending-read cache reservation. Both produce reset-reachable SAT base-case counterexamples. Their concrete external SAT inputs are replayed through healthy and faulty RTL plus the actual SRAM model in Icarus. The independent healthy queue passes. The head fault yields actual `7f` versus expected `80` at cycle 4; the reservation fault exceeds the two cache slots at cycle 5. Compilation succeeds, and replay requires an actual detected fault rather than a timeout or elaboration error.

Twelve checker tests cover actual-graph clock changes, aliased memory observations, internal-input cuts, missing payload assertions, extra stall assumptions, DUT-dependent reference admission, permanently disabled assertions, slice interface/coverage, high-bit omission and overlap. The critical reference equations are separately reviewed and checked, alongside exact generated properties, commands and actual base/step logs. This is a local behavioral proof under the stated SRAM contract, not an independent proof of the full UALink protocol.

## Reproduction and remaining work

Use the confirmed local Yosys/Icarus flow with fresh immutable labels:

```sh
python3 verification/upli_fifo_payload/run_formal.py --kd28-root PATH --label NEW --widths 8 32 512 --depths 1 2 3 5 --raw 0 1
python3 verification/upli_fifo_payload/run_sliced.py --source NEW --label NEW_D3_RAW0 --width 512 --depth 3 --raw 0 --chunk-width 64
python3 verification/upli_fifo_payload/check_formal.py --label NEW --slice-labels NEW_D3_RAW0 NEW_D3_RAW1 NEW_D5_RAW0 NEW_D5_RAW1
python3 -m unittest discover -s verification/upli_fifo_payload -p 'test_*.py'
```

Run the slice command for all four depth/mode pairs before the aggregate audit. For a fault, use `run_formal.py --fault head` or `--fault reservation` with width 8, depth 3, raw 0, then `replay_fault.py --label FAULT_RUN`. Outputs are source/runner snapshots, original/observed/proof graphs, assertions, SAT logs, witnesses and replay evidence in `build/verification/upli_fifo_payload/`.

Tests that inspect real retained evidence currently use the documented `payload_full` fixture label; run that matrix before those tests. The clean-clone production smoke result for `c84c113` predates these new proof scripts and must not be described as a clean-clone test of them.

Next prove the actual fixed KD28 SRAM bank mapper against this logical storage contract, then compose payload correctness with full TL assembly and the endpoint transaction path. This stage does not close physical bank mapping, characterized macro timing, full TL payload, CDC/RDC, main-frequency timing, PCS/FEC, INC/security/management or the final dual-IP Goal.
