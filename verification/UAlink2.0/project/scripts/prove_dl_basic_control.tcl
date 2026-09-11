# Run: UALINK_PERIOD_PS=640 UALINK_PROOF_DIR=/new/graph yosys -Q -T -c scripts/prove_dl_basic_control.tcl
# Outputs: exact before/connected/optimized graphs, reset and induction logs or counterexamples.
# Next: audit complete actual graph and run real faults before accepting the proof.
foreach key {UALINK_PERIOD_PS UALINK_PROOF_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PERIOD_PS) ni {1 640 6400 1000000 1000001 1000000000}} {error "Unsupported proof timer profile"}
set root [file dirname [file dirname [file normalize [info script]]]]
set result [file normalize $env(UALINK_PROOF_DIR)]
file mkdir $result
yosys read_verilog [file join $root rtl dl dl_basic_message_control.v]
yosys read_verilog [file join $root verification formal dl_basic_properties.v]
yosys chparam -set C_PERIOD_PS $env(UALINK_PERIOD_PS) dl_basic_properties
yosys hierarchy -check -top dl_basic_properties
yosys proc
yosys flatten
yosys write_json [file join $result before.json]
yosys select -module dl_basic_properties
yosys select -assert-count 1 w:observed_state
yosys select -assert-count 1 w:DUT.reg_local_busy
yosys connect -nomap -nounset -set {observed_state[0:0]} DUT.reg_local_busy
yosys select -assert-count 1 w:DUT.reg_local_sent
yosys connect -nomap -nounset -set {observed_state[1:1]} DUT.reg_local_sent
yosys select -assert-count 1 w:DUT.reg_local_kind
yosys connect -nomap -nounset -set {observed_state[4:2]} DUT.reg_local_kind
yosys select -assert-count 1 w:DUT.reg_local_word
yosys connect -nomap -nounset -set {observed_state[36:5]} DUT.reg_local_word
yosys select -assert-count 1 w:DUT.reg_remote_busy
yosys connect -nomap -nounset -set {observed_state[37:37]} DUT.reg_remote_busy
yosys select -assert-count 1 w:DUT.reg_remote_kind
yosys connect -nomap -nounset -set {observed_state[40:38]} DUT.reg_remote_kind
yosys select -assert-count 1 w:DUT.reg_remote_word
yosys connect -nomap -nounset -set {observed_state[72:41]} DUT.reg_remote_word
yosys select -assert-count 1 w:DUT.reg_remote_rate
yosys connect -nomap -nounset -set {observed_state[88:73]} DUT.reg_remote_rate
yosys select -assert-count 1 w:DUT.reg_local_first
yosys connect -nomap -nounset -set {observed_state[89:89]} DUT.reg_local_first
yosys select -assert-count 1 w:DUT.cnt_remote_age
yosys connect -nomap -nounset -set {observed_state[109:90]} DUT.cnt_remote_age
yosys select -assert-count 1 w:DUT.reg_remote_missed
yosys connect -nomap -nounset -set {observed_state[110:110]} DUT.reg_remote_missed
yosys select -assert-count 1 w:DUT.reg_deadline_fault
yosys connect -nomap -nounset -set {observed_state[111:111]} DUT.reg_deadline_fault
yosys select -assert-count 1 w:DUT.reg_protocol_fault
yosys connect -nomap -nounset -set {observed_state[112:112]} DUT.reg_protocol_fault
yosys select -assert-count 1 w:DUT.reg_peer_rate_valid
yosys connect -nomap -nounset -set {observed_state[113:113]} DUT.reg_peer_rate_valid
yosys select -assert-count 1 w:DUT.reg_peer_rate
yosys connect -nomap -nounset -set {observed_state[129:114]} DUT.reg_peer_rate
yosys select -assert-count 1 w:DUT.reg_peer_device_valid
yosys connect -nomap -nounset -set {observed_state[130:130]} DUT.reg_peer_device_valid
yosys select -assert-count 1 w:DUT.reg_peer_device_type
yosys connect -nomap -nounset -set {observed_state[132:131]} DUT.reg_peer_device_type
yosys select -assert-count 1 w:DUT.reg_peer_device_id
yosys connect -nomap -nounset -set {observed_state[142:133]} DUT.reg_peer_device_id
yosys select -assert-count 1 w:DUT.reg_peer_port_valid
yosys connect -nomap -nounset -set {observed_state[143:143]} DUT.reg_peer_port_valid
yosys select -assert-count 1 w:DUT.reg_peer_port
yosys connect -nomap -nounset -set {observed_state[155:144]} DUT.reg_peer_port
yosys select -clear
yosys check -assert
yosys write_json [file join $result connected.json]
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys select -assert-count 18 dl_basic_properties/i:*
yosys select -clear
yosys write_json [file join $result properties.json]
# Only the first reset is constrained. All other native inputs remain arbitrary.
yosys sat -verify -seq 2 -timeout 240 -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 -show-ports -show-regs -show o_groups -dump_json [file join $result reset_counterexample.json] dl_basic_properties
puts "DL_BASIC_RESET_BASE_PROVED"
# The sole assumption is the complete previous invariant, established by the reset query.
yosys sat -verify -seq 2 -timeout 240 -set-at 1 o_violation 0 -prove o_violation 0 -prove-skip 1 -show-ports -show-regs -show o_groups -dump_json [file join $result step_counterexample.json] dl_basic_properties
puts "DL_BASIC_FULL_INDUCTION_PROVED"
puts "DL_BASIC_FUNCTIONAL_PROVED period_ps=$env(UALINK_PERIOD_PS) state_bits=156 output_bits=194"
