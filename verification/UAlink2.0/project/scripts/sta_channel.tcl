# Run: make -f scripts/channel.mk sta-channel with explicit libraries and mapped profile.
# Outputs: full-channel paths, actual macro inventory and unchanged timing-budget checks.
# Next: fix real violations, prove equivalence, repeat all declared views; no silicon signoff.
if {[catch {
    source [file join [file dirname [file normalize [info script]]] channel_config.tcl]
    foreach key {UALINK_LIBERTY UALINK_MACRO_LIBERTY UALINK_NETLIST UALINK_MACRO_VIEW UALINK_PERIOD_NS} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    if {$env(UALINK_PERIOD_NS) ni {0.640 6.400} || $env(UALINK_MACRO_VIEW) ni {fast typical slow}} {error "Undeclared timing mode"}
    foreach key {UALINK_LIBERTY UALINK_MACRO_LIBERTY UALINK_NETLIST} {
        if {![file isfile $env($key)]} {error "Missing $key file"}
    }
    read_liberty $env(UALINK_LIBERTY)
    read_liberty $env(UALINK_MACRO_LIBERTY)
    set memory_library kd28_sram_$env(UALINK_MACRO_VIEW)
    if {[llength [get_libs -quiet $memory_library]] != 1} {error "Loaded macro library differs from declared view"}
    read_verilog $env(UALINK_NETLIST)
    link_design upli_receive_channel
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
    set macros [get_cells -hierarchical -quiet -filter {ref_name =~ KD28_SRAM_*}]
    if {[llength $macros] != $channel_macro_total} {error "Incorrect actual channel macro count"}
    set actual_counts {}; set macro_inputs {}; set macro_outputs {}; set data_pins {}; set read_addresses {}; set write_addresses {}; set wclocks {}; set rclocks {}
    foreach macro $macros {
        set type [get_property $macro ref_name]
        if {![dict exists $channel_macro_counts $type]} {error "Incorrect channel macro class"}
        dict incr actual_counts $type
        foreach pin [get_pins -of_objects $macro] {
            set leaf [lindex [split [get_full_name $pin] /] end]
            if {$leaf eq "WCLK"} {lappend wclocks $pin} elseif {$leaf eq "RCLK"} {lappend rclocks $pin} elseif {[regexp {^Q\[[0-9]+\]$} $leaf]} {
                lappend macro_outputs $pin
            } else {
                lappend macro_inputs $pin
                if {[regexp {^D\[[0-9]+\]$} $leaf]} {lappend data_pins $pin}
                if {[regexp {^RA\[[0-9]+\]$} $leaf]} {lappend read_addresses $pin}
                if {[regexp {^WA\[[0-9]+\]$} $leaf]} {lappend write_addresses $pin}
            }
        }
    }
    puts "CHANNEL_PROFILE ports=$channel_ports width=$channel_width credit_width=$channel_credit_width cap_hex=$channel_cap_hex return_depth=$channel_return_depth macro_view=$env(UALINK_MACRO_VIEW)"
    puts "CHANNEL_LIBRARY name=$memory_library"
    dict for {type count} $channel_macro_counts {
        if {![dict exists $actual_counts $type] || [dict get $actual_counts $type] != $count} {error "Wrong count of $type"}
        puts "CHANNEL_MACRO cell=$type count=[dict get $actual_counts $type]"
    }
    puts "CHANNEL_PINS write_clocks=[llength $wclocks] read_clocks=[llength $rclocks] read_outputs=[llength $macro_outputs] write_data=[llength $data_pins] read_address=[llength $read_addresses] write_address=[llength $write_addresses]"
    set registers [get_cells -hierarchical -filter {ref_name =~ DF*}]
    set reg_outputs [get_pins -of_objects $registers -filter {direction == output}]
    set reg_inputs [get_pins -of_objects $registers -filter {direction == input}]
    set classes [list control_to_register [all_inputs -no_clocks] $reg_inputs]
    if {$channel_macro_total > 0} {
        set head_ports [get_ports {o_head_payload* o_head_vc* o_head_pool o_head_valid o_consume_valid}]
        lappend classes register_to_macro $reg_outputs $macro_inputs input_to_macro [all_inputs -no_clocks] $macro_inputs macro_to_register $macro_outputs $reg_inputs
        lappend classes selection_to_head [get_ports {i_consumer_port* i_consumer_account*}] $head_ports register_to_head $reg_outputs $head_ports consumer_to_register [get_ports i_consumer_ready] $reg_inputs
        set banked 0
        foreach depth $channel_capacities {if {$depth > 2048} {set banked 1}}
        if {$banked} {
            set bank_nets [get_nets -hierarchical {*read_bank_q*}]
            set bank_outputs [get_pins -of_objects $bank_nets -filter {direction == output}]
            lappend classes bank_select_to_register $bank_outputs $reg_inputs
        }
    }
    report_units
    check_setup -verbose
    foreach {kind sources sinks} $classes {
        if {![llength $sources] || ![llength $sinks]} {error "Empty actual $kind endpoints"}
        set paths [find_timing_paths -from $sources -to $sinks -path_delay min -group_path_count 1]
        if {![llength $paths]} {error "Missing actual $kind hold path"}
        set minimum [get_property [lindex $paths 0] slack]
        set paths [find_timing_paths -from $sources -to $sinks -path_delay max -group_path_count 1]
        if {![llength $paths]} {error "Missing actual $kind setup path"}
        set maximum [get_property [lindex $paths 0] slack]
        report_checks -from $sources -to $sinks -path_delay min_max -group_path_count 1 -digits 6
        puts "CHANNEL_PATH $kind min_slack_ns=$minimum max_slack_ns=$maximum"
    }
    report_checks -path_delay min_max -group_path_count 10 -digits 6
    report_worst_slack -max -digits 6
    report_worst_slack -min -digits 6
    report_tns -digits 6
    report_check_types -violators -max_slew -max_capacitance -min_pulse_width -min_period
    set bad_setup [find_timing_paths -path_delay max -slack_max -0.000001 -group_path_count 1]
    set bad_hold [find_timing_paths -path_delay min -slack_max -0.000001 -group_path_count 1]
    if {[llength $bad_setup] || [llength $bad_hold]} {error "Negative setup or hold slack"}
    puts "PASS channel setup/hold at period_ns=$env(UALINK_PERIOD_NS); synthetic macro budget only"
} reason]} {
    puts stderr "FAIL channel STA: $reason"
    exit 1
}
exit 0
