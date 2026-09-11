# Run from any directory: yosys -Q -T -c /project/scripts/synth_uart_tx_source.tcl
# Optional explicit output directory: UALINK_BUILD_DIR=/new/path.
# Outputs: generic.json and generic_stats.json; no Liberty area or STA claim.
# Next: complete functional proof and actual-library mapping/equality/STA.
set project_root [file dirname [file dirname [file normalize [info script]]]]
set result_dir [file join $project_root build uart_tx_source_generic]
if {[info exists env(UALINK_BUILD_DIR)]} {set result_dir [file normalize $env(UALINK_BUILD_DIR)]}
foreach name {generic.json generic_stats.json} {
    if {![catch {file type [file join $result_dir $name]}]} {error "Refusing to overwrite $name"}
}
file mkdir $result_dir
yosys read_verilog [file join $project_root rtl dl dl_uart_tx_source.v]
yosys synth -top dl_uart_tx_source -flatten
yosys check -assert
yosys tee -o [file join $result_dir generic_stats.json] stat -json
yosys write_json [file join $result_dir generic.json]
puts "UART_TX_SOURCE_GENERIC_SYNTHESIZED"
