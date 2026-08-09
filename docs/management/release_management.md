# Version and Release Management

## Versioning

Repository releases use semantic versioning. A major release may break external model, IR, ISA, ABI,
KDLink, or RTL interfaces; a minor release adds backward-compatible behavior; a patch release fixes
behavior or documentation without changing a frozen interface. Protocol schema revisions remain inside
stable engineering files and are independent of the repository release label.

## Release Sources of Truth

- `config/release.yaml`: candidate version, scope, non-claims, licensing decision, and commands.
- `docs/releases/ACCEPTANCE.json`: machine-readable publication decision and evidence state.
- `docs/releases/RELEASE_NOTES.md`: human-readable changes, evidence, and limitations.
- `docs/releases/UPLOAD_MANIFEST.md`: archive contents, exclusions, and publication sequence.
- `requirements/traceability.csv`: requirement states and evidence owners.
- `third_party/dependencies.yaml`: complete external dependency inventory.

## Candidate Workflow

Prepare the candidate in an isolated worktree. Do not mix generated output from another branch or reuse a
dirty working directory as release evidence.

```bash
OVERFLOW_PAYLOAD_COMMIT='replace-with-40-character-payload-commit'
git cat-file -e "${OVERFLOW_PAYLOAD_COMMIT}^{commit}"
git worktree add --detach ../Overflow-release "${OVERFLOW_PAYLOAD_COMMIT}"
cd ../Overflow-release
python3 -m venv .release-env
. .release-env/bin/activate
python3 -m pip install --require-hashes -r requirements-build.lock
python3 -m pip install --require-hashes --no-build-isolation -r requirements-dev.lock
make release-preflight
make release-audit
make release-regression RELEASE_JOBS=2
make release-check
```

Expected outputs are documented in the root README. `release-audit` may pass with explicit holds during
preparation; `release-check` is strict and must not. Review raw logs before recording a pass in the
acceptance report. Resolving the full payload ID directly avoids assumptions about whether a clone calls
the public repository `origin`, `upstream`, or another remote name.

## Publication Sequence

1. Obtain release-manager and blocking-owner approval, including contributor rights, the copyright holder,
   path-level license matrix, and inbound contribution policy.
2. Add the selected official license texts and REUSE metadata; rerun the strict audit.
3. Commit Pod/NoC integration and release preparation as the five reviewed content commits recorded in
   `config/history_reconstruction.yaml`. Treat the fifth commit and its complete tree as the immutable
   payload; do not squash or reorder the sequence after validation.
4. Recreate a fresh worktree at that payload commit and run the complete portable regression.
5. Record the payload's full 40-character commit, tool versions, result counts, coverage, and any
   non-applicable physical gates in `ACCEPTANCE.json`; set both machine-readable publication states to
   `GO`.
6. Commit only `config/release.yaml` and `docs/releases/ACCEPTANCE.json` as the release-attestation
   commit. This avoids the impossible requirement for a commit to contain its own Git ID. The strict gate
   verifies that the recorded payload is the attestation commit's sole parent and that no other file changed.
7. Rerun `make release-candidate-check` from the clean attestation commit. This deliberately repeats the
   regression with the final metadata in place.
8. Push a release branch and merge it by a merge commit or fast-forward after review. Do not squash or
   rebase the payload/attestation pair, because either operation destroys the relationship checked by the
   release gate.
9. Fetch the public `main` and verify that the exact attestation commit is reachable from it.
10. Create an annotated and preferably signed `v1.0.0` tag on that exact attestation commit, verify it, and
   push only the tag after owner approval.
11. Confirm that the private vulnerability-reporting route named by `SECURITY.md` is operational.
12. Create the GitHub release from `RELEASE_NOTES.md`; attach only source archives produced by GitHub or
   from `git archive`. Do not attach local build directories, proprietary libraries, weights, or logs with
   host paths.

Example tag commands after all gates pass:

```bash
OVERFLOW_PUBLIC_REMOTE='github'
OVERFLOW_ATTESTATION_COMMIT="$(git rev-parse HEAD)"
git remote get-url "${OVERFLOW_PUBLIC_REMOTE}"
git push -u "${OVERFLOW_PUBLIC_REMOTE}" HEAD:refs/heads/release/1.0.0
# Create and merge the reviewed PR without squash or rebase, then continue:
git fetch "${OVERFLOW_PUBLIC_REMOTE}" main
git merge-base --is-ancestor "${OVERFLOW_ATTESTATION_COMMIT}" \
  "${OVERFLOW_PUBLIC_REMOTE}/main"
git tag -s v1.0.0 "${OVERFLOW_ATTESTATION_COMMIT}" -m "Overflow 1.0.0"
git show --show-signature v1.0.0
git push "${OVERFLOW_PUBLIC_REMOTE}" v1.0.0
```

The remote URL must be the intended public repository, the ancestor check must return zero, and the tag
must point at the accepted attestation commit. If a signing key is not part of project policy, use an
annotated tag with `git tag -a` and record that decision.

## Evidence Policy

Every performance result identifies workload shape, clocks, datatype, topology, configuration, evidence
level, commands, tool versions, and raw counters. Analytical bandwidth is never called measured, generic
synthesis is never called silicon frequency, and an operator test is never called full-model acceptance.
