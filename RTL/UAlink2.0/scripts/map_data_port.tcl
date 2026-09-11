# Run from candidate: UALINK_KD28_ROOT=/authorized/models UALINK_LIBERTY=/authorized/cold.lib UALINK_BUILD_DIR=/new/result yosys -Q -T -c scripts/map_data_port.tcl
# Outputs: generic.json, generic_stats.json, mapped.v/json, area.json; no overwrites.
# Next: full state/macro mapping correspondence and five-corner original-budget STA.
foreach key {UALINK_KD28_ROOT UALINK_LIBERTY UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set root [file dirname [file dirname [file normalize [info script]]]]
set top dl_replay_data_port
set result [file normalize $env(UALINK_BUILD_DIR)]
set cell_lib [file normalize $env(UALINK_LIBERTY)]
set dep [file normalize $env(UALINK_KD28_ROOT)]
if {![file isfile $cell_lib]} {error "Missing authorized Liberty"}
if {[file exists $result]} {error "Refusing to overwrite mapping directory"}
file mkdir $result
yosys read_verilog -lib [file join $dep Library models kd28 sram rtl kd28_sram_blackboxes.v]
yosys read_verilog [file join $dep Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
foreach name {dl_replay_data_port.v dl_replay_tx_storage.v dl_replay_tx_control.v dl_replay_event_port.v dl_replay_receiver.v dl_replay_header_tx.v} {
    yosys read_verilog [file join $root rtl dl $name]
}
yosys chparam -set C_DEPTH 128 -set C_DATA_WIDTH 32 -set C_ADDR_WIDTH 7 $top
yosys synth -top $top -flatten -nofsm -noabc
yosys check -assert
yosys tee -o [file join $result generic_stats.json] stat -json
yosys write_json [file join $result generic.json]
yosys dfflibmap -liberty $cell_lib
yosys abc -liberty $cell_lib -constr [file join $root scripts burst_abc.constr] -D 300
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
yosys hierarchy -check -top $top
yosys check -assert
yosys select -assert-count 2 $top/t:KD28_SRAM_SDP_256X32
yosys select -assert-count 2 $top/t:KD28_SRAM_*
yosys select -clear
yosys tee -o [file join $result area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $result mapped.v]
yosys write_json [file join $result mapped.json]
puts "DATA_PORT_LIBRARY_MAPPING_COMPLETE depth=128 width=32 macros=2"
