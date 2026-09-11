# Production transmit post-reset mapped correspondence

The production `tl_tx_prepared` hierarchy at WIDTH 8/16 has completed binary post-reset sequential correspondence with its actual TSMC28 standard-cell mapping. All original SRAM transaction ports are observed; SRAM read outputs are common arbitrary inputs. The RTL and mapped netlists are unchanged from the [complete physical baseline](tl_tx_prepared_timing_review.md). Timing closure, characterized SRAM signoff and the full dual-IP Goal remain open.

| WIDTH | Normalized RTL state bits | Actual mapped state bits | Common input bits including SRAM reads | Public and SRAM transaction output bits | Complete CEC partitions |
|---|---:|---:|---:|---:|---:|
| 8 | 6,244 | 6,254 | 5,511 | 4,144 | 6/6 |
| 16 | 6,564 | 6,574 | 5,831 | 4,144 | 6/6 |

## Complete state and encoding relation

Every original positive-edge FF D/Q equation is observed. `audit_cut` checks the original combinational equations, complete ports, actual clock connections and full state coverage. Each of the 64 original SRAM instances is exposed at its real interface: read outputs become common arbitrary inputs; clocks, controls, addresses, masks and write data remain compared outputs.

Actual synthesis recoded both preparation cursors from four binary bits to nine one-hot bits. The mapping logs give binary states 0,8,4,2,6,1,5,3,7 at one-hot bit positions 0 through 8. Noncursor state aliases and constants match completely. The encoded CEC compares all 4,144 public/macro output bits and every actual mapped next-state bit, conditional on both binary cursors being in 0..8.

The final comparison uses 2,048-output groups, with six groups per width. Every original output root occurs exactly once across the partitions. Each partition retains the full original input inventory and exact truth tables in its backwards cone; no internal signal is replaced with an arbitrary input. The original and pruned networks, partition coverage, equations, commands, raw logs and hashes are independently audited. All 12 partitions pass.

## Sequential establishment and preservation

Four independent arbitrary-state reset SAT queries prove 4,184 RTL and 4,194 mapped reset state bits per width. These include all FIFO cache payloads, counts, addresses, arbitration state, preparation owners and cursors. Only the actual resetless preparation payloads remain independent: 2,060 bits at WIDTH 8 and 2,380 bits at WIDTH 16. The mapped cursor reset value is one-hot bit zero, and FC preference resets to one.

Four actual RTL one-step SAT queries prove closure of `cursor <= 8` and `!owned -> cursor == 0`. The independent reset queries establish their base case. These invariants provide the domain required by the complete encoded CEC.

Four mapped one-lane SAT queries use owner zero and the reset cursor, with independent old preparation payloads in two copies of the actual mapped D/Q graph. They compare every public/macro output and all nonpayload next-state bits. When either next owner becomes one, they also compare the complete newly owned payload. The other lane and all queue/arbitration state remain common arbitrary state. Both lanes at both widths pass.

The combined relation requires identical nonpreparation state, corresponding owners/cursor encodings, and identical preparation payload only while owned. Reset establishes this relation. For each unowned lane, its independent mapped payload can be replaced by the RTL payload using the dormant lemma without changing observable outputs or relevant next state. Applying this to either or both lanes produces the complete common-state relation used by CEC. Complete CEC then gives all outputs and next-state correspondence; cursor closure and the capture part of the dormant lemmas restore the combined relation on the next edge. Induction therefore establishes the stated post-reset binary correspondence without assuming equal uninitialized preparation payloads.

## Actual faults and checker qualification

Two real mapped DFQD reset faults replace the FC preference register's D input with `i_done`, preserving its Q, clock and every other mapped cell. Reset SAT produces actual counterexamples at both widths. The same mutants are converted through the complete encoding wrapper and the exact partition helper; the observed next-state bit differs in both CEC runs.

Two real mapped payload faults replace preparation lane 0 Control bit 0's D input with old Control bit 1's Q. Normalization retains the complete state inventory. Dormant/capture SAT produces witnesses at both widths with reset inactive, initialization done, source valid, both next owners set, and the actual captured Control bit different. These are semantic failures of actual mapped cells, not intentionally failing assertions or changed proxy outputs.

Twenty-one new checker tests pass under ordinary and optimized Python: eight partition contracts, four real-ABC result cases, three reset inventories, two dormant inventories and four evidence checks. They cover changed truth tables/inputs, missing or duplicate next-state roots, unknown state exclusions, real ABC read failures, genuine mismatches, structural-hashing success messages, timeout handling and a success log paired with the wrong SAT obligation. Initial test failures are retained.

`check_mapped_correspondence.py` verifies the original physical netlist and library identities, complete actual D/Q graphs, source-bound encoding wrappers, all partitions and logs, exact reset/cursor/dormant SAT scripts, and single-D-pin mapped mutations with real witnesses. Ordinary and optimized audits pass and produce byte-identical evidence JSON.

## Evidence, experiments and commands

The evidence root is `build/verification/tl_tx_prepared`. Final stages are `explicit_wide_partition`, `independent_reset`, `cursor_relation`, `dormant_capture`, `actual_reset_fault`, `actual_capture_fault` and `actual_partition_fault`. The result is `mapped_correspondence_evidence.json`, with the optimized counterpart and raw audit logs beside it.

The original `mapped_pair` strict alias rejection, `encoded_step` BLIF read failure and whole-network/automatic-partition timeouts remain preserved. The small 128-output exploration was deliberately terminated after 14 passing WIDTH 8 blocks when wider groups proved more efficient; its interrupted block has no claimed result. No timeout or stopped experiment is counted as a pass. All final proof jobs are terminal.

```sh
python3 verification/tl_tx_prepared/run_partitioned_cec.py --label NEW_CEC --widths 8 16 --group-size 2048 --timeout 120
python3 verification/tl_tx_prepared/run_reset_state.py --label NEW_RESET --widths 8 16
python3 verification/tl_tx_prepared/run_cursor_invariants.py --label NEW_CURSOR --widths 8 16
python3 verification/tl_tx_prepared/run_dormant_state.py --label NEW_DORMANT --widths 8 16
python3 verification/tl_tx_prepared/run_reset_fault.py --label NEW_RESET_FAULT --widths 8 16
python3 verification/tl_tx_prepared/run_capture_fault.py --label NEW_CAPTURE_FAULT --widths 8 16
python3 verification/tl_tx_prepared/run_partition_fault.py --label NEW_CEC_FAULT --widths 8 16
python3 verification/tl_tx_prepared/check_mapped_correspondence.py
python3 -O verification/tl_tx_prepared/check_mapped_correspondence.py --output build/verification/tl_tx_prepared/mapped_correspondence_evidence_optimized.json
```

The proof runners use the retained paired/physical inputs described in their help. The final auditor intentionally audits the named final stages listed above; fresh labels preserve experiments and must be selected explicitly when establishing a later baseline. Generated netlists, logs and restricted library inputs remain excluded from Git.

The next implementation target is the measured Header FIFO cache-count path through qualification/arbitration and packing back to prefetch count. Current main timing closes 0/30 and reference timing 26/30; SRAM input hold is a separate concern. No current gate-level oracle simulation rerun is claimed. Full protocol/payload correspondence, Data-bank obligations, final Endpoint/Switch integration, digital PHY, INC, security, manageability and real macro signoff remain part of the active Goal. This continuation is recorded locally; the last verified remote checkpoint is `d05b020`.
