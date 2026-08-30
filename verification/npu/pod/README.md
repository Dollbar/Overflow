# NPU Pod Verification

## Reproduction Requirements

The Pod regression has no workstation-specific path and needs no proprietary PDK or Liberty file. Tools
are resolved from `PATH` and may be overridden through the Make variables `VERILATOR`,
`VERILATOR_COVERAGE`, `YOSYS`, and `PYTHON`. Run this first after cloning or forking:

```bash
make -C verification/npu/pod preflight
```

The checked configuration uses GNU Make 4.3, Python 3.12.3, Verilator 5.050,
Yosys 0.67+post, and GCC/G++ 13.3. Python 3.9 or newer is required by the coverage checker. A first
`make npu-pod-closure` build should have at least 24 GiB RAM and 10 GiB free disk; the real one-Pod lint
has measured approximately 19.8 GiB peak memory. Reduce `JOBS` if the host has limited parallel build
capacity. Generated binaries, coverage databases, reports, and Python bytecode remain below ignored
`build/` or `__pycache__/` paths.

Run `make test` in this directory, or `make npu-pod-test` at the repository root. The target performs
zero-warning Verilator lint, Yosys synthesis-readiness checks, and self-checking simulations for the Pod
scoreboard, shared-to-private loader, managed Pod, fixed 2-by-4 array, and router-independent NoC
attachment.

Use `make closure` here, or `make npu-pod-closure` at the repository root, for the release-strength Pod
gate. It adds the four-seed array stress run and measured code-coverage gate. The repository-wide
`make npu-owned-rtl-test` invokes this closure target after the compute, DMA/system, and command gates.

The current regression checks round-robin and preferred-cluster allocation, dispatch/completion
backpressure, simultaneous two-cluster retirement, quiesce, Tensor and Vector data/scale mapping,
malformed local-transfer handling, DMA/loader SRAM-read competition, and complete HBM-to-DMA-to-SRAM-to-
compute data movement using lightweight integration models. `lint-full-real` separately elaborates the
real compute, DMA, KD28 shared-SRAM, and Pod hierarchy with a reduced array dimension.

`sim-managed` drives the production decoded-command boundary through Task, malformed-command, DMA/HBM,
shared-SRAM, local-loader, and Vector-local-store paths and checks the unified completion stream.
`lint-array` elaborates all eight real managed-Pod control/DMA hierarchies plus all eight NoC attachments,
with only compute and shared-SRAM storage replaced by the same integration models used by the one-Pod test.
`tb_npu_2x4_pod_array.sv` then runs the production `ARRAY_DIM=16` geometry and concurrently checks all
eight command/completion ports, same-ID HBM partition affinity, independently reusable HBM tags, 48 NoC
attachment flits, both local loaders in every Pod, malformed-command isolation, per-Pod clear/quiesce isolation, global clear recovery,
and no duplicate completion. The reusable array package builds typed traffic; the HBM responder VIP
injects reproducible backpressure and checks partition affinity; generic ready/valid SVA checkers require
payload stability while stalled.

The array test contains an 84-bit functional-coverage bitmap. All per-Pod Task, DMA, two-loader local
transfer, malformed, HBM, and four-direction NoC bins plus clear, quiesce, completion-stall, and HBM-stall bins are mandatory; the test
fails unless the bitmap is all ones. `make sim-array-multiseed` runs four deterministic HBM seeds, and
`ARRAY_SEEDS="..."` overrides that list. The forced HBM-stall window starts only after a real request is
visible, so protocol coverage does not depend on a fortunate random seed.

`make coverage-array` produces line, branch, expression, toggle, FSM, and user coverage data below
`build/coverage/`, writes `coverage-summary.txt`, and applies non-regression gates. The current measured
integration baseline is line 96.1%, branch 56.1%, expression 77.0%, toggle 12.7%, FSM state 100.0%, and
user 25.0%. These
percentages are a top-integration regression baseline, not a claim that every duplicated DMA datapath bit
has toggled. Component DMA, loader, scoreboard, managed-Pod, and NoC tests remain required alongside it.

`tb_npu_pod_noc_attachment.sv` independently verifies the NoC handoff without supplying router behavior.
It covers both data lanes, both directions, output stability under backpressure, packet-aware quiesce,
sticky endpoint diagnostics, and clear recovery. `synth-noc` is the matching Yosys readiness target.
Routing, virtual channels, credit flow, mesh congestion, deadlock proof, and any clock-domain crossing are
outside this directory and remain owned by the NoC/system integration workstream.
