# Initial Technical Risk Register

| ID | Risk | Probability | Impact | Current mitigation | Owner |
| --- | --- | --- | --- | --- | --- |
| R-001 | Model weights, KV state, and workspace exceed logical memory capacity | Medium | Critical | Capacity model and workload traces | System |
| R-002 | MXFP4/MXFP8 semantics diverge from model references | High | Critical | Bit-exact operator conformance | Model/RTL |
| R-003 | MoE AllToAllv congests the logical fabric | High | Critical | Trace-driven routing and congestion simulation | Fabric |
| R-004 | KDLink encoding, training, and replay state machines disagree | Medium | Critical | Shared protocol vectors and fault-injection tests | Fabric |
| R-005 | Abstract memory behavior hides command and bandwidth stalls | High | High | Cycle-aware memory model with recorded assumptions | Simulator |
| R-006 | NPU pipelines fail to sustain their declared initiation intervals | Medium | Critical | RTL performance counters and continuous-flow regressions | NPU |
| R-007 | Compiler output cannot sustain kernel utilization | High | High | Scheduling regression and hand-authored references | Compiler |
| R-008 | Verification scale makes coverage closure impractical | High | High | Layered formal checks and trace replay | Verification |
| R-009 | Multi-hop channel dependencies permit protocol deadlock | Medium | Critical | Escape routing and channel-dependency analysis | Fabric |
| R-010 | Third-party licensing blocks a source release | Medium | High | SPDX metadata and dependency manifests | Release |
| R-011 | Cross-layer interface drift breaks executable compatibility | High | High | Versioned schemas and producer-consumer conformance | Architecture |
| R-012 | Peak metrics replace end-to-end tokens/s evidence | High | High | Evidence labels and model-level acceptance | System |

Review risks at every release gate. A Critical risk without an owner and a verifiable mitigation keeps the
affected gate at `HOLD`.
