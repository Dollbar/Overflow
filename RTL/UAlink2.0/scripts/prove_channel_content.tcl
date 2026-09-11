# Run through channel_content.mk with an explicit authorized external model root.
# Outputs: read-only actual SRAM/state observations and SAT property netlist/counterexamples.
# Next: prove finite native metadata/return cases; no verification memory expansion is used for PPA.
source [file join [file dirname [file normalize [info script]]] channel_config.tcl]
foreach key {UALINK_KD28_ROOT UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
set sram_dir [file join $env(UALINK_KD28_ROOT) Library models kd28 sram rtl]
yosys read_verilog [file join $sram_dir kd28_sram_sdp_model.v]
yosys read_verilog [file join $sram_dir kd28_sram_cells.v]
yosys read_verilog [file join $env(UALINK_KD28_ROOT) Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
foreach name {upli_receive_fifo upli_receive_storage upli_credit_initializer upli_credit_return_queue upli_receive_channel} {
    yosys read_verilog [file join $channel_project_root rtl upli ${name}.v]
}
yosys chparam -set C_NUM_PORTS $channel_ports -set C_PAYLOAD_WIDTH $channel_width -set C_CREDIT_WIDTH $channel_credit_width -set C_CAPACITIES $channel_yosys_capacity -set C_RETURN_DEPTH $channel_return_depth upli_receive_channel
yosys prep -top upli_receive_channel -flatten
yosys memory_map
yosys opt_clean
yosys select -module upli_receive_channel
set max_depth 1
foreach depth $channel_capacities {set max_depth [expr {max($max_depth,$depth)}]}
foreach {output signal bits} {o_formal_initial_valid initial_valid 4 o_formal_normal_valid normal_valid 4 o_formal_normal_pool normal_pool 4 o_formal_normal_vc normal_vc 8 o_formal_normal_num normal_num 8} {
    yosys select -assert-count 1 w:$signal
    yosys add -output $output $bits
    set active_bits [expr {$bits*$channel_ports/4}]
    yosys connect -nounset -set [format {%s[%d:0]} $output [expr {$active_bits-1}]] [format {%s[%d:0]} $signal [expr {$active_bits-1}]]
    if {$active_bits < $bits} {yosys connect -nounset -set [format {%s[%d:%d]} $output [expr {$bits-1}] $active_bits] "[expr {$bits-$active_bits}]'d0"}
}
yosys add -output o_formal_stages [expr {$channel_ports*3}]
yosys add -output o_formal_returns [expr {$channel_ports*$channel_return_depth*3}]
for {set port 0} {$port < $channel_ports} {incr port} {
    foreach {output signal width} [list o_formal_stages [format {Initializer_Inst.gen_ports[%d].gen_active.state_current} $port] 3 o_formal_returns [format {Return_Inst.gen_ports[%d].gen_active.saved_metadata} $port] [expr {$channel_return_depth*3}]] {
        yosys select -assert-count 1 w:$signal
        yosys connect -nounset -set [format {%s[%d:%d]} $output [expr {($port+1)*$width-1}] [expr {$port*$width}]] $signal
    }
}
foreach {member width suffix} [list unread $channel_credit_width Fifo_Inst.cnt_unread pending 1 Fifo_Inst.reg_pending cached 2 Fifo_Inst.cnt_cached read_addr $channel_credit_width read_addr write_addr $channel_credit_width write_addr head $channel_word_width Fifo_Inst.reg_head tail $channel_word_width Fifo_Inst.reg_tail read_result $channel_word_width read_data] {
    yosys add -output o_formal_$member [expr {$channel_ports*5*$width}]
    set slot 0
    foreach depth $channel_capacities {
        set low [expr {$slot*$width}]
        if {$depth == 0} {
            yosys connect -nounset -set [format {o_formal_%s[%d:%d]} $member [expr {$low+$width-1}] $low] "${width}'d0"
        } else {
            set signal [format {gen_accounts[%d].gen_storage.Storage_Inst.%s} $slot $suffix]
            yosys select -assert-count 1 w:$signal
            set source_bits $width
            if {$member in {unread read_addr write_addr}} {
                set source_bits 1
                while {(1 << $source_bits) <= $depth} {incr source_bits}
            }
            yosys connect -nounset -set [format {o_formal_%s[%d:%d]} $member [expr {$low+$source_bits-1}] $low] $signal
            if {$source_bits < $width} {yosys connect -nounset -set [format {o_formal_%s[%d:%d]} $member [expr {$low+$width-1}] [expr {$low+$source_bits}]] "[expr {$width-$source_bits}]'d0"}
        }
        incr slot
    }
}
yosys add -output o_formal_memory [expr {$channel_ports*5*$max_depth*$channel_word_width}]
set slot 0
foreach depth $channel_capacities {
    set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
    set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
    for {set address 0} {$address < $max_depth} {incr address} {
        set low [expr {($slot*$max_depth+$address)*$channel_word_width}]
        if {$address >= $depth} {
            yosys connect -nounset -set [format {o_formal_memory[%d:%d]} [expr {$low+$channel_word_width-1}] $low] "${channel_word_width}'d0"
            continue
        }
        for {set tile 0} {$tile*$macro_width < $channel_word_width} {incr tile} {
            set chunk [expr {min($macro_width,$channel_word_width-$tile*$macro_width)}]
            set signal [format {gen_accounts[%d].gen_storage.Storage_Inst.Storage_Inst.gen_depth_bank[%d].gen_width_lane[%d].gen_sdp_%dx%d.u_sram.u_model.memory[%d]} $slot [expr {$address/$macro_depth}] $tile $macro_depth $macro_width [expr {$address%$macro_depth}]]
            yosys select -assert-count 1 w:$signal
            set part_low [expr {$low+$tile*$macro_width}]
            yosys connect -nounset -set [format {o_formal_memory[%d:%d]} [expr {$part_low+$chunk-1}] $part_low] [format {%s[%d:0]} $signal [expr {$chunk-1}]]
        }
    }
    incr slot
}
yosys select -clear
yosys check -assert
yosys write_verilog -noattr [file join $run_dir instrumented.v]
foreach name {upli_receive_word_invariant upli_channel_content_properties} {yosys read_verilog [file join $channel_project_root verification formal ${name}.v]}
yosys chparam -set C_NUM_PORTS $channel_ports -set C_PAYLOAD_WIDTH $channel_width -set C_CREDIT_WIDTH $channel_credit_width -set C_CAPACITIES $channel_yosys_capacity -set C_RETURN_DEPTH $channel_return_depth -set C_OBSERVE_DEPTH $max_depth upli_channel_content_properties
yosys prep -top upli_channel_content_properties -flatten
yosys opt -full
yosys check -assert
yosys select -assert-none t:KD28_* {t:$mem*} {t:$any*} {t:$assume}
yosys write_json [file join $run_dir properties.json]
yosys sat -verify -seq 4 -timeout 120 -set-def-inputs -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 -show-inputs -show o_violation -show account_bad -show port_bad -dump_vcd [file join $run_dir reset_counterexample.vcd] upli_channel_content_properties
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 120 -set-def-inputs -set-init-zero -prove o_violation 0 -show-inputs -show o_violation -show account_bad -show port_bad -dump_vcd [file join $run_dir induction_counterexample.vcd] upli_channel_content_properties
