# Registered Control metadata implementation plan

> Execute locally with executing-plans and test-driven-development; user requested independent work. No delegation or publication.

**Goal:** capture an entire prepared Control group once, register its decoded metadata, and emit capacity-limited complete fields under backpressure.

**Architecture:** `tl_prepared_partition` owns one captured group. The emitter consumes registered field boundaries, application starts, logical Data accounts and Data counts, plus the captured raw Control/tags/capacity/auth/shared snapshot. It does not decode a cursor-masked source. The existing `tl_control_partition` interface remains available.

**Tech stack:** Verilog-2001, independent Python sequence oracle, Icarus, Yosys, TSMC28/OpenSTA. No Xilinx target scripts.

**Spec:** existing `tl_control_partition_plan.md`, Common 2.0 §5.1.1, §5.8, §5.9; the elastic ownership interface below is a local microarchitecture contract, not a wire-format extension.

## Interface contract

- Inputs: clock/synchronous active-low reset, source valid, output ready, initialization done, response/auth/shared, 256-bit Control, eight 64-bit tags, twenty WIDTH+1 capacity slots. WIDTH remains 8 through 16.
- `o_source_ready = rstn && done && (!owned || o_group_done)`; `o_captured = source_valid && o_source_ready`. Capture transfers ownership, including malformed or oversized groups; it does not indicate successful transmission.
- `o_valid` is derived only from captured state and reset. Once captured, live source, capacity, class and done changes cannot disturb an output stalled by ready=0. New epoch initialization must cancel owned groups with reset.
- `o_taken = o_valid && i_ready`; `o_group_done = o_taken && o_end==8`. Nonfinal acceptance advances the cursor to a complete field boundary. Final acceptance may capture a new group on the same edge. No combinational input-to-output fallthrough; one-cycle initial latency and one-group-per-cycle sustained throughput for single-partition groups.
- Error and capacity shortfall hold ownership until synchronous reset; no partial transaction splitting, implicit discard, or wire success acknowledgment. Reset cancels any owned/partial group, zeros visible outputs/cursor, and disallows capture.
- Invalid payload/field/end outputs are zero. Hidden metadata need not reset: reset clears ownership and cursor. Metadata is written only on capture, remains stable while owned, and is never used to produce valid output while empty.
- Capacity is total physical capacity for the captured initialization epoch. Actual credit balance checks remain in the downstream real port.

## Task 1: executable ownership contract

Files: `model/tl/prepared_partition.py`, `verification/tl_prepared_partition/test_model.py`.

- [x] Write directed tests before implementation. Literal fixtures include four 64-bit response fields, capacity one, tags 101 through 104; retirement must occur in four steps with unchanged raw sector positions.
  ```python
  first = m.step(word, tags, [1]*20, response=True, auth=True, ready=False)
  assert first['captured'] and not first['valid']
  held = m.step(0, 0, [0]*20, valid=False, ready=False, done=False)
  assert held['valid'] and held['tags'] == 101 and held['end'] == 2
  ```
- [x] Observe missing-model failure. Implement `PreparedPartitioner.step(...)` using the existing independent `choose` oracle on owned snapshots. Test stall immunity, simultaneous replace, reset cancellation, malformed ownership, shortfall ownership and throughput.
- [x] Run `python3 verification/tl_prepared_partition/test_model.py`; preserve red/green logs under `build/verification/tl_prepared_partition`.

## Task 2: actual registered RTL

Files: `rtl/tl/tl_prepared_partition.v`, `verification/tl_prepared_partition/run_rtl.py`.

- [x] Generate independent expected streaming vectors before RTL exists; prove elaboration fails for missing module.
- [x] Implement capture registers for raw word/tags/capacity, error/auth/shared and decoded descriptors. Compute suffix contributions as `application[field] && cursor <= field`, and select only registered complete boundaries.
- [x] Compare every public output on every actual clock vector for WIDTH8–16, source noise while owned, legal formats/VC/Pool, auth/shared, sparse NOPs, resets and simultaneous replacement. Count observable capture/retire/cancellation and full-throughput bursts.
- [x] Run real RTL faults for capture, ownership, reset, cursor, tags, metadata and capacity; retain failing traces. Run strict lint and structural synthesis.

## Task 3: real peers and process measurement

Files: `verification/tl_control_partition/run_peers.py`, `verification/tl_prepared_partition/run_timing.py`, mapping/STA scripts for the new top.

- [x] Add explicit `--prepared` mode to actual buffered/SRAM dual peers. A per-lane TB ownership shim drives capture only once while the historical source pointer waits for group retirement; document its inter-group bubble. Default stays unchanged.
- [x] Run normal and minimum queues at both widths/auth/shared/link delays; run the independent existing content/queue/credit trace auditor. Compare content semantics, not old cycle timestamps.
- [x] Map the actual new module with the authorized library, preserve all state and ports, run five corners and both 0.640/6.400ns budgets unchanged. Report failures honestly; no assertion of old four-state CEC applying to the new pipeline.
- [x] Run appropriate compatibility checks, update review/checkpoint and commit locally. Preserve source hashes, logs and failures; clean only completed disposable simulation binaries. Full IP goal, full registered-reference/mapped equivalence, WIDTH8 broad boundary induction and complete-top STA remain open; local ownership induction is proved at both widths.
