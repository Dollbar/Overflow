# Run: make -f scripts/return.mk prove-return PORTS=4 DEPTH=5
# Output: reports/return_properties_*.log with reset and binary induction results.
# Next: metadata simulation, mapped equivalence and actual-library STA; no data-order claim.
foreach key {UALINK_PORTS UALINK_DEPTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "ports must be 1, 2 or 4"}
if {![string is integer -strict $env(UALINK_DEPTH)] || $env(UALINK_DEPTH) < 1 || $env(UALINK_DEPTH) > 16} {error "depth must be 1..16"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl upli upli_credit_return_queue.v]
yosys read_verilog [file join $project_root verification formal upli_credit_return_properties.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) -set C_DEPTH $env(UALINK_DEPTH) upli_credit_return_properties
yosys prep -top upli_credit_return_properties -flatten
yosys check -assert
yosys sat -verify -seq 4 -timeout 45 -set-def-inputs -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 upli_credit_return_properties
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 45 -set-def-inputs -set-init-zero -prove o_violation 0 upli_credit_return_properties
