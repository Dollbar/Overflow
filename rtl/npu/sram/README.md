# NPU Scratchpad RTL

Owns tile-private scratchpad banking and pod-shared scratchpad integration. The P0 sizing proposes 8 MiB
private SRAM per tile and 16 MiB shared SRAM per pod. Storage is explicit, software-managed, and non-coherent.

The current compute path provides separate 8 MiB Tensor-A, Tensor-B, Vector-B, and Vector-C logical stores,
plus declaration-only foundry SRAM replacement boundaries. Behavioral macro storage remains verification-only.

`kd28_npu_sram_adapter.sv` implements those replacement boundaries with fixed KD28 cells. It maps the
32-word accumulator banks directly to matching TDP cells and maps local 1W/1R and feedback storage through
banked/tiled SDP cells. Use `kd28_npu_sram_models.f` for functional simulation and
`kd28_npu_sram_blackboxes.f` for synthesis or synthetic STA; do not compile either list together with
`sram_macro_blackbox.sv`.

The default local 32768x128 logical bank follows the controlled KD28 depth-based policy and maps to sixteen
`KD28_SRAM_SDP_2048X256` cells. This preserves the logical contract but pads the unused upper 128 bits in
each physical word. It is synthetic mapping evidence, not a physical area-efficiency decision.

`npu_pod_shared_sram.sv` implements the baselined 16 MiB pod scratchpad as eight interleaved 1024-bit
logical banks with independent round-robin read and write arbitration for sixteen DMA channels. Each
logical bank maps through `kd28_fifo_sdp_storage_map` to 32 fixed 2048x256 SDP macros, for exactly 256
macros in the complete Pod. Verification covers bank conflicts, read-before-write collision,
backpressure, malformed requests, reset/clear, and exact macro-count synthesis.

Compute-loader, NoC, and KDLink clients remain `HOLD` until their ownership and arbitration contracts are
approved. SRAM ECC also remains held because the repository-synthetic KD28 macros do not expose a
characterized protected width or syndrome interface.
