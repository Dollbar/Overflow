# System Context and Responsibility Boundaries

## 1. System Definition

OwerFlow covers the path from model artifacts to a simulated multi-NPU inference service and the RTL that
implements its accelerator commands, memory transactions, and KDLink communication. The lower boundary is
synthesizable RTL plus behavioral models of the surrounding digital environment.

## 2. Context Diagram

```text
                         External inputs
 +-----------------------------------------------------------+
 | Model configuration and authorized artifacts             |
 | Host requests and software dependencies                   |
 +-----------------------------+-----------------------------+
                               |
                               v
 +-----------------------------------------------------------+
 |                         OwerFlow                          |
 |                                                           |
 | Model adapter -> compiler -> executable/weight manifests  |
 |                         |                                 |
 | Serving -> runtime -> driver -> firmware/command queues   |
 |                         |                                 |
 | NPU RTL + memory interface + KDLink NIC/router/switch     |
 |                         |                                 |
 | Behavioral memory, host, and 32-node link environment     |
 +-----------------------------------------------------------+
                               |
                               v
                 Model output and performance evidence
```

## 3. In Scope

- Kimi-K3 and OF-5P6T workload manifests, operator semantics, and numerical references.
- Model import, quantized layout, TP/EP/PP partitioning, scheduling, and KD-ISA generation.
- Serving, paged KV state, continuous batching, device runtime, and driver interfaces.
- RV64 management firmware and the KD-ISA accelerator command set.
- Tensor, vector, scalar-assist, attention, MoE, on-chip NoC, DMA, and memory-interface RTL.
- KDLink packet, reliability, PCS, routing, collectives, AllToAllv, and KDSwitch RTL.
- Functional simulation, cycle modeling, RTL simulation, formal verification, CDC analysis, and coverage.
- Behavioral memory, host, and link models with latency, bandwidth, ordering, and fault controls.
- Logical multi-node deployment configuration and end-to-end inference reporting.

## 4. Outside the Repository Boundary

- Model training, training datasets, and redistribution of model weights.
- Realization below synthesizable RTL.
- External network services unrelated to the KDLink scale-up fabric.

External behavior required for correct RTL operation is represented by a digital contract and a behavioral
model. It must not leak implementation-specific assumptions into ISA, compiler, or protocol semantics.

## 5. Cross-Layer Interface Ownership

| Interface | Producer | Consumer | Authoritative location |
| --- | --- | --- | --- |
| Model manifest | `models/` | `compiler/`, `simulator/` | `specs/model/` |
| Graph and kernel IR | `compiler/` | codegen and runtime | `specs/compiler/` |
| KD-ISA binary | compiler | firmware, simulator, NPU RTL | `specs/isa/` |
| Executable and weight-manifest ABI | compiler | runtime | `specs/abi/` |
| Runtime queue ABI | runtime | driver and firmware | `specs/abi/` |
| NPU memory transaction | RTL DMA | behavioral memory model | `specs/interfaces/` |
| KDLink logical packet | NIC and collective | router and switch | `specs/kdlink/` |
| KDLink encoded block stream | KDLink PCS | behavioral link model | `specs/interfaces/` |
| Completion and telemetry | RTL and simulator | runtime and reports | `specs/abi/` |

## 6. Performance Evidence Boundary

Model throughput, compiler quality, NPU kernels, memory traffic, KDLink payload, collective efficiency, and
end-to-end tokens/s are separate metrics:

- Declared peak operations do not replace full-model tokens/s.
- Payload bits per logical cycle do not replace a measured sustained RTL stream.
- Operator simulation does not replace model-level numerical validation.
- A behavioral model result does not replace RTL simulation.
- Generic synthesis establishes structure, not implementation frequency.
