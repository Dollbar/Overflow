# Run: sta -exit scripts/size_dl_message_arbiter.tcl with explicit UALINK_LIBERTY,
# UALINK_NETLIST, UALINK_SIZE_OUT and UALINK_SIZE_CHANGES.
# Outputs: bounded sizing journal, diagnostic-only netlist and actual slacks.
# Next: apply checked replacements to the original graph, prove equivalence,
# and run every declared corner/clock. This is not a timing pass marker.
# Never use the OpenSTA export as the product: constant output ties may be lost.
if {[catch {
    foreach key {UALINK_LIBERTY UALINK_NETLIST UALINK_SIZE_OUT UALINK_SIZE_CHANGES} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    foreach key {UALINK_LIBERTY UALINK_NETLIST} {
        if {![file isfile $env($key)]} {error "Missing $key file"}
    }
    set destination [file normalize $env(UALINK_SIZE_OUT)]
    set changes_path [file normalize $env(UALINK_SIZE_CHANGES)]
    if {$destination eq $changes_path} {error "Sizing outputs must be distinct"}
    foreach path [list $destination $changes_path] {
        if {$path eq [file normalize $env(UALINK_NETLIST)] ||
            $path eq [file normalize $env(UALINK_LIBERTY)] || ![catch {file type $path}]} {
            error "Sizing output must be a new, separate regular file"
        }
    }
    read_liberty $env(UALINK_LIBERTY)
    read_verilog $env(UALINK_NETLIST)
    link_design dl_message_arbiter
    create_clock -name DL_MESSAGE -period 0.640 [get_ports i_clk]
    set_clock_uncertainty -setup 0.032 [get_clocks DL_MESSAGE]
    set_clock_uncertainty -hold 0.010 [get_clocks DL_MESSAGE]
    set_clock_transition 0.050 [get_clocks DL_MESSAGE]
    set_input_delay -clock DL_MESSAGE -max 0.128 [all_inputs -no_clocks]
    set_input_delay -clock DL_MESSAGE -min 0.020 [all_inputs -no_clocks]
    set_input_transition 0.050 [all_inputs -no_clocks]
    set_output_delay -clock DL_MESSAGE -max 0.128 [all_outputs]
    set_output_delay -clock DL_MESSAGE -min -0.020 [all_outputs]
    set_load 0.005 [all_outputs]
    set changes 0
    set journal {}
    for {set round 0} {$round < 80} {incr round} {
        set initial_wns [sta::worst_slack -max]
        puts "SIZE round=$round setup=$initial_wns hold=[sta::worst_slack -min] tns=[sta::total_negative_slack -max]"
        if {$initial_wns >= 0.010} {break}
        set names {}
        # Copy names before a replacement invalidates path objects.
        foreach path [find_timing_paths -path_delay max -group_path_count 25] {
            foreach point [get_property $path points] {
                set pin [get_property $point pin]
                if {[get_property $pin is_port]} {continue}
                foreach inst [get_cells -of_objects $pin] {lappend names [get_property $inst full_name]}
            }
        }
        set progress 0
        foreach name [lsort -unique $names] {
            set inst [get_cells $name]
            set original [get_property $inst liberty_cell]
            set original_name [get_property $original name]
            if {![regexp {^(.*)D([0-9]+(?:P[0-9]+)?)BWP40P140$} $original_name unused family drive]} {continue}
            # Sequential and clock-gating cells are never candidates. Only the
            # measured DEL025 family may trial a same-polarity ordinary buffer;
            # pin compatibility, global hold and later Boolean proof are required.
            set delay_trial [expr {$family eq "DEL025"}]
            if {[regexp {^(DF|SD|SDF|LH|LN|CKLN|CKLH)} $family] ||
                ([string match DEL* $family] && !$delay_trial)} {continue}
            set candidate_family $family
            if {$delay_trial} {set candidate_family BUFF}
            set strength [string map {P .} $drive]
            set before_wns [sta::worst_slack -max]
            set before_tns [sta::total_negative_slack -max]
            foreach candidate [get_lib_cells -quiet */${candidate_family}D*BWP40P140] {
                set candidate_name [get_property $candidate name]
                if {![regexp {^(.*)D([0-9]+(?:P[0-9]+)?)BWP40P140$} $candidate_name unused found_family found_drive]} {continue}
                if {$found_family ne $candidate_family ||
                    (!$delay_trial && [string map {P .} $found_drive] <= $strength)} {continue}
                if {![replace_cell $inst $candidate]} {continue}
                set after_wns [sta::worst_slack -max]
                set after_tns [sta::total_negative_slack -max]
                set after_hold [sta::worst_slack -min]
                if {$after_hold >= 0.005 && $after_wns >= $before_wns-0.000001 &&
                    ($after_wns > $before_wns+0.000001 || $after_tns > $before_tns+0.000001)} {
                    puts "RESIZE $name $original_name $candidate_name setup=$after_wns hold=$after_hold tns=$after_tns"
                    lappend journal [list $name $original_name $candidate_name]
                    incr changes
                    set progress 1
                    break
                }
                if {![replace_cell $inst $original]} {error "Cannot restore rejected sizing trial"}
            }
        }
        if {!$progress} {break}
    }
    report_worst_slack -max -digits 6
    report_worst_slack -min -digits 6
    report_check_types -violators -max_slew -max_capacitance -min_pulse_width -min_period
    write_verilog $destination
    set journal_file [open $changes_path w]
    puts $journal_file $journal
    close $journal_file
    puts "DONE DL message sizing changes=$changes; equivalence and all-corner STA still required"
} reason]} {
    puts stderr "FAIL DL message sizing: $reason"
    exit 1
}
exit 0
