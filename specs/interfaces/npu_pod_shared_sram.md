# NPU Pod-Shared SRAM DMA Client v0.1

Status: baselined NPU-internal contract. The storage implementation uses repository-synthetic KD28 fixed
macros and is not foundry SRAM signoff.

## 1. Scope

This interface connects the sixteen channels of one pod DMA engine to one 16 MiB non-coherent,
software-managed SRAM. It defines only the local full-beat DMA client, arbitration, banking, and reset
validity behavior. Tensor/Vector ownership transitions and cross-pod NoC clients require separate adapters.

## 2. Geometry

| Quantity | v0.1 value |
| --- | ---: |
| Capacity | 16,777,216 bytes |
| DMA clients | 16 |
| DMA beat | 128 bytes |
| Logical beat banks | 8 banks of 16,384 by 1,024 bits |
| Physical data-bank equivalent | 32 banks by 256 bits |
| Read ports per logical bank | 1 |
| Write ports per logical bank | 1 |
| Maximum conflict-free service | 8 reads plus 8 writes per cycle |

Byte address bits `[9:7]` select the logical bank and bits `[23:10]` select its row. This interleaving keeps
consecutive 128-byte beats in different banks and provides enough conflict-free service for all five HBM
lanes in either direction. It replaces the earlier 512-byte-read/256-byte-write study target, which could
not sustain the accepted 625-byte/cycle per-pod HBM service.

Each logical bank maps through `kd28_fifo_sdp_storage_map` to eight depth banks and four 256-bit width tiles,
for 32 `KD28_SRAM_SDP_2048X256` instances. The full 16 MiB array therefore uses exactly 256 fixed macros.

## 3. Client Protocol

Read request, read response, and write request channels use ready/valid. A client may have at most one read
request awaiting response. Read data is returned by client identity and remains stable under response
backpressure. A full-beat write commits on `write_valid && write_ready`.

All addresses are 128-byte aligned and at or below 16,777,088. Every write byte enable is one in v0.1.
Malformed internal requests are producer protocol errors; `protocol_error_o` is a sticky local diagnostic
and is not an ABI status.

## 4. Arbitration and Collision Semantics

Each bank has independent round-robin read and write arbitration across sixteen clients. A successful grant
advances that bank's pointer to the following client. A continuously valid eligible request wins within at
most sixteen arbitration opportunities when its response slot is available.

One read and one write may target the same bank in one cycle. The KD28 SDP read-before-write rule applies
when their complete addresses also match. Two reads or two writes to the same bank serialize through their
respective round-robin arbiters. Different banks progress independently.

## 5. Reset, Clear, and Ownership

Reset and clear remove arbitration, pending-response, and protocol-diagnostic state but do not clear SRAM
contents. The owning pod must quiesce DMA before clear. Visibility between DMA and compute is established by
an explicit software/compiler ownership transition; this block provides no cache coherence or implicit
barrier.

V0.1 provides no SRAM ECC bits because the current fixed KD28 macros expose no characterized ECC storage or
fault injection contract. An ECC revision must add protected width, syndrome behavior, scrub policy, and
completion mapping together rather than inventing client status fields locally.

## 6. Required Evidence

Required evidence includes capacity and exact macro-count checks, all-bank conflict-free saturation,
same-bank sixteen-client fairness, independent read/write traffic, response and request backpressure,
read-before-write collision, address and byte-enable diagnostics, reset/clear validity, zero-warning lint,
black-box synthesis with no inferred main storage, and three-corner KD28 synthetic SRAM timing plumbing.
