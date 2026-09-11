# UALink source delivery

This snapshot imports 1120 tracked source files from the UALink development
repository at commit `59c4bdf1784eab17fa697733953c385d4410193d`. The [ownership manifest](.ualink-export.json)
records original and exported hashes, deterministic path adaptations and relative links.

- [Digital RTL](../../rtl/UAlink2.0/): Endpoint/Switch tops and implementation/scaffold modules.
- [Verification](README.md): self-checking SV/Verilog benches, formal checks and [shared package](pkg/ualink_test_pkg.sv).
- [Simulation](../../simulator/UAlink2.0/): reference models and [memory VIP](../../simulator/UAlink2.0/vip/ualink_memory_vip.sv).
- [Project workflow](project/README.md): scripts, configuration and bounded evidence summaries.

The former uppercase `RTL/UAlink2.0/` publication is removed. No build result, waveform,
private specification, licensed PDK or external library copy is published. Existing
Overflow files are preserved except the three namespace README entries and mechanical
REUSE path refinements; existing license assignments remain unchanged. UALink sources
still have no assigned license; this import creates no new copyright or license grant.

From the Overflow root (Python 3.10+, Make and Icarus Verilog; Yosys for formal/structural checks):

```sh
cd verification/UAlink2.0/project
python3 verification/endpoint_transaction/run_read_endpoint_switch.py --kd28-root ../../.. --label your_fresh_label --matrix --inject --bank-depth 1
python3 verification/endpoint_transaction/run_transactions.py --vip-selftest --label your_fresh_vip_label
make test
```

Expected outputs are in project `build/` or `reports/`, ignored by Git. Use a fresh label.
`KD28_ROOT=../../..` explicitly selects the containing Overflow checkout and still validates
its functional SRAM source hashes. The four relative directory links provide one project
root without duplicate source files; see [layout details](project/docs/overflow_layout.md).

This verification increment closes the full ordinary Read uniform-reset test matrix:
ten normal cases across bank depths 1/3, exact partial response counts 1/2/3, backend
pending and held-completion windows. Twenty old Reads were cancelled; eighty new Reads
reused Tags and completed correctly while prior Write memory contents remained intact.
Four actual missing-reset/cancellation wiring faults were detected. Production RTL is
unchanged by this increment. Independent LinkDown and protocol epoch recovery remain open.
See the [Read reset review](project/docs/endpoint_read_reset_review.md) and
[evidence](project/docs/endpoint_read_reset_evidence.json).

The preceding Switch increment replaces three Switch shells with real packet ownership/round-robin
arbitration, full-width data fabric, and an atomic shadow/active route table. All three
are connected in ualink_switch_top. Static routes remain the default; ROUTE_CONFIG_ENABLE=1
adds a local explicit write/commit interface. Commit requires no ingress valid and no
packet owner, including during packet bubbles; rejected commands preserve the active table.
This is a local sideband unicast service, not standard CSR mapping or per-hop TL/DL routing.

Actual top packet tests delivered 7,097 complete words in 3,033 packets across ports 2/3/4/5.
Configuration checks covered ports 1/3/4/5 in both modes (195 checks); two real wiring faults
were detected. The refactored ESE again completed 812 mixed transactions with 8 replays.
Leaf simulation and static checks, whole-project make test, and configuration-enabled
Yosys elaboration passed. No process STA or full protocol completeness is claimed.
See the [Switch integration review](project/docs/switch_integration_review.md) and
[bounded evidence](project/docs/switch_integration_evidence.json).

The preceding Read increment implements full ordinary uncompressed Read with DWORD lengths 4..256B,
first/last byte masks, complete 2048-bit backend results and all expected response Beats.
Single-mode responses allow arbitrary offsets; multi-mode reception reconstructs offsets
and finality from length. Error responses still collect every expected Beat before retirement.
Application data is masked locally; ignored wire bytes need not be zero.

Three actual Endpoint/Switch cases completed 1,652 transactions, including 12 actual Write
executions and 8 replays. The independent model and RTL encoder each checked 532,480 legal
geometry/ATTR masks. Receiver/Tag checks separately cover multi-mode responses; ESE TX uses
single mode. Uniform Write reset passed three in-flight windows at two bank depths, with
108 new-epoch completions and memory preservation checked through real Read requests.
See the [Read review](project/docs/endpoint_read_integration_review.md),
[bounded evidence](project/docs/endpoint_read_evidence.json) and
[independent model review](project/docs/endpoint_read_model_review.md).

The default capacity matrix remains 29/29; old Write bank1/replay compatibility completed
566 transactions. Source make test passed, including 199 tool tests with two conditional
skips. After export, the full Read matrix at bank1 with replay completed 812 transactions;
the independent Read model with four actual mutations and full-Read-only write-rejection
check also passed from these published directories before pushing.

The inventory is 202 RTL entries: 72 partially implemented and 130 disabled interface
scaffolds. Set TRANSACTION_MODE=1 and FULL_READ_ENABLE=1 for the documented complete ordinary
Read profile; WRITE_ENABLE=1 independently adds ordinary Write/WriteFull. Defaults preserve
the earlier fixed Read subset. Strict core lint still reports 15 warnings per Write setting;
new-top process STA is open. Independent LinkDown/epoch,
native UPLI, standard per-hop routing/framing, PHY, INC, security, management and CDC/RDC
remain unfinished. This snapshot is not a complete Endpoint/Switch protocol delivery.

The upstream cleared RTL namespace README and added KD-UAlink2_0.png remain preserved.

After this export, the real top configuration test including both actual wiring faults,
the arbiter port1..5 simulation/static suite, and the complete Read ESE bank1/replay matrix
were repeated successfully from the published layout before pushing.

The bank1 exact-three-Beat reset case and actual missing-Endpoint-reset fault were rerun
successfully from the exported layout before pushing. Upstream 25ecfd1 and its uploaded
UPLI controller pin diagram are preserved as unowned user content.

## Native Request / OrigData sender increment

Typed Request/OrigData leaves now use a shared parity primitive, with an actual one-sender/two-credit-bank native transmit wrapper. Inventory: 203 modules, 76 partial implementations and 127 explicit shells. Final-source tests cover 970 Request, 3688 OrigData and 7084 parity vectors, actual 1/2/4-port shared credit/TDM sending, 16 simulation faults and two formal counterexamples. Full-output combinational equivalence, strict static checks, structure checks and repository make test pass; full Read partial-response uniform-reset compatibility also passes.

Relocated shared sender tests including faults/static checks, OrigData real sender matrix, and shared parity equivalence have been rerun from this published layout. The first CEC relocation failure was fixed in the source root expression; no RTL change was required. Tests and fixtures live under verification/UAlink2.0/upli_channels. Complete station/Endpoint native adapters, response integration, RX/RAS, independent LinkDown, protocol completion, CDC/RDC and process STA remain open. See project/docs/upli_native_sender_integration_review.md for commands and scope.

## Native Read / Write Response field increment

All four native channel types now have typed transmit fields and parity RTL. Final Read Response tests passed 7396 vectors and eight actual faults; Write Response passed 3508 vectors and five actual faults, with strict static checks. Independent cross-review found no concrete field/parity/reset wiring defect. Current inventory is 203 entries, 78 partial implementations and 125 explicit shells (Endpoint/Switch pending slots 93/118). Structure and actual full Read partial-response reset compatibility pass. Relocated Read normal/fault/static tests plus Write normal/static and control-parity fault pass in this repository layout.

Response credit/TDM sender candidates and credit guard/return adapters are the next parallel tasks; full native station/Endpoint integration and process STA remain open. Read Response debug Src is preserved per Beat and will not be used for functional sender admission. Commands and exact scope: project/docs/upli_response_integration_review.md; next integration contract: project/docs/upli_station_integration_execution.md.

## Native response senders and TX/SRAM loop

Five new partial implementations provide Read/Write Response credit/TDM senders, a credit parity guard, a direct returned-credit adapter and a three-sender aggregate. Current inventory: 208 entries, 83 partial implementations, 125 explicit shells; Endpoint/Switch pending slots remain 93/118. Five actual 1/2/4-port configurations at credit widths3/4/16 and capacities4/5 complete 1480 native beats through SRAM and retire them. Uniform reset cancels 249 sent/unretired payloads; new rounds show no old-data leakage. Final g2001, strict lint, Yosys, structure, repository make test and existing full Read reset compatibility pass; 17 actual sender/adapter/aggregate faults are detected.

Read sender final production matrix covers30351 cycles; Write sender production wide run covers1552 cycles/467 sends, with identical frozen RTL also validated across six configurations. Credit adapters cover3418 independent vectors. Independent aggregate bit-level review checks three senders/four guards, four banks and distinct capacity mapping. Evidence and exact commands: project/docs/upli_station_tx_integration_review.md.

Relocated Read sender full matrix/faults, Write sender wide/static, credit adapter actual SRAM integration and station port4/width16/capacity5/static plus actual guard fault have passed from this publication layout. The aggregate tests independent response streams, not backend-derived native response causality. Complete native RX ordering/validation, required poison/Drop policy, Endpoint context adapters, independent LinkDown/epoch and process STA remain open. Diagnostic-only credit guards do not implement required corrupted-credit discard/recovery.

## Native receive ordering and TDM observation

Two new partial implementations observe receive-side TDM phase and preserve each port's chronological acceptance order across the five VC/pool SRAM accounts. The ordered wrapper retains payload storage in the existing receive channel and adds only the account journal. A detected journal/SRAM mismatch now blocks retirement and credit return while reporting current and sticky errors. Current inventory: 210 entries, 85 partial implementations and 125 explicit shells.

The final 1/2/4-port ordered matrix ran 8,736 cycles with 3,699 accepted Beats, 3,696 retired and returned Beats, and three deliberately reset-cancelled pending Beats. Three live wiring/data faults were detected. TDM unit tests covered 24,923 slots; real station integration covered 3,483 edges and 1,034 native events, detecting phase, idle and cross-channel faults. Strict lint, Yosys structural checks, structure validation and the source repository test suite passed.

Relocated ordered receive and TDM tests are rerun from this published layout before pushing. Full native channel parity conversion, per-Beat poison and Drop handling, burst ownership, Endpoint request/context causality, independent LinkDown/epoch and process STA remain open. See `project/docs/upli_ordered_receive_channel_execution.md` and `project/docs/upli_native_rx_execution.md` for commands and the bounded scope.

## Protected native receive, Endpoint request holding and Switch capacity

Three native receive/Endpoint modules and one Switch capacity module now replace or supplement prior shells. Four native channel kinds check received protection, convert data or byte-enable errors to per-Beat poison, store protected envelopes in the ordered SRAM path, and return credits from the original account. A complete Endpoint holding assembles Request184 and up to four OrigData Beats while preserving Port/VC/Pool/Auth/Src/Tag. Switch egress admission now reserves all buffer units for a packet atomically with independent per-egress round-robin service. Inventory: 213 entries, 89 partial implementations and 124 explicit shells; pending role bits are Endpoint 93 and Switch 117.

The protected native receive matrix covers four kinds and 1/2/4 ports over 152,957 sampled edges, with 9,529 accepted Beats, 9,517 retirements, 12 reset cancellations and six detected RTL faults. The Endpoint bridge completes 981 descriptors and 2,459 actual SRAM head transfers with the same number of original-account credit returns; long backpressure, Read/Write queue overlap, reset and four RTL faults pass. Switch reservation normal and optimized runs each cover four configurations and 3,970 cycles, detecting six RTL faults; nine static checks pass. The repository suite passes 403 model and 199 tool tests with two conditional skips.

The corresponding normal, fault and static runners are rerun from this published layout before pushing. Native role-level Drop/Isolation, authentication, burst monitoring, actual station/top wiring, Endpoint backend-derived response causality, Switch egress queues and VC/request-response partitions remain open. Process STA has not been run for these new modules. See `project/docs/upli_native_rx_channel_execution.md`, `project/docs/upli_endpoint_request_bridge_execution.md` and `project/docs/switch_credit_reservation_review.md`.

## Endpoint native RX frontend and Switch VC queues

The production tree now adds an Endpoint native receive frontend, a role-scoped receive fault controller, a single-resource Switch packet queue, and Request/Response/VC-partitioned Switch egress queues. Inventory: 216 RTL entries, 93 partial implementations and 123 explicit shells; pending role bits are Endpoint 93 and Switch 116. The Switch VC queue replaces slot55 while keeping its stable bit assignment.

The Endpoint frontend connects four protected native RX channels, one three-phase monitor and the complete Request/OrigData holding bridge. Normal and optimized source runs each cover 1/2/4 ports and complete 216 descriptors, 1,341 SRAM head transfers and 1,341 original-account credit returns. Drop admission/cancellation/reset recovery is covered, and four actual wiring faults are detected. The role controller covers nine parameter configurations and 19,530 unit slots plus nine real RX/SRAM cases; forward Beat errors and reverse-direction returned-credit errors retain distinct Originator/Completer ownership.

The single-resource packet queue covers 7,600 normal and 5,700 illegal-input cycles and detects seven RTL faults. The VC combination covers 6,900 normal and 13,800 illegal-input cycles, all 40 enabled slots and two disabled slots, detecting five RTL faults. It accepts 2,234 headers and 4,693 body words and retires 2,220 complete packets; Response resources continue while Request is full, and independent VCs continue while VC0 is full. Complete-packet reservation occurs once and is released only by the final output-word handshake.

All new production runners pass from this published linked layout, including Endpoint 1/2/4-port static checks, its four wiring faults, the role controller real-RX matrix and faults, and both Switch queue fault/static suites. The first relocated Endpoint run exposed a runner-only path-classification bug because the project RTL link also resides below the Overflow checkout; commit `842d9a0` restricts external hash checks to exact manifest paths, and the final published rerun passes. Repository tests and generic synthesis of both existing tops pass in the source checkout.

The Endpoint response collector and backend-derived causality, full role Isolation/dummy completion/recovery epoch, Switch ingress classification/physical egress scheduling/repacking/top connection, standard per-hop TL/DL, CDC/RDC and process STA remain open. See `project/docs/upli_endpoint_native_rx_path_execution.md`, `project/docs/upli_rx_role_fault_controller_execution.md`, `project/docs/switch_egress_packet_queue_review.md` and `project/docs/switch_egress_vc_queues_review.md`.


## Native Endpoint IP frontend and Switch physical scheduler

Five new partial implementations raise the inventory to 221 RTL entries: 98 partial implementations and 123 explicit disabled shells. `upli_endpoint_response_collector` retires complete Read/Write heads through the existing native RX consumer boundary, which remains the sole credit-return owner. `upli_endpoint_ip_top` connects the two role connections, the actual four-channel transmit station, protected four-channel receive path, response collector and the unique role fault controller. Its explicit `o_backend_implemented=0` boundary records that backend execution and Tag completion remain open.

The production Endpoint layout passes 1/2/4-port non-TL and 4-port TL-scope cases. Each case accepts 50 descriptors and accounts for 301 receive heads and returns; five real wiring mutations are detected. The standalone collector normal and optimized matrices cover 15,337 unit slots and actual protected-RX transfer/retirement, with ten source mutations detected. The diagnostic burst monitor covers 7,877 unit slots and observes 5,109 actual native-path edges, 271 Requests and 440 Data Beats; ten mutations are detected. It consumes explicit command classification and existing TDM phase and owns no traffic filtering, credit, Drop or TDM state.

`switch_egress_scheduler` selects the Request/Response/VC-partitioned queues onto one stream per physical egress, locks ownership from the first offered beat through the final accepted beat, and applies bounded response preference plus per-class VC round robin. Four configurations cover 8,300 cycles and 2,764 completed packet services; seven actual RTL mutations and twelve static checks pass. It generates no reservation or release events. `switch_egress_pipeline` now connects the real partitioned queues to that scheduler across nine PORTS×VCS configurations: 303 packets are admitted, 294 complete with exactly 294 releases, and nine are cancelled by reset. Five queue/scheduler wiring mutations are detected. Standard TL classification/repacking and Switch top connection remain open.

The source repository suite passes 403 model and 199 tool tests with two conditional skips. The linked publication layout independently passes the Endpoint 1/2/4-port static matrix, collector and burst-monitor real-RX fault matrices, and the scheduler and queue-to-scheduler pipeline normal/fault/static matrices. Existing Endpoint and Switch digital tops synthesize successfully with 149 and 135 elaborated modules respectively. Process STA for the new native Endpoint top and Switch scheduling path has not been completed. Endpoint backend/Tag completion, Isolation/dummy completion/recovery epoch, standard per-hop TL/DL, PHY, INC, security, management and CDC/RDC remain unfinished. See `project/docs/upli_endpoint_ip_top_execution.md`, `project/docs/upli_endpoint_response_collector_execution.md`, `project/docs/upli_native_rx_burst_monitor_execution.md` and `project/docs/switch_egress_scheduler_review.md`.

## Endpoint request context, integrated burst faults and typed Switch egress

The inventory now contains 222 RTL entries: 100 partial implementations and 122 explicit disabled shells. Pending role bits are Endpoint 93 and Switch 115. A four-entry `upli_endpoint_request_context` preserves the complete descriptor produced by the real Request/OrigData bridge, issues it in FIFO order, and retains ownership until an external generation-qualified final release. The local token does not replace the native network Tag. Across 1/2/4 ports the unit and bridge suites cover nine allocations, eight issues, seven releases and two reset-cancelled contexts per bridge case, with five RTL mutations detected. The context is not yet instantiated in `upli_endpoint_ip_top`; backend execution and final response ownership remain open.

The Endpoint top now instantiates one native burst monitor and routes its diagnostics into the existing unique role fault controller. Explicit same-event command classification drives Request/OrigData burst pairing without guessing an opcode in production RTL. Six normal configurations cover 558 native edges, 122 Requests, 212 Data Beats and 54 first faults; disconnect, role-scope and Beat-count wiring mutations are detected. Existing Endpoint-top 1/2/4-port and TL-scope regressions retain 50 accepted descriptors and 301 receive heads/returns per case.

`switch_egress_repack` replaces stable Switch slot 58 with an elastic, backpressure-stable typed handoff for the complete 544-bit local egress record plus Request/Response, VC, Last and token metadata. Nine PORTS×VCS configurations cover 18,759 rows, 25,703 accepted records including reset cancellations and 25,663 retirements; nine RTL mutations and 27 static/elaboration checks pass. It does not reconstruct prepared Control/Data/Auth sources and is not yet connected to `tl_tx_prepared` or the production Switch top.

The source repository passes 403 model tests and 199 tool tests with two conditional skips. Generic synthesis passes for the existing digital Endpoint top at 149 elaborated modules and about 145,887 cells, and the Switch top at 134 modules and about 21,472 cells. The relocated request-context, burst-integration, Endpoint-top and typed-repack runners are repeated from this published layout before push. Full backend/top integration, standard per-hop TL/DL, Isolation/dummy completion/recovery epoch, PHY, INC, security, management, CDC/RDC and process STA remain unfinished.

## Endpoint context top, typed Switch top and originator isolation

The inventory now contains 223 RTL entries: 103 partial implementations and 120 explicit disabled shells. Pending role bits are Endpoint 91 and Switch 114. The production Endpoint top has an opt-in persistent request-context path; the independently verified single-outstanding memory adapter keeps command, result, completion and final response retirement as separate ownership stages, but automatic response formatting and its top connection remain open.

The production Switch top has an opt-in bounded egress path combining Request/Response/VC queues, packet-locking scheduling and a lossless 544-bit typed handoff. Queue capacity release and typed downstream retirement are independently accounted. Helper and top each pass nine PORTS×VCS configurations; eight wiring mutations are detected. This local typed record lacks enough information to reconstruct complete prepared Control/Data/Auth sources, so standard per-hop TL/DL remains open.

`ras_originator_isolation` now tracks real slot/port/epoch completion obligations for Endpoint-wide or Switch-port isolation. Late real completions are consumed without clearing dummy obligations; dummy request acceptance does not release a slot, and only an independent `dummy_done` clears it. The 24 PORTS×CAPACITY×role configurations and nine RTL mutations pass. An 8-bit epoch completes 255 recoveries and then rejects wrap. The dummy response generator, Tag owner, system recovery and native TL/DL connection remain open.

The source suite passes 403 model and 199 tool tests with two conditional skips. Generic synthesis passes at 147 modules/about 145,890 cells for Endpoint and 133 modules/about 21,468 cells for Switch. Relocated memory-adapter, Endpoint-context, Switch-typed-top, isolation and 223-entry structure suites pass from this published layout. Process STA, CDC/RDC closure and full protocol completion have not been completed.
