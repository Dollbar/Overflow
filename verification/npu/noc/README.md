# NPU NoC verification

This directory owns self-checking verification for the frozen 2x4 NPU NoC
contract. The package creates canonical control/data flits, and the source and
sink VIPs provide reusable ready/valid endpoint behavior.

Run the reproducible local closure gate from the repository root:

```bash
make npu-noc-closure
```

The gate requires Verilator, `verilator_coverage`, Yosys, Python 3, and a C++
compiler. It performs strict RTL/TB lint, an executable Gray-pointer CDC
structure audit, generic structural synthesis, bounded formal proofs, all
self-checking RTL simulations, the independent Python route and bandwidth
model, and merged Router normal/error-path coverage gates.
Generated files remain under `verification/npu/noc/build/` and can be removed
with `make -C verification/npu/noc clean`.

The smaller `make npu-noc-test` command runs every gate except instrumented
coverage. Individual entry points are `npu-noc-lint`, `npu-noc-synth`,
`npu-noc-formal`, `npu-noc-sim`, and `npu-noc-coverage`.

## Regression matrix

| Test | Checked contract |
| --- | --- |
| `tb_npu_noc_vc_fifo.sv` | non-power-of-two depth, full turnover, ordering, clear |
| `tb_npu_noc_lane_router.sv` | all legal output directions, four VCs, credits, arbitration, backpressure, telemetry |
| `tb_npu_noc_router_errors.sv` | invalid route, malformed packet lock, overlength drain, credit overflow recovery |
| `tb_npu_noc_mesh.sv` | all 64 ordered endpoint pairs on control and both data lanes, seven-source incast, lengths 2/31/32, quiesce, backpressure, long-flow and middle-bisection utilization |
| `tb_npu_noc_pod_cdc.sv` | bidirectional ordering, FIFO wrap/full pressure, padding, reset, and 1:1, 1:2, 2:1, unrelated clock ratios |
| `tb_npu_noc_cdc_mesh.sv` | complete eight-Pod CDC plus Mesh composition, bidirectional control/data, stable drain/quiesce |
| `vc_fifo.ys` | bounded FIFO count, pointer, full, and empty invariants |
| `router_invariants.ys` | bounded credit, lock ownership, and grant mutual-exclusion invariants |
| `escape_dependency.ys` | VC0 deterministic-XY distance decrease and horizontal-to-vertical dependency monotonicity |

The measured Router coverage baseline is gated at line 94%, branch 80%,
expression 58%, and toggle 17%. Toggle is intentionally treated as a
regression baseline: wide payload and telemetry bits are not expected to all
toggle in a protocol-directed run. The current local measurement is line
95.2%, branch 83.9%, expression 60.0%, and toggle 18.2%.

Evidence produced here is labelled `RTL_SIM` for Verilator, `FORMAL` for the
bounded SAT suite, `GENERIC_SYNTH` for Yosys structural checks, and `ANALYTICAL`
for the Python model. The cycle-level Mesh test measures 100% active-window
utilization for one maximum-length flow and for all four data lanes across the
middle cut. These results are not process-qualified PPA evidence.
