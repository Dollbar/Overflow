# Run: UALINK_CLOCK_PERIOD_PS=640 UALINK_LIBERTY=/authorized/cold.lib UALINK_NETLIST=/exact/mapped.v yosys -Q -T -c scripts/equiv_dl_basic_control.tcl
# Outputs: actual reset-base and full state/output one-step mapping induction markers.
# Next: exact-netlist STA at the same configured clock, then integrated UART validation.
foreach key {UALINK_CLOCK_PERIOD_PS UALINK_LIBERTY UALINK_NETLIST} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_CLOCK_PERIOD_PS) ni {640 6400}} {error "Undeclared physical timer profile"}
foreach key {UALINK_LIBERTY UALINK_NETLIST} {
    if {![file isfile $env($key)]} {error "Missing $key file"}
}
set root [file dirname [file dirname [file normalize [info script]]]]
set top dl_basic_message_control
yosys read_verilog [file join $root rtl dl dl_basic_message_control.v]
yosys chparam -set C_CLOCK_PERIOD_PS $env(UALINK_CLOCK_PERIOD_PS) $top
yosys prep -top $top -flatten
yosys rename $top gold
yosys design -stash gold_design
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top $top -flatten
yosys rename $top gate
yosys design -copy-from gold_design gold
foreach name {reg_local_busy reg_local_sent reg_local_kind reg_local_word reg_remote_busy reg_remote_kind reg_remote_word reg_remote_rate reg_local_first cnt_remote_age reg_remote_missed reg_deadline_fault reg_protocol_fault reg_peer_rate_valid reg_peer_rate reg_peer_device_valid reg_peer_device_type reg_peer_device_id reg_peer_port_valid reg_peer_port} {
    foreach side {gold gate} {
        yosys select -assert-count 1 $side/w:$name
        yosys expose $side/w:$name
    }
}
yosys miter -equiv -make_outputs -make_outcmp -flatten gold gate dl_basic_mapping_miter
yosys hierarchy -check -top dl_basic_mapping_miter
if {[info exists env(UALINK_BUILD_DIR)]} {yosys write_json [file join $env(UALINK_BUILD_DIR) mapping_before_opt.json]}
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys select -assert-count 48 dl_basic_mapping_miter/o:cmp_*
yosys select -assert-count 18 dl_basic_mapping_miter/i:*
yosys select -clear
if {[info exists env(UALINK_BUILD_DIR)]} {yosys write_json [file join $env(UALINK_BUILD_DIR) mapping_miter.json]}
set dump_base {}
set dump_step {}
if {[info exists env(UALINK_BUILD_DIR)]} {
    set dump_base [list -dump_json [file join $env(UALINK_BUILD_DIR) mapping_reset_counterexample.json]]
    set dump_step [list -dump_json [file join $env(UALINK_BUILD_DIR) mapping_step_counterexample.json]]
}
yosys sat -verify -seq 2 -timeout 120 {*}$dump_base -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 dl_basic_mapping_miter
puts "DL_BASIC_MAPPING_RESET_PROVED"
yosys sat -verify -seq 2 -timeout 120 {*}$dump_step -set-at 1 trigger 0 -prove trigger 0 -prove-skip 1 dl_basic_mapping_miter
puts "DL_BASIC_MAPPING_INDUCTION_PROVED"
puts "DL_BASIC_MAPPING_PROVED configured_period_ps=$env(UALINK_CLOCK_PERIOD_PS) comparisons=48"
