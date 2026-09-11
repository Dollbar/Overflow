# Run through make -f scripts/burst.mk equiv-burst-control with explicit LIB_ROOT.
# Output: reset-convergence and binary temporal-induction equivalence log.
# Next: STA on this exact mapped netlist; no ignored undefined-cell proof.
foreach key {UALINK_NETLIST UALINK_LIBERTY UALINK_PORTS UALINK_CREDIT_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl upli upli_burst_control.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) -set C_CREDIT_WIDTH $env(UALINK_CREDIT_WIDTH) upli_burst_control
yosys prep -top upli_burst_control
yosys rename upli_burst_control gold
yosys design -stash gold_design
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top upli_burst_control -flatten
yosys rename upli_burst_control gate
yosys design -copy-from gold_design gold
# Match real hidden ownership state as additional outputs, not arbitrary inputs.
# These actual drivers must converge after reset and satisfy induction as well.
foreach suffix {reg_active reg_vc reg_last reg_pools cnt_offset} {
    yosys select -assert-count $env(UALINK_PORTS) gold/w:*.$suffix
    yosys select -assert-count $env(UALINK_PORTS) gate/w:*.$suffix
    yosys expose gold/w:*.$suffix gate/w:*.$suffix
}
yosys miter -equiv -make_outputs -flatten gold gate burst_miter
yosys hierarchy -top burst_miter
yosys opt_clean
yosys sat -verify -seq 4 -timeout 60 -set-def-inputs -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 burst_miter
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 60 -set-def-inputs -set-init-zero -prove trigger 0 burst_miter
