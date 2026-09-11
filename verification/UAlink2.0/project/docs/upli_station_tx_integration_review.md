# Native TX senders and actual credit/SRAM integration

Production RTL now includes independent Read Response and Write Response senders, a returned-credit parity guard, a direct credit-return adapter and a three-sender native TX aggregate. These add five partial implementations: 208 inventory entries, 83 existing_partial, 125 explicit shells. Stable Endpoint/Switch pending slots remain 93/118. The complete upli_station_port shell is deliberately still present because RX validation, error ownership and Endpoint context adapters are incomplete.

The aggregate combines both roles' transmit services with explicit, separate connection qualifications. Request/OrigData retain one shared sender, phase and two banks; Read and Write responses each own one independent phase and bank. Four guards expose complete returned-credit parity diagnostics. Guards do not invent a corrupted-credit suppression or recovery policy. Common 2.0 section 3.1.4.2 requires discarding bad control beats/returned credits and entering the applicable Drop scope; that required RAS owner is not implemented by this TX aggregate. Section 3.1.4.1 requires data/ByteEn parity errors to propagate as poisoned data with corrected protection in the normal data-error policy; this RX processing also remains pending. Existing senders retain their own error/reset boundary. The adapter directly protects actual registered receive-channel credit output without another cycle, ready or TDM filter.

Read Response supports single NumBeats=0 with independent Offset/Last and complete-staged multi bursts up to four beats, whole-burst credit qualification and per-port immutable tails. Each real beat debits one original VC/pool account. Src is preserved per beat and excluded from functional admission. Write Response sends one complete native response only with old credit/init and its own slot. Neither sender implements backend execution, Tag collection, ISOLATE or authorization.

Final installed evidence:

| Check | Actual scope/result |
|---|---|
| Read sender | Four configurations, 30351 cycles, seven actual RTL faults detected; nine g2001/strict lint/Yosys checks pass |
| Write sender | Final production 4-port/16-bit run: 1552 cycles, 467 sends; three actual faults detected. Frozen identical RTL also has six-config owner evidence: 8040 cycles, 3725 sends |
| Credit adapters | 3418 independent vectors; actual four-port SRAM receive/retire/return run passes; two guard unit faults plus InitDone fault at one port and return-gating fault at four ports detected |
| Actual TX/SRAM aggregate | Five configurations: ports 1/2/4 at width4/capacity4, port4 at width16/capacity5, port1 at width3/capacity5. Two complete rounds per configuration: 1480 native beats delivered through actual SRAM and retired |
| Reset | Between complete rounds, common reset cancels 249 already-sent/unretired payloads across the five configurations. Quiet rebuild shows no old traffic; changed-data new rounds pass |
| Aggregate checks | 5885 actual clock edges including reset and setup, 170670 assertions; separate phase tracking, full fields/parity, four credit-control and idle-valid parity diagnostics, source-candidate noise and real return paths |
| Aggregate faults/static | Actual Read Tag, Write Tag and guard-bypass faults detected; all five configurations pass g2001, strict Verilator and Yosys |
| Compatibility | Repository make test, 208-entry structure check and actual full Read bank1 reset after exactly three response Beats pass |

The aggregate TB creates expected native queues from accepted original candidate tuples, compares all actual native fields, then checks actual SRAM retirement against those already-verified events. It does not read sender tail memories or bank state to manufacture expected payloads. Request stimuli use ordinary Write command 0x28 with aligned N-beat length and Read command3/Num0. Native response streams remain independently constructed: this test does not prove request-to-backend-to-response causality, response timing after the last OrigData, native Endpoint bridging or complete RX protocol validation. Arbitrary Auth fields test preservation, not authentication correctness. Full Read compatibility remains the existing Endpoint path, not a native station bridge.

Independent review checks the Read sender and the aggregate. Aggregate Yosys bit-by-bit inspection confirms three senders/four guards, exactly four banks and all typed/diagnostic connections. Distinct Req/Data/Read/Write capacities 1/4/3/2 are separately elaborated to expose parameter cross-wiring; that is a structural check, not the runtime traffic profile above.

Failures remain recorded. The first station guard mutant disabled the Request guard while only Read control parity was corrupted, so it was not detected; the final TB exercises all four control groups and idle valid protection, and the final bypass mutation is detected. Initial strict lint failed because a command-line capacity override was unsized; width-qualified overrides fix the test invocation with no waiver or RTL change. Some adapter integration fault attempts used non-triggering conditions (healthy credit traffic for guard faults, even parity of all four InitDone bits); final unit and selected integration faults are separately identified, not relabeled as universal fault coverage. Earlier syntax-only compilation used an ignored missing Read sender and is never counted as simulation evidence.

Reproduce from the project root with fresh labels:

```sh
python3 verification/upli_channels/run_read_response_sender.py --label NEW_read --faults
python3 verification/upli_channels/run_write_response_sender.py --label NEW_write --ports 4 --width 16 --init-cycles 2
python3 verification/upli_channels/run_write_response_sender.py --label NEW_debit --ports 4 --fault debit
python3 verification/upli_channels/run_write_response_sender.py --label NEW_phase --ports 4 --fault phase
python3 verification/upli_channels/run_write_response_sender.py --label NEW_tag --ports 4 --fault high_tag
python3 verification/upli_channels/run_credit_adapter.py --label NEW_credit --integration --ports 4 --kd28-root /path/to/authorized/Overflow
python3 verification/upli_channels/run_credit_adapter.py --label NEW_valid_fault --fault guard_valid
python3 verification/upli_channels/run_credit_adapter.py --label NEW_mask_fault --fault guard_mask
python3 verification/upli_channels/run_credit_adapter.py --label NEW_init_fault --fault adapter_init --integration --ports 1 --kd28-root /path/to/authorized/Overflow
python3 verification/upli_channels/run_credit_adapter.py --label NEW_gate_fault --fault adapter_gate --integration --ports 4 --kd28-root /path/to/authorized/Overflow
python3 verification/upli_channels/run_station_tx.py --label NEW_station --kd28-root /path/to/authorized/Overflow --static
python3 verification/upli_channels/run_station_tx.py --label NEW_wide --kd28-root /path/to/authorized/Overflow --ports 4 --capacity 5 --credit-width 16 --static
python3 verification/upli_channels/run_station_tx.py --label NEW_min --kd28-root /path/to/authorized/Overflow --ports 1 --capacity 5 --credit-width 3 --static
python3 verification/upli_channels/run_station_tx.py --label NEW_rd_fault --kd28-root /path/to/authorized/Overflow --ports 4 --fault rd_tag
python3 verification/upli_channels/run_station_tx.py --label NEW_wr_fault --kd28-root /path/to/authorized/Overflow --ports 4 --fault wr_tag
python3 verification/upli_channels/run_station_tx.py --label NEW_guard_fault --kd28-root /path/to/authorized/Overflow --ports 4 --fault guard_bypass
```

Logs, snapshots, vectors and hashes are under build/verification/upli_channels; exact final sources and references are in upli_station_tx_evidence.json. External KD28 functional source hashes are checked against the dependency manifest and files remain read-only. This is actual authorized SRAM-model RTL use, not physical macro/SerDes or process timing signoff.

Next complete native RX parity/TDM/burst checks and error ownership, preserve full native transaction context through Endpoint adapters, and prove backend-derived response causality. Independent LinkDown/epoch, standard per-hop TL/DL, remaining PHY/INC/security/management, CDC/RDC and process STA remain open. The full dual-IP goal is unchanged.
