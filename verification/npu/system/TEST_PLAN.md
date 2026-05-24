# NPU DMA and Pod Verification Plan

Status: required pull-request gate for the versioned NPU-internal DMA, HBM beat boundary, and DMA-only
Pod-shared SRAM scope. Host queues, KD-ISA encoding, IOVA/protection, physical HBM, NoC, additional compute
SRAM clients, ECC, CDC, and post-layout signoff are outside this plan and remain separately gated.

## 1. Reproducible Gate

Run from a clean repository checkout after installing `requirements-dev.txt`:

```sh
make check
make kd28-sram-fifo
make npu-system-test
make sta-kd28
make npu-system-sta-nangate45
```

`make npu-system-sta-nangate45` resolves the open-source OpenROAD Flow Scripts checkout from
`third_party/OpenROAD-flow-scripts` by default. `OPENROAD_FLOW_ROOT` may select another checkout without
editing a tracked path. The reproducibility baseline is OpenROAD Flow Scripts revision
`7ff3adf8eda37712a40591dbd8ec3bef449e6fee`. Generated output remains below `verification/npu/system/build/`,
`verification/kd28/work/`, and `technology/work/`; these paths are ignored and must not enter a commit.

## 2. RTL Module Coverage

| RTL modules | Direct or owning test | Required evidence |
| --- | --- | --- |
| `npu_dma_address_generator.sv`, `npu_dma_pkg.sv` | `tb_npu_dma_address_generator` | Linear, 2-D, 3-D, overlap, malformed version, alignment, bounds, overflow, clear/reset, and ready-valid stability; lint, synthesis, 1 GHz STA |
| `npu_dma_channel_mover.sv`, `npu_dma_tag_metadata_bank.sv` | `tb_npu_dma_channel_mover` | Both directions, HBM/SRAM stalls, tag metadata, error drain, completion backpressure; lint, synthesis, 1 GHz STA |
| `npu_dma_command_queue.sv`, `npu_dma_engine.sv` | `tb_npu_dma_engine` | Sixteen channels, four contexts per channel, five-lane issue, completion routing, quiesce, high-watermark; lint and synthesis |
| `npu_dma_hbm_egress.sv`, `npu_dma_hbm_request_slot.sv` | `tb_npu_dma_hbm_egress` | Sixteen-to-five arbitration, QoS, age promotion, refill, lane backpressure, stable payload, no loss; lint, synthesis, 1 GHz STA |
| `npu_dma_hbm_response_router.sv`, `npu_dma_hbm_response_channel.sv` | `tb_npu_dma_hbm_response_router` | Five-to-sixteen routing, same-channel collision, per-channel order, malformed partition, backpressure, no loss/duplication; lint, synthesis, 1 GHz STA |
| `npu_dma_hbm_tag_tracker.sv` | `tb_npu_dma_hbm_tag_tracker` | Exhaustive 4096-tag fill/drain, same-cycle reuse, duplicate/unknown events, randomized bitmap; lint, synthesis, 1 GHz STA |
| `npu_dma_local_tag_allocator.sv`, `npu_dma_priority_encoder256.sv` | `tb_npu_dma_local_tag_allocator` | Exhaustive claim/release, full pool, turnover, unknown release, randomized free bitmap; lint, synthesis, 1 GHz STA |
| `npu_dma_hbm_status_monitor.sv` | `tb_npu_dma_hbm_status_monitor` | All four statuses on sixteen inputs, sticky diagnostics, randomized accumulation, reset/drain; lint, synthesis, 1 GHz STA |
| `npu_dma_hbm_boundary.sv` | `tb_npu_dma_hbm_boundary` | 1536 mixed beats, allocation-to-retirement lifetime, all statuses, independent request/response stalls, quiesce/drain/resume; lint, synthesis, 1 GHz STA |
| `npu_dma_hbm_control_buffer.sv`, `npu_dma_hbm_wide_control_buffer.sv`, `npu_dma_carry_select_block.sv`, `npu_dma_carry_select_adder.sv`, `npu_dma_hbm_rank_count16.sv` | Egress, router, tracker, boundary, address-generator, and monitor tests | Elaboration in every owning datapath, stable-control behavior under backpressure, lint, mapped synthesis, and owning-top STA |
| `npu_pod_shared_sram.sv`, `npu_round_robin_arbiter16.sv` | `tb_npu_pod_shared_sram` | Read/write conflicts, fairness progress, read-before-write, response stalls, malformed request, counters, clear/reset, exact 256-Macro synthesis |
| `npu_dma_pod.sv` | `tb_npu_dma_pod` | 128-beat HBM-to-SRAM and SRAM-to-HBM round trip, five-lane activity, conflicts, independent stalls, quiesce/drain, exact 256-Macro synthesis |
| `kd28_npu_sram_adapter.sv` | `tb_npu_kd28_sram_adapter`, `tb_sram_macro_contract` | Fixed TDP widths, banked SDP mapping, one-cycle contract, no residual inferred memory, fixed-Macro link |

The `kd28_npu_sram_models.f` functional list and `kd28_npu_sram_blackboxes.f` synthesis list are separately
elaborated by `make kd28-sram-fifo`; compiling both lists together is prohibited.

## 3. Static Timing Coverage

The mapped Nangate45 pre-layout gate constrains these production tops at 1.000 ns: request egress, response
router, tag tracker, tag allocator, status monitor, integrated HBM boundary, address generator, and channel
mover. Every top must report non-negative setup slack and zero max-slew, max-capacitance, and max-fanout
violations. The KD28 synthetic gate separately covers SRAM, FIFO-mapped SRAM, and the NPU SRAM adapter at
fast, typical, and slow corners.

These results are `GENERIC_SYNTH` or synthetic-model evidence. They are not physical KD28 standard-cell,
licensed SRAM compiler, clock-tree, routing, IR-drop, or post-layout signoff evidence.

## 4. Pull-Request Acceptance

A pull request is admissible only when:

1. the five commands in Section 1 pass from a clean checkout;
2. the repository path scan finds no workstation path, generated artifact, or untracked source dependency;
3. NPU-017 through NPU-027 remain consistent with the RTL and owning specifications;
4. every changed RTL file appears in the module matrix above or is explicitly excluded with rationale; and
5. the PR records tool versions, the tested commit, and any evidence limitation.
