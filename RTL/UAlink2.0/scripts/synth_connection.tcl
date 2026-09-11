# Run with: UALINK_LIBERTY=... UALINK_BUILD_DIR=... UALINK_ROLE=0 UALINK_WAIT=0 yosys -c scripts/synth_connection.tcl
# Outputs: mapped.v, mapped.json, area.json in the explicit build directory.
# Next: scripts/sta_connection.tcl at each declared library corner/clock mode.
foreach key {UALINK_LIBERTY UALINK_BUILD_DIR UALINK_ROLE UALINK_WAIT} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
foreach key {UALINK_ROLE UALINK_WAIT} {
    if {$env($key) ni {0 1}} {error "$key must be 0 or 1"}
}
set cell_lib [file normalize $env(UALINK_LIBERTY)]
if {![file isfile $cell_lib]} {error "Liberty does not exist"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
yosys read_verilog [file join $project_root rtl upli upli_connection_side.v]
yosys chparam -set C_IS_COMPLETER $env(UALINK_ROLE) -set C_COMPLETER_WAITS $env(UALINK_WAIT) upli_connection_side
yosys hierarchy -check -top upli_connection_side
yosys synth -top upli_connection_side
yosys dfflibmap -liberty $cell_lib
yosys abc -D 640 -liberty $cell_lib
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
yosys hierarchy -check -top upli_connection_side
yosys check -assert
yosys tee -o [file join $run_dir area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $run_dir mapped.v]
yosys write_json [file join $run_dir mapped.json]
