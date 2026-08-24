# KD28 FIFO Wrappers

The KD28 FIFO package contains ready/valid wrappers whose storage is tiled onto fixed KD28 SDP SRAM cells.

| Module | Clocking | Capacity rule |
| --- | --- | --- |
| `kd28_sync_fifo` | one clock | any `DEPTH` from 2 through 65536 |
| `kd28_async_fifo` | independent write/read clocks | power-of-two `DEPTH` from 4 through 65536 |

`DATA_WIDTH` must be a positive multiple of eight because the backing SRAM uses byte write masks. Both
wrappers provide a registered output that remains stable during downstream backpressure. The
asynchronous wrapper synchronizes Gray-coded pointers with two flip-flops; it never synchronizes payload
bits directly. Integrators must synchronize deassertion of each active-low asynchronous reset before it
reaches the wrapper. Both domains must participate in the same FIFO reset event; independent one-sided
runtime reset is outside this wrapper contract.

The storage mapper selects the fixed macro class from logical depth:

| Logical depth | Fixed macro class |
| --- | --- |
| 2 through 256 | `KD28_SRAM_SDP_256X32` |
| 257 through 512 | `KD28_SRAM_SDP_512X64` |
| 513 through 1024 | `KD28_SRAM_SDP_1024X128` |
| 1025 through 65536 | `KD28_SRAM_SDP_2048X256`, banked above 2048 |

Logical words wider than the selected macro are tiled across width lanes. The final width lane and final
depth bank may contain unused physical bits or words; FIFO control still exposes exactly the configured
logical capacity.

Compile [`kd28_fifo.f`](kd28_fifo.f) for functional simulation. Compile
[`kd28_fifo_blackboxes.f`](kd28_fifo_blackboxes.f) for synthesis or STA mapping. Both lists include the
same mapper and FIFO control RTL but select functional fixed cells or fixed black boxes respectively.
