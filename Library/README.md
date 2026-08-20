# Reusable Model Library

`Library/` is the repository-level source of truth for reusable behavioral models. Assets here may be
consumed by multiple simulators or verification environments without copying their source.

## Layout

| Path | Content |
| --- | --- |
| [`models/`](models/) | Executable HBM and KDLink digital SerDes models |

Tests, testbenches, tool adapters, generated outputs, and scenario configuration remain with their
consumer under `simulator/` or `verification/`. Restricted foundry and vendor collateral must not be
copied here.

Asset licensing follows [`LICENSES/README.md`](../LICENSES/README.md). Third-party assets require
provenance, license, version, and checksum records before admission.
