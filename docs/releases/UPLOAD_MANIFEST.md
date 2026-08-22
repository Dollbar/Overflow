# Upload Manifest

## Overflow v0.1 release candidate

- Prepared: 2026-08-22
- State: `APPROVED_FOR_PR`
- Base for review: `origin/main` at `579cab4`
- Final-tree candidate files: 147
- Legacy versioned paths removed by the rename: 71
- Release workflow: candidate committed on a dedicated feature branch; no release tag is created by this manifest

## Final-tree candidate whitelist

- `AGENTS.md`
- `Library/models/hbm/README.md`
- `config/system_baseline.yaml`
- `docs/releases/RELEASE_NOTES.md`
- `docs/releases/UPLOAD_MANIFEST.md`
- `requirements/README.md`
- `requirements/kdlink_traceability.csv`
- `requirements/traceability.csv`
- `rtl/kdlink/README.md`
- `rtl/kdlink/coll_fp32_add_lane.v`
- `rtl/kdlink/coll_reduction_engine.v`
- `rtl/kdlink/kdlink_bonded_port.v`
- `rtl/kdlink/kdlink_bonded_reorder.v`
- `rtl/kdlink/kdlink_bonded_tx_register.v`
- `rtl/kdlink/kdlink_collective32_int32.v`
- `rtl/kdlink/kdlink_collective_datapath16.v`
- `rtl/kdlink/kdlink_context_scheduler16.v`
- `rtl/kdlink/kdlink_credit_bank8.v`
- `rtl/kdlink/kdlink_defs.vh`
- `rtl/kdlink/kdlink_depacketizer.v`
- `rtl/kdlink/kdlink_descrambler64.v`
- `rtl/kdlink/kdlink_direct_scheduler32.v`
- `rtl/kdlink/kdlink_fabric32.v`
- `rtl/kdlink/kdlink_header_checker.v`
- `rtl/kdlink/kdlink_int32_reduce512.v`
- `rtl/kdlink/kdlink_int32_reduce_array512.v`
- `rtl/kdlink/kdlink_link_manager.v`
- `rtl/kdlink/kdlink_nic8.v`
- `rtl/kdlink/kdlink_nic8_cdc.v`
- `rtl/kdlink/kdlink_packetizer.v`
- `rtl/kdlink/kdlink_pcs.v`
- `rtl/kdlink/kdlink_pcs_deskew10.v`
- `rtl/kdlink/kdlink_pcs_rx.v`
- `rtl/kdlink/kdlink_pcs_tx.v`
- `rtl/kdlink/kdlink_reliable_bonded_endpoint.v`
- `rtl/kdlink/kdlink_reliable_endpoint.v`
- `rtl/kdlink/kdlink_reliable_nic8.v`
- `rtl/kdlink/kdlink_replay_buffer.v`
- `rtl/kdlink/kdlink_replay_window.v`
- `rtl/kdlink/kdlink_reverse_codec.v`
- `rtl/kdlink/kdlink_reverse_ctrl.v`
- `rtl/kdlink/kdlink_rx_commit.v`
- `rtl/kdlink/kdlink_scrambler64.v`
- `rtl/kdlink/kdlink_slice.v`
- `rtl/kdlink/kdlink_switch32.v`
- `rtl/kdlink/kdlink_switch_crossbar4.v`
- `rtl/kdlink/kdlink_switch_rr_arbiter32.v`
- `rtl/kdlink/kdlink_switch_slice32.v`
- `rtl/kdlink/kdlink_tensor_bank_array.v`
- `rtl/kdlink/kdlink_tensor_bank_lane.v`
- `rtl/kdlink/kdlink_vc_ingress8.v`
- `simulator/kdlink/README.md`
- `simulator/kdlink/config/chassis32.json`
- `simulator/kdlink/manifest.json`
- `simulator/kdlink/model/kdlink_model/__init__.py`
- `simulator/kdlink/model/kdlink_model/bonding.py`
- `simulator/kdlink/model/kdlink_model/chassis.py`
- `simulator/kdlink/model/kdlink_model/constants.py`
- `simulator/kdlink/model/kdlink_model/pcs.py`
- `simulator/kdlink/model/kdlink_model/performance.py`
- `simulator/kdlink/model/kdlink_model/protocol.py`
- `simulator/kdlink/model/link/kdlink_reverse_channel_model.sv`
- `simulator/kdlink/model/system/kdlink_baseboard32_model.sv`
- `simulator/kdlink/model/system/kdlink_card_model.sv`
- `simulator/kdlink/model/tests/test_kdlink_bonding.py`
- `simulator/kdlink/model/tests/test_kdlink_chassis.py`
- `simulator/kdlink/model/tests/test_kdlink_pcs.py`
- `simulator/kdlink/model/tests/test_kdlink_performance.py`
- `simulator/kdlink/model/tests/test_kdlink_protocol.py`
- `simulator/kdlink/model/tests/test_kdlink_serdes_spec.py`
- `simulator/kdlink/model/tests/test_kdlink_topology.py`
- `simulator/kdlink/pkg/kdlink_env_pkg.sv`
- `simulator/kdlink/pkg/kdlink_tb_pkg.sv`
- `simulator/kdlink/scripts/run.py`
- `simulator/kdlink/tb/subsystem/tb_kdlink_bonded_port.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_collective_datapath16.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_endpoint_credit_recovery.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_nic8.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_nic8_cdc.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_pcs.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_reduction_dtype_ii1.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_reduction_random.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_reverse_ctrl.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_serdes_full_link.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_serdes_pcs_link.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_switch32_congestion.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_switch32_permutation.sv`
- `simulator/kdlink/tb/system/tb_kdlink_baseboard32.sv`
- `simulator/kdlink/tb/system/tb_kdlink_collective32_int32.sv`
- `simulator/kdlink/tb/system/tb_kdlink_direct32.sv`
- `simulator/kdlink/tb/system/tb_kdlink_fabric32.sv`
- `simulator/kdlink/tb/system/tb_kdlink_four_node_full_duplex.sv`
- `simulator/kdlink/tb/system/tb_kdlink_multiboard_e2e.sv`
- `simulator/kdlink/tb/system/tb_kdlink_reliable_bonded_endpoint.sv`
- `simulator/kdlink/tb/system/tb_kdlink_reliable_endpoint_e2e.sv`
- `simulator/kdlink/tb/system/tb_kdlink_reliable_nic8_fabric.sv`
- `simulator/kdlink/tb/system/tb_kdlink_reliable_reset_recovery.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_bonded_reorder.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_context_scheduler16.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_credit_bank8.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_direct_scheduler32.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_env_pkg.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_fifo_primitives.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_link_manager.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_pcs_deskew10.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_replay_buffer.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_replay_timeout.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_rx_commit_stress.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_serdes_channel.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_serdes_full_lane.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_serial_if.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_slice.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_tensor_bank_array.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_vc_ingress8.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_vip_stream.sv`
- `simulator/kdlink/vip/kdlink_serial_if.sv`
- `simulator/kdlink/vip/kdlink_stream_if.sv`
- `simulator/kdlink/vip/kdlink_stream_monitor.sv`
- `specs/interfaces/README.md`
- `specs/interfaces/hbm_transaction.md`
- `specs/interfaces/npu_gemm_vector_core.md`
- `specs/kdlink/README.md`
- `specs/kdlink/kdlink_requirements.md`
- `specs/kdlink/simulation_environment.md`
- `verification/kdlink/README.md`
- `verification/kdlink/cdc/README.md`
- `verification/kdlink/cdc/summary.json`
- `verification/kdlink/coverage/README.md`
- `verification/kdlink/coverage/summary.json`
- `verification/kdlink/formal/README.md`
- `verification/kdlink/formal/escape_dependency.ys`
- `verification/kdlink/formal/fifo_credit.ys`
- `verification/kdlink/formal/formal_escape_dependency.sv`
- `verification/kdlink/formal/formal_fifo_credit.sv`
- `verification/kdlink/formal/formal_replay_progress.sv`
- `verification/kdlink/formal/formal_rx_exact_once.sv`
- `verification/kdlink/formal/formal_vc_service.sv`
- `verification/kdlink/formal/replay_progress.ys`
- `verification/kdlink/formal/rx_exact_once.ys`
- `verification/kdlink/formal/summary.json`
- `verification/kdlink/formal/vc_service.ys`
- `verification/kdlink/scripts/run_coverage.py`
- `verification/kdlink/scripts/run_formal.py`
- `verification/kdlink/scripts/run_sta.py`
- `verification/kdlink/scripts/run_static.py`
- `verification/kdlink/sta/README.md`
- `verification/kdlink/sta/summary.json`

## Legacy versioned paths removed or renamed

- `rtl/kdlink/kdlink_v2_bonded_port.v`
- `rtl/kdlink/kdlink_v2_bonded_reorder.v`
- `rtl/kdlink/kdlink_v2_bonded_tx_register.v`
- `rtl/kdlink/kdlink_v2_collective32_int32.v`
- `rtl/kdlink/kdlink_v2_context_scheduler16.v`
- `rtl/kdlink/kdlink_v2_defs.vh`
- `rtl/kdlink/kdlink_v2_depacketizer.v`
- `rtl/kdlink/kdlink_v2_descrambler64.v`
- `rtl/kdlink/kdlink_v2_direct_scheduler32.v`
- `rtl/kdlink/kdlink_v2_fabric32.v`
- `rtl/kdlink/kdlink_v2_header_checker.v`
- `rtl/kdlink/kdlink_v2_int32_reduce512.v`
- `rtl/kdlink/kdlink_v2_int32_reduce_array512.v`
- `rtl/kdlink/kdlink_v2_nic8.v`
- `rtl/kdlink/kdlink_v2_nic8_cdc.v`
- `rtl/kdlink/kdlink_v2_packetizer.v`
- `rtl/kdlink/kdlink_v2_pcs.v`
- `rtl/kdlink/kdlink_v2_pcs_deskew10.v`
- `rtl/kdlink/kdlink_v2_pcs_rx.v`
- `rtl/kdlink/kdlink_v2_pcs_tx.v`
- `rtl/kdlink/kdlink_v2_replay_buffer.v`
- `rtl/kdlink/kdlink_v2_reverse_codec.v`
- `rtl/kdlink/kdlink_v2_reverse_ctrl.v`
- `rtl/kdlink/kdlink_v2_scrambler64.v`
- `rtl/kdlink/kdlink_v2_slice.v`
- `rtl/kdlink/kdlink_v2_switch32.v`
- `rtl/kdlink/kdlink_v2_switch_crossbar4.v`
- `rtl/kdlink/kdlink_v2_switch_rr_arbiter32.v`
- `rtl/kdlink/kdlink_v2_switch_slice32.v`
- `rtl/kdlink/kdlink_v2_tensor_bank_array.v`
- `rtl/kdlink/kdlink_v2_tensor_bank_lane.v`
- `simulator/kdlink/model/system/kdlink_v2_baseboard32_model.sv`
- `simulator/kdlink/model/system/kdlink_v2_card_model.sv`
- `simulator/kdlink/model/tests/test_kdlink_v2_bonding.py`
- `simulator/kdlink/model/tests/test_kdlink_v2_chassis.py`
- `simulator/kdlink/model/tests/test_kdlink_v2_pcs.py`
- `simulator/kdlink/model/tests/test_kdlink_v2_performance.py`
- `simulator/kdlink/model/tests/test_kdlink_v2_protocol.py`
- `simulator/kdlink/model/tests/test_kdlink_v2_serdes_spec.py`
- `simulator/kdlink/model/tests/test_kdlink_v2_topology.py`
- `simulator/kdlink/pkg/kdlink_v2_env_pkg.sv`
- `simulator/kdlink/pkg/kdlink_v2_tb_pkg.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_bonded_port.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_nic8.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_nic8_cdc.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_pcs.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_reverse_ctrl.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_serdes_pcs_link.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_serdes_full_link.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_switch32_congestion.sv`
- `simulator/kdlink/tb/subsystem/tb_kdlink_v2_switch32_permutation.sv`
- `simulator/kdlink/tb/system/tb_kdlink_v2_baseboard32.sv`
- `simulator/kdlink/tb/system/tb_kdlink_v2_collective32_int32.sv`
- `simulator/kdlink/tb/system/tb_kdlink_v2_direct32.sv`
- `simulator/kdlink/tb/system/tb_kdlink_v2_fabric32.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_bonded_reorder.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_context_scheduler16.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_env_pkg.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_pcs_deskew10.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_replay_buffer.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_serdes_channel.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_serdes_full_lane.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_serial_if.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_slice.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_tensor_bank_array.sv`
- `simulator/kdlink/tb/unit/tb_kdlink_v2_vip_stream.sv`
- `simulator/kdlink/vip/kdlink_v2_serial_if.sv`
- `simulator/kdlink/vip/kdlink_v2_stream_if.sv`
- `simulator/kdlink/vip/kdlink_v2_stream_monitor.sv`
- `specs/interfaces/hbm_transaction_v0.1.md`
- `specs/interfaces/npu_gemm_vector_core_v0.1.md`

## External SerDes dependencies already on main

These files are referenced by joint simulation but are not part of this upload candidate:

- `Library/models/kdlink/serdes/kdlink_v2_serdes_channel_model.sv`
- `Library/models/kdlink/serdes/kdlink_v2_serdes_lane_full_model.sv`
- `Library/models/kdlink/serdes/kdlink_v2_serdes_channel_full_model.sv`
- `Library/models/kdlink/serdes/kdlink_v2_serdes_link_model.sv`
- `Library/models/kdlink/serdes/kdlink_v2_serdes_link_full_model.sv`

## Timing dependencies already on main

The local STA flow consumes these upstream assets, but they are unchanged relative to `origin/main` and
are not newly uploaded by this candidate:

- `Library/timing/interfaces/overflow_hbm_serdes_abstract_fast.lib`
- `Library/timing/interfaces/overflow_hbm_serdes_abstract_typical.lib`
- `Library/timing/interfaces/overflow_hbm_serdes_abstract_slow.lib`
- `Library/timing/interfaces/manifest.yaml`
- `Library/timing/interfaces/profiles.yaml`
- `technology/**`

## Explicit exclusions

- `Library/models/kdlink/serdes/**` (every SerDes simulation model, package, profile, and file list)
- `Library/timing/**` and `technology/**` (already present unchanged on `origin/main`)
- `simulator/memory/**` (already present unchanged on `origin/main`)
- `simulator/kdlink/model/serdes/**`
- All other unchanged `Library/**` content already present on `main`
- `simulator/kdlink/work/**`
- `verification/kdlink/coverage/work/**`
- `verification/kdlink/formal/work/**`
- `verification/kdlink/cdc/work/**`
- `verification/kdlink/sta/work/**`
- Python bytecode and `__pycache__`
- Waveforms, compiled binaries, build logs, and generated C++
- External Liberty/PDK files, credentials, and private data

`Library/models/hbm/README.md` is the only `Library` file in the candidate. It only updates the stable
`specs/interfaces/hbm_transaction.md` link and does not contain or modify a simulation model.

Approval of this document authorizes review of the candidate file boundary only. Staging, committing,
tagging, and pushing remain separate actions and have not been performed.
