# Run: UALINK_NETLIST=... UALINK_LIBERTY=... UALINK_PORTS=4 yosys -c scripts/equiv_return.tcl
# Outputs: reset-convergence and temporal-induction proof log, nonzero on failure.
# Next: OpenSTA on the same mapped netlist; binary functional proof is not signoff.
foreach key {UALINK_NETLIST UALINK_LIBERTY UALINK_PORTS} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "ports must be 1, 2 or 4"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl upli upli_credit_return_queue.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) upli_credit_return_queue
yosys prep -top upli_credit_return_queue
yosys rename upli_credit_return_queue gold
yosys design -stash gold_design
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top upli_credit_return_queue -flatten
yosys rename upli_credit_return_queue gate
yosys design -copy-from gold_design gold
# Compare real saved slot registers as proved strengthening, not assumptions or cuts.
# The external count is already an output; idle cycles can conceal unequal metadata.
yosys select -assert-count [expr {$env(UALINK_PORTS)*4}] gold/w:*reg_saved
yosys select -assert-count [expr {$env(UALINK_PORTS)*4}] gate/w:*reg_saved
yosys expose gold/w:*reg_saved gate/w:*reg_saved
yosys miter -equiv -make_outputs -flatten gold gate return_miter
yosys hierarchy -top return_miter
yosys opt_clean
yosys sat -verify -seq 4 -timeout 45 -set-def-inputs -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 return_miter
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 45 -set-def-inputs -set-init-zero -prove trigger 0 return_miter
