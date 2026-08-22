# OwerFlow Automation and AI Collaboration Rules

This file applies to the entire repository. Deeper `AGENTS.md` files may add constraints but may not
weaken the verification, licensing, or evidence requirements defined here.

## 1. Project Boundary

- The repository covers the path from model semantics through synthesizable RTL.
- External memory, host, and link behavior is represented by versioned digital interfaces and behavioral models.
- Do not add implementation domains below RTL or project-management material unrelated to source delivery.
- Evaluate model, compiler, runtime, RTL, simulator, verification, and documentation impact for cross-layer changes.

## 2. Change Rules

- Read the root README, the target directory README, and relevant `specs/` before editing.
- Do not independently change widths, clocks, addresses, protocol fields, or error semantics before the
  interface is frozen.
- Modify only the requested scope and never remove or revert unexplained user changes.
- Separate hand-written sources from generated files and record source inputs and generation commands.

### Stable Engineering File Names

- Engineering file names must be version-neutral. This applies to RTL and testbench sources (`.v`, `.vh`,
  `.sv`), models, scripts, configuration, manifests, requirements, traceability data, and engineering guides.
- Do not embed release or protocol version tokens such as `v0.1`, `v0.2`, or `v2` in engineering file names.
- Record project release status and protocol revision in the contents of stable explanatory documents such as
  `RELEASE_NOTES.md`; a release must not require renaming source files.
- External dependencies may retain their upstream names on disk, but they must not be copied into a release
  solely to work around this rule. Record such dependencies and exclusions in the release notes.

## 3. Evidence Levels

Every engineering claim uses one of these labels:

- `ANALYTICAL`: formula, capacity model, or declared-clock calculation.
- `FUNCTIONAL_SIM`: functional or non-cycle-accurate execution.
- `RTL_SIM`: cycle-level RTL simulation.
- `FORMAL`: bounded or unbounded property evidence with recorded assumptions.
- `GENERIC_SYNTH`: technology-independent structural synthesis evidence.

Do not call analytical bandwidth measured, generic synthesis a frequency result, or an operator test a
full-model result.

## 4. Open-Source Rules

- Do not commit model weights, private datasets, credentials, license files, or non-redistributable binaries.
- Record source, version, license, checksum, and acquisition method for every third-party dependency.
- Kimi-K3 weights retain their separate license and are not relicensed by OwerFlow.

## 5. Completion

Changes are not complete without applicable lint, tests, simulation, formal checks, documentation, and
traceability updates. A missing required result remains `HOLD`; do not substitute a fabricated result or an
unexecuted command.
