# NPU NoC verification

This directory owns self-checking verification for the frozen 2x4 NPU NoC
contract. The package creates canonical control/data flits. Reusable source,
sink, passive monitor, and passive protocol-checker VIPs provide ready/valid
endpoint behavior and protocol diagnosis. `npu_noc_vip.f` is the portable VIP
file list; `make npu-noc-vip` runs its self-checking smoke test.

Run the reproducible local closure gate from the repository root:

```bash
make npu-noc-closure
```

The gate requires Verilator, `verilator_coverage`, Yosys, Python 3, and a C++
compiler. It performs strict RTL/TB lint, an executable Gray-pointer CDC
structure audit, generic structural synthesis, bounded formal proofs, all
self-checking RTL simulations, the independent Python route and bandwidth
model, and both Router-focused and full-NoC merged coverage gates.
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
| `tb_npu_noc_vip.sv` | reusable source/sink/monitor/checker integration, stall stability, legal packet accounting, malformed-tail diagnosis |
| `tb_npu_noc_mesh.sv` | all 64 control endpoint pairs, all 512 ordered data pair/lane/VC combinations, seven-source incast, fixed transpose, four deterministic random seeds, lengths 2/31/32, quiesce, backpressure, and full middle-cut utilization |
| `tb_npu_noc_pod_cdc.sv` | bidirectional ordering, FIFO wrap/full pressure, padding, reset, and eight clock-ratio/release-phase cases spanning 1:1, 1:2, 2:1, and unrelated clocks |
| `tb_npu_noc_cdc_mesh.sv` | complete eight-Pod CDC plus Mesh composition with eight distinct Pod clocks, concurrent bidirectional traffic, and the full 576 control/data route matrix |
| `vc_fifo.ys` | depth-eight bounded FIFO count, pointer, full, and empty invariants through 20 steps |
| `async_fifo.ys` | equal-clock formal subset of Gray-pointer, ready/valid, no-underflow, ordering, and data-integrity properties through 24 steps |
| `router_invariants.ys` | four-VC bounded credit, lock ownership, and grant mutual-exclusion invariants through 8 steps |
| `escape_dependency.ys` | VC0 deterministic-XY distance decrease and horizontal-to-vertical dependency monotonicity |

`make npu-noc-formal-deep` extends the four-VC Router proof to 10 steps for a
workstation/nightly run. It is intentionally separate from the portable
release gate because its SAT runtime is substantially larger.

The measured Router coverage baseline is gated at line 94%, branch 80%,
expression 58%, and toggle 17%. The merged full-NoC suite is independently
gated at line 92%, branch 78%, expression 61%, and toggle 38%. Toggle is
intentionally treated as a regression baseline: wide payload and telemetry
bits are not expected to all toggle in a protocol-directed run. The current
local measurements are Router 95.2/83.9/60.0/18.2% and full-NoC
93.3/79.4/63.0/40.8% (line/branch/expression/toggle).

Evidence produced here is labelled `RTL_SIM` for Verilator, `FORMAL` for the
bounded SAT suite, `GENERIC_SYNTH` for Yosys structural checks, and `ANALYTICAL`
for the Python model. The cycle-level Mesh test measures 100% active-window
utilization for one maximum-length flow and for all four data lanes across the
middle cut. These results are not process-qualified PPA evidence.

The requirements-to-evidence inventory and the explicit external signoff
boundary are recorded in `CLOSURE.md`.
