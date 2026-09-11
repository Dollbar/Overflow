# Direct credit-slot matching candidate

The candidate replaces intermediate five-bit slot encoding followed by fixed-account comparisons in `tl_credit_admission` with direct Request/Response, Pool and VC matching. Field extraction, six-bit contribution/reduction arithmetic, shared Data Pool merge, public requirements masking and allow/wait/shortfall expressions are unchanged. No port, parameter, state, cycle, clock/reset or credit-charging behavior is added.

The prior FIFO prefetch experiment was rejected and restored before this candidate was applied. Its completed rejection checkpoint is `ec569982fa7229efce66ad573ac0d474d0245ee0`, pushed and verified on `work/tl-receive-credit`. The candidate at `c84c113` is now adopted as the research baseline after complete current-source semantic, physical and mapped audits. The prior comparison baseline is `6f10b33`.

## Semantic qualification

The frozen source reference is `6f10b33539624664cc4231bbb681e7b1d62dc401`. Candidate SHA-256 is `4f7578ab3caa5d1a2909ea19c8d51816097ebb886f040708cd581a66013d2e54`. Before applying it to active RTL:

- All WIDTH 8–16 complete 207 actual SAT queries over all 123 public outputs. Each width first proves 20 unconditional six-bit requirement slots, then proves three flags using only those discharged equalities. The real RTL shares all external inputs; there are no free internal cuts or protocol legality assumptions. Snapshot/reference identities, complete comparison coverage, query commands and successful proof counts are audited separately.
- Independent model vectors pass 8,371 cases at each of WIDTH 8/16, totaling 16,742. Six real candidate faults produce twelve failing vector runs with successful compilation: missing future Data cost, wrong dedicated Data VC, missing shared merge, merging the wrong pool, ignoring available credit and bypassing initialization.
- Complete actual output/next-state comparisons of standalone packer and integrated channels pass at WIDTH 8/16: four configurations with independent resets. These use the older immutable `1f917a1` reference, so the intervening adopted changes are included in the comparison.
- Strict Verilator lint passes at WIDTH 8/16. Independent static RTL checking reports zero errors and three advisories about existing generate-style integer literals. All candidate changes have explanatory Chinese comments and retain the repository's compact style.

The existing proof runner's explicit reference option initially rejected a different immutable commit because it shared a historical cache. Explicit references now use their own source/metadata snapshots; only the original `4376b8b` flow maintains the legacy cache needed by historical auditors. Four real-filesystem regression tests pass in normal and optimized Python, including rejection of incomplete/corrupted legacy pairs. The new-reference actual entry passes 23 queries while preserving the existing legacy bytes. An actual wrong-Pool mutation fails the first slot query; its SAT inputs are captured and the mismatch is replayed through both real RTL modules in Icarus, with no unknown outputs.

## Production and physical gates

Current production unit regressions pass all 36 configurations, and both actual production peer matrices pass 32 configurations. Independent wire/queue/partition/capture audits pass; normal/optimized wire evidence is identical, and all 128 actual trace files match the adopted header-visibility baseline byte for byte. All 22 production wire faults are detected. Standard admission checks pass strict lint/synthesis and invalid WIDTH 7/17 rejection, six fault types at both widths and sixteen actual wrapper-bypass faults. The admission fault runner supports both the historical encoded-slot anchor and the new direct Data-only VC mutation.

The 27-configuration ownership matrix is complete, with 35 assertions per configuration and byte-identical normal/optimized audits. A clean Git clone at `c84c113` passes `make test rtl-smoke prepared-tx-smoke` with the authorized SRAM root supplied explicitly; the clone also passes the 23-query explicit-reference admission proof without a shared legacy cache.

All 60 physical measurements are complete and independently audited in normal/optimized Python with identical evidence. WIDTH 8/16 standard-cell areas are 43,569.792/45,162.054 µm², reductions of 2.73%/0.97% relative to `6f10b33`. Worst setup is −1.816202/−1.799045 ns: WIDTH 8 regresses 9.817 ps and WIDTH 16 improves 35.620 ps. Worst hold remains −0.008036 ns at both widths; 640 ps closes 0/30 profiles and 6.4 ns closes 26/30. These are standard-cell, synthetic-SRAM prelayout measurements, excluding SRAM area.

Actual mapped reset, cursor and dormant-state relations pass four queries each, and all six actual mapped reset/capture/partition faults are detected. All twelve complete output/next-state CEC partitions now pass, six per width, covering 4,144 public/macro output bits per width and actual complete next state. The normal/optimized final mapped evidence is byte-identical. No old-source mapped proof is transferred to this candidate.

The candidate is retained for measured area reduction at both widths, with the disclosed WIDTH8 setup regression and WIDTH16 improvement. Current-source mapped correspondence is complete in its explicit binary/reset/SRAM-input scope. Macro signoff, activity-based power and full dual-IP completion remain unestablished. Evidence bindings are recorded in `docs/tl_credit_slot_selection_evidence.json`. Full Endpoint/Switch, protocol/payload, digital PHY/PCS/FEC, INC, security, management, CDC/RDC and characterized-macro obligations remain open.

## Reproduction

Use a clone containing the reference commits and fresh labels:

```sh
python3 -m unittest discover -s verification/tl_credit_reduction -p test_reference_cache.py
python3 verification/tl_credit_reduction/run_equivalence.py --reference-commit 6f10b33 --widths 8 9 10 11 12 13 14 15 16 --label NEW_EQ
python3 verification/tl_credit_admission/run_rtl.py --label NEW_VECTORS
python3 verification/tl_credit_admission/run_checks.py --kd28-root PATH --label NEW_CHECKS
```

The check stage requires the existing sixteen healthy `pressure_verified` fixtures as documented in the earlier admission review. `--replace FILE` on the equivalence/vector entries accepts an isolated candidate named `tl_credit_admission.v`. Outputs are snapshots, exact miters/scripts, SAT/vector logs and `results.json` under their stage-specific `build/verification/` directories. Continue with the established production unit/peer/ownership, physical and mapped-correspondence commands using the same source snapshot.
