# Run: UALINK_LIBERTY=corner.lib UALINK_NETLIST=mapped.v UALINK_PERIOD_NS=0.640
#      sta -exit scripts/sta_dl_message_arbiter.tcl
# Outputs: complete path/electrical diagnostics and conditional completion.
# Next: check_dl_message_sta_report.py plus source/netlist/corner identities.
# Local single-clock prelayout budgets; no routing, source RAM, PHY or ACK claim.
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
    link_design dl_message_arbiter
    create_clock -name DL_MESSAGE -period $env(UALINK_PERIOD_NS) [get_ports i_clk]
    set_clock_uncertainty -setup 0.032 [get_clocks DL_MESSAGE]
    set_clock_uncertainty -hold 0.010 [get_clocks DL_MESSAGE]
    set_clock_transition 0.050 [get_clocks DL_MESSAGE]
    set_input_delay -clock DL_MESSAGE -max 0.128 [all_inputs -no_clocks]
    set_input_delay -clock DL_MESSAGE -min 0.020 [all_inputs -no_clocks]
    set_input_transition 0.050 [all_inputs -no_clocks]
    set_output_delay -clock DL_MESSAGE -max 0.128 [all_outputs]
    set_output_delay -clock DL_MESSAGE -min -0.020 [all_outputs]
    set_load 0.005 [all_outputs]
    report_units
    check_setup -verbose
    report_checks -path_delay min_max -group_path_count 10 -digits 9
    report_worst_slack -max -digits 9
    report_worst_slack -min -digits 9
    report_tns -digits 9
    report_check_types -violators -max_slew -max_capacitance -min_pulse_width -min_period
    set bad_setup [find_timing_paths -path_delay max -slack_max -0.000000000001 -group_path_count 1]
    set bad_hold [find_timing_paths -path_delay min -slack_max -0.000000000001 -group_path_count 1]
    if {[llength $bad_setup] || [llength $bad_hold]} {error "Negative setup or hold slack"}
    puts "PASS dl_message_arbiter setup/hold at period_ns=$env(UALINK_PERIOD_NS); prelayout budget only"
} reason]} {
    puts stderr "FAIL DL message arbiter STA: $reason"
    exit 1
}
exit 0
