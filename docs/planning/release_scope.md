# Release Scope and Acceptance

## Positioning

Overflow `1.0.0` is the first formal source-and-verification baseline for the repository's model-to-RTL
boundary. It is intended for architecture review, RTL simulation, formal analysis, portable synthesis,
and integration development. It is not a finished inference appliance or a silicon signoff release.

The authoritative machine-readable status is `config/release.yaml`, mirrored by
`docs/releases/ACCEPTANCE.json`. Any blocking item keeps publication at `HOLD`.

## Included Deliverables

- System and NPU configuration, ADRs, stable interface contracts, and requirement traceability.
- MXFP tensor/vector compute, independent Vector issue, command gateway, DMA, shared SRAM, compute Pod,
  managed Pod, and eight-Pod array RTL.
- The three-plane two-by-four Pod mesh, routers, virtual channels, escape path, per-Pod CDC, reset/quiesce
  handling, and the integrated Pod/NoC top.
- KDLink digital endpoint, reliable transport, router, collective, scale simulation, and digital SerDes
  models with retained acceptance evidence.
- HBM functional and beat-level RTL models; KD28 SRAM/FIFO mapping models; synthetic interface and SRAM
  timing views.
- Self-checking testbench packages, reusable VIP, deterministic seeds, lint, generic synthesis, bounded
  formal, functional/RTL simulation, and measured coverage gates.
- Release audit, hash-locked Python environment, third-party inventory, publication manifest, and known
  limitations.

## Explicit Non-Claims

- No Kimi-K3 weight or private dataset is distributed or executed by the release gate.
- Compiler, ISA producer, runtime, kernel driver, firmware, and deployment directories do not form a
  complete executable product.
- The proposed 2 PFLOPS-equivalent NPU, 5 TB/s HBM, 50 decode token/s, and full workload behavior are not
  demonstrated as an end-to-end system or measured silicon result.
- The current compute-local compatibility stores are verification-oriented scratchpads. The proposed
  production private SRAM capacity is not frozen; no hardware cache or coherence claim is made.
- Thresholded code-coverage gates exist for KDLink, the Pod array, and NoC. Compute, command, and NPU system
  use directed and stress simulation, lint, and synthesis-readiness checks but do not have one merged
  release-gated code-coverage result. The release does not claim exhaustive functional or code coverage.
- Repository synthetic Liberty files validate front-end plumbing only. They do not establish foundry PVT,
  post-layout timing, area, power, DFT, IR drop, electromigration, retention, yield, or physical CDC/RDC.
- HBM PHY, SerDes analog behavior, package, board channel, BER, SI/PI, and vendor-controller compliance are
  outside the repository boundary.

## Acceptance Criteria

1. A clean validated payload commit is followed by one attestation-only commit; the tag resolves to the
   attestation and the strict gate verifies its recorded parent and allowed two-file delta.
2. The repository owner confirms contributor rights, approves the copyright holder, path-level license
   matrix, and inbound contribution policy; selected full license texts and REUSE metadata cover every
   tracked file.
3. Stable engineering file names contain no release or protocol version suffix.
4. All dependencies record source, version, license, checksum subject/value, redistribution status,
   acquisition method, and replacement strategy.
5. Every requirement outside `BASELINED` or `VERIFIED` is named as an explicit release non-claim.
6. No tracked weights, credentials, private data, generated build output, or restricted binaries exist.
7. `make release-regression RELEASE_JOBS=2` passes on a fresh clone with the declared open toolchain.
8. `make release-check` prints `RELEASE_GATE_PASS` with no error or hold.
9. `docs/releases/ACCEPTANCE.json` is updated to `GO` only after retained logs and exact tool versions are
   reviewed.
10. GitHub private vulnerability reporting is enabled, or `SECURITY.md` names another monitored private
    contact.

Licensed external standard-cell or SRAM data may support a separately labeled implementation report, but
it is not required for the portable source release and must never enter the source archive.
