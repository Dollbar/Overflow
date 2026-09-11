# UALink source delivery

This snapshot imports 1020 tracked source files from the UALink development
repository at commit `abff72898061d833d8ce264d3e32e86dd766ffef`. The [ownership manifest](.ualink-export.json)
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
