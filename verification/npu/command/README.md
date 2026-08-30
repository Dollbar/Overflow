# NPU Command Verification

Run `make test` here or `make npu-command-test` at repository root. The gate performs zero-warning
Verilator lint, Yosys synthesis-readiness using parser facades checked against the production ABI, and a
self-checking RTL simulation.

The regression covers Task/local/DMA routing, selected-leaf command backpressure, malformed Pod rejection,
output stability, simultaneous completion arbitration, round-robin progress, counters, reset state, and
sticky diagnostics. `pkg/` contains record constructors; `vip/` contains reusable decoded-command source
and unified-completion sink monitors.

The Yosys frontend cannot parse the production scheduler's cross-package struct types. Files under
`models/` reproduce only the frozen packed type layout for synthesis parsing. Production-package Verilator
lint and static `$bits` assertions guard the facade widths; simulation never uses the facades.
