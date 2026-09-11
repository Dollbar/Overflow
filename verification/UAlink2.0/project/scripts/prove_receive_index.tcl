# Run: UALINK_DEPTH=128 yosys -Q -T -c scripts/prove_receive_index.tcl
# Output: exact combinational SAT theorem for a declared capacity, without assumptions.
# Next: use only alongside the unchanged ownership invariant and actual-memory induction.
if {![info exists env(UALINK_DEPTH)]} {error "Missing depth"}
set depth $env(UALINK_DEPTH)
if {![string is integer -strict $depth] || $depth < 1 || $depth > 4095} {error "Depth must be1..4095"}
set root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $root verification formal receive_index_bounds.v]
yosys chparam -set C_DEPTH $depth receive_index_bounds
yosys prep -top receive_index_bounds
yosys wreduce
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$any*} {t:$assume} {t:$dff*} a:blackbox=1
yosys select -assert-count 6 receive_index_bounds/i:*
yosys select -clear
yosys sat -verify -prove o_violation 0 -show-inputs -timeout 30 receive_index_bounds
puts "RECEIVE_INDEX_BOUND_PROVED depth=$depth"
