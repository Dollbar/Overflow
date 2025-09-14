# Engineering Scripts

Scripts validate specifications, generate deterministic artifacts, run model and compiler checks, execute
simulator and RTL regressions, and assemble release evidence. Scripts default to read-only behavior or write
only to explicit build directories; they must not silently overwrite hand-written sources.

Run the v0.1 repository checks:

```bash
python3 -m pip install -r requirements-dev.txt
make check
```
