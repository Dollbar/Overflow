# Production transmit physical baseline review

The actual `tl_tx_prepared` hierarchy has been mapped at WIDTH 8 and 16 using the confirmed TSMC28 HPC+ SSG 0.81 V/125 C standard-cell library, HEADER_DEPTH=2 and BANK_DEPTH=3. The RTL is unchanged from `eb1d3004f9cdc18e63c3f2f290e230ac7683215c`.

| WIDTH | Cells including SRAM instances | Positive-edge FF | SRAM macros | Standard-cell area, µm² |
|---|---:|---:|---:|---:|
| 8 | 73,677 | 6,254 | 64 | 47,213.082 |
| 16 | 75,364 | 6,574 | 64 | 48,461.994 |

Area excludes SRAM: no characterized macro area or total silicon area is claimed. Each macro is the actual fixed `KD28_SRAM_SDP_256X32` interface; clocks remain directly connected to the original `i_clk`. The flow maps standard cells around the macro instances and never synthesizes behavioral memory arrays.

## Completed measurements

All 60 measurements are complete: WIDTH 8/16 × five confirmed standard-cell corners × three synthetic SRAM views × 0.640/6.400 ns periods. Ordinary and optimized Python audits independently checked all raw logs, source/library/tool identities, actual macro/clock inventory and Liberty-based standard-cell areas. Their evidence JSON files are byte-identical. Session 4476 terminated with exit 1 because timing violations remain; this is a complete measurement matrix, not timing closure.

| WIDTH | Main period closed | Reference period closed | Worst setup, ns | Worst hold, ns |
|---|---:|---:|---:|---:|
| 8 | 0/15 | 13/15 | −3.217651 | −0.008036 |
| 16 | 0/15 | 13/15 | −3.261416 | −0.008036 |

The four remaining reference-period failures are hold violations at the two fast standard-cell corners with the slow synthetic SRAM view. Every corner/view pair has the expected 5.760 ns setup shift and unchanged hold slack between periods.

The worst setup path at WIDTH 8 connects Response Header FIFO `cnt_cached[0]` to `cnt_unread[1]`. At WIDTH 16 it connects Request Header FIFO `cnt_cached[0]` through class arbitration to Response Header FIFO `cnt_unread[1]`. The dependency passes through header availability, qualification, packing, wire consumption and prefetch scheduling. The worst hold path is Request Data input `i_data1[0]` to a Bank 0 SRAM input. `critical_paths.json` binds the actual mapped endpoints and raw logs. Queue-feedback optimization and SRAM input hold repair are separate obligations.

The original partial `checkpoint_results.json` and its manifest are retained unchanged. The complete results are in `evidence.json` and `evidence_optimized.json`; the terminal job record supersedes the previous running handoff.

## Timing assumptions and qualification

The three SRAM Liberty views are explicitly synthetic repository assumptions. The external `profiles.yaml` specifies setup/hold/clock-to-Q in ns as fast 0.060/0.020/0.120, typical 0.100/0.030/0.200 and slow 0.160/0.050/0.320. They are not foundry PVT corners. The Cartesian matrix tests the actual standard-cell corners against each assumption; it does not equate their process labels.

All runs use an ideal common clock, setup/hold uncertainty 0.032/0.010 ns, clock/input transition 0.050 ns, input max/min delays 0.128/0.020 ns, output max/min delays 0.128/−0.020 ns, and 0.005 pF output load. No false paths, multicycle exceptions or parasitics are introduced. Six actual path families are required: input-to-register, register-to-register, register-to-output, register-to-macro, input-to-macro and macro-to-register. Successful measurement is distinct from setup/hold/limit closure.

Twelve report-parser tests and six tests that mutate actual mapped inventories pass under ordinary and optimized Python. They reject missing/wrong macro or pin counts, omitted path families, wrong clock mode/view, nonfinite results, tool failures, unconstrained endpoints, missing completion, misclassified negative timing, changed clocks and unknown cells. Original missing-checker test failures remain preserved. Both mapped standard-cell areas were independently recalculated from actual standard-cell Liberty areas and mapped instance counts.

## Commands and remaining gates

```sh
python3 verification/tl_tx_prepared/run_physical.py --lib-root /authorized/NLDM --kd28-root /authorized/repository --sta /configured/sta --label physical_baseline
python3 verification/tl_tx_prepared/test_timing_report.py
python3 verification/tl_tx_prepared/test_physical_audit.py --graph build/verification/tl_tx_prepared/physical_baseline/w8/mapped.json
python3 verification/tl_tx_prepared/check_physical.py --label physical_baseline
python3 -O verification/tl_tx_prepared/check_physical.py --label physical_baseline --output build/verification/tl_tx_prepared/physical_baseline/evidence_optimized.json
```

The first command has terminated; do not overwrite this baseline. For later fresh runs, supply a new label. Outputs include RTL/script snapshots, exact tool commands, mapped Verilog/JSON, area, raw STA logs and result summaries. Exit 1 is expected when timing violations remain; it does not by itself establish that all measurements completed. The full auditor deliberately refuses an incomplete matrix.

Actual mapped-state/output correspondence is now established in the [mapped correspondence review](tl_tx_prepared_mapping_review.md). Next repair setup/hold with preserved source-capture, partition-queue, wire-consumption and throughput contracts. The actual mapping recodes both preparation cursors from four binary bits to nine one-hot bits. Full D/Q extraction passes, but direct identical-state matching correctly rejects this difference; an explicit encoding relation is required. See [mapped correspondence plan](tl_tx_prepared_mapping_plan.md).

Full payload/Data-bank formal checks, final UPLI/Endpoint/Switch integration, remaining protocol items, digital PHY, INC, security and manageability remain open. The current measurements do not finish the full Goal. The user authorized pushing the existing implementation to `origin/work/tl-receive-credit` at `7b45017` before this continuation.
