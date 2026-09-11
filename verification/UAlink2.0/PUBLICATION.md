# UALink source delivery

This snapshot imports 922 tracked source files from the UALink development
repository at commit `ec31dfc39379b1b78fb165511b1746e1c1cc72a0`. The [ownership manifest](.ualink-export.json)
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

This increment implements full ordinary uncompressed Read with DWORD lengths 4..256B,
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

The inventory remains 202 RTL entries: 69 partially implemented and 133 disabled interface
scaffolds. Set TRANSACTION_MODE=1 and FULL_READ_ENABLE=1 for the documented complete ordinary
Read profile; WRITE_ENABLE=1 independently adds ordinary Write/WriteFull. Defaults preserve
the earlier fixed Read subset. Strict core lint still reports 15 warnings per Write setting;
new-top process STA is open. Full Read partial-response reset, independent LinkDown/epoch,
native UPLI, standard per-hop routing/framing, PHY, INC, security, management and CDC/RDC
remain unfinished. This snapshot is not a complete Endpoint/Switch protocol delivery.

The upstream cleared RTL namespace README and added KD-UAlink2_0.png remain preserved.
