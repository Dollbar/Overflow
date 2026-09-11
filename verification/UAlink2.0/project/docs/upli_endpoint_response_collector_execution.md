# Endpoint native response collector — local retirement adapter

This candidate connects selectable protected native Read Response and Write Response heads to an Endpoint consumer. It preserves complete Read 619-bit and Write 101-bit payloads, original physical port, VC, Pool and account. It has no payload FIFO, Tag table, credit bank or credit-return queue. The existing `upli_native_rx_channel` remains the unique SRAM/account journal/credit owner. An independent verification ledger observes its actual credits; duplicating that ledger as a second hardware credit issuer would return each credit twice.

The scope derives from existing production native RX interfaces and the Common 2.0 boundary mapping in `docs/upli_native_rx_execution.md`: §2.7.5/Table 2-15 and §2.7.6/Table 2-18 describe response fields; the collector transports fields without interpreting transaction eligibility. Read poison/error data, authentication tags, debug Src, NumBeats/Offset/Last and Write TypeInfo remain intact. Arbitrary field-preservation stimuli do not prove that every tested record is a legally executable response. In particular, ISOLATE must be handled by the downstream control path, never assumed to be an ordinary Tag completion.

## Frozen interface and ownership

`C_NUM_PORTS` accepts 1, 2 or 4; other values fail elaboration. Clock/reset are `i_clk` and synchronous active-low `i_rstn`. All two-channel buses use **low item Read, high item Write**, unlike the four-kind native index scheme.

- `i_select_valid[1:0]`, `i_select_port[3:0]` select independent physical ports. `o_consumer_port[3:0]` connects directly to the corresponding original RX consumer selector.
- Inputs `i_head_valid`, `i_consume_valid`, `i_head_vc`, `i_head_pool`, `i_head_account` and `i_read_payload[618:0]`/`i_write_payload[100:0]` come from those selected RX heads. `head_valid` means a protected head; `consume_valid` additionally requires original credit-return reservation space.
- Outputs `o_response_valid`, full payload and original metadata describe the same heads. `o_response_port` always equals the current query port, including when invalid; payload/VC/Pool/account are zero while invalid. No output declares application completion or Tag eligibility.
- `i_retire_ready` is the downstream consumer's real acceptance qualification. `o_consumer_ready = o_response_valid & i_retire_ready`; `o_retired` is the exact same event. Only this handshake retires original SRAM and causes its single existing return queue to retain the original VC/Pool. There is no separate credit output from this adapter.
- Once a selected protected head is observed without retirement, its port is locked even if credit-return space is unavailable. New selectors and withdrawn selection-valid cannot replace that head. Only retirement or common reset releases the lock. The RX owner must retain its head until that handshake. No automatic empty-port polling, fairness scheduler or cross-channel ordering is added.
- `i_stop` suppresses business outputs/retirement immediately while preserving the port lock. It must accompany the matching RX/role stop as required by integration. It does not reset or gate previously registered credits.
- `o_metadata_error[1:0]` diagnoses an invalid selected port or a valid head whose account is not `Pool ? 4 : VC`. A newly detected error immediately suppresses both Originator response paths; `o_fault_stop_request` remains asserted until reset. It requests the external role controller's action and implements no Isolation/recovery. Invalid unselected metadata is ignored; selectors changing while an old head is locked are not new accepted selections.

Read payload layout, high to low: `{Auth64,Src10,Dst10,Tag11,NumBeats2,Data512,Status4,Offset2,Last1,DataError1,TypeInfo2}`. Write: `{Auth64,TypeInfo2,Tag11,Status4,Src10,Dst10}`. Fixed widths prevent changes to the native ABI.

## Verification and retained evidence

The portable runner and SV tests are under `verification/upli_channels/`. Normal and Python `-O` runs use distinct labels. Each final run has 17 passing cases: three unit configurations, five unit RTL mutations, one illegal-port elaboration rejection, three real dual-native-RX/KD28 simulations, and five integration source mutations. Each healthy unit configuration passes Verilog-2001 elaboration, strict Verilator `-Wall` with no waivers, and Yosys `proc/opt/memory_map/check -assert`. Skill artifact validation covers 79/79 commented code lines with zero errors/warnings. Whole-skill cleanup/workflow execution is not run because it would modify files outside the isolated candidate directory; no whole-skill certification is claimed.

Unit checks execute 15,337 total sampled rows for ports 1/2/4, walking all 720 payload bits, all account/port classes, credit-space stalls, independent response readiness, selector changes during locks, stop, reset, and metadata rejection. The integer reference owns its state and never reads RTL internal state. Five actual candidate mutations test lost port lock, Pool corruption, high Read payload loss, ignored downstream ready and ignored stop; each compiles successfully then fails the checker.

Real integration instantiates two existing native RX channels, with actual KD28 behavioral macros and unique original credit queues. Three rounds fill every configured account to its actual capacity three before draining. Ports 1/2/4 execute 335/509/885 cycles, respectively; together 633 accepted records comprise 630 real retirements and three reset cancellations. Original response FIFO order, every payload bit, VC/Pool/account, initial capacity and exact per-port credit totals are checked independently. A second chronological credit journal verifies each returned original VC/Pool, including Pool records with distinct VC, before retiring its verification entry. Long/asymmetric application backpressure, simultaneous channels and external Drop/stop preserve ownership. Integration mutations corrupt Pool, readiness, port lock, high payload, and the actual original return queue's saved VC; all compile successfully and fail runtime checks. No DUT memory or state is used as expected data.

Retained historical evidence includes missing-module TDD RED for all three port configurations; `first_matrix`; `receive_first` whose final reset-preparation record was missing from the **test** ledger; corrected `receive_corrected`; and the original skill comment-placement failures. The reset preparation now records its actual acceptance and cancellation. Historical failed results remain failed. Final snapshots, commands, timing, logs and SHA-256 manifests are retained by label; `freeze.json` identifies installable files.

## Reproduction and next boundary

After installation, run from any cwd:

```sh
python3 /PATH/UALink/verification/upli_channels/run_response_collector.py --label NEW --faults --receive --kd28-root /PATH/AUTHORIZED_KD28
python3 -O /PATH/UALink/verification/upli_channels/run_response_collector.py --label NEW_OPT --faults --receive --kd28-root /PATH/AUTHORIZED_KD28
```

The runner uses `ROOT=Path(__file__).resolve().parents[2]`, reads production RTL under ROOT, verifies the existing KD28 dependency manifest, and snapshots each file once for matching compilation/hash evidence. Outputs are `ROOT/build/verification/upli_channels/response_collector/LABEL`; existing labels are never overwritten. For isolated candidate verification, add `--rtl CANDIDATE/upli_endpoint_response_collector.v --project-root /PATH/UALink` to the release runner invocation. No candidate-only source dependency is required after installation.

Next integrate the consumer's real Tag/transaction eligibility and dedicated control-event handling with these atomic retire inputs. This deliverable alone is not a complete Endpoint, complete station/RX RAS controller, authentication implementation, certified protocol stack, or macro timing signoff.
