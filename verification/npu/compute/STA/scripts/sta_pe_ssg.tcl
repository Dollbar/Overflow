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
puts "Corner: SSG_0P72V_125C"
puts "Clock period: $::env(CLOCK_PERIOD_NS) ns"
puts "Clock uncertainty: $::env(CLOCK_UNCERTAINTY_NS) ns"
puts "Input/output delay: $::env(INPUT_DELAY_NS)/$::env(OUTPUT_DELAY_NS) ns"
puts "Output load: $::env(OUTPUT_LOAD_PF) pF"
puts "================================================================"
report_units
check_setup -verbose
report_checks -path_delay max -group_path_count 10 -endpoint_path_count 1 \
    -fields {slew cap input_pin net fanout} -digits 4
report_worst_slack -max -digits 4
report_tns -max -digits 4
report_clock_min_period -clocks [get_clocks clk_i] -include_port_paths
report_check_types -max_slew -max_capacitance -max_fanout -violators

set worst_slack [sta::worst_slack_cmd max]
puts "SSG_1GHZ_WORST_SLACK_NS $worst_slack"
if {$worst_slack < 0.0} {
    puts stderr "SSG_1GHZ_TIMING_FAIL"
    exit 2
}
puts "SSG_1GHZ_TIMING_PASS"
exit 0
