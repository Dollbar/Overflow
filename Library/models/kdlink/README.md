# KDLink Reusable Models

This directory is the stable source location for KDLink models shared by specifications and simulation.

| Path | Contract |
| --- | --- |
| `serdes/` | Vendor-neutral digital ten-lane channel and full-duplex link models |

The specification tests, SystemVerilog testbenches, test inventory, and runner remain in
`simulator/kdlink/`.
The SerDes models stop at a digital PCS/PMA streaming boundary and make no analog or physical claims.
