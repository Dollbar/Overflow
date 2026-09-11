# Native RX normal burst monitor

This candidate observes native Request and OrigData events at the receive boundary. It detects missing same-edge first Data, unexplained Data, overlapping data-bearing requests, gaps at the port's next TDM opportunity, wrong Offset/Last and wrong original request VC. It does not filter events, produce ready, generate Drop, own credits, stage payload, execute commands or schedule TDM.

The contract uses Common 2.0 §2.7.7/Table 2-21 and §2.7.8 pp70–72, interpreted alongside §2.5 and the existing `docs/upli_native_rx_execution.md`, `model/ualink/upli_burst.py`, `upli_burst_control` and `upli_burst_sender`. First Data must accompany its data-bearing Request. Its relative Offset starts at zero; subsequent data is contiguous in that port's TDM opportunities, increments Offset and asserts Last exactly on the original NumBeats boundary. Data VC remains the original Request VC; Pool can change per beat. A no-data Read may overlay an older data tail without replacing that tail's context. This document paraphrases these boundaries and includes no private specification text.

## Frozen interface

`C_NUM_PORTS` accepts only 1, 2 or 4. `i_clk/i_rstn` are the common clock and synchronous active-low reset. Inputs are actual native `i_req_valid/port/vc/num_beats` and `i_data_valid/port/vc/offset/last`. They are not candidates or delayed SRAM accepted/retired events.

`i_req_class_known` and `i_req_has_data` are explicit local qualification from an already confirmed command decoder. This monitor does not infer command class from NumBeats, incoming Data presence, or an opcode guess. The integrated test recognizes only the existing ordinary Read `03`, Write `28` and WriteFull `29` profile. Legal Atomic/vendor/Message classes need their separately confirmed decoder. Unknown valid Request classification is diagnosed, not silently treated as Read. Geometry, byte enables, Tag, authentication, parity, data poison and credit sufficiency are outside this module's checks.

`i_tdm_known/i_tdm_port` connect to the existing `upli_receive_tdm_monitor.o_phase_known[0]` and `.o_expected_port[1:0]`, representing the current pre-edge slot. There is **no TDM state or additional TDM instance** in this candidate. An initial Request may pair with initial Data before phase-known is set; the next slot comes from the existing TDM owner. Checking that otherwise valid events occur on the correct TDM port remains that owner's job. This module only uses the supplied current slot to know when an existing tail is mandatory.

Outputs `o_error[9:0]` are current pre-edge diagnostics, reset-qualified. Bits mean:

| Bit | Meaning |
| --- | --- |
| 0 | Valid native Request or Data has an unconfigured port |
| 1 | New data-bearing Request lacks its same-port, same-edge first Data |
| 2 | Data has no existing burst owner or matching new data-bearing Request |
| 3 | New data-bearing Request attempts to replace an active burst on its port |
| 4 | Active port reaches its supplied TDM opportunity without matching Data |
| 5 | Owned Data Offset differs from the expected relative position |
| 6 | Owned Data Last differs from the original request's final position |
| 7 | Owned Data VC differs from original Request VC |
| 8 | Valid Request has no confirmed command classification |
| 9 | An active context lacks a usable existing TDM state/port input |

`o_error_sticky` captures the first error group on the common edge and holds until reset. `o_active[C_NUM_PORTS-1:0]` is the current registered tail context. Any first error freezes **all local monitor contexts**, and subsequent `o_error` is zero while sticky remains nonzero. This is an explicit fail-stop *diagnostic profile*, not station recovery: no traffic or credit is changed. Reset is the only resynchronization boundary. The caller must not interpret active bits after a sticky error as verified transaction ownership. Normal poison or error data never shortens the expected burst; no data/error input is needed to enforce that rule. Exceptional legally aborted bursts under Drop/Isolation are not automatically recognized and may leave this monitor in its documented diagnostic state until the common reset.

## TDD and actual verification

`missing_red` retains failed elaboration for the absent monitor for all three port configurations. `first_matrix`, `path_first`, `frozen` and `frozen_optimized` retain successive evidence without overwriting labels. The final normal and Python `-O` runs each contain 17 passing cases: three unit configurations, five mutated monitor RTL cases, one invalid-port elaboration rejection, three real native Endpoint path integrations, and five mutated observer-connection cases. Each healthy monitor is also elaborated as Verilog-2001, checked with strict Verilator `-Wall` without waivers, and synthesized through Yosys `proc/opt/memory_map/check -assert`. Skill artifact validation reports 86/86 commented lines and zero errors/warnings. The whole skill's external cleanup/workflow gate is not run because it changes files outside the isolated candidate boundary.

The unit oracle is an independent Python list of future expected `(Offset, Last, VC)` events per port. It reads no RTL or DUT state. Checks cover 1–4 Data beats, every first port, concurrent per-port bursts, idle slots, Read overlays with changed VC and Num fields, final retirement, reset cancellation, invalid ports, unknown classification and frozen diagnostic history. Directed cases distinguish wrong first versus tail Offset/Last/VC, missing first, orphan Data, mismatched first ports, a new data-bearing request during an old tail, missing tail with/without a Read overlay, and missing final Last. Unit stimuli supply the existing TDM qualifier as an external input; they do not re-test its phase-generation state machine. Actual monitor mutations remove first-pair/gap/Offset/Last checks or let Read overwrite the saved descriptor. All compile successfully and are rejected by the independent checker.

Integration inserts the small `rx_burst_path_bind.svh` observer into a **snapshot** of the existing production `verification/ip_tops/endpoint_native_rx_path_tb.sv`. The production file and production RTL are unmodified. The test exercises real station TX senders, the existing single RX TDM owner, four native protected RX channels, actual KD28 SRAM, ordered account journals and credit returns. The observer connects directly to raw native outputs and the path's public TDM outputs, not hidden DUT state. Existing full payload/order/credit assertions remain active. Ports 1/2/4 run 1,724/1,727/1,733 total cycles, including 1,699/1,702/1,708 non-reset observed edges, with 85/91/95 Request and 140/148/152 Data events. Summed: 5,109 observed edges, 271 Requests and 440 Data beats. Existing poison and Pool changes do not truncate bursts. Common reset cancels old partial traffic; dropped-but-still-present native events are still observed rather than replaced by storage acceptance.

Five actual monitor-input connection faults remove first Data or a tail, corrupt Offset, invert Last, or change VC. They compile successfully and produce `BURST_PATH_ERROR` with first diagnostic `002/010/020/040/080`, respectively. These are observer-boundary fault injections; they do not claim that the path already routes this new diagnostic into the role Drop controller.

## Reproduce and install

The six release files consist of RTL, unit oracle/TB, path observer include, runner and this contract. `freeze.json` lists their exact SHA-256 values. The runner snapshots each source once, compiles those same bytes, preserves logs/commands/exit codes and verifies authorized KD28 source hashes. Existing labels are refused.

After installation, from any cwd:

```sh
python3 /PATH/UALink/verification/upli_channels/run_rx_burst.py --label NEW --faults --receive --kd28-root /PATH/AUTHORIZED_KD28
python3 -O /PATH/UALink/verification/upli_channels/run_rx_burst.py --label NEW_OPT --faults --receive --kd28-root /PATH/AUTHORIZED_KD28
```

Outputs are `ROOT/build/verification/upli_channels/rx_burst/LABEL`, where `ROOT=Path(__file__).resolve().parents[2]`. To verify the isolated release runner before installation, append `--rtl CANDIDATE/upli_native_rx_burst_monitor.v --project-root /PATH/UALink`. The production path TB is an explicit existing test dependency, not copied development RTL.

Next connect these diagnostics into the existing role fault policy alongside parity/TDM/storage errors, with the confirmed command-class qualifier. This candidate is not complete native RX RAS, Isolation, Endpoint transaction validation, a full station or timing/protocol certification.
