# NPU Compute Integration Verification

This directory contains the reusable integration verification environment for the split NPU compute RTL
under `rtl/npu/{common,tensor,vector,scheduler,sram,compute}`. It keeps
simulation-only code out of production RTL and uses Verilator as the mandatory default simulator.

## Layout

| Path | Contents |
| --- | --- |
| `pkg/` | Shared test constants, types, and default descriptor construction |
| `vip/` | Reusable descriptor source and ready/valid result sink modules |
| `models/` | Deterministic Python references and verification-only SRAM behavior |
| `tb/` | Deterministic self-checking SystemVerilog regressions |
| `waves/` | GTKWave save files for directed waveform inspection |
| `STA/` | TSMC28 SSG synthesis, SDC, and OpenSTA timing scripts |
| `build/` | Generated binaries, vectors, logs, and VCD files; ignored by Git |

Production synthesis must use `rtl/npu/sram/sram_macro_blackbox.sv` or the exact selected macro
adapter. `models/sram_macro_model.sv` intentionally shares the macro module names and therefore replaces,
rather than accompanies, the black-box declarations in simulation source lists.

## Commands

```bash
make help
make lint
make sim
make sim-peak
make sta
make test
make waves
make view-waves WAVE=descriptor_path
```

Tools are resolved from `PATH` by default and remain overridable by command
name. Foundry libraries have no repository default; pass the exact Liberty
view from the caller's environment when running synthesis or STA:

```bash
make lint VERILATOR=verilator JOBS=8
make test LIBERTY_SSG="$LIBERTY_SSG" JOBS=8
```

No checked-in Makefile, Tcl script, Python script, or SDC file contains a
developer-home, hostname, server, PDK-root, or tool-installation path. All
project-owned inputs and generated outputs resolve below this repository;
external executables use `PATH`, and the proprietary Liberty input is an
explicit caller-supplied dependency.

`make test` runs zero-warning SystemVerilog lint, deterministic Python reference
generation, every self-checking RTL test, and the SSG 1 GHz PE and external
MX formatter setup-timing
gate. Any compiler warning, assertion, scoreboard mismatch, timeout,
numerical-contract failure, missing PASS path, or negative timing slack returns
a nonzero status. `make waves` reruns the directed tests with tracing and writes
VCD files below `build/waves/`.

The lint gate is deliberately hierarchical. `lint-system` checks a 2x2 system
with a verification-only Tile interface model so all west-to-east and
north-to-south connections elaborate without flattening four complete Tiles
into one process. Separate zero-warning targets elaborate the production PE,
the full 256-PE Tile, MX Tile paths, and the K=4096 environment. The interface
model is never used for production simulation, synthesis, or STA.

The full `ARRAY_DIM=16` regression uses Verilator library creation to compile
the production `TILE_FP8_16_FIFO` once, then instantiates that fixed-parameter
model at all 256 Tile locations. This avoids flattening 65,536 PE instances in
the host compiler while preserving the production Tile RTL. The verification
adapter fixes `DAZ=0`, `FTZ=0`, and runtime coordinates; its control file waives
only the deliberate filename mismatch and conservative DPI-boundary
`UNOPTFLAT` reports. Production direct-link Tile RTL remains independently
gated by zero-warning `-Wall` lint.

`make sta` maps both `PE_FP8` and the complete 16-channel
`npu_post_output_formatter16` to the TSMC28 HPC+ SSG 0.72 V/125 C NLDM library
and requires nonnegative setup slack at a 1.000 ns clock, 30 ps uncertainty,
50 ps input/output delay, and 0.005 pF output load. Functional-mode STA fixes
`rst_i`/`clear_i` inactive; RTL regressions cover their assertion and recovery.
This is pre-layout mapped-netlist evidence, not CTS/parasitic/physical signoff.

## Regression Map

| Test | Primary coverage | Evidence |
| --- | --- | --- |
| `tb_descriptor_path` | Slot write/submit atomicity, hold, reuse, protocol error, clear/reset | `RTL_SIM` |
| `tb_npu_input_scheduler` | Dependencies, tag allocation, command fanout, no-bubble issue, completion, and independent-Vector descriptor propagation across 13 operations x 4 B-operand sources x 2 result routes (104 combinations) | `RTL_SIM` |
| `tb_vector_engine16` | Seven pipelines, tag matching, mixed latency, collision FIFO, backpressure | `RTL_SIM` |
| `tb_sram_macro_contract` | 32x32/64/128 dual-port registered-read replacement contract | `RTL_SIM` |
| `tb_mxfp_numeric`, `tb_mxfp_block_convert`, `tb_mxfp_quantize_block32` | MXFP4 E2M1 and MXFP8 E4M3FN, boundary values, exact reduction, paired quantization | `RTL_SIM` |
| `tb_npu_post_output_formatter16` | Both v0.2 MX formats, atomic scale/format metadata, full 16-lane 256-element/cycle no-bubble output | `RTL_SIM` |
| `tb_npu_gemm_vector_coupler16_peak` | Full 16-channel Vector result transport, atomic MX scale, 256-element/cycle no-bubble output | `RTL_SIM` |
| `tb_npu_independent_vector_path` | Version-3 Vector-only issue, Tile-K-major Activation SRAM reads, real Vector PASS arithmetic, per-lane backpressure, tail masks, and completion; combined with the scheduler matrix and all-operation Vector-engine numeric test for compositional closure | `RTL_SIM` |
| `tb_npu_activation_read_fairness` | Continuous GEMM/Vector contention, alternating SRAM grants, response ownership, and uncontended GEMM throughput | `RTL_SIM` |
| `tb_npu_gemm_feedback_writer16` | Full 16-channel E4M3/FP4 writes, direct and Vector feedback routes, no-bubble ingress and bank drain | `RTL_SIM` |
| `tb_mxfp_k_accumulator` | 70-bit block input, 85-bit cross-K accumulation, final-only rounding, maximum `2^20` products | `RTL_SIM` |
| `tb_pe_mx_exact` | MXFP4/MXFP8 exact-product payload, forwarding, clear, and one-product-per-cycle burst; confirms no PE-local accumulator | `RTL_SIM` |
| `tb_tile_mx_gemm_path` | Real 16x16 PE Tile with double banks and Tile reduction: continuous/gapped traffic, backpressure, clear/reset recovery | `RTL_SIM` |
| `tb_tile_mx_gemm_k4096` | Three complete `K=4096` Tile tasks and 768 FP32 checks | `RTL_SIM` |
| `tb_gemm_array16_peak` | Fixed-origin full 256-Tile/65,536-PE array, 65,536 values, 256-FP32-per-cycle peak | `RTL_SIM` |
| `tb_gemm_buffer_stream_peak` | 8 MiB A/B stores, real buffer-to-executor reads, K=256 fast, every-other-cycle Activation-stall, and K=4096 long runs; A/W pairing and full-array numeric results | `RTL_SIM` |
| `tb_npu_heterogeneous_k8192` | Parameterized K=8192 external/feedback stream: short 8 MiB run plus 256-task 1 GiB run with 2,097,152 dense cycles, 536,870,912 A/B lane pairs, and 524,288 beats on each result route; cycle- and lane-bubble assertions cover every active burst | `RTL_SIM` |
| `tb_gemm_boundary_skew` | Continuous, gapped, and single input plus in-flight clear/reset and recovery with compact VCD | `RTL_SIM` |
| `sta-pe-ssg` | TSMC28 SSG mapped PE pre-layout setup closure at 1.000 ns | `GENERIC_SYNTH` |
| `sta-output-ssg` | Complete 16-channel external MX formatter: +0.0094 ns worst setup slack, 0.99 ns minimum period, 1009.49 MHz derived Fmax | `GENERIC_SYNTH` |
| Python references | FP32/FP8 conversion and vector approximation error contracts | `FUNCTIONAL_SIM` |

The environment closes the complete 16-by-16 Tile array numerically for both
dense direct injection and the local-buffer/executor path, and gates the
representative PE and the complete external MX formatter at SSG 1 GHz. The
K=8192 and 1 GiB system regressions are compositional: production transport/control and
buffer paths are used, while GEMM and Vector arithmetic are independently
covered by real-module regressions and replaced by verification models in this
resource-bounded long run. It does not
claim array physical timing, CTS/parasitic closure, CDC, physical SRAM signoff,
or end-to-end model accuracy.
