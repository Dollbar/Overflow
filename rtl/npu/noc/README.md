# NPU On-Chip Network RTL

This directory implements the accepted ADR-0008 NoC baseline: eight Routers in a deterministic 2 by 4
Mesh, one independent control fabric, two independent data-lane fabrics, per-input-VC buffering, cardinal
credits, packet-locked round-robin/age arbitration, diagnostics, telemetry, and a complete Pod-clock CDC
wrapper. Adaptive routing and remote DMA/SRAM payload semantics remain outside this contract.

| Module | Role |
| --- | --- |
| `npu_noc_pkg.sv` | Geometry, port, lane, VC, depth, packet, and packed-width constants |
| `npu_noc_vc_fifo.sv` | Exact-depth synchronous per-input-VC FIFO |
| `npu_noc_lane_router.sv` | Five-port deterministic XY Router Leaf for one physical lane |
| `npu_noc_fabric_mesh.sv` | Eight-Router cardinal-link Mesh for one control or data fabric |
| `npu_noc_mesh.sv` | One control plus two independent data fabrics at one NoC clock |
| `npu_noc_async_fifo.sv` | Exact-depth Gray-pointer ready/valid asynchronous FIFO |
| `npu_noc_reset_sync.sv` | Asynchronous-assert, synchronous-release reset helper |
| `npu_noc_level_sync.sv` | Single-level synchronizer used only for CDC coordination |
| `npu_noc_pod_cdc.sv` | One Pod's bidirectional control/data CDC bridges |
| `npu_noc_cdc_mesh.sv` | Eight independent Pod clock domains connected to the NoC Mesh |

The Pod boundary remains the ADR-0005 ready/valid interface: a 128-bit control payload and two 1,024-bit
data payload lanes in each direction. Credits and VC identity terminate inside this directory. Control
flits are padded from 158 to 160 bits and data flits from 1,166 to 1,176 bits only while stored in the CDC
FIFOs; padding is forced to zero and never changes the external packed flit.

Verification is owned by `verification/npu/noc`. The portable closure command is
`make npu-noc-closure`. The proposed 2 GHz clock and its 256 GB/s/lane calculation remain `ANALYTICAL`;
generic synthesis and cycle-level throughput tests do not claim physical timing closure.
