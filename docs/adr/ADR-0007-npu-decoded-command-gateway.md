# ADR-0007: NPU Already-Decoded Command Gateway

Status: accepted for the NPU-internal v0.1 boundary
Date: 2026-08-29
Owners: NPU Pod, scheduler, DMA, and verification

## Context

The compute Pod already had separate Task, local-transfer, and DMA command ports, but no single NPU-owned
ingress or completion stream. KD-ISA encoding, software queues, interrupts, cancellation, IOVA translation,
and runtime ABI semantics remain owned outside the NPU RTL and are not sufficiently frozen for RTL.

## Decision

Adopt a versioned, already-decoded internal envelope containing class, request ID, Pod ID, optional target,
and an opaque leaf payload. One `npu_pod_command_gateway` validates the envelope and referenced leaf record,
forwards exactly one Task/local/DMA transaction, and serializes leaf completions into one stable ready/valid
stream. Malformed records are consumed only when an error-completion slot is available and produce an
explicit command-source failure completion.

Completion selection is fair round-robin across Task, all local loaders, and all DMA channels. Quiesce
blocks new command admission but does not discard buffered completions. The gateway is integrated with the
raw one-Pod leaf through `npu_managed_compute_pod`.

## Consequences

- The NPU has a complete internal command/completion path without inventing KD-ISA or software fields.
- Leaf debug and verification retain direct access through `npu_compute_pod`.
- A future queue/ISA adapter must translate into this envelope and consume its completion stream.
- Cancellation, timeout, interrupt delivery, protection, and host-visible ordering remain separate contracts.

## Evidence

Zero-warning Verilator lint, self-checking routing/error/backpressure/fair-completion RTL simulation, Yosys
synthesis-readiness, and an end-to-end managed-Pod Task/DMA/local-transfer regression are required.
