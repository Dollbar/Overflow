# KD28 SRAM and FIFO Digital Contract v0.1

Status: versioned reusable-model contract. Evidence from this package is limited to `RTL_SIM`,
`GENERIC_SYNTH`, and synthetic front-end `ANALYTICAL` timing checks.

## 1. Boundary

KD28 is the repository name for a technology-neutral, 28 nm-style SRAM mapping and simulation package.
It is not a foundry PDK, memory-compiler release, or characterized silicon library. The package provides
portable behavioral models, explicit fixed macro names, black-box declarations, synthetic Liberty views,
and FIFO wrappers that use the same synchronous-memory semantics.

Licensed foundry SRAM Verilog, Liberty, LEF, GDS, and characterization reports remain external inputs.
A physical implementation must replace every KD28 synthetic view with one selected compiler release and
record its process, voltage, temperature, license, checksum, and read/write collision semantics.

## 2. SRAM Families

| Family | Ports | Clocks | Read behavior | Intended use |
| --- | --- | --- | --- | --- |
| `KD28_SRAM_SP_*` | one read/write port | one | registered, one cycle | tables and private state |
| `KD28_SRAM_SDP_*` | one write plus one read port | independent | registered in read domain | FIFOs and producer/consumer buffers |
| `KD28_SRAM_TDP_*` | two read/write ports | shared | registered, one cycle | dual-client scratchpad state |

All data widths are byte-addressable. A high write-mask bit updates the corresponding byte. A disabled
port preserves its output. Memory contents are not reset. Consumers that require reset-visible validity
must provide a wrapper-level valid bit.

For SDP, a read and write to the same address on coincident clock edges returns the previous stored word in
the portable model. A selected physical macro may differ and must be adapted explicitly. For TDP, two writes
to the same address in one cycle are outside the contract. A read concurrent with a write to the same address
returns the previous word in the portable model.

## 3. Fixed Mapping Set

The controlled fixed cells are declared in `Library/models/kd28/sram/macros.yaml`. Their names use
`KD28_SRAM_<family>_<depth>X<width>`. Behavioral and black-box source lists are mutually exclusive:

- simulation uses `kd28_sram_models.f`;
- synthesis or STA uses `kd28_sram_blackboxes.f` plus the selected Liberty scenario;
- physical implementation replaces both with licensed macro collateral.

## 4. FIFO Wrappers

`kd28_sync_fifo` uses an SDP instance with one shared clock. `kd28_async_fifo` uses an SDP instance with
independent write and read clocks plus Gray-coded pointers and two-stage pointer synchronizers. Both expose
ready/valid channels and accept `DATA_WIDTH` and `DEPTH` parameters. `DATA_WIDTH` must be a positive
multiple of eight. The synchronous wrapper accepts any `DEPTH` from 2 through 65536 and preserves that
exact logical capacity even when `DEPTH` is not a power of two.

The asynchronous wrapper requires a power-of-two `DEPTH` from 4 through 65536. Reset assertion is
asynchronous in each domain; system integration must synchronize reset deassertion independently for the
write and read domains. Both domains must participate in the same FIFO reset event; independent one-sided
runtime reset is outside the contract. Occupancy is not exported across domains because a single exact
count would itself be an unsafe CDC contract.

## 5. Timing Boundary

The fast, typical, and slow KD28 Liberty files are repository-authored scalar-table assumptions. They
validate cell naming, black-box linking, setup/hold arcs, and clock-to-output plumbing only. They do not
support physical PVT, Fmax, area, leakage, dynamic power, retention, yield, or signoff claims.

## 6. Verification

Run from the repository root:

```bash
make kd28-sram-fifo
make sta-kd28
```

Expected source evidence is `[RTL_SIM PASS] kd28_sram_fifo`. Expected timing evidence is one
`[STA_KD28 PASS]` line for each fast, typical, and slow scenario. The next integration step is to bind a
real SRAM compiler macro set behind the fixed KD28 names and rerun the consumer RTL regressions.
