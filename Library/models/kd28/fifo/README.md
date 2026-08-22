# KD28 FIFO Wrappers

The KD28 FIFO package contains ready/valid wrappers over the generic KD28 SDP SRAM model.

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

Compile [`kd28_fifo.f`](kd28_fifo.f) from the repository root after selecting the behavioral SRAM source
list. Exact fixed-macro replacement is a synthesis/integration operation and is not implied by an arbitrary
parameter combination.
