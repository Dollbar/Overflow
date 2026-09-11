# Production transmit ownership proof review

The production `tl_tx_prepared` now has unbounded proofs for source-group ownership and actual header-FIFO conservation across WIDTH 8..16 and HEADER_DEPTH 1/2/3: 27 configurations, each with 35 compiled assertions. Both Request and Response are present in every proof. BANK_DEPTH remains 3. No production RTL or independent protocol model changed in this stage.

## What is proved

Each lane has independent verification counters, wider than the DUT counts. After synchronous reset, captured groups minus fully queued groups equals the actual preparation owned bit and remains 0 or 1. Partition enqueues minus actual wire header retirements equals the actual FIFO count and remains within its exact configured capacity. Bounds and equality prevent modular counter wrap from concealing lost ownership.

The same induction proves atomic source/tag capture, equality between partition handshakes and actual SRAM FIFO writes, equality between wire header retirements and actual FIFO consumption, unread/cache/pending conservation, double-cache reservation bounds and reset cancellation. A held header selection implies a valid locked class whose actual header cache is nonempty. That last invariant is essential to the composition proof: the first attempt had unreachable induction states with a locked header but an empty cache. Adding an asserted invariant closed the induction without adding assumptions.

The only environment assumption is an initial synchronous reset. Later reset, mode, source data, source tags, budgets, credit inputs, Data inputs and wire ready are arbitrary. Legal integration still requires the documented epoch configuration and producer contracts; these count invariants hold over a broader input space and do not establish correctness of payload interpretation under changing configuration.

## Actual hierarchy and abstraction boundary

The runner elaborates all original RTL and the authorized SRAM mapping, checks the original clock structure, then adds observation ports to existing state and event nets. Exactly 64 `KD28_SRAM_SDP_256X32` instances have their read-output drivers replaced by arbitrary formal inputs. All other cells, connections, state transitions, original ports and non-top modules are preserved identically in the parsed JSON representation. The independent auditor rejects any additional internal cut, changed state driver, removed control cell or wrong observation.

This proves the stated control properties for all possible SRAM read values. It does not prove memory payload integrity, FIFO payload order, complete protocol behavior, Data-bank conservation, liveness, RTL-to-mapped equivalence or macro timing. The formal graphs contain 6,258..6,586 original FF bits across this matrix; that pre-technology-map inventory differs from optimized structural synthesis and is not a PPA measure.

## Negative and reachability evidence

Three actual production wiring mutations were checked at WIDTH 8 and 16, depth 1: bypass source-tag readiness, advance preparation despite a full header queue, and bypass the preparation reset with source-valid. All six compile successfully and produce reset-reachable SAT counterexamples. The auditor reads numeric witness signals and checks the named violation; a timeout, compile failure, arbitrary induction counterexample or mere nonzero exit cannot count as a detection.

Two additional SAT witnesses, WIDTH 8 and 16, demonstrate both lanes queuing their old final partition and capturing the next group at step 3, both queues full with retained groups and no partition enqueue at step 4, occupied reset at step 5, and cleared ownership/counts at step 6. Auth is enabled and the wire consumer is stopped throughout. The otherwise identical WIDTH 8 query requiring absent tags during replacement has no solution.

The evidence auditor's 15 tests pass in ordinary and optimized Python. They include altered actual D inputs, deleted control logic, new arbitrary control inputs, changed observations/original ports/memory outputs, changed non-top modules, added assumptions, weakened group bounds, missing compiled assertions, missing-value witness decoding and rejection of nonviolating or entirely unknown witnesses.

Preliminary evidence remains available: the missing-auditor test failure, initial insufficient induction, original tag mutation, and SAT signal-export failures. The latter came from removing observation aliases during name cleanup; preserving the aliases fixed witness export. Those tool errors are excluded from all final pass/detection counts. The stopped initial matrix is explicitly recorded as cancelled after that diagnosis.

## Reproduction and remaining work

Use new labels when rerunning; runners refuse to overwrite evidence directories. Replace the `ownership` prefix consistently, pass the new `PREFIX_final` through the cover runner's `--parent`, and use `check_formal.py --prefix PREFIX` to audit that independent run.

```sh
python3 verification/tl_tx_prepared/run_formal.py --kd28-root /authorized/repository --label ownership_final --widths 8 9 10 11 12 13 14 15 16 --depths 1 2 3
python3 verification/tl_tx_prepared/run_formal.py --kd28-root /authorized/repository --label ownership_tags_final --widths 8 16 --depths 1 --fault tags
python3 verification/tl_tx_prepared/run_formal.py --kd28-root /authorized/repository --label ownership_enqueue_final --widths 8 16 --depths 1 --fault enqueue
python3 verification/tl_tx_prepared/run_formal.py --kd28-root /authorized/repository --label ownership_reset_final --widths 8 16 --depths 1 --fault reset
python3 verification/tl_tx_prepared/run_formal_cover.py --label ownership_cover_red --widths 8 --impossible
python3 verification/tl_tx_prepared/run_formal_cover.py --label ownership_cover_w8 --widths 8
python3 verification/tl_tx_prepared/run_formal_cover.py --label ownership_cover_w16 --widths 16
python3 verification/tl_tx_prepared/test_formal_audit.py --fixture build/verification/tl_tx_prepared/ownership_final/w8_d1
python3 verification/tl_tx_prepared/check_formal.py
```

The three mutation commands intentionally return 1 with retained counterexamples. Expected outputs are original/observed/proof graphs, source snapshots, Yosys scripts/logs, witnesses, stage reports and `build/verification/tl_tx_prepared/ownership_evidence.json`. Ordinary and optimized evidence audits must agree. `ownership_manifest.json` binds the local commit, tracked sources, current evidence and the preceding production-integration manifest.

Next, perform actual standard-cell mapping and combined-top STA, keeping synthetic SRAM timing distinct from characterized macro signoff; extend formal correspondence to payload/Data queues and mapped state. Final UPLI transaction conversion, Endpoint/Switch composition, per-VC independence, oversized Write/Atomic behavior, Data Poison, digital PHY, INC, security and manageability remain part of the unchanged full Goal. No push is authorized by this stage's local commit.
