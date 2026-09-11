# Run: yosys -Q -T -c scripts/prove_uart_reset_control.tcl
# Outputs: retained reset-base and induction log; optional UALINK_PROOF_DIR graph and counterexamples.
# Next: verify complete source/state inventory, then library equality and timing.
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl dl dl_uart_reset_control.v]
yosys read_verilog [file join $project_root verification formal uart_reset_properties.v]
yosys hierarchy -check -top uart_reset_properties
yosys proc
yosys flatten
yosys select -module uart_reset_properties
yosys select -assert-count 1 w:observed_state
foreach {name low high} {sta_local 0 1 cnt_noops 2 7 cnt_wait 8 31 reg_local_all 32 32 cnt_response 33 37 reg_response_scope 38 41 reg_fault 42 42} {
    set source Reset_Inst.$name
    set sink [format {observed_state[%d:%d]} $high $low]
    yosys select -assert-count 1 w:$source
    yosys connect -nomap -nounset -set $sink $source
}
yosys select -clear
yosys check -assert
if {[info exists env(UALINK_PROOF_DIR)]} {
    set proof_dir [file normalize $env(UALINK_PROOF_DIR)]
    file mkdir $proof_dir
    yosys write_json [file join $proof_dir connected.json]
}
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys select -assert-count 9 uart_reset_properties/i:*
yosys select -clear
# Full relation, including all43 actual state bits and all56 output bits.
# Only the actual first reset is constrained for the base; every other input is arbitrary.
set dump_base {}
set dump_step {}
if {[info exists proof_dir]} {
    set dump_base [list -dump_json [file join $proof_dir reset_counterexample.json]]
    set dump_step [list -dump_json [file join $proof_dir step_counterexample.json]]
}
yosys sat -verify -seq 2 -timeout 120 -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 -show o_groups {*}$dump_base uart_reset_properties
puts "UART_RESET_RESET_BASE_PROVED"
# This single-step invariant assumption is itself established by the preceding reset query.
yosys sat -verify -seq 2 -timeout 120 -set-at 1 o_violation 0 -prove o_violation 0 -prove-skip 1 -show o_groups {*}$dump_step uart_reset_properties
puts "UART_RESET_FULL_INDUCTION_PROVED"
puts "UART_RESET_FUNCTIONAL_PROVED groups=3 state_bits=43 output_bits=56"
