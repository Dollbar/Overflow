# Production transmit mapped correspondence plan

Execute alone. Use the actual netlists from `physical_baseline`, preserving that timing evidence. RTL baseline: `eb1d3004f9cdc18e63c3f2f290e230ac7683215c`; current tooling checkpoint: `7b450175424d1119a3e72760a7df765309dd3691`.

Goal: establish complete post-reset correspondence between production RTL and its actual standard-cell mapping. Common arbitrary SRAM read outputs are allowed only when all original macro clocks, controls, addresses, masks and write-data outputs are compared. No behavioral memory replacement, internal arbitrary cut or output-only shortcut may conceal unmatched state.

- [x] Elaborate actual gold/gate hierarchies and expose every fixed SRAM transaction port, retaining source/netlist/library identities.
- [x] Inventory every original positive-edge FF and match semantic register aliases. Extract actual D/Q equations without modifying combinational logic; reject missing state or changed clocks.
- [x] Qualify complete output/next-state comparison with actual mapped-cell mutation, then run healthy CEC for WIDTH 8/16.
- [x] Prove reset and independent dormant preparation payload cases, so an assumed equal-state CEC is not mislabeled as reset-reachable sequential equivalence.
- [x] Audit all scope boundaries and bind evidence. Full payload/protocol reference correspondence and physical timing closure remain separate Goal obligations.

Entry command: `python3 verification/tl_tx_prepared/run_mapped_pair.py --label mapped_pair --widths 8 16`. Outputs actual paired graphs, semantic state layouts, SRAM observations and preparation logs under `build/verification/tl_tx_prepared/LABEL`. Subsequent proof commands must consume these exact artifacts.

Current findings: exact D/Q extraction covers 6,244/6,564 normalized RTL state bits and 6,254/6,574 actual mapped state bits. Both preparation cursors were recoded from binary 4-bit to one-hot 9-bit storage; a strict identical-state match correctly rejects the pair. The actual mapping-log codebook gives a complete explicit relation. Five tests under ordinary/optimized Python qualify codebook completeness, unique one-hot values, constant preservation and complete state coverage.

`run_encoding_cec.py --label NEW_LABEL --widths 8 16` uses that relation and compares all public/macro outputs plus every actual mapped next-state bit, conditional on both binary cursors being 0..8. The original `encoded_step` artifacts retain a BLIF read failure caused by unlowered wrapper operators. The `encoded_step_techmapped` run lowers those operators; both complete-network queries and the WIDTH 8 partitioned diagnostic terminated at the 150-second external limit. All are unresolved; no live job remains. Reset establishment, independent dormant payloads and actual mapped-cell fault qualification remain open even if this conditional comparison later passes.

Completed checkpoint: `explicit_wide_partition` proves all six output/next-state blocks at each width. `independent_reset`, `cursor_relation` and `dormant_capture` each prove four SAT obligations. Two actual mapped reset-D faults, two actual mapped capture-D faults and two fault replays through the partition CEC all detect real mismatches. The normal and optimized `check_mapped_correspondence.py` audits agree. The full post-reset standard-cell correspondence is established with common arbitrary SRAM read values; protocol payload proofs, timing closure and the complete dual-IP Goal remain open. See `tl_tx_prepared_mapping_review.md`.
