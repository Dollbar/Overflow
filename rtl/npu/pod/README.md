# NPU Compute Pod

This directory owns Pod-local integration logic under ADR-0004. One production Pod contains two
`npu_square_gemm_system` compute clusters, one sixteen-channel DMA engine, one 16 MiB shared SRAM, two
shared-to-private loaders, and one local scheduler/scoreboard. The HBM controller, HBM PHY, NoC router,
KD-ISA decoder, and runtime completion queue are outside this directory or remain held by their owning
contracts.

## Current RTL

| Module | Role | Evidence |
| --- | --- | --- |
| `npu_pod_pkg.sv` | Frozen 2 by 4 organization constants and local-transfer types | lint + package consumers |
| `npu_pod_scoreboard.sv` | Two-cluster allocation, stable dispatch, retirement, and completion buffering | `RTL_SIM` |
| `npu_pod_local_loader.sv` | One shared-SRAM data/scale pair to current Tensor or Vector 128-bit write ports | `RTL_SIM` |
| `npu_pod_sram_read_mux.sv` | Fair DMA/loader sharing of one SRAM read client with response ownership | `RTL_SIM` |
| `npu_compute_pod.sv` | Complete two-cluster, DMA, shared-SRAM, loader, task, result, and HBM integration | `RTL_SIM` |
| `npu_managed_compute_pod.sv` | Decoded command and unified-completion production wrapper around one raw Pod | `RTL_SIM` |
| `npu_pod_noc_pkg.sv` | Frozen Pod/NoC v0.1 widths and packed-flit geometry | lint + package consumers |
| `npu_pod_noc_link_slice.sv` | Packet-aware one-entry elastic boundary and endpoint protocol checks | `RTL_SIM` |
| `npu_pod_noc_attachment.sv` | Router-independent full-duplex control and dual-data-lane handoff | `RTL_SIM` |

The loader is a bring-up compatibility path. Its maximum local write rate is 16 bytes/cycle per compute
cluster, while the shared SRAM beat is 128 bytes and the five HBM lanes provide up to 640 raw bytes/cycle.
The production path therefore needs a wider bank-write interface and double buffering after the current
end-to-end Pod wrapper is functional.

## Integration Status

The single-clock Pod v0.1 wrapper is complete. DMA clients zero and one share their read slots with the two
loaders; all DMA writes and the remaining reads stay direct. ADR-0005 now provides a separately verified
logical attachment for the NoC team. It is intentionally not wired to DMA or SRAM because cross-Pod mover
payload semantics remain unapproved. Router, VC, credit, routing, and NoC CDC remain external. Eight-Pod
replication and per-Pod attachment wiring are implemented structurally by `rtl/npu/npu_2x4_pod_array.sv`;
that shell does not claim router or congestion closure.
