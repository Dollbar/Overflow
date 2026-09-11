# Prepared transmit integration implementation plan

Execute alone using writing-plans/executing-plans, TDD and the RTL review workflow.

**Goal:** place the registered complete-group preparation and actual SRAM transmit queues in one production RTL module, with capture-based producers and no retirement shim.

**Architecture:** `tl_tx_prepared` contains two `tl_prepared_partition` instances feeding one `tl_tx_buffered`. Request and Response capture independently. A source group comprises 256 Control bits and eight 64-bit tags; Auth requires both valid signals at capture. Source capture, final partition enqueue, and actual wire consumption are distinct observable events. Data/BE and FC follow the unchanged actual buffered path. Auth/shared/capacity configuration remains stable for the initialization epoch; reset flushes the whole combination.

**Contract:** `docs/tl_prepared_partition_plan.md`, `docs/tl_tx_buffered_plan.md`, `docs/tl_cost_compression_review.md`. Immutable starting commit `cdc943ca8e38fb3b67e4671049afa5c36968bc40`. No wire format or unconfirmed protocol decision changes. Full Endpoint/Switch, PHY/INC/security/manageability and 640 ps requirements remain open.

- [x] Extend the existing actual dual-peer test to instantiate the production wrapper and advance source data/tags on capture. Keep retirement and actual FIFO enqueues independently counted. Observe a missing-module failure before implementation.
- [x] Implement `rtl/tl/tl_tx_prepared.v` in Verilog-2001 with Chinese explanatory code comments. Preserve the old buffered API. Expose capture/tag capture, group queued, partition queued, preparation errors and existing actual wire/queue observations.
- [x] Add independent two-lane reference checks for actual source capture and partition data; exercise missing tags, source changes after capture, stalled queues, simultaneous replacement, reset and invalid groups.
- [x] Run actual dual SRAM/credit peers across WIDTH 8/16, Auth/shared modes, link delays and normal/minimal queue depths. Audit source/partition/queue/wire traces with separate counters and actual negative wiring tests.
- [x] Run strict lint/artifact and meaningful compatibility checks. Audit single clock/reset integration. Full new-top process STA remains an explicit next obligation; submodule timing cannot establish it.
- [x] Review source-bound evidence, update project checkpoint and commit locally. Keep raw passed/failed traces and private dependencies; clean only terminal wave/compiled caches. Do not push.

Files: new `verification/tl_tx_prepared/integrated_tb.py` transforms only the reused peer test wiring/producer; `run_peers.py --integrated` selects it. New dedicated checks live under `verification/tl_tx_prepared`. Runner docstrings describe commands, output paths and next gates.
