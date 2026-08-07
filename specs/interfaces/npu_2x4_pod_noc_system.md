# NPU 2x4 Pod + NoC system v0.1

## Scope

`npu_2x4_pod_noc_system` is the production structural integration of
`npu_2x4_pod_array` and `npu_noc_cdc_mesh`. It fixes eight Pods in the existing
2x4 logical geometry and owns every connection between the Pod-side attachment
buffers and the NoC-side CDC/Mesh boundary.

## Clock, reset, and quiesce contract

- `pod_clk_i[7:0]` are independent Pod clocks; `noc_clk_i` is the Mesh clock.
- `async_rst_i` and `clear_i` are asynchronously asserted and synchronously
  released independently into each of the nine clock domains.
- The synchronized `pod_rst_o` vector is the only reset applied to the Pod
  Array. Global `clear_i` is not directly fanned into Pod logic.
- `quiesce_i` is synchronized independently. New endpoint injection is blocked,
  existing attachment/CDC/router contents drain, and `system_quiesced_o` is
  asserted only after NoC drain and synchronized Pod/attachment quiescence.
- Pod-domain status bits are synchronized into `noc_clk_i` before forming the
  three system summary signals.

## Transport path

The complete path is:

```text
Pod packet client -> Pod attachment -> TX async FIFO -> 2x4 Mesh
                  -> RX async FIFO -> Pod attachment -> Pod packet client
```

The external packet-client boundary remains one 160-bit control stream and two
1,176-bit data streams per Pod. Flit layout and metadata are defined by
`npu_pod_noc_pkg`; routing, VC, CDC, and telemetry are defined by `npu_noc_pkg`
and the NoC interface specifications.

## Status

- `pod_*`, `command_*`, and `attachment_*` vectors retain per-Pod ownership.
- `noc_busy_o`, `noc_quiesced_o`, and `noc_protocol_error_o` report the CDC/Mesh.
- `system_busy_o`, `system_quiesced_o`, and `system_protocol_error_o` are
  NoC-clock-domain management summaries.
- Existing command/completion, five HBM lanes per Pod, GEMM/vector/feedback,
  events, and telemetry remain visible without changing their frozen contracts.

## Explicit non-goals

Packet payloads are opaque. Remote DMA/SRAM operations, collectives, retry,
timeout, ordering beyond the NoC contract, and software-visible completion
semantics are not defined by this system shell. They require separately
versioned packet-client adapters and must not be inferred from this wiring.

## Verification evidence

`verification/npu/pod_noc` provides strict production/TB lint and a
self-checking joint simulation over eight distinct Pod clocks. The release
target composes this joint gate with the separately maintained Pod and NoC
lint, synthesis-readiness, formal, multiseed, and coverage gates.
The joint eight-Pod simulation substitutes the standard verification compute
and shared-SRAM models; the complete attachment/CDC/Mesh transport is real RTL,
while the separate Pod gate retains the real production-hierarchy lint.
