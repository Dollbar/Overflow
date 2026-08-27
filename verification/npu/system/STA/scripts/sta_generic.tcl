set liberty $::env(LIBERTY)
set netlist $::env(NETLIST)
set top $::env(TOP)
set sdc $::env(SDC)

if {[catch {read_liberty $liberty} message]} {
    puts stderr "STA_READ_LIBERTY_FAIL $message"
    exit 3
}
if {[catch {read_verilog $netlist} message]} {
    puts stderr "STA_READ_NETLIST_FAIL $message"
    exit 3
}
if {[catch {link_design $top} message]} {
    puts stderr "STA_LINK_FAIL $message"
    exit 3
}
if {[catch {read_sdc $sdc} message]} {
    puts stderr "STA_READ_SDC_FAIL $message"
    exit 3
}

puts "================================================================"
puts "Evidence: GENERIC_SYNTH pre-layout timing check"
puts "Top: $top"
puts "Clock period: $::env(CLOCK_PERIOD_NS) ns"
puts "Clock uncertainty: $::env(CLOCK_UNCERTAINTY_NS) ns"
puts "Input/output delay: $::env(INPUT_DELAY_NS)/$::env(OUTPUT_DELAY_NS) ns"
puts "Output load: $::env(OUTPUT_LOAD_PF) pF"
puts "================================================================"
report_units
check_setup -verbose
report_checks -path_delay max -group_path_count 3 -endpoint_path_count 1 \
    -fields {slew cap input_pin net fanout} -digits 4
report_worst_slack -max -digits 4
report_tns -max -digits 4
report_clock_min_period -clocks [get_clocks clk_i] -include_port_paths
report_check_types -max_slew -max_capacitance -max_fanout -violators

set worst_slack_seconds [sta::worst_slack_cmd max]
set worst_slack_ns [expr {$worst_slack_seconds * 1.0e9}]
set max_slew_violations [sta::max_slew_violation_count]
set max_capacitance_violations [sta::max_capacitance_violation_count]
set max_fanout_violations [sta::max_fanout_violation_count]
puts "GENERIC_1GHZ_WORST_SLACK_NS $worst_slack_ns"
puts "GENERIC_MAX_SLEW_VIOLATIONS $max_slew_violations"
puts "GENERIC_MAX_CAPACITANCE_VIOLATIONS $max_capacitance_violations"
puts "GENERIC_MAX_FANOUT_VIOLATIONS $max_fanout_violations"
if {$worst_slack_seconds < 0.0} {
    puts stderr "GENERIC_1GHZ_TIMING_FAIL"
    exit 2
}
if {($max_slew_violations != 0) ||
    ($max_capacitance_violations != 0) ||
    ($max_fanout_violations != 0)} {
    puts stderr "GENERIC_ELECTRICAL_LIMIT_FAIL"
    exit 2
}
puts "GENERIC_1GHZ_TIMING_PASS"
exit 0
