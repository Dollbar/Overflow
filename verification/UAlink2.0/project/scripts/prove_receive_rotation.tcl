# Run: yosys -Q -T -c scripts/prove_receive_rotation.tcl
# Outputs: arbitrary-row combinational equivalence theorem for exactly128 words.
# Next: preserve the ownership invariant and prove actual memory/control transitions.
set root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $root verification formal receive_rotation_bounds.v]
yosys prep -top receive_rotation_bounds
yosys wreduce
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$any*} {t:$assume} {t:$dff*} a:blackbox=1
yosys select -assert-count 6 receive_rotation_bounds/i:*
yosys select -clear
yosys sat -verify -prove o_violation 0 -show-inputs -timeout 30 receive_rotation_bounds
puts "RECEIVE_ROTATION_BOUND_PROVED depth=128"
