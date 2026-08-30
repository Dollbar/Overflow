# NPU On-Chip Network RTL

Owns pod-local switching, inter-pod routers, credits, virtual channels, routing, QoS, and performance
telemetry. The P0 proposal uses a 2 x 4 pod mesh, a 2 GHz logical NoC clock, one escape VC, and three
non-escape traffic classes. These values are `PROPOSED`, not frozen interface fields.

ADR-0005 and `npu_pod_noc_attachment_v0.1.md` now freeze the Pod-facing ready-valid handoff: one 128-bit
control lane and two 1,024-bit data lanes per direction with opaque payloads. Router-internal VC mapping,
credits, routing, ordering, fault behavior, CDC, and performance remain owned here. NPU-NOC-001 therefore
has a stable endpoint interface but still requires its NoC-owner implementation contract and `FORMAL`
deadlock evidence; analytical bisection and an operator test do not satisfy that obligation.
