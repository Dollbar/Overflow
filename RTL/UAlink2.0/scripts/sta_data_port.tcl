# Run from candidate: UALINK_PERIOD_PS=640 UALINK_LIBERTY=/authorized/corner.lib UALINK_NETLIST=/exact/mapped.v UALINK_MACRO_LIBERTY=/authorized/slow.lib UALINK_MACRO_VIEW=slow sta -exit scripts/sta_data_port.tcl
# Outputs: real two-macro inventory, six macro path classes and original-budget timing reports.
# Next: independently audit reports and mapped correspondence; synthetic SRAM is not silicon signoff.
if {[catch {
    foreach key {UALINK_PERIOD_PS UALINK_LIBERTY UALINK_NETLIST UALINK_MACRO_LIBERTY UALINK_MACRO_VIEW} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    if {$env(UALINK_PERIOD_PS) ni {640 6400}} {error "Undeclared clock profile"}
    if {$env(UALINK_MACRO_VIEW) ni {fast typical slow}} {error "Undeclared synthetic SRAM view"}
    foreach key {UALINK_LIBERTY UALINK_NETLIST UALINK_MACRO_LIBERTY} {
        if {![file isfile $env($key)]} {error "Missing $key file"}
    }
    set period_ns [format %.3f [expr {$env(UALINK_PERIOD_PS)/1000.0}]]
    set view $env(UALINK_MACRO_VIEW)
    read_liberty $env(UALINK_LIBERTY)
    read_liberty $env(UALINK_MACRO_LIBERTY)
    if {[llength [get_libs -quiet kd28_sram_$view]] != 1} {error "Wrong synthetic SRAM library"}
    read_verilog $env(UALINK_NETLIST)
    link_design dl_replay_data_port
    create_clock -name LLR_DATA -period $period_ns [get_ports i_clk]
    set_clock_uncertainty -setup 0.032 [get_clocks LLR_DATA]
    set_clock_uncertainty -hold 0.010 [get_clocks LLR_DATA]
    set_clock_transition 0.050 [get_clocks LLR_DATA]
    set_input_delay -clock LLR_DATA -max 0.128 [all_inputs -no_clocks]
    set_input_delay -clock LLR_DATA -min 0.020 [all_inputs -no_clocks]
    set_input_transition 0.050 [all_inputs -no_clocks]
    set_output_delay -clock LLR_DATA -max 0.128 [all_outputs]
    set_output_delay -clock LLR_DATA -min -0.020 [all_outputs]
    set_load 0.005 [all_outputs]
    puts "LLR_DATA_PROFILE depth=128 width=32 period_ns=$period_ns macro_view=$view"
    set macros [get_cells -hierarchical -filter {ref_name =~ KD28_SRAM_*}]
    if {[llength $macros] != 2} {error "Incorrect actual macro count"}
    set registers [get_cells -hierarchical -filter {ref_name =~ DF*}]
    set reg_outputs [get_pins -of_objects $registers -filter {direction == output}]
    set path_classes {}; set lanes {}
    foreach macro $macros {
        set name [get_full_name $macro]
        if {![regexp {^u_storage\.u_storage\.gen_depth_bank\[0\]\.gen_width_lane\[([01])\]} $name unused lane]} {error "Unknown actual macro owner $name"}
        if {$lane in $lanes} {error "Duplicate width lane"}
        lappend lanes $lane
        if {[get_property $macro ref_name] ne "KD28_SRAM_SDP_256X32"} {error "Incorrect actual macro class"}
        set inputs {}; set outputs {}; set wc {}; set rc {}; set data {}; set ra {}; set wa {}
        foreach pin [get_pins -of_objects $macro] {
            set leaf [lindex [split [get_full_name $pin] /] end]
            if {$leaf eq "WCLK"} {lappend wc $pin} elseif {$leaf eq "RCLK"} {lappend rc $pin} elseif {[regexp {^Q\[[0-9]+\]$} $leaf]} {
                lappend outputs $pin
            } else {
                lappend inputs $pin
                if {[regexp {^D\[[0-9]+\]$} $leaf]} {lappend data $pin}
                if {[regexp {^RA\[[0-9]+\]$} $leaf]} {lappend ra $pin}
                if {[regexp {^WA\[[0-9]+\]$} $leaf]} {lappend wa $pin}
            }
        }
        if {[llength $wc] != 1 || [llength $rc] != 1 || [llength $outputs] != 32 || [llength $data] != 32 || [llength $ra] != 8 || [llength $wa] != 8} {error "Macro pin inventory mismatch"}
        puts "LLR_DATA_MACRO lane=$lane cell=KD28_SRAM_SDP_256X32 write_clock=1 read_clock=1 outputs=32 data=32 ra=8 wa=8"
        lappend path_classes lane${lane}_register_to_macro $reg_outputs $inputs lane${lane}_input_to_macro [all_inputs -no_clocks] $inputs lane${lane}_macro_to_output $outputs [all_outputs]
    }
    report_units
    check_setup -verbose
    foreach {kind sources sinks} $path_classes {
        if {![llength $sources] || ![llength $sinks]} {error "Empty actual $kind endpoints"}
        set minimum [find_timing_paths -from $sources -to $sinks -path_delay min -group_path_count 1]
        if {![llength $minimum]} {error "Missing actual $kind hold path"}
        # Consume a path before the next search replaces OpenSTA's owned path ends.
        set lo [format %.9f [sta::time_sta_ui [sta::PathEnd_slack [lindex $minimum 0]]]]
        set maximum [find_timing_paths -from $sources -to $sinks -path_delay max -group_path_count 1]
        if {![llength $maximum]} {error "Missing actual $kind setup path"}
        set hi [format %.9f [sta::time_sta_ui [sta::PathEnd_slack [lindex $maximum 0]]]]
        report_checks -from $sources -to $sinks -path_delay min_max -group_path_count 1 -digits 9
        puts "LLR_DATA_PATH $kind min_slack_ns=$lo max_slack_ns=$hi"
    }
    report_checks -path_delay min_max -group_path_count 10 -digits 9
    report_worst_slack -max -digits 9
    report_worst_slack -min -digits 9
    report_tns -digits 9
    report_check_types -violators -max_slew -max_capacitance -min_pulse_width -min_period
    puts "LLR_DATA_REPORT_COMPLETE synthetic_macro_timing=true"
    set bad_setup [find_timing_paths -path_delay max -slack_max -0.000000000001 -group_path_count 1]
    set bad_hold [find_timing_paths -path_delay min -slack_max -0.000000000001 -group_path_count 1]
    if {[llength $bad_setup] || [llength $bad_hold]} {error "Negative setup or hold slack"}
    puts "PASS LLR_DATA setup/hold period_ns=$period_ns; prelayout budget only"
} reason]} {
    puts stderr "FAIL LLR_DATA STA: $reason"
    exit 1
}
exit 0
