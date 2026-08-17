# Configuration

Contains committable workload, logical-capacity, protocol, and tool-independent configuration. Host paths,
credentials, and local developer settings use ignored `*.local.yaml` files.

`system_baseline.yaml` is the machine-readable v0.1 architecture target. Changes require synchronized
requirements, specifications, verification expectations, and an ADR when multiple subsystems are affected.

`npu_arch_proposed.yaml` is an analytical NPU sizing proposal. It is deliberately not a frozen interface
baseline; promote selected values only through the required ADR and specification updates.
