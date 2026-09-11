# Transmit header visibility qualification

The final source checkpoint `1194c73711541aadc2633a52fafe8de368d778ff` is adopted as the next research baseline after complete RTL composition checks, actual mapped correspondence and all 60 physical measurements. The 640 ps target and full dual-IP delivery remain open. Evidence summaries and hashes are recorded in `docs/tl_tx_header_visibility_evidence.json`.

The candidate moves invalid-word masking from the two transmit Header FIFO outputs to the channel's final payload assembly. Qualification can inspect the retained header directly, while header eligibility and diagnostics still require the original valid flag. Existing public FIFO/storage and channel callers retain their original defaults. No port, register, cycle, logical queue capacity or Data-bank behavior is added or changed.

`upli_receive_fifo` and `upli_receive_storage` add `C_ZERO_INVALID`, default 1. Only the Header FIFO instances in `tl_tx_buffered` select 0. `tl_tx_channels` adds `RAW_HEADERS`, default 0; only that buffered composition selects 1. In this profile the selected invalid header and its atomic tags are zeroed at assembly, and invalid `has_data` is also zero. The latter is required even for arbitrary, inconsistent held states. Both parameters reject values other than 0 and 1 during elaboration.

## Verification boundary

The frozen RTL reference is `6839cac6a0e789fdef41787ae6da3e8546e896b2`. The channel proof compares its explicitly masked header/tag inputs with the candidate's raw inputs, retaining every public output and all eight actual next-state bits. No stall, validity, held-state or credit assumptions are introduced. WIDTH 8–16 all pass, with independent reset SAT on both sides. Existing standalone channel semantics also pass all nine widths against the older `1f917a1` reference.

The FIFO proof checks default and raw/remasked composition at data widths 8, 32 and 512, and depths 1, 2, 3, 5, 129 and 257: 36 complete-state configurations and 72 independent reset checks. It also checks that the actual raw profile exposes the retained `reg_head` bits. The buffered proof compares every real FF transition, public output and exposed SRAM transaction output against the frozen reference, with arbitrary common SRAM read data. It does not substitute internal control signals.

Two actual RTL faults remove invalid payload/tag masking or invalid `has_data` masking. Both are detected at WIDTH 8/16 by the same complete channel comparison. The initial missing-parameter elaboration is retained as the pre-implementation failure. A BLIF export initially duplicated shared macro-address aliases; the proof helper now runs Yosys alias cleanup after independently auditing the exact D/Q cut. The failed export is retained and is not counted as an equivalence result.

The first candidate triggered strict lint warnings because logical negation was applied to integer parameters. The isolated corrected candidate uses explicit equality to zero. Its 16 profile elaboration/lint checks pass, including rejection of signed −1 and 2. Yosys requires the two's-complement literal for −1; the initial command-parser rejection is retained separately from the successful RTL parameter rejection. Both corrected channel proof matrices, the 36 FIFO configurations and six buffered WIDTH 8/16, depth 1/2/3 configurations pass. Both corrected fault types are also detected at both widths.

## Final integration and physical evidence

The initial source candidate passes all 1,258 channel vectors, 36 production unit configurations / 5,760 modeled cycles, six actual SRAM FIFO depth runs, 32 actual production peer configurations, and their independent wire/queue/partition/capture audits. All 128 peer trace files are byte-identical to the qualification-reuse baseline. All 27 production ownership configurations pass 35 properties per configuration; normal and optimized Python audits agree. All 22 production-top wire faults, 16 channel unit fault instances and 64 channel peer fault instances are detected. The initial channel check stage remains failed because its lint warnings are real; successful fault detection does not override that failure.

All final-source checks use the `header_visibility_clean` labels, except the 16 parameter/lint checks named `header_visibility_final_profiles`. Both nine-width channel comparisons and the 36 FIFO configurations pass. Complete buffered composition passes WIDTH 8–16 × Header/Data depth 1/2/3: 27 configurations and 54 reset queries. Source snapshots, current RTL hashes, actual CEC outcomes and all 126 FIFO/buffered reset logs are checked in `header_visibility_clean_composition_evidence.json`.

The final source also passes 1,258 channel vectors, strict lint/synthesis, 36 production unit configurations / 5,760 cycles, six actual SRAM FIFO depth runs, 32 production peer configurations and independent wire/queue/partition/capture checks. The peer runs cover 28,868 cycles, 13,016 stored SRAM words, 7,712 FC transfers, 1,536 source groups, 5,248 partitions and 6,912 fields. All 128 trace files match the prior qualification-reuse baseline byte for byte. All 27 ownership configurations pass 35 properties each; no new ownership cover or ownership-fault matrix is claimed. The final 22 production wire faults, 16 channel unit fault instances, 64 channel peer fault instances and four missing-mask fault instances are detected.

| WIDTH | Standard-cell area before / after (µm²) | Worst setup before / after (ns) | Setup improvement |
|---|---:|---:|---:|
| 8 | 44,696.106 / 44,790.732 | −1.853540 / −1.806385 | 47.155 ps |
| 16 | 46,074.420 / 45,603.936 | −1.861665 / −1.834665 | 27.000 ps |

The final mappings contain 69,382 / 69,967 cells, unchanged 6,254 / 6,574 FFs and 64 SRAM interfaces. WIDTH 8 area increases 0.212%; WIDTH 16 area decreases 1.021%. The same five standard-cell corners, three synthetic SRAM views, two periods and unchanged clock/IO constraints complete all 60 measurements. Main 640 ps timing closes 0/30 profiles; reference 6.4 ns timing closes 26/30. Worst hold remains −0.008036 ns. The nonzero physical-run exit reports these timing violations; measurement completeness is separately audited. Normal and optimized Python physical audits are byte-identical. Both complete mapped Verilog files also match the initial candidate, with identity recorded separately.

The final WIDTH 8 critical path starts at Response Header FIFO `reg_head[120]` and ends at Request Header FIFO `cnt_unread[1]`. WIDTH 16 starts at Request Header FIFO `reg_head[123]` and ends at Response Header FIFO `cnt_unread[1]`. Actual graph aliases, path logs and the completed measurement matrix are bound in `header_visibility_clean_critical_paths.json`. Header qualification through opposite-class consume/prefetch is the next timing target; no subsequent optimization gain is assumed.

## Final mapped correspondence and limits

All 12 complete actual output/next-state partitions pass at WIDTH 8/16. Each width includes all 4,144 public/SRAM transaction output bits; RTL/mapped state counts are 6,244/6,254 and 6,564/6,574 respectively. Four independent reset, four cursor-domain and four dormant-payload/capture queries pass. Six actual mapped fault checks detect reset-D, capture-D and partition-CEC mutations. The final ten-stage correspondence auditor passes in normal and optimized Python and produces identical evidence.

This establishes binary post-reset correspondence with common arbitrary SRAM reads, including the actual cursor encoding and dormant payload relation. It does not prove the SRAM implementation or complete protocol correctness. All timing numbers use actual standard cells with synthetic SRAM timing, without layout parasitics; they are not characterized macro or full-IP signoff. Area excludes SRAM. Activity-based power analysis, full-chip area, physical implementation, full-top CDC/RDC and complete Endpoint/Switch integration remain open, together with the remaining protocol/payload, digital PHY/PCS/FEC, INC, security and manageability scope.

A clean source-only local clone at `1194c73` passes `make test rtl-smoke prepared-tx-smoke` with the authorized dependency root, plus the new channel comparison, FIFO subset and all 16 profile checks. The 31 proof/audit helper checks pass in normal and optimized Python. Independent RTL static checking with the confirmed `i_clk` metadata reports zero errors and two existing genvar-constant advisories; the earlier unconfigured wrapper report remains retained. Initial lint failures, alias-export failure and stale-source audit rejection are historical evidence, not final passes.

## Reproduction

Run from the repository root with the authorized dependency root supplied explicitly:

```sh
python3 verification/tl_tx_qualification/run_header_visibility.py --label NEW_COMPOSITE
python3 verification/tl_tx_qualification/run_header_visibility.py --label NEW_PAYLOAD_FAULT --fault payload --widths 8 16
python3 verification/tl_tx_qualification/run_header_visibility.py --label NEW_DATA_FAULT --fault has_data --widths 8 16
python3 verification/tl_tx_qualification/run_storage_visibility.py --label NEW_FIFO --top fifo --depths 1 2 3 5 129 257
python3 verification/tl_tx_qualification/run_storage_visibility.py --label NEW_BUFFERED --top buffered --kd28-root "$KD28_ROOT" --widths 8 9 10 11 12 13 14 15 16 --depths 1 2 3
python3 verification/tl_tx_qualification/run_visibility_profiles.py --label NEW_PROFILES --kd28-root "$KD28_ROOT"
```

Each label creates immutable source snapshots, generated proof/elaboration scripts, logs and `results.json` under `build/verification/tl_tx_qualification`. An optional `--rtl-root` points to an isolated candidate tree. Follow with the production unit/peer/ownership, physical and mapped-correspondence commands in the existing qualification review. The full Endpoint/Switch, protocol/payload, digital PHY, INC, security, manageability and characterized macro obligations remain open.
