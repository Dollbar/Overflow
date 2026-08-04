# NPU NoC closure inventory

This inventory defines what `make npu-noc-closure` closes and prevents
portable RTL evidence from being mistaken for physical signoff.

| Requirement | Evidence | Closure gate |
| --- | --- | --- |
| 2x4 topology, boundary isolation, deterministic XY | RTL lint, generic structural synthesis, Python topology model | `lint`, `synth`, simulator model |
| Control reachability | all 64 ordered endpoint pairs | `tb_npu_noc_mesh`, `tb_npu_noc_cdc_mesh` |
| Two data lanes and four VCs | all 512 ordered pair/lane/VC combinations | `tb_npu_noc_mesh` |
| Full Pod-clock integration | full 576 route matrix across eight distinct Pod clocks | `tb_npu_noc_cdc_mesh` |
| Backpressure and packet integrity | endpoint stalls, incast, maximum packets, protocol checker | Mesh, Router, CDC, and VIP tests |
| Malformed/error recovery | invalid route, malformed lock, overlength drain, credit overflow | `tb_npu_noc_router_errors` |
| CDC structure and behavior | attributed synchronizers, Gray-pointer audit, eight ratio/phase cases | `cdc-static`, `tb_npu_noc_pod_cdc` |
| FIFO and Router invariants | bounded SAT over depth-eight FIFOs and all four Router VCs (8-step release, optional 10-step deep run) | `formal`, `formal-deep` |
| Escape-VC dependency order | exhaustive combinational proof | `escape_dependency.ys` |
| Reusable verification components | package plus source/sink/monitor/checker file list and smoke test | `npu_noc_vip.f`, `sim-vip` |
| Regression coverage | Router and full-NoC merged metric thresholds | `coverage` |

## Evidence classification

- `RTL_SIM`: cycle-accurate self-checking Verilator regressions.
- `FORMAL`: bounded or exhaustive Yosys SAT properties as identified above.
- `GENERIC_SYNTH`: technology-independent elaboration and structural checks.
- `ANALYTICAL`: Python routing/bandwidth model and nominal throughput math.

## External signoff boundary

The following are deliberately not reported as closed by this portable gate:

- 2 GHz setup/hold closure with a selected standard-cell library and extracted
  interconnect;
- CDC signoff from a commercial structural/metastability tool;
- DFT, UPF/power-intent, IR-drop, EM, and physical congestion closure;
- end-to-end traffic behavior with separately owned consumers beyond the
  frozen Pod ready/valid interface.

Those items require a frozen process, library corners, floorplan, clock/reset
constraints, and owner-level integration environment. Until those inputs and
reports exist, their release status is `HOLD`, not `PASS`.
