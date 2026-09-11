# Run: UALINK_TARGET=path UALINK_LIBERTY=/authorized/corner.lib UALINK_NETLIST=/exact/mapped.v UALINK_PERIOD_NS=0.640 sta -exit scripts/sta_uart_rx.tcl
# Path additionally requires UALINK_DEPTH, UALINK_MACRO_LIBERTY and UALINK_MACRO_VIEW=fast/typical/slow.
# Outputs: real path/electrical reports, macro inventory, conditional setup/hold marker.
# Next: strict check_uart_rx_sta_report.py and provenance checks; synthetic macros are not silicon signoff.
if {[catch {
    foreach key {UALINK_TARGET UALINK_LIBERTY UALINK_NETLIST UALINK_PERIOD_NS} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    if {$env(UALINK_TARGET) ne "path"} {error "Unknown UART target"}
    if {$env(UALINK_PERIOD_NS) ni {0.640 6.400}} {error "Undeclared clock mode"}
    foreach key {UALINK_LIBERTY UALINK_NETLIST} {
        if {![file isfile $env($key)]} {error "Missing $key file"}
    }
    set top dl_uart_rx_$env(UALINK_TARGET)
    set depth 0
    set view none
    read_liberty $env(UALINK_LIBERTY)
    if {$env(UALINK_TARGET) eq "path"} {
        foreach key {UALINK_DEPTH UALINK_MACRO_LIBERTY UALINK_MACRO_VIEW} {
            if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
        }
        set depth $env(UALINK_DEPTH)
        set view $env(UALINK_MACRO_VIEW)
        if {![string is integer -strict $depth] || $depth < 1 || $depth > 4095} {error "UART depth must be1..4095"}
        if {$view ni {fast typical slow}} {error "Undeclared synthetic SRAM view"}
        if {![file isfile $env(UALINK_MACRO_LIBERTY)]} {error "Missing synthetic SRAM Liberty"}
        read_liberty $env(UALINK_MACRO_LIBERTY)
        set memory_library kd28_sram_$view
        if {[llength [get_libs -quiet $memory_library]] != 1} {error "Wrong loaded synthetic SRAM view"}
    }
    read_verilog $env(UALINK_NETLIST)
    link_design $top
    create_clock -name UART_RX -period $env(UALINK_PERIOD_NS) [get_ports i_clk]
    set_clock_uncertainty -setup 0.032 [get_clocks UART_RX]
    set_clock_uncertainty -hold 0.010 [get_clocks UART_RX]
    set_clock_transition 0.050 [get_clocks UART_RX]
    set_input_delay -clock UART_RX -max 0.128 [all_inputs -no_clocks]
    set_input_delay -clock UART_RX -min 0.020 [all_inputs -no_clocks]
    set_input_transition 0.050 [all_inputs -no_clocks]
    set_output_delay -clock UART_RX -max 0.128 [all_outputs]
    set_output_delay -clock UART_RX -min -0.020 [all_outputs]
    set_load 0.005 [all_outputs]
    puts "UART_RX_PROFILE target=$env(UALINK_TARGET) depth=$depth macro_view=$view"
    set path_classes {}
    if {$env(UALINK_TARGET) eq "path"} {
        set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
        set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
        set expected_count [expr {($depth+$macro_depth-1)/$macro_depth}]
        set expected_cell KD28_SRAM_SDP_${macro_depth}X${macro_width}
        set macros [get_cells -hierarchical -filter {ref_name =~ KD28_SRAM_*}]
        if {[llength $macros] != $expected_count} {error "Incorrect actual SRAM count"}
        set macro_inputs {}; set macro_outputs {}; set macro_d {}; set macro_ra {}; set macro_wa {}; set wclocks {}; set rclocks {}
        foreach macro $macros {
            if {[get_property $macro ref_name] ne $expected_cell} {error "Incorrect actual SRAM class"}
            foreach pin [get_pins -of_objects $macro] {
                set leaf [lindex [split [get_full_name $pin] /] end]
                if {$leaf eq "WCLK"} {lappend wclocks $pin} elseif {$leaf eq "RCLK"} {lappend rclocks $pin} elseif {[regexp {^Q\[[0-9]+\]$} $leaf]} {
                    lappend macro_outputs $pin
                } else {
                    lappend macro_inputs $pin
                    if {[regexp {^D\[[0-9]+\]$} $leaf]} {lappend macro_d $pin}
                    if {[regexp {^RA\[[0-9]+\]$} $leaf]} {lappend macro_ra $pin}
                    if {[regexp {^WA\[[0-9]+\]$} $leaf]} {lappend macro_wa $pin}
                }
            }
        }
        puts "UART_RX_LIBRARY name=$memory_library"
        puts "UART_RX_MACRO cell=$expected_cell count=[llength $macros]"
        puts "UART_RX_PINS write_clocks=[llength $wclocks] read_clocks=[llength $rclocks] read_outputs=[llength $macro_outputs] write_data=[llength $macro_d] read_address=[llength $macro_ra] write_address=[llength $macro_wa]"
        set registers [get_cells -hierarchical -filter {ref_name =~ DF*}]
        set reg_outputs [get_pins -of_objects $registers -filter {direction == output}]
        set reg_inputs [get_pins -of_objects $registers -filter {direction == input}]
        set path_classes [list register_to_macro $reg_outputs $macro_inputs input_to_macro [all_inputs -no_clocks] $macro_inputs macro_to_register $macro_outputs $reg_inputs]
        if {$expected_count > 1} {
            set bank_nets [get_nets {Storage_Inst.Storage_Inst.read_bank_q*}]
            set bank_outputs [get_pins -of_objects $bank_nets -filter {direction == output}]
            lappend path_classes bank_select_to_register $bank_outputs $reg_inputs
        }
    }
    report_units
    check_setup -verbose
    foreach {kind sources sinks} $path_classes {
        if {![llength $sources] || ![llength $sinks]} {error "Empty $kind endpoint collection"}
        set minimum [find_timing_paths -from $sources -to $sinks -path_delay min -group_path_count 1]
        if {![llength $minimum]} {error "Missing actual $kind hold path"}
        # get_property formats time to six decimals on the validated OpenSTA.
        # Use the actual path value and library time conversion, matching the
        # nine-digit global report without relaxing any slack acceptance rule.
        set minimum_slack [format %.9f [sta::time_sta_ui [sta::PathEnd_slack [lindex $minimum 0]]]]
        set maximum [find_timing_paths -from $sources -to $sinks -path_delay max -group_path_count 1]
        if {![llength $maximum]} {error "Missing actual $kind setup path"}
        set maximum_slack [format %.9f [sta::time_sta_ui [sta::PathEnd_slack [lindex $maximum 0]]]]
        report_checks -from $sources -to $sinks -path_delay min_max -group_path_count 1 -digits 9
        puts "UART_RX_PATH $kind min_slack_ns=$minimum_slack max_slack_ns=$maximum_slack"
    }
    report_checks -path_delay min_max -group_path_count 10 -digits 9
    report_worst_slack -max -digits 9
    report_worst_slack -min -digits 9
    report_tns -digits 9
    report_check_types -violators -max_slew -max_capacitance -min_pulse_width -min_period
    set bad_setup [find_timing_paths -path_delay max -slack_max -0.000000000001 -group_path_count 1]
    set bad_hold [find_timing_paths -path_delay min -slack_max -0.000000000001 -group_path_count 1]
    if {[llength $bad_setup] || [llength $bad_hold]} {error "Negative setup or hold slack"}
    puts "PASS $top setup/hold at period_ns=$env(UALINK_PERIOD_NS); prelayout budget only"
} reason]} {
    puts stderr "FAIL UART RX STA: $reason"
    exit 1
}
exit 0
