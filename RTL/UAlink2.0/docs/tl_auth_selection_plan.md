# Shared AuthTags selection implementation plan

Execute independently with the established planning, test-driven and RTL review
workflow. Preserve the complete Endpoint/Controller and Switch goal. Reference
commit is 9994f2d0491e8ae444c88146d1e6e82889afb7af. The actual 640ps STA failure
is −1.057862ns at WIDTH8 and −1.054325ns at WIDTH16; both end at AuthTags.

- [x] Preserve baseline RTL, dependency identities and measured paths under local
  `build/verification/tl_auth_selection/`.
- [x] Try a private shared tag shifter: one common offset by consumed field count,
  followed by the original per-output-slot enable. Keep boundary priority, all
  original outputs, four state bits, reset and handshake. No protocol assumptions.
- [x] Run unchanged independent vectors, strict lint and full RTL CEC at WIDTH8/16
  before actual mapping and five-corner/two-period measurement. Keep failures.
- [x] If measured PPA supports adoption, prove all widths8–16, actual mapped CEC,
  reset and real faults, dual peers at normal/minimum capacity, identical actual
  traces, default compatibility and artifact checks. Update affected fault anchors
  to mutate real tag offset logic, never retain an ineffective unused-signal fault.
- [x] Adopt only a supported improvement, record tradeoffs and locally commit.
  If no improvement, retain current production RTL and the measured evidence.
  Continue real timing-path decomposition/full-top work without relaxing 640ps.

Commands use `verification/tl_control_partition/run_rtl.py --replace FILE --label
NAME`; `verification/tl_prefix_cost/run_equivalence.py --candidate FILE --reference
9994f2d0491e8ae444c88146d1e6e82889afb7af --label NAME --widths 8 16`; then
`verification/tl_prefix_cost/run_timing.py --candidate FILE --label NAME --lib-root
PATH --sta PATH`. Candidate filenames remain `tl_control_partition.v`; generated
proofs/netlists/reports stay ignored. No push in this continuation.

Completed: shared shift adopted after nine-width RTL and two-width mapped CEC,
actual reset/fault checks, 32 peers/96 identical traces, 72 functional faults and
clean-export compatibility. Main timing remains open; next work must address
registered metadata, ownership, backpressure and throughput, then full-top STA.
