# Reusable Behavioral Models

This directory contains portable models whose contracts are useful outside one test environment.

| Domain | Stable path | Primary consumers |
| --- | --- | --- |
| HBM | [`hbm/`](hbm/) | `simulator/memory/` |
| KDLink SerDes | [`kdlink/serdes/`](kdlink/serdes/) | `simulator/kdlink/`, protocol specifications |
| KD28 SRAM/FIFO | [`kd28/`](kd28/) | `verification/kd28/`, NPU integration |

Models describe functional or analytical behavior only at the boundary documented beside each asset.
They do not stand in for qualified controller, PHY, analog, foundry, or production macro collateral.
