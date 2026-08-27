# KDLink Coverage

Run the source-level coverage gate from the repository root:

```bash
python3 verification/kdlink/scripts/run_coverage.py --jobs 4
```

The script instruments line, expression/branch, FSM, and toggle coverage, executes the selected portable
RTL regressions, strips testbench records, removes elaboration hierarchy from otherwise identical source
points, merges the databases, and checks these thresholds:

- line: at least 95 percent;
- branch: at least 90 percent;
- toggle: at least 95 percent.

## Reviewed Exclusions

The toggle gate sets `--coverage-max-width 64`. Payload buses wider than 64 bits, wide tensor arithmetic,
packet memories, replay memories, and FIFO storage arrays are excluded from the toggle denominator. Their
correctness is checked by bit-exact scoreboards, CRC/replay tests, queue invariants, and synthesis/static
timing gates. This exclusion prevents data values and memory capacity from being mistaken for control-state
coverage.

Testbench and behavioral-model source paths are removed from the release metric. Reset-only implementation
nodes and tool-generated temporary signals are not enabled with `--coverage-underscore`.

Source pragmas exclude only reviewed defensive branches that cannot be reached by the legal transition
relation: unused encodings of multi-bit state registers, exhaustive one-bit-state defaults, the compile-time
`STAGE_COUNT` default, reserved RX response-event combinations, and the FP32 minimum-normal promotion guard.
The `coverage_reachability`, `route_pair_order`, `route_stage_scale`, `spine_escape`, and `rx_exact_once`
formal jobs record the corresponding reachability evidence. The recovery logic remains present in synthesized
RTL; only its source coverage points are removed from the denominator.

Raw databases and compiler objects are written below `verification/kdlink/coverage/work/`. The checked
summary is written to `verification/kdlink/coverage/summary.json`.
