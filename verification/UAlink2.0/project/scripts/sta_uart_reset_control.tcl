# Run: UALINK_CLOCK_PERIOD_PS=640 UALINK_LIBERTY=/authorized/corner.lib UALINK_NETLIST=/exact/mapped.v sta -exit scripts/sta_uart_reset_control.tcl
# Outputs: real register/I/O path and electrical reports plus conditional completion marker.
# Next: reject incomplete/violating reports and bind each result to exact source/netlist/library hashes.
# Scope: prelayout ideal-clock standard-cell budgets; the mapped timer must match the actual clock.
if {[catch {
    foreach key {UALINK_CLOCK_PERIOD_PS UALINK_LIBERTY UALINK_NETLIST} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    if {$env(UALINK_CLOCK_PERIOD_PS) ni {640 6400}} {error "Undeclared physical timer profile"}
    foreach key {UALINK_LIBERTY UALINK_NETLIST} {
        if {![file isfile $env($key)]} {error "Missing $key file"}
    }
    set period_ns [format %.3f [expr {$env(UALINK_CLOCK_PERIOD_PS)/1000.0}]]
    set timer_bits [expr {$env(UALINK_CLOCK_PERIOD_PS) == 640 ? 24 : 21}]
    read_liberty $env(UALINK_LIBERTY)
    read_verilog $env(UALINK_NETLIST)
    link_design dl_uart_reset_control
    create_clock -name UART_RESET -period $period_ns [get_ports i_clk]
    set_clock_uncertainty -setup 0.032 [get_clocks UART_RESET]
    set_clock_uncertainty -hold 0.010 [get_clocks UART_RESET]
    set_clock_transition 0.050 [get_clocks UART_RESET]
    set_input_delay -clock UART_RESET -max 0.128 [all_inputs -no_clocks]
    set_input_delay -clock UART_RESET -min 0.020 [all_inputs -no_clocks]
    set_input_transition 0.050 [all_inputs -no_clocks]
    set_output_delay -clock UART_RESET -max 0.128 [all_outputs]
    set_output_delay -clock UART_RESET -min -0.020 [all_outputs]
    set_load 0.005 [all_outputs]
    puts "UART_RESET_PROFILE configured_period_ps=$env(UALINK_CLOCK_PERIOD_PS) response_depth=4 timer_bits=$timer_bits"
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
    puts "PASS dl_uart_reset_control setup/hold at period_ns=$period_ns; prelayout budget only"
} reason]} {
    puts stderr "FAIL UART RESET STA: $reason"
    exit 1
}
exit 0
