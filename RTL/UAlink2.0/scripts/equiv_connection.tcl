# Run with UALINK_NETLIST, UALINK_LIBERTY, UALINK_ROLE and UALINK_WAIT.
# Output: Yosys proof log; nonzero on failure or unknown cells. No clock-time claim.
# Next: rerun physical STA; Boolean equivalence cannot prove analog timing.
foreach key {UALINK_NETLIST UALINK_LIBERTY UALINK_ROLE UALINK_WAIT} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
foreach key {UALINK_ROLE UALINK_WAIT} {
    if {$env($key) ni {0 1}} {error "$key must be 0 or 1"}
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl upli upli_connection_side.v]
yosys chparam -set C_IS_COMPLETER $env(UALINK_ROLE) -set C_COMPLETER_WAITS $env(UALINK_WAIT) upli_connection_side
yosys prep -top upli_connection_side
yosys rename upli_connection_side gold
yosys design -stash gold_design

# Actual cell Boolean/FF models come from Liberty, not hand-written ideal stubs.
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top upli_connection_side -flatten
yosys rename upli_connection_side gate
yosys design -copy-from gold_design gold
yosys miter -equiv -make_outputs -flatten gold gate connection_miter
yosys hierarchy -top connection_miter
yosys opt_clean

# First prove reset convergence from arbitrary initial binary FF values.
# In Yosys SAT, time step 1 observes pre-edge state; compare from step 2 onward.
yosys sat -verify -seq 6 -timeout 30 -set-def-inputs -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 connection_miter

# All three RTL registers and the three non-inverting DFQD2 storage bits are zero
# immediately after reset. Prove all subsequent binary input/reset sequences from
# that post-reset state, with base and induction enabled (not a depth-only check).
yosys sat -verify -tempinduct -seq 4 -maxsteps 20 -timeout 30 -set-def-inputs -set-init-zero -prove trigger 0 connection_miter
