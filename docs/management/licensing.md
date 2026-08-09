# Licensing and REUSE Policy

The recorded copyright holder is `刘键宇`. The owner approved the matrix below, the corresponding official
texts and path-level metadata are installed, and the `v1.0.0` release records the completed rights,
attribution, payload, and attestation decisions.

## Owner-Approved Matrix

| Path class | SPDX expression | Decision record |
| --- | --- | --- |
| User-space software, Python, simulator, scripts, verification utilities, and configuration | `Apache-2.0` | Owner approved on 2026-08-31 |
| RTL, SystemVerilog testbenches, VIP, hardware models, Liberty, SDC, and hardware specifications | `Apache-2.0 WITH SHL-2.1` | Owner approved on 2026-08-31 |
| General prose documentation | `CC-BY-4.0` | Owner approved on 2026-08-31 |
| Future Linux kernel driver code | `GPL-2.0-only` | Owner approved on 2026-08-31 |
| Kimi-K3 weights and third-party proprietary collateral | Not redistributed | Remain excluded |

The SPDX identifier for Solderpad 2.1 is the exception expression `Apache-2.0 WITH SHL-2.1`, not
`Solderpad-2.1`. `REUSE.toml` assigns `Copyright 2025-2026 刘键宇` and the approved expression to every
covered path. Later matching annotations override the repository default for documentation, hardware, and
the driver subtree.

## Official Text Provenance

The four unmodified texts are from SPDX License List `v3.28.0`:

| File | SHA-256 |
| --- | --- |
| `Apache-2.0.txt` | `1f83bfbb6ab612d244b9619bcf615e54c2e107fc78a05eb6e16bc1ce41fd2f8f` |
| `SHL-2.1.txt` | `bab79b6677dd5b646559bdd6dd0948f2caf678b4b6eb10290c1a6b72e70e0c34` |
| `CC-BY-4.0.txt` | `7f38c38147b1b5e3fc5788e34104c965873b60bbf639c52392a85297810ebcbe` |
| `GPL-2.0-only.txt` | `d29dbcc178acaf8370a7f861f30ae9ebec8e96c0177d2205280a96ae0e0b5d46` |

Source template: `https://github.com/spdx/license-list-data/blob/v3.28.0/text/<SPDX-ID>.txt`.

The current Git history contains three author identity strings controlled by `刘键宇`. On 2026-08-31, the
owner also confirmed that the named contributors in `config/contributors.yaml` transferred the relevant
copyrights in writing to `刘键宇`. The private assignment records are not redistributed. Future external
contributions use the Developer Certificate of Origin 1.1 and require a `Signed-off-by` trailer on every
contributed commit, as documented in `CONTRIBUTING.md`.

Run `make release-audit` to inspect the release state and `make release-check` for the strict gate. The
published release is expected to report zero errors, zero holds, and `RELEASE_GATE_PASS`.

This document records engineering release state and is not legal advice; the rights holder should review
the final matrix and contributor history before publication.
