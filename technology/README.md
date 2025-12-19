# HBM and SerDes Interface STA Validation

This directory owns the executable OpenSTA validation for the synthetic interface Liberty views under
`Library/timing/interfaces/`. It does not contain foundry or vendor implementation collateral.

Run from the repository root:

```bash
make sta-interfaces
```

The target first checks every `profiles.yaml` setup, hold, and clock-to-output value against the matching
Liberty cell and pin. It then parses, links, constrains, and reports fast, typical, and slow scenarios with
OpenSTA. Expected signatures are `[PROFILE_LIBERTY PASS]` and one `[STA_INTERFACE PASS]` per scenario.

Generated reports are:

| Output | Purpose |
| --- | --- |
| `technology/work/interface_sta/opensta_fast.log` | Synthetic fast max/min paths |
| `technology/work/interface_sta/opensta_typical.log` | Synthetic typical max/min paths |
| `technology/work/interface_sta/opensta_slow.log` | Synthetic slow max/min paths |

The next integration step is to replace these abstractions with legally obtained controller, PHY, or
transceiver Liberty and a design-specific SDC. A pass here is front-end plumbing evidence only.
