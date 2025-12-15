# HBM System Model

This package tests the redistributable v0.1 logical HBM model in
[`Library/models/hbm/`](../../Library/models/hbm/). The model covers capacity, bank/row scheduling,
refresh, turnaround, ECC/fault injection, byte enables, transaction latency, per-partition payload
bandwidth, outstanding limits, backpressure, sparse data storage, and read/write completion ordering. It
does not allocate the declared 192 GB address space.

The baseline has eight independent 24 GB decimal partitions. Each partition transfers a combined
read-plus-write budget of 625 payload bytes per 1 ns logical cycle, equivalent to 625 GB/s per partition
and 5 TB/s aggregate under balanced traffic.
The nominal latency is 500 cycles;
[`hbm_v0.1.yaml`](../../Library/models/hbm/hbm_v0.1.yaml) also records the 800-cycle stress override.

Run the self-checking model regression from the repository root:

```bash
make hbm-model
```

This target runs 27 Python cases plus the self-checking SystemVerilog beat BFM with Verilator. The model
is vendor-neutral and is not an HBM controller, PHY, DRAM timing model, JEDEC compliance model,
power model, or evidence that a physical implementation can sustain the declared bandwidth. Vendor VIP
or encrypted controller models remain external dependencies and must be recorded under `third_party/`.
