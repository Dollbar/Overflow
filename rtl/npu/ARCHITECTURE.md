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
    pod_noc_router
  interpod_mesh           # proposed 2 x 4
  memory_adapter          # boundary with rtl/memory
  kdlink_adapter          # boundary with rtl/kdlink
  completion_telemetry
```

One NPU contains eight proposed pods and two tensor tiles per pod. Sixteen 256 x 256 arrays provide
1,048,576 MXFP4-by-MXFP8 MAC/cycle. With two operations per MAC and the declared 1 GHz logical tensor
clock, the peak is 2.097152 PFLOPS-equivalent (`ANALYTICAL`).

## 2. Decision Classification

| Item | State | Authority |
| --- | --- | --- |
| Tensor array geometry: 256 x 256 | BASELINED | ADR-0001 |
| Tensor logical clock: 1 GHz | BASELINED assumption | ADR-0001 |
| One MX-only square-GEMM array and sixteen Vector channels | VERIFIED in v0.2 scope | NPU core contract; NPU-007..015 |
| Local Tensor/Vector registered SRAM replacement boundary | VERIFIED in v0.2 scope | NPU core contract; NPU-009 and NPU-014 |
| 16 tensor tiles and 8 pods | PROPOSED | NPU P0 sizing proposal |
| MXFP4 x MXFP8 peak: 2.097152 PFLOPS-equivalent | ANALYTICAL | checked calculator |
| 2 x 4 inter-pod mesh | PROPOSED | NPU P0 sizing proposal |
| NoC logical clock and port widths | PROPOSED | NPU P0 sizing proposal |
| KD-ISA and software ABI fields | EXTERNAL / HOLD | external ISA and software-owner specifications |
| Decoded-command, DMA, address, and internal error fields | HOLD | missing NPU consuming-interface specifications |
| FP8 and BF16 tensor issue rates | HOLD | missing multiplier-sharing decision |
| Reset and CDC protocol | HOLD | missing clock/reset interface specification |

`BASELINED assumption` means downstream analytical work may rely on the value. It does not claim
`RTL_SIM`, `GENERIC_SYNTH`, or implementation timing closure.

The verified v0.2 compute boundary accepts descriptors and data already resident in local SRAM. It does
not promote the proposed pod count, shared-SRAM organization, DMA, NoC, or external command fields to an
implementation contract. Follow the gated sequence in
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
NoC is proposed at 2 GHz. Any boundary crossing requires an explicit CDC mechanism from `rtl/common/` and
CDC evidence. Decoded-command, memory, KDLink, and reset clock relationships remain `HOLD` until
specified.

Internal implementation signals may evolve within a work package. Signals consumed outside `rtl/npu/`
must first be defined in the owning `specs/` document, including width, ordering, backpressure, reset,
error, and compatibility behavior.

## 5. Integration Sequence

1. Freeze numerical semantics and NPU-local parameter types.
2. Implement independently testable tensor, vector, SRAM, and router leaf blocks.
3. Integrate one pod with DMA and scheduling behavioral stubs.
4. Integrate the eight-pod mesh and memory/KDLink adapters.
5. Add cycle counters and saturation tests before making sustained-throughput claims.

See [Work Breakdown](WORK_BREAKDOWN.md) for assignable task IDs and acceptance gates.
