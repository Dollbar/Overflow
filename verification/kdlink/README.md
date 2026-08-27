# KDLink Verification Gates

This directory owns release-facing static and dynamic verification for KDLink. Portable functional and
RTL simulations remain under `simulator/kdlink`; this directory adds coverage aggregation, bounded formal
properties, structural lint and CDC audits, partitioned OpenSTA, and release evidence generation.

Generated compiler objects, raw coverage databases, synthesized netlists, and solver work directories are
written below a `work/` directory and are ignored by Git. Only concise, redistributable summaries belong in
the repository.

## Gates

| Directory | Gate |
| --- | --- |
| `coverage/` | Source-level line, branch, expression, and control-toggle coverage |
| `formal/` | Bounded safety and progress properties using Yosys SAT |
| `cdc/` | Structural clock/reset-domain crossing audit |
| `sta/` | Multi-corner registered-partition timing plus HBM/SerDes interface-Liberty validation |
| `scripts/` | Reproducible orchestration and report generation |

The release target is a 1.000 ns clock period for each explicitly reported partition. RTL simulation with
a 1 ns testbench clock is not accepted as timing evidence.

## Portable Release Entry Points

From any clone, run `make kdlink-preflight` to verify the tool versions in
`config/kdlink_toolchain.json`, all 61 manifest paths, repository-contained SerDes/interface dependencies,
stable engineering filenames, and absence of host-specific absolute paths. Run `make kdlink-release-check`
for the sequential functional-model, RTL, lint/CDC, formal, coverage, and repository gates. These targets
derive every source and work path from the repository and do not consume developer-local configuration.

The preflight writes no generated file and must end with `KDLINK_RELEASE_PREFLIGHT_PASS`. The complete
portable release target refreshes `verification/kdlink/cdc/summary.json`, `coverage/summary.json`, and
`formal/summary.json`; the separate `kdlink-sta` target refreshes `sta/summary.json` when licensed external
libraries are supplied. Detailed intermediate output remains below ignored `work/` directories. After a
PASS, review `docs/releases/UPLOAD_MANIFEST.md`, then stage only its exact whitelist.

Technology-specific STA is intentionally separate:

```bash
make kdlink-sta KDLINK_STA_ARGS='--corner fast=third_party_local/fast.lib --corner typical=third_party_local/typical.lib --corner slow=third_party_local/slow.lib --driving-cell BUFFD4BWP40P140'
```

Relative Liberty paths are resolved from the repository root even when the command is launched elsewhere.
The external standard-cell libraries are not redistributed and may instead reside outside the clone by
using absolute command-line paths. Only library basenames and redistribution status enter the committed
summary. Repository HBM/SerDes interface Liberty views are always loaded by repository-relative path.
