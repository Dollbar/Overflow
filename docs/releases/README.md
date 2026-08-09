# Release Artifacts

This directory contains stable release documents. Product and protocol versions are recorded inside these
files rather than in their file names.

| File | Purpose |
| --- | --- |
| `ACCEPTANCE.json` | Machine-readable overall release decision, blockers, and evidence state |
| `KDLINK_ACCEPTANCE.json` | KDLink-specific retained acceptance evidence |
| `RELEASE_NOTES.md` | Human-readable release scope, changes, evidence, and non-claims |
| `UPLOAD_MANIFEST.md` | Source publication contents, exclusions, and publication procedure |

Overflow `1.0.0` is published at annotated tag `v1.0.0`. Run `make release-audit` to inspect its recorded
state and `make release-regression RELEASE_JOBS=2` to reproduce the portable engineering suite. Future
candidates must follow the payload/attestation sequence in release management; a `HOLD` in
`ACCEPTANCE.json` remains a publication stop, not a waiver.
