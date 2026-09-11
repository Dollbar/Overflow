# Run: UALINK_KD28_ROOT=/authorized/models UALINK_BUILD_DIR=/new/result yosys -Q -T -c scripts/synth_uart_rx_path.tcl
# Optional UALINK_DEPTH=128 (research1..4095). Outputs: generic.json/generic_stats.json.
# Next: complete independent proof and actual-library whole-state/macro-port STA.
# Generic cell counts exclude SRAM contents; no mapped area/timing claim.
set project_root [file dirname [file dirname [file normalize [info script]]]]
foreach key {UALINK_KD28_ROOT UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing explicit $key"}
}
set depth 128
if {[info exists env(UALINK_DEPTH)]} {set depth $env(UALINK_DEPTH)}
if {![string is integer -strict $depth] || $depth < 1 || $depth > 4095} {error "RX depth must be1..4095"}
set result [file normalize $env(UALINK_BUILD_DIR)]
foreach name {generic.json generic_stats.json} {
    if {![catch {file type [file join $result $name]}]} {error "Refusing to overwrite $name"}
}
file mkdir $result
set dep [file normalize $env(UALINK_KD28_ROOT)]
yosys read_verilog -lib [file join $dep Library models kd28 sram rtl kd28_sram_blackboxes.v]
yosys read_verilog [file join $dep Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
foreach name {upli/upli_receive_fifo.v upli/upli_receive_storage.v dl/dl_uart_rx_path.v} {
    yosys read_verilog [file join $project_root rtl $name]
}
yosys chparam -set C_RX_DEPTH $depth dl_uart_rx_path
yosys synth -top dl_uart_rx_path -flatten
yosys check -assert
set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
set count [expr {($depth+$macro_depth-1)/$macro_depth}]
yosys select -assert-count $count dl_uart_rx_path/t:KD28_SRAM_SDP_${macro_depth}X${macro_width}
yosys select -assert-count $count dl_uart_rx_path/t:KD28_SRAM_*
yosys select -clear
yosys tee -o [file join $result generic_stats.json] stat -json
yosys write_json [file join $result generic.json]
puts "UART_RX_GENERIC_SYNTHESIZED depth=$depth macro_count=$count"
