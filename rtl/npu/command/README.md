# NPU Command Front End

Owns KD-ISA command intake, validation, dependency metadata extraction, dispatch, completion, and fault
reporting inside the NPU. Inputs come from the firmware/queue boundary; outputs feed `scheduler/`.

NPU-CMD-001 is `HOLD` until command encoding, queue ordering, cancellation, completion, and error semantics
are versioned in `specs/isa/` and `specs/abi/`. RTL must not invent placeholder fields that escape a local
testbench. Acceptance requires malformed-command, backpressure, reset, and completion-order RTL tests.
