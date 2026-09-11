# Native Request / OrigData transmit integration

The production tree now contains typed native Request and OrigData outputs, one shared Request/Data sender, and the common four-channel parity primitive. Three provisional leaves were replaced; the new sender helper adds one inventory entry. Inventory: 203 entries, 76 existing_partial, 127 explicitly unimplemented shells; Endpoint/Switch pending shell slots: 95/120. These counts are engineering inventory, not protocol completion percentages.

The helper instantiates exactly one existing burst sender, retaining its two credit banks, TDM phase, complete-staged burst ownership and reset. A fixed 184-bit local request bundle preserves all Request fields. Request valid comes from the actual credit-qualified send event; OrigData outputs all traverse the typed leaf. The producer remains responsible for legal command/geometry and inactive authorization-tag zeroing. Request idle/reset outputs zero; the OrigData leaf preserves even invalid fields, while the actual sender supplies idle zeros. No independent credit consumption or additional native ready was introduced.

Both typed leaves instantiate the common parity primitive. Full-output two-state combinational SAT proves equality against frozen original XOR fixtures (Request 191 input / 194 compared output bits; OrigData 586 / 597). Actual Tag-high omission and byte-enable-masked data parity faults produce counterexamples. This proof is not a stateful sender proof or four-state simulation claim.

Final installed RTL results:

- Request: 970 vectors and six actual field/valid wiring faults detected.
- OrigData: 3688 vectors and three actual data/parity/poison faults detected. Real sender integration at 1/2/4 ports: 4507/9279/22076 input rows and 1402/2022/3437 data events.
- Common parity: 1771 vectors per channel kind, 7084 total; four actual gating/classification faults detected.
- Actual combined sender: 1/2/4 ports each 10 Request and 11 OrigData events, 708/1665/5071 checks; three actual wrapper faults detected. Includes independent credit accounting, insufficient whole-burst credit, no same-cycle return bypass, Read overlay changing VC/Pool, TDM tails and reset cancellation.
- Verilog-2001, strict Verilator and Yosys checks pass for the parity kinds, typed leaves and combined sender at 1/2/4 ports. Structure check and repository `make test` pass. Existing full Read bank-depth 1 reset at exactly three of four response Beats passes on this production source tree.

The 16 simulation faults and two formal faults are distinct test executions, not a percentage of all possible defects. Exact final source hashes and run references are in `upli_native_sender_evidence.json`. Earlier candidate reviews identify their own snapshots; the final installed runs are authoritative for the shared primitive conversion.

Reproduce from the project root with fresh labels:

```sh
python3 verification/upli_channels/run_parity.py --label NEW_parity --faults --static
python3 verification/upli_channels/run_request_channel.py --label NEW_request --faults --static
python3 verification/upli_channels/run_orig_data.py --label NEW_orig --integration
python3 verification/upli_channels/run_orig_data.py --label NEW_data_fault --fault data_msb
python3 verification/upli_channels/run_orig_data.py --label NEW_mask_fault --fault masked_parity
python3 verification/upli_channels/run_orig_data.py --label NEW_poison_fault --fault poison
python3 verification/upli_channels/run_request_data_sender.py --label NEW_sender --faults --static
python3 verification/upli_channels/run_shared_parity.py --label NEW_equivalence
python3 scripts/check_ip_structure.py --label NEW_structure
python3 verification/endpoint_transaction/run_read_reset.py --label NEW_read_reset --kd28-root /path/to/authorized/Overflow --bank-depth 1 --stage 2 --partial-beats 3
```

Results, source snapshots, logs and hashes remain under `build/verification/`; only source runners, testbenches and independent reference fixtures are published. Next integrate separately reviewed native response leaves and explicit station/Endpoint adapters. Full station receive storage/credit return, parity-driven RAS isolation, independent LinkDown/epoch, standard per-hop TL/DL, per-VC scheduling, PHY/INC/security/management, CDC/RDC and process STA remain open. The shared sender is not yet instantiated as the Endpoint's full native station. No complete IP, interoperability certification or timing signoff is claimed.
