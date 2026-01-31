# Reusable Timing Views

This directory contains redistributable, repository-authored timing abstractions that accompany reusable
models. The values are synthetic front-end assumptions unless a selected vendor and process explicitly
provide characterized replacements.

| Path | Scope |
| --- | --- |
| [`interfaces/`](interfaces/) | HBM and SerDes scalar boundary cells, parameter scenarios, blackboxes, and SDC template |
| [`kd28/`](kd28/) | KD28 SRAM fixed-cell synthetic Liberty and mapping views |

Physical HBM controller/PHY, SerDes macro, and SRAM compiler libraries remain external licensed inputs.
Do not use these views for PVT, Fmax, area, power, signal-integrity, or signoff claims.
