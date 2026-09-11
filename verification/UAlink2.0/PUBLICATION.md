# UALink source delivery

This snapshot imports 863 tracked source files from the UALink development
repository at commit `6599e8009ab1a626825854b207a907988d6854f3`. The [ownership manifest](.ualink-export.json)
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
make ip-transaction-smoke KD28_ROOT=../../.. IP_RUN_LABEL=your_fresh_label
python3 verification/endpoint_transaction/run_transactions.py --vip-selftest --label your_fresh_vip_label
make test
```

Expected outputs are in project `build/` or `reports/`, ignored by Git. Use a fresh label.
`KD28_ROOT=../../..` explicitly selects the containing Overflow checkout and still validates
its functional SRAM source hashes. The four relative directory links provide one project
root without duplicate source files; see [layout details](project/docs/overflow_layout.md).

The relocated real Endpoint→Switch→Endpoint Read/replay test, standalone VIP selftest
and 15 exporter fixture tests passed from these actual directories. The relocated `make test`
model/tool suite also completed successfully. Originator checks passed for 1/2/4 ports,
and the Completer check completed 32 request/result/response chains and detected its three injected faults. Source-side extraction
also passed three communication configurations (48/48 transactions), three injected wiring
fault detections and the VIP holding/reset test; see [bounded evidence](project/docs/endpoint_vip_extraction_evidence.json).

The inventory remains 202 RTL entries: 66 partially implemented and 136 explicit disabled
interface scaffolds. Current real application execution covers the documented single64B
Read subset. Full Endpoint/Switch protocol functionality, PHY, INC, security, management,
CDC/RDC and new-top process STA are unfinished. Next, expand the transaction and reset
coverage and replace the remaining service scaffolds.
