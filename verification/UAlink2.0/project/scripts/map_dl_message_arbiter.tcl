# Run: UALINK_LIBERTY=/authorized/cold.lib UALINK_BUILD_DIR=build/dl_mapping
#      yosys -Q -T -c scripts/map_dl_message_arbiter.tcl
# Outputs: mapped.v, mapped.json, area.json in a new, non-overwritten directory.
# Next: exact mapped equivalence followed by the same netlist's five-corner STA.
foreach key {UALINK_LIBERTY UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set result_dir [file normalize $env(UALINK_BUILD_DIR)]
set cell_lib [file normalize $env(UALINK_LIBERTY)]
if {![file isfile $cell_lib]} {error "Missing authorized Liberty"}
foreach name {mapped.v mapped.json area.json} {
    if {![catch {file type [file join $result_dir $name]}]} {error "Refusing to overwrite $name"}
}
file mkdir $result_dir
yosys read_verilog [file join $project_root rtl dl dl_message_arbiter.v]
# Preserve source state encodings for an explicit complete-state miter. This
# is a mapping choice, not a cut or a change to the externally proved function.
yosys synth -top dl_message_arbiter -flatten -nofsm -noabc
yosys dfflibmap -liberty $cell_lib
yosys abc -liberty $cell_lib -constr [file join $project_root scripts burst_abc.constr] -D 300
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
yosys hierarchy -check -top dl_message_arbiter
yosys check -assert
yosys tee -o [file join $result_dir area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $result_dir mapped.v]
yosys write_json [file join $result_dir mapped.json]
puts "DL_MESSAGE_LIBRARY_MAPPING_COMPLETE"
