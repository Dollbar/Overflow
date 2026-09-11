# Run: sta -exit scripts/sta_tl_prepared_partition.tcl with UALINK_LIBERTY,
# UALINK_NETLIST and UALINK_PERIOD_NS=0.640 or 6.400 explicitly supplied.
# Outputs: complete timing/limit diagnostics and a conditional pass marker.
# Next: run check_sta_report.py --design prepared_partition and bind to the exact mapped artifact.
# Ideal clocks, local digital IO budgets and no wire parasitics or analog claims.
if {[catch {
    foreach key {UALINK_LIBERTY UALINK_NETLIST UALINK_PERIOD_NS} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    if {$env(UALINK_PERIOD_NS) ni {0.640 6.400}} {error "Undeclared clock mode"}
    foreach key {UALINK_LIBERTY UALINK_NETLIST} {
        if {![file isfile $env($key)]} {error "Missing $key file"}
    }
    read_liberty $env(UALINK_LIBERTY)
    read_verilog $env(UALINK_NETLIST)
    link_design tl_prepared_partition
    create_clock -name UPLI -period $env(UALINK_PERIOD_NS) [get_ports i_clk]
    set_clock_uncertainty -setup 0.032 [get_clocks UPLI]
    set_clock_uncertainty -hold 0.010 [get_clocks UPLI]
    set_clock_transition 0.050 [get_clocks UPLI]
    set_input_delay -clock UPLI -max 0.128 [all_inputs -no_clocks]
    set_input_delay -clock UPLI -min 0.020 [all_inputs -no_clocks]
    set_input_transition 0.050 [all_inputs -no_clocks]
    set_output_delay -clock UPLI -max 0.128 [all_outputs]
    set_output_delay -clock UPLI -min -0.020 [all_outputs]
    set_load 0.005 [all_outputs]
    report_units
    check_setup -verbose
    report_checks -path_delay min_max -group_path_count 10 -digits 6
    report_worst_slack -max -digits 6
    report_worst_slack -min -digits 6
    report_tns -digits 6
    report_check_types -violators -max_slew -max_capacitance -min_pulse_width -min_period
    set bad_setup [find_timing_paths -path_delay max -slack_max -0.000001 -group_path_count 1]
    set bad_hold [find_timing_paths -path_delay min -slack_max -0.000001 -group_path_count 1]
    if {[llength $bad_setup] || [llength $bad_hold]} {error "Negative setup or hold slack"}
    puts "PASS prepared_partition setup/hold at period_ns=$env(UALINK_PERIOD_NS); prelayout budget only"
} reason]} {
    puts stderr "FAIL prepared partition STA: $reason"
    exit 1
}
exit 0
