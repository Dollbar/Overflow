# Configuration

Contains committable workload, logical-capacity, protocol, and tool-independent configuration. Host paths,
credentials, and local developer settings use ignored `*.local.yaml` files.

`system_baseline.yaml` is the machine-readable v0.1 architecture target. Changes require synchronized
requirements, specifications, verification expectations, and an ADR when multiple subsystems are affected.

`npu_arch_proposed.yaml` is an analytical NPU sizing proposal. It is deliberately not a frozen interface
baseline; promote selected values only through the required ADR and specification updates.

`release.yaml` is the machine-readable public-release scope, non-claim, licensing-decision, and gate
configuration. It is mirrored by `docs/releases/ACCEPTANCE.json`; both statuses must agree.

`contributors.yaml` records the owner-confirmed contributor identities, public Git emails, development
periods, responsibilities, copyright-transfer status, and centralized committer identity used by the
reviewed history-reconstruction process.

`history_reconstruction.yaml` records the reviewed source-commit to contributor mapping for that process.
It remains planning metadata until reconstruction and verification are complete.
