# Registered prepared Control equivalence plan

Execute locally with the existing writing-plans/executing-plans/TDD workflow; no delegation; existing commits published only under the explicit user push instruction. Full IP scope and 640 ps budget remain unchanged.

**Goal:** establish complete cycle correspondence between the registered metadata module and an immutable complete-field RTL baseline with independent source ownership.

**Architecture:** the reference captures raw Control/tags/capacity/class/auth/shared and instantiates the old `tl_control_partition`. It has its own ownership and cursor; no candidate-derived signals control the reference. Both sides receive identical external inputs. Compare all twelve public outputs, 531 bits, after a real synchronous reset edge. Inputs may change on every subsequent edge, including while either side is stalled or owns a malformed group.

**Reference:** `1e26fbd486ca4ee96de4635fd9a2442801bfc89d`, including its decoder/tenure/admission dependencies. This proves preservation relative to that RTL baseline; independent protocol-format correctness remains supported by the separate Python oracle and specification cross-checks, not by calling shared RTL dependencies independent VIP.

## Execution

- [x] Write `verification/tl_prepared_partition/run_reference.py` before the reference RTL exists. It replays completed independent streaming vectors, compares every output and snapshots immutable baseline sources; preserve the missing-reference failure.
- [x] Add `verification/tl_prepared_partition/reference.v`. Input capture is `valid && rstn && done && (!owned || group_done)`. Once captured, the old splitter receives held raw fields, held attributes, held valid and constant initialized=true; only the reference splitter's last-partition acceptance retires reference ownership.
- [x] Execute reference vectors at WIDTH8/16 and compare with the independent Python sequence oracle. Add actual capture/retirement/class/tag negative variants if the oracle fails to detect an incorrect reference.
- [x] Add a full two-machine sequential miter and preserve actual source port/clock/state inventories before proof lowering. Use one required reset edge; retain arbitrary initial payload state using the tool's explicit nondeterministic initialization encoding. Do not discard an output, turn internal signals into unconstrained cut inputs, or assume the compared outputs equal.
- [x] Run actual sequential proof. A timeout remains unresolved. If decomposition is needed, list and prove each state relation separately before using it as a lemma; a free-signal cut without a proved relation cannot count as equivalence.
- [x] Exercise the proof with actual candidate faults and retained counterexamples. Tie every success to source snapshots, the exact miter, tool scripts and raw logs.
- [ ] Extend to actual mapped artifacts only with verified clocks and all surviving state correspondence. The former four-cursor-state mapped checker is out of scope for this larger machine.
- [x] Update status/review, preserve failures, commit locally. Keep complete protocol proofs, full integrated-top STA, main frequency and both full IPs open wherever evidence is missing.

Commands and outputs are supplied in each executable runner's docstring. Expected reference vector success is all 531 bits at every existing oracle vector; expected proof success is an explicit unconditional post-reset sequential result, not just bounded agreement or simulation.

Result: composed RTL proof passed all nine widths; see `docs/tl_prepared_equivalence_review.md`. Direct PDR remained undecided; mapped equivalence remains open.
