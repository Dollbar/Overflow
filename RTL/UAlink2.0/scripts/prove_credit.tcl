# Run: make -f scripts/credit.mk prove-credit PORTS=4 CREDIT_WIDTH=4 INIT_CYCLES=2
# Output: reports/credit_bounds_*.log; reset/base and inductive capacity proof.
# Next: model regression and mapped equivalence; this property is not full conformance.
foreach key {UALINK_PORTS UALINK_CREDIT_WIDTH UALINK_INIT_CYCLES UALINK_CAPACITIES} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "UALINK_PORTS must be 1, 2 or 4"}
foreach {key lower upper} {UALINK_CREDIT_WIDTH 3 16 UALINK_INIT_CYCLES 2 15} {
    if {![string is integer -strict $env($key)] || $env($key) < $lower || $env($key) > $upper} {
        error "$key outside this proof fixture's bounds"
    }
}
if {![regexp {^[0-9a-fA-F]+$} $env(UALINK_CAPACITIES)]} {error "capacities must be packed hex"}
set bits [expr {$env(UALINK_PORTS)*5*$env(UALINK_CREDIT_WIDTH)}]
if {[string length $env(UALINK_CAPACITIES)] > ($bits+3)/4 || [expr "0x$env(UALINK_CAPACITIES)"] >= (1 << $bits)} {
    error "capacities exceed configured width"
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl upli upli_credit_bank.v]
yosys read_verilog [file join $project_root verification formal upli_credit_bounds.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) -set C_CREDIT_WIDTH $env(UALINK_CREDIT_WIDTH) -set C_INIT_CYCLES $env(UALINK_INIT_CYCLES) -set C_CAPACITIES "${bits}'h$env(UALINK_CAPACITIES)" upli_credit_bounds
yosys prep -top upli_credit_bounds -flatten
yosys check -assert
# Prove that a real reset edge establishes safety from arbitrary binary state.
yosys sat -verify -seq 3 -timeout 45 -set-def-inputs -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 upli_credit_bounds
# No assume or cut points: base checks zero reset state and induction checks all
# binary states satisfying the property. Inputs, including errors/reset, are free.
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 45 -set-def-inputs -set-init-zero -prove o_violation 0 upli_credit_bounds
