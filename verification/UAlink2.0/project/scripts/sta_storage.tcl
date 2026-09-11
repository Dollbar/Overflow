# Run: make -f scripts/storage.mk sta-storage with explicit roots, DEPTH/WIDTH and macro view.
# Outputs: actual whole-storage paths, macro inventory and synthetic-budget diagnostics.
# Next: fix violations then repeat declared corners/views; not characterized-macro signoff.
if {[catch {
    foreach key {UALINK_LIBERTY UALINK_MACRO_LIBERTY UALINK_NETLIST UALINK_DEPTH UALINK_WIDTH UALINK_MACRO_VIEW UALINK_PERIOD_NS} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    set depth $env(UALINK_DEPTH)
    set width $env(UALINK_WIDTH)
    if {![string is integer -strict $depth] || $depth < 1 || $depth > 65535} {error "depth must be 1..65535"}
    if {![string is integer -strict $width] || $width < 8 || $width % 8 != 0} {error "width must be a positive byte multiple"}
    if {$env(UALINK_PERIOD_NS) ni {0.640 6.400}} {error "Undeclared UPLI clock mode"}
    if {$env(UALINK_MACRO_VIEW) ni {fast typical slow}} {error "Undeclared synthetic macro view"}
    foreach key {UALINK_LIBERTY UALINK_MACRO_LIBERTY UALINK_NETLIST} {
        if {![file isfile $env($key)]} {error "Missing $key file"}
    }
    read_liberty $env(UALINK_LIBERTY)
    read_liberty $env(UALINK_MACRO_LIBERTY)
    set memory_library kd28_sram_$env(UALINK_MACRO_VIEW)
    if {[llength [get_libs -quiet $memory_library]] != 1} {error "Loaded macro library does not match declared view"}
    read_verilog $env(UALINK_NETLIST)
    link_design upli_receive_storage
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
    set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
    set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
    set expected_cell KD28_SRAM_SDP_${macro_depth}X${macro_width}
    set expected_count [expr {(($depth+$macro_depth-1)/$macro_depth)*(($width+$macro_width-1)/$macro_width)}]
    set macros [get_cells -hierarchical -filter {ref_name =~ KD28_SRAM_*}]
    if {[llength $macros] != $expected_count} {error "Incorrect fixed macro count"}
    set macro_inputs {}; set macro_outputs {}; set macro_d {}; set macro_ra {}; set macro_wa {}; set wclocks {}; set rclocks {}
    foreach macro $macros {
        if {[get_property $macro ref_name] ne $expected_cell} {error "Incorrect fixed macro class"}
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
    puts "STORAGE_PROFILE depth=$depth width=$width macro_view=$env(UALINK_MACRO_VIEW)"
    puts "STORAGE_LIBRARY name=$memory_library"
    puts "STORAGE_MACRO cell=$expected_cell count=[llength $macros]"
    puts "STORAGE_PINS write_clocks=[llength $wclocks] read_clocks=[llength $rclocks] read_outputs=[llength $macro_outputs] write_data=[llength $macro_d] read_address=[llength $macro_ra] write_address=[llength $macro_wa]"
    set registers [get_cells -hierarchical -filter {ref_name =~ DF*}]
    set reg_outputs [get_pins -of_objects $registers -filter {direction == output}]
    set reg_inputs [get_pins -of_objects $registers -filter {direction == input}]
    set path_classes [list register_to_macro $reg_outputs $macro_inputs input_to_macro [all_inputs -no_clocks] $macro_inputs macro_to_register $macro_outputs $reg_inputs]
    if {$depth > 2048} {
        set bank_nets [get_nets {Storage_Inst.read_bank_q*}]
        set bank_outputs [get_pins -of_objects $bank_nets -filter {direction == output}]
        lappend path_classes bank_select_to_register $bank_outputs $reg_inputs
    }
    report_units
    check_setup -verbose
    foreach {kind sources sinks} $path_classes {
        if {![llength $sources] || ![llength $sinks]} {error "Empty $kind path endpoint collection"}
        set minimum [find_timing_paths -from $sources -to $sinks -path_delay min -group_path_count 1]
        if {![llength $minimum]} {error "Missing actual $kind hold path"}
        # Path objects are owned by the current search; capture scalar properties
        # before the next search/report replaces the backing path storage.
        set minimum_slack [get_property [lindex $minimum 0] slack]
        set maximum [find_timing_paths -from $sources -to $sinks -path_delay max -group_path_count 1]
        if {![llength $maximum]} {error "Missing actual $kind setup path"}
        set maximum_slack [get_property [lindex $maximum 0] slack]
        report_checks -from $sources -to $sinks -path_delay min_max -group_path_count 1 -digits 6
        puts "STORAGE_PATH $kind min_slack_ns=$minimum_slack max_slack_ns=$maximum_slack"
    }
    report_checks -path_delay min_max -group_path_count 10 -digits 6
    report_worst_slack -max -digits 6
    report_worst_slack -min -digits 6
    report_tns -digits 6
    report_check_types -violators -max_slew -max_capacitance -min_pulse_width -min_period
    set bad_setup [find_timing_paths -path_delay max -slack_max -0.000001 -group_path_count 1]
    set bad_hold [find_timing_paths -path_delay min -slack_max -0.000001 -group_path_count 1]
    if {[llength $bad_setup] || [llength $bad_hold]} {error "Negative setup or hold slack"}
    puts "PASS storage setup/hold at period_ns=$env(UALINK_PERIOD_NS); synthetic macro budget only"
} reason]} {
    puts stderr "FAIL storage STA: $reason"
    exit 1
}
exit 0
