# Source Publication Manifest

## Release Identity

- Project: Overflow
- Published tag: `v1.0.0`
- Release date: 2026-09-01
- Current publication state: `GO`
- Authoritative decision: `ACCEPTANCE.json`
- Source archive root: the tagged release-attestation commit, whose sole parent is the validated payload

The exact source file list is generated from the accepted commit with `git ls-tree -r --name-only
v1.0.0`. It is not duplicated manually in this document because a handwritten list drifts from the Git
tree.

## Included Tree

The source archive includes all tracked files under `Library/`, `config/`, `docs/`, `requirements/`, `rtl/`,
`scripts/`, `simulator/`, `specs/`, `technology/`, and `verification/`, plus the top-level governance,
security, conduct, release, build, dependency, and license files. Placeholder ownership directories remain included so the
model-to-RTL boundary and explicit non-claims are not lost.

Repository-authored behavioral models and synthetic timing views are included only after the owner-approved
license matrix covers them. The source tag contains no generated binaries or regression logs.

## Mandatory Exclusions

- Model weights, KV state, private datasets, tokens, credentials, keys, or local environment files.
- Vendor PDK, standard-cell, SRAM compiler, HBM controller/PHY, SerDes macro, IBIS-AMI, package, or board
  collateral.
- Ignored `build/`, `work/`, `.pytest_cache/`, `__pycache__/`, `obj_dir/`, waveforms, netlists, timing logs,
  coverage databases, and simulator executables.
- Local virtual environments and optional `third_party/OpenROAD-flow-scripts` checkouts.
- Any artifact whose source, version, license, checksum, and redistribution rights are unknown.

## Reproducible Archive Check

To reproduce and inspect the published source-only archive locally:

```bash
mkdir -p docs/releases/work/archive
git archive --format=tar.gz --prefix=Overflow-1.0.0/ \
  -o docs/releases/work/archive/Overflow-1.0.0.tar.gz v1.0.0
sha256sum docs/releases/work/archive/Overflow-1.0.0.tar.gz \
  > docs/releases/work/archive/Overflow-1.0.0.sha256
tar -tzf docs/releases/work/archive/Overflow-1.0.0.tar.gz | sed '/\/$/d' | sort \
  > docs/releases/work/archive/Overflow-1.0.0.files.txt
git ls-tree -r --name-only v1.0.0 | sed 's#^#Overflow-1.0.0/#' | sort \
  > docs/releases/work/archive/Overflow-1.0.0.expected.txt
diff -u docs/releases/work/archive/Overflow-1.0.0.expected.txt \
  docs/releases/work/archive/Overflow-1.0.0.files.txt
```

Expected outputs are one recorded SHA-256 digest and an empty `diff`. The archive and temporary inventory
files are release artifacts, not Git sources. GitHub generates the published ZIP and TAR archives directly
from the annotated release tag; no local build output is attached.

## Published GitHub Release Checks

- The repository default branch contains the accepted commit.
- The tag is annotated and points to the attestation commit; its parent is the payload commit
  recorded in `ACCEPTANCE.json` and `config/release.yaml`.
- The public history preserves the payload and attestation commits.
- GitHub release notes match `RELEASE_NOTES.md` and repeat the non-claims.
- The repository About text does not claim a complete product or a license different from the committed
  license matrix.
- The repository does not claim an in-tree hosted CI implementation; the documented commands remain the
  reproducible local or external-runner path.
- The owner confirmed the private vulnerability-reporting route named by `SECURITY.md` is operational.
