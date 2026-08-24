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
