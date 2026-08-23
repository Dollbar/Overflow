# KD28 SRAM Model Library

This package provides portable SRAM behavior and a controlled fixed-cell mapping set. The generic models
are synthesizable Verilog-2001 inference templates. Generated fixed wrappers bind the controlled cell names
to those models for simulation; generated black boxes provide the mutually exclusive synthesis/STA view.

## Families

| Family | Semantics |
| --- | --- |
| SP | one synchronous read/write port |
| SDP | one synchronous write port and one independently clocked synchronous read port |
| TDP | two synchronous read/write ports on one shared clock |

Reads are registered. Write-mask bits are active high per byte. Memory contents are not reset. See
[`macros.yaml`](macros.yaml) for the fixed mapping set and
[`specs/interfaces/kd28_sram_fifo_v0.1.md`](../../../../specs/interfaces/kd28_sram_fifo_v0.1.md) for
collision and replacement semantics.

## Source Selection

```text
Simulation: Library/models/kd28/sram/kd28_sram_models.f
Mapping:    Library/models/kd28/sram/kd28_sram_blackboxes.f
```

Do not compile the behavioral fixed cells and black-box declarations together. A real implementation
replaces the black boxes and synthetic KD28 Liberty with one licensed memory-compiler release.
