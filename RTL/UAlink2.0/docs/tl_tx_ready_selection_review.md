# Selected-ready experiment rejected

The held-class-aware ready bypass is functionally equivalent, but both actual mapped widths regress in area and worst setup. The one-line RTL experiment was therefore removed, and `rtl/tl/tl_tx_channels.v` was restored byte for byte to the proven `6839cac` checkpoint. No RTL change from this experiment is adopted.

The experiment replaced `ready[selected_class]` with `r_hold_valid ? ready[r_hold_class] : (|ready)`. Actual channel graphs prove the identity at WIDTH 8/16 with all eight state bits arbitrary and no environment assumptions. Ignoring the held class produces a real counterexample: Response is held, only Request is ready, and the selected actual ready is zero. An actual RTL mutation that removes the held branch is also detected by full output/next-state CEC at both widths.

## Verification and measured result

- The candidate passes complete public-output and actual next-state equivalence for WIDTH 8–16, plus 18 independent reset queries. The standalone packer is unchanged.
- All 1,258 independent channel vectors and 36 production-unit configurations / 5,760 modeled cycles pass. Channel lint/synthesis pass at both widths; eight unit fault types generate 16 detections, and 64 actual channel peer faults are detected.
- All 32 actual SRAM peer configurations and independent wire/capture audits pass. All 128 wire, queue, partition and capture traces are byte-identical to the proven qualification-reuse baseline. Normal and optimized Python audits agree.
- All 27 production ownership configurations / 35 properties per configuration pass; the existing independent structural/property/log auditor agrees under normal and optimized Python. All 22 production-top wire faults are detected.
- Both widths are mapped with the same 64 SRAM interfaces and 6,254 / 6,574 FFs. The same five standard-cell corners, three synthetic SRAM views and two clock periods complete all 60 measurements. Normal and optimized physical audits are byte-identical.

| WIDTH | Baseline area (µm²) | Candidate area (µm²) | Baseline worst setup (ns) | Candidate worst setup (ns) |
|---|---:|---:|---:|---:|
| 8 | 44,696.106 | 44,770.698 | −1.853540 | −1.859017 |
| 16 | 46,074.420 | 47,464.452 | −1.861665 | −1.953218 |

Area increases about 0.167% / 3.017%, and worst setup worsens by 5.477 / 91.553 ps. Candidate mapped cell counts are 69,012 / 71,181; fewer cells do not imply smaller area or better timing. Main 640 ps timing closes 0/30 profiles and reference 6.4 ns timing closes 26/30, with worst hold still −0.008036 ns. Synthetic SRAM views remain an abstraction and these are prelayout measurements.

The candidate's actual mapped equivalence was not pursued after the physical rejection. Its measurements describe the generated candidate netlists and do not establish their functional signoff. The restored baseline retains its previously completed mapped correspondence and timing evidence.

## Evidence and reproduction

Evidence remains under `build/verification/tl_tx_qualification`, `tl_tx_channels`, `tl_control_partition` and `tl_tx_prepared`, using `ready_identity*`, `ready_ignore_hold_cec`, `ready_selection_*` and `ready_rejected_candidate` labels. The latter preserves the exact rejected source, its SHA-256 and the verified restoration decision. The initial negative SAT run lost the expected failure banner to output buffering; its witness and incomplete classification are retained. The runner now uses line buffering and checks the actual ready/held/selected witness values; that initial incomplete run is not counted as a qualified pass.

From a clone containing the proven checkpoint:

```sh
python3 verification/tl_tx_qualification/run_ready_identity.py --label NEW_IDENTITY
python3 verification/tl_tx_qualification/run_ready_identity.py --label NEW_NEGATIVE --ignore-held
```

These commands emit actual source snapshots, full D/Q graphs, added observations and SAT proofs/witnesses at WIDTH 8/16. To repeat the rejected physical experiment, use a separate checkout at `6839cac`, apply the single expression change shown above, then run the equivalence, production peer/ownership and full physical entries documented in [the prior review](tl_tx_qualification_reuse_review.md). The physical auditor checks current source identity, so the rejected candidate's audit must run before restoring the RTL or in that separate checkout.

The next target is the [header visibility path](tl_tx_header_visibility_plan.md). Actual baseline path cell `_060149_` combines cache-count bits with retained header bit 119 before subsequent logic; the retained physical netlist and normalized gate aliases bind that observation. Investigate separating raw qualification data from validity-controlled output masking, while preserving all current public behavior. Full 640 ps closure, Endpoint/Switch completion, protocol/payload, digital PHY, INC, security, manageability and macro signoff remain open.
