# Third-Party Dependencies

`dependencies.yaml` is the release inventory for every required or optional external tool and input. Each
entry records name, version, source, license, checksum and checksum subject, redistribution status,
acquisition method, and replacement strategy.

The repository does not vendor these packages. Install `requirements-build.lock` with `--require-hashes`,
then install `requirements-dev.lock` with `--require-hashes --no-build-isolation` on the validated release
platform. This pins the build backend for the REUSE source distribution. Provide Verilator, Yosys,
OpenSTA, GNU Make, and a C++ compiler from `PATH`; then run
`make release-audit`. The expected audit output includes no dependency schema, version, or hash-lock
error. `requirements-dev.txt` remains the version-pinned development input. Run the full release
regression next.

The optional OpenROAD Flow Scripts checkout and all licensed foundry/vendor inputs remain ignored and
outside the source archive. Do not store model weights, private datasets, credentials, or restricted
binaries here.
