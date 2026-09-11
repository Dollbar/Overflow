# Shared prefix cost implementation plan

Execute independently with writing-plans, executing-plans, test-driven-development
and erie-verilog-generator. Preserve the full Endpoint/Controller and Switch Goal.

Goal: shorten the measured Control-to-Auth path by sharing field cost decoding and
balanced prefix totals, without changing ports, clocks, state, latency or accepted
input behavior. The red performance baseline is the actual `static_reduction`
mapping: both widths fail all five main-clock corners, worst setup −1.250022 ns.

- [x] Preserve the current `1bc57c1` source and actual failing timing evidence.
  Work first on a private `tl_control_partition.v` candidate; keep the independent
  Python model and existing vector expectations unchanged.
- [x] Decode the cursor-masked suffix once using the existing real decode/tenure
  modules. Derive each field's original CMD/Data account and Beat contribution,
  including shared Data pool normalization. Reuse balanced per-account prefix
  sums at all eight complete boundaries. Original source format diagnostics,
  selected field count, field bits, tag order and handshake remain unchanged.
- [x] Check arbitrary-state binary equivalence against the preserved full RTL
  using the audited named-state CEC flow, including original outputs and all four
  next-state bits. Do not assume the cursor is at a legal source boundary to hide
  differences. Keep one-edge reset checks and actual fault detection.
- [x] Run the unchanged independent unit vectors and actual dual-peer normal and
  minimum storage configurations; compare all actual traces with the baseline.
  Run relevant lint, synthesis and artifact checks on any retained candidate.
- [x] Measure actual TSMC28 mapping with the unchanged script and all five corners
  at both periods. Recheck actual mapped equivalence before adopting improvements.
  Preserve failing candidates and reports; do not report projected timing as STA.
- [x] Update evidence/status and locally commit only supported outcomes. Main-clock
  closure and complete integrated IP remain requirements even if this step improves
  area or delay without meeting the main period. Publication follows the user’s explicit 2026-09-11 push authorization.

Files: candidate and private proof scripts under
`build/verification/tl_prefix_cost/`; eventual retained RTL in
`rtl/tl/tl_control_partition.v`, reusable checks under `verification/tl_prefix_cost/`.
Use `verification/tl_control_partition/run_rtl.py --replace <candidate>` first.
Outputs are local vectors/logs, actual netlists, proof and timing records. Next:
integrated timing and complete UPLI/per-VC/remaining protocol work.

Completed: unchanged independent vectors, nine-width RTL CEC, two-width mapped CEC,
reset/fault checks, 32 real peer configurations and all 96 identical traces. The
reusable timing runner reproduced both exact mapped netlists and all 20 STA
results. Main-clock violations and full integrated IP requirements remain open.
