# Requirements and Traceability Management

## 1. Requirement IDs

Requirements use `<DOMAIN>-<NNN>`:

- `SYS`: end-to-end workload and logical system behavior.
- `MOD`: model semantics and numerical references.
- `CMP`: compiler and IR.
- `ISA`: instruction set and executable semantics.
- `RUN`: runtime, driver, and firmware.
- `NPU`: NPU RTL and memory transactions.
- `KDL`: KDLink endpoint, PCS, router, switch, and collectives.
- `VER`: verification and evidence.
- `REL`: repository and release integrity.

## 2. Requirement Quality

Requirements are measurable and verifiable. Avoid terms such as high performance, low latency, or scalable
without a threshold and a stated evidence method. Every requirement includes an owner, consumer,
verification method, evidence level, and status.

Changes spanning multiple domains require an ADR. Interface changes update the producing specification,
all known consumers, compatibility tests, and migration guidance together.

## 3. States

- `PROPOSED`: under review and not binding.
- `BASELINED`: accepted as an architecture target.
- `IMPLEMENTED`: source exists but required evidence is incomplete.
- `VERIFIED`: required evidence level is satisfied.
- `HOLD`: blocked by a named missing result or failed gate.
- `RETIRED`: removed through a controlled change.

The machine-readable source is `requirements/traceability.csv`; prose summaries do not replace it.
