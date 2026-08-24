# NPU System RTL Verification

This directory owns self-checking RTL tests for NPU integration blocks outside the frozen Tensor/Vector
compute leaf. Production sources remain under `rtl/npu/`; this tree contains testbenches and generated
build output only.

Run the DMA HBM request/response lint, synthesis-readiness, and simulation gate from the repository root:

```sh
make npu-system-test
```

The request test drives all sixteen DMA channels and checks five-beat-per-cycle issue, random independent
HBM lane backpressure, stalled-payload stability, tag/data scoreboarding, simultaneous retire/refill, QoS
age promotion, counters, and reset-visible empty state. The response test checks five simultaneous
same-channel responses, five-lane acceptance, random independent destination stalls, stable output payload,
per-channel ordering, no loss/duplication, malformed-partition drop, sticky error, counters, and drain.

Run the mapped generic pre-layout STA gate with a readable Liberty path supplied by the caller:

```sh
make npu-system-sta LIBERTY=/path/to/standard_cells.lib
```

No repository target contains a workstation-specific Liberty path. The gate constrains both production
tops at 1.000 ns with 0.030 ns uncertainty, 0.050 ns input/output delays, and 0.005 pF output load. It fails
on setup, max slew, max capacitance, or max fanout violations. Passing evidence is `GENERIC_SYNTH`; it is
not HBM controller bandwidth, post-layout closure, or KD28 foundry signoff.
