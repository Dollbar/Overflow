# Engineering Scripts

Scripts validate specifications, generate deterministic artifacts, run model and compiler checks, execute
simulator and RTL regressions, and assemble release evidence. Scripts default to read-only behavior or write
only to explicit build directories; they must not silently overwrite hand-written sources.

Run the repository checks:

```bash
python3 -m pip install -r requirements-dev.txt
make check
```

Reproduce the proposed NPU analytical sizing:

```bash
python3 scripts/analyze_npu_proposal.py
```

The split NPU compute RTL verification workflow is intentionally owned by its local Makefile rather than a
standalone script:

```bash
make npu-compute-test
make npu-compute-waves
```

These targets keep generated simulator code, numerical vectors, logs, and waveforms below
`verification/npu/compute/build/`. The test target resolves open-source tools
from `PATH`; its SSG timing stage requires the caller to provide
`LIBERTY_SSG` without recording a PDK installation path in the repository.

`check_release.py` audits stable file names, tracked artifacts, common secret signatures, dependency
manifest completeness, hashed Python release pins, explicit requirement non-claims, licensing metadata,
acceptance status, and the two-commit payload/attestation relationship. Run `make release-audit` during
preparation and `make release-check` before tagging. The former may report explicit holds; the latter is
strict.

`check_release_toolchain.py` verifies the Linux x86-64/CPython 3.12 release host, exact locked Python
packages, required RTL/timing commands, declared versions, and executable evidence hashes before a long
regression starts. Run it through `make release-preflight`.
