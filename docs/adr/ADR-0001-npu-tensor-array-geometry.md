# ADR-0001: NPU Tensor Array Geometry

- State: accepted
- Owners: NPU architecture and model-to-RTL integration
- Date: 2026-08-17
- Evidence: `ANALYTICAL`

## Context

The OF-5P6T baseline targets approximately 2 PFLOPS-equivalent MXFP4-by-MXFP8 peak per logical NPU but did
not define the tensor-array geometry or tensor logical clock. Task allocation and derived NoC/SRAM sizing
require one declared point.

## Decision

A tensor array is 256 x 256 MAC cells and uses a declared logical 1 GHz tensor clock. A MAC counts as two
operations. One array is therefore 131.072 TOPS-equivalent. The P0 organization uses 16 arrays, producing
2.097152 PFLOPS-equivalent and 4.86 percent analytical margin above the 2 PF target.

The 1 GHz value is a calculation assumption and architecture target. This ADR does not claim timing
closure, measured frequency, PPA, `GENERIC_SYNTH` frequency evidence, or sustained workload utilization.

## Alternatives

- 32 arrays at the same geometry and clock: 4.194304 PFLOPS-equivalent, rejected for the current 2 PF
  allocation baseline because it doubles the compute target and changes SRAM/NoC provisioning.
- 256 x 128 arrays: rejected by the architecture owner in favor of the required square 256 x 256 array.
- A lower clock with more arrays: deferred; it may be reconsidered only with recorded implementation evidence.

## Consequences

Tensor transport, tile count, SRAM operand service, scheduler resources, simulator capacity, and
performance counters derive from this geometry. Numerical formats and external interfaces are not frozen
by this ADR. Changing geometry or the declared logical clock requires a superseding ADR and synchronized
configuration, documentation, simulator, RTL, verification, and traceability updates.
