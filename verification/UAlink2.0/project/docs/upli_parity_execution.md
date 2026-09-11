# UPLI parity implementation contract

Common 2.0 Tables2-2,2-15,2-18,2-21 and sections3.1.1/3.1.2 define separate protection groups. This module generates and checks those groups without adding latency, credit consumption, channel connection, message validation, authentication verification or RAS recovery. Authorization mismatch has its own diagnostic, because it is not included in the explicit control/data error lists. The OrigData ByteEn parity table's self-reference is interpreted using the explicit ByteEn protection requirement in section3.1.1 and the existing independent model.

CHANNEL_KIND0/1/2/3 selects Request/Read Response/Write Response/OrigData. i_control[67:0] carries respectively68/48/42/9 protected bits in its low portion; upper unused bits are ignored. These are local signal bundles, not a new UPLI wire format.

- Request group: Tag11, Len6, Attr8, Cmd6, MetaData8, VC2, ASI2, Src10, Dst10, Port2, NumBeats2, Pool1. Address57 and AuthTag64 have independent parity.
- Read Response group: TypeInfo2, Tag11, Status4, Offset2, Last1, NumBeats2, VC2, Src10, Dst10, Port2, DataError1, Pool1. AuthTag64 and eight natural64-bit data slices have independent parity.
- Write Response group: TypeInfo2, Tag11, Status4, Src10, Dst10, Port2, VC2, Pool1. AuthTag64 is separate.
- OrigData group low bits match the existing model: Last0, Error1, Offset3:2, Port5:4, VC7:6, Pool8. Eight natural64-bit data slices and the64-bit ByteEn vector are separately protected.

Output parity/error positions: valid0, control1, address2, auth3, data11:4, ByteEn12, CreditVld13, CreditFields14. CreditFields covers all four ports' VC8/Num8/Pool4 whenever any CreditVld bit is1; inactive-port fields must not be masked out. Vld and CreditVld parity are checked on every enabled check cycle, even valid0. Other groups are checked only on actual channel valid; credit fields only on nonzero CreditVld. Generation includes masked and poisoned data lanes.

i_check_enable controls diagnostics only; wrapper owns its reset policy. o_control_error combines bits0/1/2/13/14. o_data_error combines bits4..12, including ByteEn; automatic poisoning or isolation is not implemented here. o_auth_error is bit3. Nonexistent groups generate zero and ignore received parity. CHANNEL_KIND must be0..3; invalid kinds report control error when checking is enabled.

TDD sequence: retain interface_red against the real old shell (missing semantic ports, compile2; not a behavior proof), implement combinational RTL, check all four kinds against independent bit-count oracle, inject actual valid-qualification/data-mask/credit-mask/ByteEn-classification faults, then run g2001, strict Verilator and Yosys. Candidate remains isolated until all affected scaffold/typed wiring can change together.

Run: python3 verification/upli_channels/run_parity.py --label NEW --faults --static
Candidate override: --rtl build/development/upli_parity/upli_parity.v
Outputs: build/verification/upli_channels/parity/NEW source/test snapshots, vectors, logs and hashes. Next: connect complete typed channel fields and independently check their group packing. This unit does not complete the native station or RAS subsystems.
