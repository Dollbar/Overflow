# Switch local egress pipeline

The candidate `switch_egress_pipeline` connects the actual production `switch_egress_vc_queues` to the frozen `switch_egress_scheduler`. It produces one complete-packet stream per physical egress while preserving Request/Response class, VC, full payload, token and Last. It adds no buffer, credit owner, reservation state, packet-length decoder or release generator.

The scheduler dependency was frozen before implementation at SHA-256 `cf40a6827f3a3ede11bbb3f4e5b19958d67ad795e037da693d2170a8d58371c0`; its full freeze snapshot is retained in the candidate. Queue RTL was read from production at SHA-256 `50a67eb3a04ee83c7a2efe1236c7f7727853411bc63e6390dfb04603aa1245f3`. Exact dependency snapshots and hashes accompany each run. No production files or inventory are changed by this candidate.

## Interface and unique ownership

PORTS and VCS independently support 1/2/4. Parameters preserve queue DATA_WIDTH=544, TOKEN_WIDTH=8, UNIT_WIDTH=4, DEFAULT_CAPACITY=4 and CAPACITIES, then append scheduler RSP_BURST_MAX=2. The slot index is `(response*VCS+vc)*PORTS+egress`; Request=0 and Response=1. CAPACITIES, accounting, release and selected buses all use that same order.

All source header/body inputs, header/body ready and queue diagnostics pass directly to the single real queue wrapper. A header handshake reserves the full packet exactly once and establishes the source's saved domain/egress/token. Subsequent body ownership uses that saved state despite changing candidate route, class, VC or header token. The final body write releases only source write ownership. It does **not** release buffer capacity.

The queue's complete heads feed scheduler `i_valid/data/last/token`. Scheduler `o_ready[slots]` is the queue's only consumer-ready input. Physical `i_ready[PORTS]` feeds scheduler `i_ready`, and its physical `o_valid/data/last/token/vc/response` are the pipeline outputs. The queue's own last-word dequeue alone emits `o_release_valid/units` and returns its original complete reservation. Scheduler has no release or reservation port; its packet completion is never counted a second time.

`o_selected[slots]` and `o_owned[PORTS]` expose the scheduler's actual selection and physical packet lock. A first visible head stalled by physical ready remains owned even if a higher-priority class arrives later. Packet lock persists through queue prefetch bubbles. Only a real valid/ready/Last handshake completes it. Each egress is independent. Queue account observations remain unchanged. `o_error` is the queue's existing diagnostic aggregate; this wrapper invents no scheduler error/recovery protocol.

Both components receive exactly the same synchronous low reset. It cancels stored and scheduled packet ownership together; callers must not reset one half independently. This is a local digital packet interface, not a standard TL destination parser or a complete wire-protocol scheduler. Existing scheduler bounded Response preference is inherited; this integration does not re-prove network deadlock freedom or cycle-bounded fairness.

## Verification

TDD retains the actual missing-module elaboration RED under `red/`. The first integration attempt (`first`) had a testbench delta-cycle header sampling error and failed all healthy cases; those results remain failed. Its generic failure-marker mutation labels are not credited as useful fault evidence. `handshake_corrected` fixes the test stimulus timing. The historical `frozen` snapshot preceded a comment-only cleanup. Final evidence uses `final_freeze` and `final_freeze_optimized`, which pin the actual installable RTL and use fault-specific checker markers.

Each final invocation passes all nine PORTS×VCS combinations at DATA_WIDTH544/TOKEN_WIDTH8/UNIT_WIDTH4/default capacity4 and RSP_BURST_MAX2, plus five actual source wiring mutations. The SV oracle maintains independent per-slot admitted-packet lists, source body owners, physical output packet owners and integer reservation/stored/completed ledgers. It records real external handshakes and never reads internal DUT state. It does not compute a second copy of scheduler arbitration: any scheduled token must be the actual expected head of its original class/VC/egress and retain physical packet ownership until Last.

Three rounds populate each class/VC/egress slot with a packet of one to four complete 544-bit words before draining. Tests change candidate route/class/VC/header token during body ownership, insert body gaps, hold physical outputs while new classes arrive, vary per-egress ready, preserve payload/token/Last across stalls, and cancel a genuinely owned complete packet with common reset. Every noncancelled packet must be admitted once, complete once and release once with its original length. Across the nine healthy configurations: **2,944 cycles, 303 admitted packets, 294 completed packets and releases, 737 output words, 5,746 stalled-egress observations, and nine reset cancellations**. A stalled-egress observation is one valid/not-ready physical port per edge and may exceed total clock cycles.

Five compile-success/runtime-failure mutations are retained:

| Wiring fault | Required checker |
| --- | --- |
| Queue ready forced high, bypassing physical sink | `PIPELINE_RELEASE_ONCE` |
| Body token wired from changing new header token | `PIPELINE_UNEXPECTED_ERROR` |
| Physical Response class forced to Request | `PIPELINE_CLASS_VC_TOKEN` |
| Physical VC forced zero | `PIPELINE_CLASS_VC_TOKEN` |
| Physical Last forced zero | `PIPELINE_PAYLOAD_LAST` |

All nine healthy actual hierarchies pass Icarus Verilog-2001 elaboration, strict Verilator `-Wall` with no waivers and Yosys `proc/opt/check -assert`. The generated hierarchy independently confirms one queue wrapper, one scheduler, exactly 2×VCS reservation owners, 2×VCS packet queue instances and 2×VCS×PORTS real `upli_receive_fifo` instances, with zero latches. This is local synthesizable register storage; no KD28 SRAM mapping, macro STA, FPGA implementation or PPA is claimed. Skill artifact validation passes 83/83 commented lines with zero errors/warnings using the appropriate purely hierarchical scope; the full hierarchy reset and synthesizability are checked by the actual tools/tests. Whole-skill external cleanup is not run because it would modify files outside candidate ownership.

The matrix uses uniform capacity4 and default Response quota2. Arbitrary capacities/quota limits retain their leaf contracts and have not been exhaustively re-tested here. Sources are driven sequentially during packet construction; contention fairness beyond the completed queue-head scenarios is a leaf-level claim. No protocol format, route-table update, CDC, independent LinkDown recovery or full Switch interoperability completion is implied.

## Install and reproduce

`freeze.json` lists the four installable release files, all dependency hashes, final commands/results and per-configuration statistics. The runner uses `ROOT=Path(__file__).resolve().parents[2]`, snapshots each source once and hashes exactly the bytes it compiles. Fresh labels are required; outputs go to `ROOT/build/verification/ip_tops/switch_egress_pipeline/LABEL`.

After installing scheduler and pipeline release files into production:

```sh
python3 /PATH/UALink/verification/ip_tops/run_switch_egress_pipeline.py --label NEW --faults
python3 -O /PATH/UALink/verification/ip_tops/run_switch_egress_pipeline.py --label NEW_OPT --faults
```

To run the isolated candidate before installation, use its release runner and append:

```sh
--rtl /PATH/CANDIDATE/switch_egress_pipeline.v \
--scheduler /PATH/FROZEN_SCHEDULER/switch_egress_scheduler.v \
--project-root /PATH/UALink
```

Next connect this local physical-egress stream to the explicitly supported TL formatting/link profile. Existing unique capacity ownership must remain unchanged at that integration boundary.
