# Specifications

This directory is the single source of truth for cross-subsystem interfaces. Specifications define versions,
compatibility, semantics, error behavior, and conformance requirements before implementation.

- `model/`: manifests, dtypes, operator semantics, KV state, and sharding.
- `compiler/`: IR and pass contracts.
- `isa/`: KD-ISA encoding and execution semantics.
- `abi/`: executable, queue, completion, and telemetry contracts.
- `kdlink/`: packet, PCS, routing, collective, and management protocols.
- `interfaces/`: digital memory, host, clock/reset, and encoded-link boundaries.
