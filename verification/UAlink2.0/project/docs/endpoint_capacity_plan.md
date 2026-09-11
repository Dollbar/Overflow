# Endpoint transaction capacity implementation plan

**Goal:** Make actual Read transaction storage capacity configurable through the Endpoint top, while retaining the full dual-IP objective.

**Architecture:** Propagate independent originator and completer capacities into their existing ownership modules. Keep the public two-bit memory slot interface unchanged: the integrated completer supports one through four slots; the originator table retains its existing one-through-255 bound. Defaults remain four. Invalid configurations hold the transaction core in reset and report an error.

**Spec:** `docs/endpoint_transaction_execution.md` defines the current wire subset. Capacity is local resource allocation, not a new protocol encoding. This increment does not claim general Read/Write/Atomic or independent link-reset recovery.

**Tech Stack:** Verilog-2001, existing SystemVerilog bench/pkg/VIP, Python, Icarus Verilog, Yosys.

- [x] Extend the real causal bench and runner with independent capacities, occupancy bounds and saturation evidence; observe failure on the current hard-coded four-slot implementation.
- [x] Add top/core parameters, propagate them, and gate invalid integrated configurations.
- [x] Repair and verify the completer's non-power-of-two memory mapping independently; preserve existing request/result ownership.
- [x] Run actual two-Endpoint/Switch communication for originator capacities 1/2/3/4/8 and completer capacities 1/2/3/4, including recovery and minimum buffering selections.
- [x] Verify invalid-capacity diagnostics and use a real ignored-capacity wiring fault to check the occupancy oracle.
- [x] Preserve existing default regression and run structural checks appropriate to parameter changes. Record source hashes, results and limitations.

Parallel verification also exercises uniform synchronous network reset in outstanding-request, memory-execution and completion-holding phases. All resettable participants cancel the old epoch together; this does not establish independent-endpoint epoch negotiation.
