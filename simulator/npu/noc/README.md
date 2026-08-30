# NPU NoC Reference Model

This directory contains the standard-library-only golden model for the deterministic 2 by 4 Pod Mesh.
It checks coordinate mapping, all 56 directed routes, link legality, bisection geometry, declared-clock
payload calculations, packet limits, the architectural nonlocal-HBM traffic budget, hotspot/transpose
accounting, and a reproducible 4,096-flow uniform-random workload.

Run it from this directory or through the repository target:

```bash
make test
python3 scripts/run.py
```

The model is `ANALYTICAL` and `FUNCTIONAL_SIM` evidence. It does not measure RTL throughput, prove
deadlock freedom, or establish physical 2 GHz timing.
