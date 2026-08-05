# Reusable Model Library

`Library/` is the repository-level source of truth for reusable behavioral models. Assets here may be
consumed by multiple simulators or verification environments without copying their source.

## Layout

| Path | Content |
| --- | --- |
| [`models/`](models/) | Executable HBM, KDLink SerDes, and KD28 SRAM/FIFO models |
| [`timing/`](timing/) | Synthetic interface and KD28 SRAM timing views for portable front-end STA |

Tests, testbenches, tool adapters, generated outputs, and scenario configuration remain with their
consumer under `simulator/`, `verification/`, or `technology/`. Restricted foundry and vendor collateral
must not be copied here.

Asset licensing follows [`docs/management/licensing.md`](../docs/management/licensing.md). Third-party assets require
provenance, license, version, and checksum records before admission.
