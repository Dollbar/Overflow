# Run: UALINK_PORTS=4 UALINK_CREDIT_WIDTH=16 yosys -c scripts/prove_burst_control.tcl.
# Output: reset base and binary temporal-induction proof against an independent model.
# Next: real-bank/FSM/payload integration; connection qualification is fixed high here.
foreach key {UALINK_PORTS UALINK_CREDIT_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "Undeclared port count"}
if {![string is integer -strict $env(UALINK_CREDIT_WIDTH)] || $env(UALINK_CREDIT_WIDTH) < 3 || $env(UALINK_CREDIT_WIDTH) > 16} {error "Invalid credit width"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl upli upli_burst_control.v]
yosys read_verilog [file join $project_root verification formal upli_burst_properties.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) -set C_CREDIT_WIDTH $env(UALINK_CREDIT_WIDTH) upli_burst_properties
yosys prep -top upli_burst_properties -flatten
yosys check -assert
# No cuts, assumptions, blackboxes or second product instance as an oracle.
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys sat -verify -seq 4 -timeout 90 -set-def-inputs -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 upli_burst_properties
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 20 -timeout 90 -set-def-inputs -set-init-zero -prove o_violation 0 upli_burst_properties
