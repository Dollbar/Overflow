# NPU System RTL Verification

This directory owns self-checking RTL tests for NPU integration blocks outside the frozen Tensor/Vector
compute leaf. Production sources remain under `rtl/npu/`; this tree contains testbenches and generated
build output only.

Run the current DMA HBM egress lint and simulation gate from the repository root:

```sh
make npu-system-test
```

The gate performs zero-warning Verilator lint, a Yosys synthesizable-process/readiness check, and a test
that drives all sixteen DMA channels and checks five-beat-per-cycle request issue, random independent HBM
lane backpressure, stalled-payload stability, tag/data scoreboarding, simultaneous retire/refill, QoS age
promotion, counters, and reset-visible empty state. Passing evidence is `RTL_SIM`, not controller bandwidth
or physical timing closure.
