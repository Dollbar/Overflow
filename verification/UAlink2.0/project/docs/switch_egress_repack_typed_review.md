# Switch egress typed local record handoff

This candidate implements the bounded local subset of planned `switch_egress_repack` (inventory Switch slot 58): an actual independent one-entry elastic register per physical egress, preserving every bit of the local 544-bit record and its Request/Response, VC, token and packet Last. It presents named fields with one atomic ready/valid handshake. It is neither an opaque unimplemented shell nor a completed standard TL repacker. Production RTL, inventory and tops are unmodified.

## Why `tl_tx_prepared` is not connected

The existing `ualink_endpoint_top` digital record is `{local_DL_header24,record_aux6,TL_msg2,TL_flit512}`. It is already on the packed TL/DL side. `tl_tx_prepared` instead accepts separate Request and Response 256-bit source control groups, class-specific 512-bit tag groups, and independently counted 0/1/2 Data-half inputs. Header capture (`o_source_captured`), Data admission (`o_data_accepted`) and actual wire consumption (`i_taken`) are distinct events. A 512-bit packed flit cannot be assigned to a 256-bit source group without decoding its field layout, retaining ordering/Data association and reconstructing authentication metadata. Local class/VC/Last sidebands alone do not supply that missing mapping.

Accordingly the candidate does **not** instantiate `tl_tx_prepared`, does not produce fabricated `source_control` or tag fields, and does not reinterpret a local handshake as prepared capture. The unimplemented boundary is explicit: a future confirmed packet/field decoder must consume this typed record, handle its local DL metadata separately, recover ordered complete control fields and their Data/tags, then obey prepared's independent capture/admission handshakes. No direct wire compatibility is claimed. The new typed output can also be consumed by a separately defined packed-link interface, but that integration is not included here.

## Frozen contract

Parameters: PORTS/VCS independently 1/2/4; TOKEN_WIDTH positive, default8. Record width is fixed544 to prevent implicit ABI truncation. Inputs `i_valid/i_data/i_last/i_token/i_vc/i_response` match the physical egress packet stream; `o_ready` acknowledges this local register's real acceptance. Output `o_valid` and the following fields are consumed atomically only when `i_ready` is asserted:

| Typed output | Original local record/source |
| --- | --- |
| `o_local_dl_header[24/port]` | record `[543:520]` |
| `o_record_aux[6/port]` | record `[519:514]`, preserved even when nonzero |
| `o_tl_msg[2/port]` | record `[513:512]` |
| `o_tl_flit[512/port]` | record `[511:0]`, exact bit ordering |
| `o_token/o_vc/o_response/o_last` | corresponding original packet sideband, captured with that record |

Low slices belong to physical port0. Request/Response is not inferred from the TL msg field. Each port can hold one record independently. Empty storage accepts a new valid record; a full entry can be replaced on the same edge its previous record is consumed. There is no combinational data bypass. While stalled, all stored fields remain unchanged even if another port transfers. Invalid output fields are zero.

`o_input_error[PORTS]` is a current reset-qualified diagnostic for valid input VC outside the configured range. Such input gets no ready and is not accepted; an older trusted output remains valid and can drain. No packet classification, source continuity, credit, parity or RAS policy is invented. The producer must maintain packet class/VC/token and valid/data stability according to the existing scheduler contract. Synchronous low `i_rstn` cancels all held entries and gates public transfers; reset is common to the local epoch.

This register's acceptance is a new local storage boundary, not final TL/link transmission. Inserting it after `switch_egress_pipeline` changes the point at which that upstream queue sees acceptance; its reservation is for its own queue storage. System-level credit/physical-send association must be reviewed in the later actual connection rather than claiming that this unit test established it.

## Evidence and scope

TDD retains missing typed module elaboration RED and the real existing planned shell's incompatible-interface elaboration log, including its source snapshot. The final normal and Python `-O` labels each run all nine PORTS×VCS combinations, nine actual RTL wiring/storage faults, and two invalid-parameter elaboration cases. The independent Python oracle uses per-port deques; expected field boundaries are computed with numerical `divmod`, not RTL slices or internal state. Each physical port walks all544 original bits, including every field boundary. Random multi-beat streams exercise original packet sidebands, complete payload order, independent backpressure, simultaneous consume/replace, held-input stability, reset cancellation and invalid VC while an older output is retained.

Mutations bypass storage fullness/ready, shift the local header, discard aux bits, shift msg, drop the highest flit bit, force Request class, force VC0, remove Last or remove token. All compile successfully and fail the actual self-check. Healthy 1/2/4×1/2/4 configurations pass Verilog-2001 elaboration, strict Verilator `-Wall` with no waivers and Yosys `proc/opt/check -assert`. Skill artifact checking is retained separately; the whole skill's external cleanup workflow is not run because it writes/deletes outside candidate ownership. No actual `tl_tx_prepared` or pipeline integration is claimed by these unit results; this stage intentionally freezes the installable typed boundary first.

`freeze.json` lists exact release/source hashes, labels, per-case statistics and evidence. Failed or superseded evidence is not overwritten. No macro mapping, STA, PPA, standardized forwarding decode, full Switch or interoperability certification is implied.

## Reproduce and next step

Install the five release files, then run from any cwd:

```sh
python3 /PATH/UALink/verification/ip_tops/run_switch_egress_repack.py --label NEW --faults
python3 -O /PATH/UALink/verification/ip_tops/run_switch_egress_repack.py --label NEW_OPT --faults
```

The runner uses `ROOT=Path(__file__).resolve().parents[2]`; outputs are `ROOT/build/verification/ip_tops/switch_egress_repack/LABEL`. Each input is read once and the exact snapshot bytes are compiled and hashed. Existing labels are rejected. For the isolated release runner, add `--rtl /PATH/CANDIDATE/switch_egress_repack.v`. Next review the explicit decoder/Data/tag association contract before connecting to prepared, and separately verify actual queue→typed-handoff backpressure and release boundaries.
