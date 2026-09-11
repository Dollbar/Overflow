# Run: UALINK_LIBERTY=... UALINK_NETLIST=... UALINK_WIDTH=8|16 yosys -c scripts/equiv_tl_control_partition.tcl
# Output: reset convergence and binary temporal induction logs, nonzero on failure.
# Next: inspect proof status alongside exact-netlist process STA; no protocol proof claim.
foreach key {UALINK_LIBERTY UALINK_NETLIST UALINK_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_WIDTH) ni {8 16}} {error "Undeclared WIDTH"}
set root [file dirname [file dirname [file normalize [info script]]]]
foreach name {tl_control_partition tl_credit_admission tl_control_decode tl_control_tenure} {
    yosys read_verilog [file join $root rtl tl $name.v]
}
yosys chparam -set WIDTH $env(UALINK_WIDTH) tl_control_partition
yosys prep -top tl_control_partition -flatten
yosys rename -top gold
yosys design -stash original
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top tl_control_partition -flatten
yosys rename tl_control_partition gate
yosys design -copy-from original gold
# The real four-bit cursor is compared without cutting its drivers or adding inputs.
yosys select -assert-count 1 gold/w:r_cursor
yosys select -assert-count 1 gate/w:r_cursor
yosys expose gold/w:r_cursor gate/w:r_cursor
yosys miter -equiv -make_outputs -flatten gold gate partition_miter
yosys hierarchy -top partition_miter
yosys opt_clean
yosys sat -verify -seq 2 -timeout 180 -set-def-inputs -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 partition_miter
# Reset convergence above is independent of initial storage. The induction below
# proves the zero-initialized binary state relation with unconstrained later reset/data.
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 8 -timeout 180 -set-def-inputs -set-init-zero -prove trigger 0 partition_miter
