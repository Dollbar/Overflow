# Run: make -f scripts/channel.mk equiv-channel after same-profile synthesis.
# Outputs: reset and binary induction comparison, including every macro transaction pin.
# Next: actual-memory regressions and STA; matched arbitrary macro Q does not prove memory contents.
source [file join [file dirname [file normalize [info script]]] channel_config.tcl]
foreach key {UALINK_NETLIST UALINK_LIBERTY UALINK_KD28_ROOT} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set macro_rtl [file join $env(UALINK_KD28_ROOT) Library models kd28 sram rtl kd28_sram_blackboxes.v]
set map_rtl [file join $env(UALINK_KD28_ROOT) Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
yosys read_verilog -lib $macro_rtl
yosys read_verilog $map_rtl
foreach name {upli_receive_fifo upli_receive_storage upli_credit_initializer upli_credit_return_queue upli_receive_channel} {
    yosys read_verilog [file join $channel_project_root rtl upli ${name}.v]
}
yosys chparam -set C_NUM_PORTS $channel_ports -set C_PAYLOAD_WIDTH $channel_width -set C_CREDIT_WIDTH $channel_credit_width -set C_CAPACITIES $channel_yosys_capacity -set C_RETURN_DEPTH $channel_return_depth upli_receive_channel
yosys prep -top upli_receive_channel -flatten
yosys rename upli_receive_channel gold
yosys design -stash gold_design
yosys read_verilog -lib $macro_rtl
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top upli_receive_channel -flatten
yosys rename upli_receive_channel gate
yosys design -copy-from gold_design gold
foreach side {gold gate} {
    dict for {type count} $channel_macro_counts {yosys select -assert-count $count $side/t:$type}
    yosys select -assert-count $channel_macro_total $side/t:KD28_SRAM_*
    if {$channel_macro_total > 0} {yosys expose -evert $side/t:KD28_SRAM_*}
    # Extra observations retain their real drivers. Never cut DFF feedback or
    # assume internal state equality; the miter must prove each exposed value.
    yosys expose $side/w:*cnt_* $side/w:*reg_pending $side/w:*reg_read_addr $side/w:*reg_write_addr $side/w:*reg_*_o $side/w:*reg_saved $side/w:*state_current
    # Synthesis removes byte-padding bits unused by the channel. Observe only
    # payload+original VC/Pool from head/tail; all macro D/Q bits remain matched.
    yosys select -module $side
    set slot 0
    foreach depth $channel_capacities {
        if {$depth > 0} {
            foreach member {head tail} {
                set signal [format {gen_accounts[%d].gen_storage.Storage_Inst.Fifo_Inst.reg_%s} $slot $member]
                set count [expr {$channel_width+3}]
                yosys add -output o_eq_${member}_${slot} $count
                yosys connect -nounset -set o_eq_${member}_${slot} "$signal\[[expr {$count-1}]:0\]"
            }
        }
        incr slot
    }
    yosys select -clear
}
yosys write_json [file join $env(UALINK_BUILD_DIR) equivalence_observations.json]
yosys miter -equiv -make_outputs -flatten gold gate channel_miter
yosys hierarchy -top channel_miter
yosys opt_clean
yosys sat -verify -seq 4 -timeout 120 -set-def-inputs -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 channel_miter
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 120 -set-def-inputs -set-init-zero -prove trigger 0 channel_miter
