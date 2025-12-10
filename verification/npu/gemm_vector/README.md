# GEMM/Vector Core Verification

This directory contains the reusable verification environment for `rtl/npu/gemm_vector`. It keeps
simulation-only code out of production RTL and uses Verilator as the mandatory default simulator.

## Layout

| Path | Contents |
| --- | --- |
| `pkg/` | Shared test constants, types, and default descriptor construction |
| `vip/` | Reusable descriptor source and ready/valid result sink modules |
| `models/` | Deterministic Python references and verification-only SRAM behavior |
| `tb/` | Deterministic self-checking SystemVerilog regressions |
| `waves/` | GTKWave save files for directed waveform inspection |
| `build/` | Generated binaries, vectors, logs, and VCD files; ignored by Git |

Production synthesis must use `rtl/npu/gemm_vector/sram_macro_blackbox.sv` or the exact selected macro
adapter. `models/sram_macro_model.sv` intentionally shares the macro module names and therefore replaces,
rather than accompanies, the black-box declarations in simulation source lists.

## Commands

```bash
make help
make lint
make sim
make test
make waves
make view-waves WAVE=descriptor_path
```

Tool locations are overridable, for example:

```bash
make test VERILATOR=/opt/verilator/bin/verilator PYTHON=/usr/bin/python3 JOBS=8
```

`make test` runs zero-warning SystemVerilog lint, deterministic Python reference generation, and every
self-checking RTL test. Any compiler warning, assertion, scoreboard mismatch, timeout, numerical-contract
failure, or missing PASS path returns a nonzero status. `make waves` reruns the same tests with tracing and
writes VCD files below `build/waves/`.

## Regression Map

| Test | Primary coverage | Evidence |
| --- | --- | --- |
| `tb_descriptor_path` | Slot write/submit atomicity, hold, reuse, protocol error, clear/reset | `RTL_SIM` |
| `tb_npu_input_scheduler` | Dependencies, tag allocation, command fanout, no-bubble issue, completion | `RTL_SIM` |
| `tb_vector_engine16` | Seven pipelines, tag matching, mixed latency, collision FIFO, backpressure | `RTL_SIM` |
| `tb_sram_macro_contract` | 32x32/64/128 dual-port registered-read replacement contract | `RTL_SIM` |
| Python references | FP32/FP8 conversion and vector approximation error contracts | `FUNCTIONAL_SIM` |

The environment is module and path focused. It does not claim full 16-by-16 array numerical closure,
generic synthesis, foundry timing, physical SRAM signoff, or end-to-end model accuracy.
