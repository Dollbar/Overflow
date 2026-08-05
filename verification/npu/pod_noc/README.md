# 2x4 Pod + NoC joint verification

This directory closes the production transport connection between the fixed
eight-Pod array and the 2x4 NoC. The DUT is `npu_2x4_pod_noc_system`; traffic
crosses the real Pod attachment, asynchronous Pod/NoC FIFOs, Mesh routers, the
destination CDC, and the destination attachment.

The joint simulation uses the existing verification-only compute-cluster and
shared-SRAM models so eight full Pod control hierarchies remain portable on a
workstation. No attachment, CDC, router, Mesh, command gateway, scoreboard, or
system-top RTL is stubbed. The layered release target separately runs the real
one-Pod production hierarchy lint and the complete Pod/NoC subsystem suites.

Run from the repository root:

```sh
make npu-pod-noc-system-closure
```

For the complete layered release gate, including the existing Pod and NoC
lint, structural synthesis, formal, multiseed, and coverage suites, run:

```sh
make npu-pod-noc-release
```

The closure first runs a structural guard that checks every filelist path,
requires both production instances, requires synchronized reset/quiesce, and
rejects direct global-clear fanout into the Pod Array. The joint test then uses
eight distinct Pod clocks and a ninth NoC clock. It checks
all 64 ordered control routes, all 512 ordered source/destination/data-lane/VC
combinations, endpoint backpressure stability, eight concurrent local task
commands, quiesce/drain, clear recovery, counters, and absence of protocol
errors. The final expected line is:

```text
[RTL_SIM PASS] npu_2x4_pod_noc_system control_routes=64 data_lane_vc_routes=512 commands=8 distinct_pod_clocks=8
```

Generated files are confined to
`verification/npu/pod_noc/build/verilator/tb_npu_2x4_pod_noc_system/`.
The executable is `Vtb_npu_2x4_pod_noc_system`. `make ... clean` removes only
that generated build directory.

The packet-client payload remains opaque. This test proves transport and local
compute coexistence; it does not invent or claim a remote DMA, remote SRAM,
collective, retry, timeout, or software-completion packet protocol. Those
functions require separately frozen and versioned client adapters.
