# UALink source delivery

This snapshot imports 897 tracked source files from the UALink development
repository at commit `6b794142c3f3a3bbbbe33a722700dba6c971b712`. The [ownership manifest](.ualink-export.json)
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
python3 verification/endpoint_transaction/run_write_endpoint_switch.py --kd28-root ../../.. --label your_fresh_label --all-lengths --inject --bank-depth 1
python3 verification/endpoint_transaction/run_transactions.py --vip-selftest --label your_fresh_vip_label
make test
```

Expected outputs are in project `build/` or `reports/`, ignored by Git. Use a fresh label.
`KD28_ROOT=../../..` explicitly selects the containing Overflow checkout and still validates
its functional SRAM source hashes. The four relative directory links provide one project
root without duplicate source files; see [layout details](project/docs/overflow_layout.md).

This increment implements ordinary Write/WriteFull with one shared Read/Write Tag table,
ordered backend dispatch, complete Data/BE ownership and real memory-result responses.
The corrected actual Endpoint/Switch regressions completed 1,172 transactions, 320 Write
executions and 16 replays; replays did not duplicate memory execution. Independent models,
receiver checks, four core capacities and isolated faults provide separate evidence.
The ESE length matrix covers 64 ordinary LEN representatives and 10 legal Full geometries;
the 2,080 legal ordinary start/LEN combinations are covered at unit/model level.
See the [Write review](project/docs/endpoint_write_integration_review.md),
[bounded evidence](project/docs/endpoint_write_evidence.json) and
[independent test audit](project/docs/endpoint_write_test_audit.md).

The default Read capacity matrix remains 29/29 and three in-flight reset windows pass.
Existing model/tool tests pass, with two pre-existing conditional tool skips.
After export, the all-lengths bank1/replay ESE case, capacity3 mixed core and optimized
Write model/fault checks passed again from these published directories before pushing.
No waveform, generated simulation executable or private dependency is tracked.

The inventory is 202 RTL entries: 69 partially implemented and 133 disabled interface
scaffolds. WRITE_ENABLE defaults to zero; set TRANSACTION_MODE=1 and WRITE_ENABLE=1
for the documented uncompressed Write/WriteFull plus single64B Read profile.
Strict core lint still reports 16 warnings without waivers; new-top process STA is open.
Full Endpoint/Switch protocol functionality, native UPLI, standard per-hop routing/framing,
PHY, INC, security, management, CDC/RDC and mixed-Write reset/epoch recovery are unfinished.

Upstream commits through 186769a were fast-forwarded before this export. Their cleared
RTL namespace README and added KD-UAlink2_0.png are preserved; the README was merged back
into the development source so the exporter does not restore the removed text.
