# NPU Command Front End

Owns the NPU-internal already-decoded command intake, leaf dispatch, unified completion, and local fault
reporting. `npu_pod_command_gateway` routes versioned Task, local-transfer, and DMA records to one Pod and
fairly aggregates their completions. Reusable source/sink VIP and self-checking tests live under
`verification/npu/command/`.

ADR-0007 and `npu_decoded_command.md` freeze only this internal boundary. KD-ISA encoding, firmware and
runtime queues, cancellation, interrupts, IOVA translation, and host-visible completion/error semantics
remain external `HOLD` items and must translate through a separately versioned adapter.
