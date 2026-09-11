# Run through channel_proof.mk with explicit external dependency root.
# Outputs: actual-state observation netlist, proof JSON and SAT counterexample if failing.
# Next: metadata/content proofs; arbitrary macro Q here only supports control ownership.
source [file join [file dirname [file normalize [info script]]] channel_config.tcl]
foreach key {UALINK_KD28_ROOT UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
set macro_rtl [file join $env(UALINK_KD28_ROOT) Library models kd28 sram rtl kd28_sram_blackboxes.v]
set map_rtl [file join $env(UALINK_KD28_ROOT) Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
yosys read_verilog -lib $macro_rtl
yosys read_verilog $map_rtl
foreach name {upli_receive_fifo upli_receive_storage upli_credit_initializer upli_credit_return_queue upli_receive_channel} {
    yosys read_verilog [file join $channel_project_root rtl upli ${name}.v]
}
yosys chparam -set C_NUM_PORTS $channel_ports -set C_PAYLOAD_WIDTH $channel_width -set C_CREDIT_WIDTH $channel_credit_width -set C_CAPACITIES $channel_yosys_capacity -set C_RETURN_DEPTH $channel_return_depth upli_receive_channel
yosys prep -top upli_receive_channel -flatten
# All controller state retains real drivers. Only new output aliases are added.
yosys select -module upli_receive_channel
foreach {output signal bits} {o_formal_initial_valid initial_valid 4 o_formal_normal_valid normal_valid 4 o_formal_normal_num normal_num 8} {
    yosys select -assert-count 1 w:$signal
    yosys add -output $output $bits
    # Yosys may trim the constant inactive-port upper bits of internal aliases.
    # Observe all active bits and explicitly restore the inactive zero shape.
    set active_bits [expr {$bits*$channel_ports/4}]
    yosys connect -nounset -set [format {%s[%d:0]} $output [expr {$active_bits-1}]] [format {%s[%d:0]} $signal [expr {$active_bits-1}]]
    if {$active_bits < $bits} {
        yosys connect -nounset -set [format {%s[%d:%d]} $output [expr {$bits-1}] $active_bits] "[expr {$bits-$active_bits}]'d0"
    }
}
yosys add -output o_formal_stages [expr {$channel_ports*3}]
for {set port 0} {$port < $channel_ports} {incr port} {
    set signal [format {Initializer_Inst.gen_ports[%d].gen_active.state_current} $port]
    yosys select -assert-count 1 w:$signal
    yosys connect -nounset -set [format {o_formal_stages[%d:%d]} [expr {$port*3+2}] [expr {$port*3}]] $signal
}
foreach {member width} [list unread $channel_credit_width pending 1 cached 2 read_addr $channel_credit_width bank 5] {
    yosys add -output o_formal_$member [expr {$channel_ports*5*$width}]
    set slot 0
    foreach depth $channel_capacities {
        set dest [format {o_formal_%s[%d:%d]} $member [expr {($slot+1)*$width-1}] [expr {$slot*$width}]]
        if {$depth == 0} {
            yosys connect -nounset -set $dest "${width}'d0"
        } else {
            set prefix [expr {$member in {pending read_addr} ? "reg" : "cnt"}]
            set signal [format {gen_accounts[%d].gen_storage.Storage_Inst.Fifo_Inst.%s_%s} $slot $prefix $member]
            if {$member eq "bank"} {set signal [format {gen_accounts[%d].gen_storage.Storage_Inst.Storage_Inst.read_bank_q} $slot]}
            yosys select -assert-count 1 w:$signal
            set source_bits $width
            if {$member in {unread read_addr}} {
                set source_bits 1
                while {(1 << $source_bits) <= $depth} {incr source_bits}
            }
            if {$member eq "bank"} {
                set banks [expr {$depth <= 2048 ? 1 : ($depth+2047)/2048}]
                set source_bits 1
                while {(1 << $source_bits) < $banks} {incr source_bits}
            }
            set low [expr {$slot*$width}]
            yosys connect -nounset -set [format {o_formal_%s[%d:%d]} $member [expr {$low+$source_bits-1}] $low] $signal
            if {$source_bits < $width} {
                yosys connect -nounset -set [format {o_formal_%s[%d:%d]} $member [expr {$low+$width-1}] [expr {$low+$source_bits}]] "[expr {$width-$source_bits}]'d0"
            }
        }
        incr slot
    }
}
yosys select -clear
yosys check -assert
yosys write_verilog -noattr [file join $run_dir instrumented.v]
yosys read_verilog [file join $channel_project_root verification formal upli_receive_channel_properties.v]
yosys chparam -set C_NUM_PORTS $channel_ports -set C_PAYLOAD_WIDTH $channel_width -set C_CREDIT_WIDTH $channel_credit_width -set C_CAPACITIES $channel_yosys_capacity -set C_RETURN_DEPTH $channel_return_depth upli_receive_channel_properties
yosys prep -top upli_receive_channel_properties -flatten
dict for {type count} $channel_macro_counts {yosys select -assert-count $count upli_receive_channel_properties/t:$type}
yosys select -assert-count $channel_macro_total upli_receive_channel_properties/t:KD28_SRAM_*
# Lift only actual macro cells to the environment: every Q becomes a free primary
# input, while clocks, enables, addresses and D remain real controller outputs.
if {$channel_macro_total > 0} {yosys expose -evert upli_receive_channel_properties/t:KD28_SRAM_*}
yosys select -clear
yosys check -assert
yosys write_json [file join $run_dir properties.json]
yosys sat -verify -seq 6 -timeout 120 -set-def-inputs -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 -dump_vcd [file join $run_dir reset_counterexample.vcd] upli_receive_channel_properties
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 120 -set-def-inputs -set-init-zero -prove o_violation 0 -show account_bad -show port_bad -show o_violation -dump_vcd [file join $run_dir induction_counterexample.vcd] upli_receive_channel_properties
