# NPU Subsystem Architecture Proposal P0

Status: `PROPOSED`, not frozen. Evidence level: `ANALYTICAL`.

This document turns the `OF-5P6T-v0.1` system targets into a reproducible NPU sizing proposal. It is not
an interface specification and must not be treated as measured performance. Widths, clocks, addresses,
and protocol fields become authoritative only after an ADR and the affected `specs/` documents are
approved. The machine-readable source is [`config/npu_arch_proposed.yaml`](../../config/npu_arch_proposed.yaml),
and the calculations are reproduced by [`scripts/analyze_npu_proposal.py`](../../scripts/analyze_npu_proposal.py).

## 1. Workload and Roofline Consequences

For a four-bit weight used once in a matrix operation, one parameter contributes approximately two
operations while consuming 0.5 bytes. The decode weight-stream intensity is therefore approximately
4 op/B before activation, scale, metadata, and padding traffic.

| Quantity | Kimi-K3 reference | OF-5P6T envelope |
| --- | ---: | ---: |
| Active parameters per token | 104 B | 208 B |
| Approximate operations per token | 208 GOP | 416 GOP |
| Four-bit weight bytes per token | 52 GB | 104 GB |
| System compute at 50 token/s | 10.4 TOPS | 20.8 TOPS |
| Per-NPU compute at 32-way ideal sharding | 0.325 TOPS | 0.650 TOPS |
| Per-NPU weight traffic at 50 token/s | 81.25 GB/s | 162.50 GB/s |

The NPU peak balance is 2 PFLOPS-equivalent / 5 TB/s = 400 op/B. A workload must reuse each fetched
four-bit weight approximately 100 times to move from the 4 op/B decode point to that balance point.
Consequently, the 2 PFLOPS-equivalent target is a prefill, batched-decode, or expert-reuse peak. It is not
a prediction that a single decode stream will sustain 2 PFLOPS. Compiler and runtime work should expose
at least 128-token weight-reuse groups when latency and expert routing allow it.

## 2. Physical-Logical Organization

One logical NPU is divided into eight pods arranged as a 2 x 4 mesh. Each pod owns two tensor/vector
tiles, one 24 GB logical HBM partition, one HBM DMA front end, and one KDLink injection/ejection port.
This gives 16 compute tiles, eight HBM partitions, and eight KDLink ports per NPU. The alignment keeps
the dominant HBM-to-compute and expert-to-link paths local to a pod.

```text
NPU: 2 x 4 pod mesh

  [P0]--[P1]--[P2]--[P3]      Each pod:
   |     |     |     |          2 x tensor/vector tile
  [P4]--[P5]--[P6]--[P7]        16 MiB shared SRAM
                                 1 x 24 GB HBM partition + DMA
                                 1 x KDLink port
```

## 3. Tensor Datapath

Each tile contains a 256 x 256 logical systolic array. At one MXFP4-by-MXFP8 MAC per cell per tensor
clock, the 16 tiles provide 1,048,576 MAC/cycle. Counting a MAC as two operations at the fixed 1 GHz
logical tensor clock gives 2.097152 PFLOPS-equivalent, a 4.86 percent margin over the 2 PF target.
Accumulation is FP32. FP8 and BF16 issue rates remain `HOLD` until multiplier sharing and numerical
semantics are specified; they must not be inferred from the MXFP4-by-MXFP8 number.

For every K step, one tile consumes 256 MXFP8 values and 256 MXFP4 values, or 384 B/cycle before scale
metadata. The tile-private SRAM read target is 512 B/cycle, leaving 33.3 percent headroom for scales,
layout effects, and bank conflicts. Tensor operand injection is local SRAM traffic and does not cross
the global pod mesh.

## 4. Vector and Special Functions

Every tile has a 2048-bit vector datapath: 256 FP8, 128 BF16, or 64 FP32 lanes. With one FMA per lane per
cycle at 1 GHz, aggregate peaks are 8.192 TFLOPS FP8, 4.096 TFLOPS BF16, and 2.048 TFLOPS FP32 across
the NPU. Sixteen special-function lanes per tile cover exp2, reciprocal, and reciprocal square root.
These are initial provisioning values; an operator/shape manifest is required before freezing them.

## 5. SRAM Hierarchy

Each compute tile has 8 MiB private software-managed SRAM organized as 32 banks of 256 bits. The target
port service is 512 B/cycle read plus 256 B/cycle write at 1 GHz. Each pod also has 16 MiB shared SRAM
for DMA staging, cross-tile exchange, collective fragments, and weight-reuse groups. Total explicit SRAM
capacity is 256 MiB per NPU: 128 MiB private plus 128 MiB pod-shared. The memory is non-coherent; ownership
and producer-consumer barriers are explicit in KD-ISA/runtime contracts.

## 6. On-Chip NoC

The NoC runs at a proposed logical 2 GHz and separates bulk data from control. A tile data port is 2048
bits, or 512 GB/s in each direction. Two tile ports provide 1.024 TB/s of directional pod service. Each
pod HBM attachment is 3072 bits, or 768 GB/s, against a 625 GB/s HBM-partition target.

Neighboring pods use two 1024-bit data lanes per direction, giving 512 GB/s per directed mesh edge. The
middle bisection of the 2 x 4 mesh has two edges and therefore 1.024 TB/s per direction. This does not
support arbitrary redistribution of the full 5 TB/s HBM stream. Instead, compiler placement and address
mapping must keep at least 80 percent of HBM traffic pod-local; traces that exceed the 20 percent nonlocal
budget are a placement failure or require a topology revision.

Four virtual channels are proposed: one deterministic XY escape VC, bulk read response, bulk write, and
KDLink/collective traffic. Adaptive routing may be used only outside the escape VC. Deadlock freedom is a
future `FORMAL` obligation and is not established by this proposal.

## 7. DMA

There is one HBM DMA engine per pod and 16 logical channels per engine. Descriptors support linear 1D,
strided 2D/3D, scatter-gather, indexed gather/scatter, pod-local multicast, and zero-fill transfers. The
proposed data beat is 128 B; aligned adjacent beats may coalesce into transfers up to 4 KiB. A descriptor
may cover up to 16 MiB and descriptors may be chained.

At 625 GB/s, a 500 ns HBM round trip requires 312.5 kB in flight and an 800 ns stress latency requires
500 kB. The proposed 4096 outstanding 128 B beats provide 512 KiB per engine, enough for the 800 ns
stress point with modest headroom. Sixty-four active descriptors per engine avoid coupling this data
credit pool to a single command stream. Four QoS classes separate demand loads, writeback, prefetch, and
collective traffic. Starvation prevention requires age-based promotion.

The proposed address width is 52 bits, but it is deliberately not frozen. HBM capacity needs fewer bits;
the wider proposal is for IOVA, protection domains, and future system mapping. The authoritative width,
fault responses, ordering, and cancellation semantics belong in `specs/interfaces/`.

## 8. Acceptance Path and Holds

1. `ANALYTICAL`: the checked-in calculator must reproduce compute, bandwidth, bisection, SRAM, and DMA
   bandwidth-delay-product values.
2. `FUNCTIONAL_SIM`: workload traces must establish HBM locality, DMA channel occupancy, weight reuse,
   and vector/SFU demand.
3. `RTL_SIM`: continuous tensor issue, NoC saturation, DMA backpressure, QoS, and KDLink coexistence must
   be measured at declared logical clocks.
4. `FORMAL`: the escape routing and credit rules must prove freedom from protocol deadlock under recorded
   assumptions.
5. `GENERIC_SYNTH`: structural cost may inform a clock/topology revision but is not a frequency result.

The following remain `HOLD`: HBM bandwidth directionality, FP8/BF16 tensor issue rate, external memory
transaction fields, vector SFU sufficiency, and the 20 percent nonlocal traffic assumption. They require
workload evidence or a cross-owner ADR before implementation interfaces are frozen.
