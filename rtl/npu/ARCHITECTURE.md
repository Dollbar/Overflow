# NPU RTL Architecture and Allocation Boundary

Status: implementation allocation baseline. Current performance evidence: `ANALYTICAL`.

## 1. Hierarchy

```text
npu_top
  decoded_command_ingress    # consumes external-owner output; no KD-ISA decoder here
  global_scheduler
  pod[0..7]
    pod_scheduler
    tensor_tile[0..1]     # 256 x 256 each
    vector_tile[0..1]
    tile_sram[0..1]
    pod_shared_sram
    dma_frontend
    pod_noc_attachment    # frozen logical handoff; no routing or credits
    pod_noc_router        # separately owned implementation
  interpod_mesh           # baselined 2 x 4 placement; packet/credit RTL held
  memory_adapter          # boundary with rtl/memory
  kdlink_adapter          # boundary with rtl/kdlink
  completion_telemetry
```

One NPU contains eight baselined pods and two tensor tiles per pod under ADR-0004. Sixteen 256 x 256 arrays provide
1,048,576 MXFP4-by-MXFP8 MAC/cycle. With two operations per MAC and the declared 1 GHz logical tensor
clock, the peak is 2.097152 PFLOPS-equivalent (`ANALYTICAL`).

## 2. Decision Classification

| Item | State | Authority |
| --- | --- | --- |
| Tensor array geometry: 256 x 256 | BASELINED | ADR-0001 |
| Tensor logical clock: 1 GHz | BASELINED assumption | ADR-0001 |
| One MX-only square-GEMM array and sixteen Vector channels | VERIFIED in v0.2 scope | NPU core contract; NPU-007..015 |
| Local Tensor/Vector registered SRAM replacement boundary | VERIFIED in v0.2 scope | NPU core contract; NPU-009 and NPU-014 |
| 16 tensor tiles and 8 pods | BASELINED | ADR-0004 |
| MXFP4 x MXFP8 peak: 2.097152 PFLOPS-equivalent | ANALYTICAL | checked calculator |
| 2 x 4 logical Pod placement and HBM affinity | BASELINED | ADR-0004 |
| Pod/NoC synchronous control/data attachment widths | BASELINED | ADR-0005 and Pod/NoC v0.1 contract |
| NoC logical clock, VC, credit, and router behavior | PROPOSED / EXTERNAL | NPU P0 sizing proposal and NoC owner |
| Five 128-byte HBM request/response lanes per pod | BASELINED | ADR-0002 and NPU HBM RTL beat contract |
| KD-ISA and software ABI fields | EXTERNAL / HOLD | external ISA and software-owner specifications |
| NPU-internal decoded command, DMA descriptor, and unified completion | VERIFIED | ADR-0003/0007; NPU-034 |
| KD-ISA decode, IOVA/protection, runtime queue and fault-policy fields | EXTERNAL / HOLD | external ISA, memory-management, and software-owner specifications |
| FP8 and BF16 tensor issue rates | HOLD | missing multiplier-sharing decision |
| Reset and CDC protocol | HOLD | missing clock/reset interface specification |

`BASELINED assumption` means downstream analytical work may rely on the value. It does not claim
`RTL_SIM`, `GENERIC_SYNTH`, or implementation timing closure.

The verified v0.2 compute boundary accepts descriptors and data already resident in local SRAM. ADR-0004
promotes the Pod count, compute-cluster count, and HBM affinity to an implementation contract, while NoC
packet fields, external commands, and production private-SRAM capacity remain held. Follow the gated sequence in
[`NPU System Closure Plan`](../../docs/architecture/npu_system_closure_plan.md).

## 3. Dataflow

Already-decoded commands enter through the NPU sink in `command/`, become dependency-tracked work in
`scheduler/`, and are issued to a pod. KD-ISA decoding and software queues are outside this workstream.
The NPU-side `dma/` front end moves tiles between finite HBM transactions and explicit scratchpad.
Tensor and vector engines consume scratchpad operands and return results to scratchpad. Only DMA, explicit
cross-pod transfers, completion traffic, and KDLink traffic use the pod mesh.

The implementation is non-coherent. Compiler/runtime artifacts own buffer placement and lifetime;
scheduler barriers own producer-consumer visibility. Cache-coherent behavior must not be inferred.

## 4. Clock and Interface Boundary

The tensor clock is a declared logical 1 GHz baseline. Vector and tile SRAM are proposed at 1 GHz; the
NoC is proposed at 2 GHz. ADR-0005 freezes only a synchronous attachment and does not select either clock.
Any boundary crossing requires an explicit CDC mechanism from `rtl/common/` and
CDC evidence. Decoded-command, memory, KDLink, and reset clock relationships remain `HOLD` until
specified.

Internal implementation signals may evolve within a work package. Signals consumed outside `rtl/npu/`
must first be defined in the owning `specs/` document, including width, ordering, backpressure, reset,
error, and compatibility behavior.

## 5. Integration Sequence

1. Freeze numerical semantics and NPU-local parameter types.
2. Implement independently testable tensor, vector, SRAM, and router leaf blocks.
3. Integrate and verify one managed Pod with DMA, shared SRAM, Tensor, Vector, and completion routing.
4. Replicate eight Pods with fixed HBM affinity and router-independent NoC attachments.
5. Let the NoC and system owners integrate router, CDC, memory-controller, KDLink, and runtime adapters
   against the frozen boundaries.
6. Add system saturation evidence before making sustained-throughput claims.

See [Work Breakdown](WORK_BREAKDOWN.md) for assignable task IDs and acceptance gates.
