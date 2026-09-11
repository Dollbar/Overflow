# Run: UALINK_NETLIST=... UALINK_LIBERTY=... UALINK_PORTS=4 yosys -c scripts/equiv_initialization.tcl
# Output: reset-convergence and temporal-induction proof log, nonzero on failure.
# Next: OpenSTA on the same mapped netlist; this is binary functional proof only.
foreach key {UALINK_NETLIST UALINK_LIBERTY UALINK_PORTS} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "UALINK_PORTS must be 1, 2 or 4"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl upli upli_credit_initializer.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) upli_credit_initializer
yosys prep -top upli_credit_initializer
yosys rename upli_credit_initializer gold
yosys design -stash gold_design

# Actual Liberty Boolean/FF definitions; no ignored unknown-cell proof option.
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top upli_credit_initializer -flatten
yosys rename upli_credit_initializer gate
yosys design -copy-from gold_design gold
# Expose actual account stage and issued count as additional compared outputs.
# No cut/input option: their real drivers remain, and reset/base must prove the
# relation. Compare hidden publication progress as a proved strengthening;
# external idle outputs alone do not identify the current account or issued count.
yosys select -assert-count $env(UALINK_PORTS) gold/w:*state_current
yosys select -assert-count $env(UALINK_PORTS) gate/w:*state_current
yosys expose gold/w:*state_current gate/w:*state_current
yosys select -assert-count $env(UALINK_PORTS) gold/w:*cnt_issued
yosys select -assert-count $env(UALINK_PORTS) gate/w:*cnt_issued
yosys expose gold/w:*cnt_issued gate/w:*cnt_issued
yosys miter -equiv -make_outputs -flatten gold gate initialization_miter
yosys hierarchy -top initialization_miter
yosys opt_clean

# Step one observes pre-edge state; one reset edge must converge by step two.
yosys sat -verify -seq 4 -timeout 45 -set-def-inputs -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 initialization_miter
# All authored and mapped non-inverting storage bits are zero after reset.
# Prove base plus binary-state induction; traffic/reset remain unconstrained.
# Explicit -tempinduct-def excludes X-valued inductive states, not binary data.
# This is not four-state X-propagation equivalence or an analog proof.
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 45 -set-def-inputs -set-init-zero -prove trigger 0 initialization_miter
