# Shorten the selected-ready feedback path

Continue the full dual-IP Goal alone. The current RTL checkpoint is `2228187`; its measured worst paths run from Header FIFO cache-count state through qualification/arbitration to the opposite class's unread-count state. WIDTH 8/16 setup remains −1.853540/−1.861665 ns at 640 ps. The current mapped correspondence has now passed the complete partition, reset, cursor, dormant/capture and actual-fault audits. Preserve that source checkpoint and its measured netlists before changing the RTL.

One remaining redundant dependency is `ready[selected_class]`. With no held class, the arbitration chooses a ready class whenever either is ready, so the selected readiness equals `|ready`. With a held class, readiness must still use `ready[r_hold_class]`, including arbitrary inconsistent source/state combinations. A candidate may express this exact identity directly, bypassing the priority-selection path into the packer header-ready input. Other selected payload, tag, NOP, Data-owner and acknowledgement paths retain their existing semantics until separately justified.

- [x] Establish the ready-selection identity against the actual RTL and retain a failing negative that incorrectly ignores the held class.
- [x] Make the bounded channel-only change; preserve public ports, all eight state bits and cycle behavior. Complete WIDTH 8–16 public-output/next-state and reset equivalence against the frozen RTL reference.
- [x] Rerun independent channel vectors, actual prepared-transmit SRAM peers/ownership checks and the relevant real wiring faults. Audit current source identity and healthy/failing outcomes separately.
- [ ] Map WIDTH 8/16 at the existing libraries, 64 macro interfaces and original IO/clock budgets. Run the full 60-measurement matrix and actual new mapped correspondence; retain the experiment if timing does not improve.
- [ ] Record actual critical paths and remaining setup/hold gaps, then continue full timing closure and the Endpoint/Switch, protocol/payload, digital PHY, INC, security and manageability obligations.

The Boolean identity alone does not establish a physical improvement: synthesis may already simplify some of the dependency, or the critical path may move. Adoption requires measured improvement and complete semantic evidence. This is a next-step plan, not implemented RTL or a completed timing repair.

## Experiment outcome

Rejected after all 60 physical measurements and normal/optimized audits: both widths worsen in area and worst setup. The exact one-line candidate is retained under `ready_rejected_candidate`; the RTL is restored to `6839cac`. The mapped-equivalence part of the adoption gate was not pursued for this rejected candidate and is not claimed complete. See [the experiment review](tl_tx_ready_selection_review.md) and [the next header-visibility plan](tl_tx_header_visibility_plan.md). The full Goal and timing target remain unchanged.
