# UALink source delivery

This isolated subtree imports 842 tracked files from Dollbar/KD-UAlink2.0 commit
`68a3b7961abe0d592d955cbf9ee39bbe40642010`. The exact source hashes are in
[publication_manifest.json](docs/publication_manifest.json). Upstream files are unchanged.
This snapshot is separate from the existing Overflow release and acceptance scope.

The Endpoint and Switch development tops exist. Current RTL_SIM and structural
GENERIC_SYNTH evidence, with prior gate-synthesis results bounded to their original
snapshot, is described in [the bring-up guide](docs/ip_top_bringup.md) and
[the typed-module increment](docs/typed_modules_progress.md). The inventory
contains 202 RTL entries: 60 partially implemented modules and 142 disabled interface
scaffolds. Module presence is not functional completion. Full protocol conformance,
causal application transactions, PHY, security, INC and final timing remain incomplete.
Historical source-side timing scripts and bounded evidence summaries are retained for
reproduction; no physical implementation domain, licensed PDK, private specification,
external library copy, waveform or build result is included.

Run from the Overflow root (Python 3.10+, Make, Icarus Verilog and Yosys required):

```sh
cd RTL/UAlink2.0
python3 verification/endpoint_transaction/test_model.py --label imported_model
make ip-module-smoke IP_RUN_LABEL=imported_modules
make ip-top-smoke KD28_ROOT=../.. IP_RUN_LABEL=imported_typed_tops
```

Expected outputs: model results under `build/verification/endpoint_transaction/`,
structure and link evidence under `build/verification/`, and Switch logs under
`reports/ip_tops/`. Use fresh labels for subsequent runs. `KD28_ROOT=../..` explicitly
selects the containing Overflow checkout; dependency checks retain their hash checks.
Next, implement typed service modules and their transactions while preserving the
existing backpressure, replay and credit regressions.

The imported upstream source has no assigned license. Root REUSE annotations are
mechanically restricted to pre-existing root namespaces, preserving their previous
license mappings and avoiding an implicit license grant for this new subtree.
No copyright holder or license is assigned to UALink by this import.
