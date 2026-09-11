# Native response TX field integration

The production tree replaces the Read Response and Write Response provisional shells with complete typed transmit fields and generated parity. All four native UPLI channel types now have transmit field leaves. Response credit/TDM senders, native receive checks and full station/Endpoint integration remain separate work; this increment does not instantiate response senders in the Endpoint top.

Read Response preserves 624 information bits (48 control, 64 authorization, 512 data), with valid/auth/control and eight data parity groups. Write Response preserves 106 information bits (42 control, 64 authorization), with valid/auth/control parity. Both use the existing common primitive with CHANNEL_KIND 1/2 and shared reset gating. Invalid/reset outputs are zero; valid error/poisoned Read data remains complete and protected. Neither leaf interprets command/status legality, performs authorization, manages credits, or accepts a native ready signal. Upstream logic must supply a real qualified send event and correct response context.

The final installed Read leaf passed 7396 independent vectors, eight actual wiring/parity faults, Verilog-2001, strict Verilator and Yosys checks. The Write leaf passed 3508 vectors, five actual faults and the same static checks, with exactly one common parity instance and zero latches. Agents independently cross-reviewed the other leaf's complete fields, parity group widths/mapping and reset gating without finding a concrete wiring defect. This is bounded review, not proof of all protocol semantics. Reserved encodings in bit-preservation vectors are not counted as legal transaction coverage.

The production structure check now reports 203 inventory entries: 78 existing_partial and 125 unimplemented shells. Stable pending slots are Endpoint 93 / Switch 118; removed shell slots remain reserved and are not reused. Actual dual-Endpoint full Read uniform reset at three of four received Beats, bank depth 1, passes on this source tree. The preceding Request/OrigData snapshot passed repository make test; that history is not relabeled as a new whole-suite run for these two leaves.

Reproduce from the project root with fresh labels:

```sh
python3 verification/upli_channels/run_read_response_channel.py --label NEW_read --faults --static
python3 verification/upli_channels/run_write_response.py --label NEW_write
python3 verification/upli_channels/run_write_response.py --label NEW_tag_fault --fault tag_msb
python3 verification/upli_channels/run_write_response.py --label NEW_auth_fault --fault auth_drop
python3 verification/upli_channels/run_write_response.py --label NEW_pool_fault --fault pool_parity
python3 verification/upli_channels/run_write_response.py --label NEW_reset_fault --fault valid_reset
python3 verification/upli_channels/run_write_response.py --label NEW_status_fault --fault status
python3 scripts/check_ip_structure.py --label NEW_structure
python3 verification/endpoint_transaction/run_read_reset.py --label NEW_reset --kd28-root /path/to/authorized/Overflow --bank-depth 1 --stage 2 --partial-beats 3
```

Outputs are fresh source/vector/log/hash directories below `build/verification/`. Final hashes and results are listed in `upli_response_evidence.json`. The existing private-spec AuthTagParity Driver-column discrepancy remains documented in both execution contracts; generating parity beside the transmitted AuthTag is an explicit local TX choice, not resolution of the specification issue.

Next implement the independent response credit/TDM senders and credit protection adapters described in `upli_station_integration_execution.md`, then connect actual station TX/RX and Endpoint context adapters. Preserve distinct channel phases and real connection directions. Full RAS recovery, independent LinkDown/epoch, remaining protocol features, CDC/RDC and process STA remain open.
