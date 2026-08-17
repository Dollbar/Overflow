# NPU On-Chip Network RTL

Owns pod-local switching, inter-pod routers, credits, virtual channels, routing, QoS, and performance
telemetry. The P0 proposal uses a 2 x 4 pod mesh, a 2 GHz logical NoC clock, one escape VC, and three
non-escape traffic classes. These values are `PROPOSED`, not frozen interface fields.

NPU-NOC-001 is `HOLD` until packet fields, link widths, credit return, reset, ordering, and fault behavior
are specified. Deterministic escape routing requires `FORMAL` deadlock evidence; analytical bisection and
an operator test do not satisfy that obligation.
