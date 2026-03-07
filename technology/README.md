# Portable Synthetic STA Validation

This directory owns executable OpenSTA validation for synthetic interface Liberty under
`Library/timing/interfaces/` and synthetic KD28 SRAM Liberty under `Library/timing/kd28/`. It does not
contain foundry or vendor implementation collateral.

Run from the repository root:

```bash
make sta-interfaces
make sta-kd28
```

The target first checks every `profiles.yaml` setup, hold, and clock-to-output value against the matching
Liberty cell and pin. It then parses, links, constrains, and reports fast, typical, and slow scenarios with
OpenSTA. KD28 additionally verifies all fixed macro names, generated source views, and controlled
checksums. Expected signatures include `[PROFILE_LIBERTY PASS]`, `[KD28_PROFILE PASS]`,
`[STA_INTERFACE PASS]`, `[STA_KD28 PASS]`, and `[STA_NPU_KD28_SRAM PASS]`.

Generated reports are:

| Output | Purpose |
| --- | --- |
| `technology/work/interface_sta/opensta_fast.log` | Synthetic fast max/min paths |
| `technology/work/interface_sta/opensta_typical.log` | Synthetic typical max/min paths |
| `technology/work/interface_sta/opensta_slow.log` | Synthetic slow max/min paths |
| `technology/work/kd28_sta/opensta_fast.log` | KD28 synthetic fast max/min paths |
| `technology/work/kd28_sta/opensta_typical.log` | KD28 synthetic typical max/min paths |
| `technology/work/kd28_sta/opensta_slow.log` | KD28 synthetic slow max/min paths |
| `technology/work/kd28_sta/opensta_fifo_fast.log` | FIFO-mapped SDP macros with independent write/read clocks at fast corner |
| `technology/work/kd28_sta/opensta_fifo_typical.log` | FIFO-mapped SDP macros with independent write/read clocks at typical corner |
| `technology/work/kd28_sta/opensta_fifo_slow.log` | FIFO-mapped SDP macros with independent write/read clocks at slow corner |
| `technology/work/kd28_sta/opensta_npu_sram_fast.log` | Representative NPU local SRAM mapping at the fast corner |
| `technology/work/kd28_sta/opensta_npu_sram_typical.log` | Representative NPU local SRAM mapping at the typical corner |
| `technology/work/kd28_sta/opensta_npu_sram_slow.log` | Representative NPU local SRAM mapping at the slow corner |

The next integration step is to replace these abstractions with legally obtained controller, PHY,
transceiver, or SRAM compiler Liberty and a design-specific SDC. A pass here is front-end plumbing
evidence only.

`kd28/constraints/kd28_async_fifo_cdc.sdc` is an integration template for a synthesized asynchronous
FIFO. It marks the clocks asynchronous while allowing explicitly bounded Gray-pointer paths, limits their
datapath delay, and applies bus skew when the STA tool supports that command. Consumers must confirm
post-synthesis register names and replace example clock periods before timing signoff. Full FIFO control-logic
STA additionally requires a selected KD28 standard-cell Liberty; the current FIFO OpenSTA smoke covers the
fixed SRAM storage boundary only.
