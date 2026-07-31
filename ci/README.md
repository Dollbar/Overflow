# Continuous Integration Policy

The root `Makefile` and subsystem Makefiles are the authoritative reproducible gate definitions. The
repository currently does not contain a GitHub Actions workflow or a checked-in container image, so this
directory must not be interpreted as proof that hosted CI is configured.

The minimum release runner executes:

```bash
python3 -m pip install --require-hashes -r requirements-build.lock
python3 -m pip install --require-hashes --no-build-isolation -r requirements-dev.lock
make release-preflight
make release-audit
make release-regression RELEASE_JOBS=2
make release-check
```

Expected outputs are described in the root README. A hosted runner must provide the versions declared in
`third_party/dependencies.yaml`, retain raw logs and coverage summaries, reject secrets and restricted
artifacts, and expose no proprietary Liberty or PDK data to untrusted jobs. The next implementation step is
an owner-approved workflow or self-hosted runner with branch protection; until then, release evidence is a
reviewed local or external-runner result, not an automated GitHub status claim.

Use a runner with at least 32 GiB of RAM for the default `RELEASE_JOBS=2`. Set `RELEASE_JOBS=1` when less
memory is available and provide swap; one validated full-Pod lint process used about 20 GiB by itself. The
release regression is expected to take multiple hours from an empty build cache; CI timeout and
log-retention policies must account for that duration.
