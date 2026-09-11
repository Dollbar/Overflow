# Run: UALINK_CLOCK_PERIOD_PS=640 UALINK_LIBERTY=/authorized/cold.lib UALINK_BUILD_DIR=/new/result yosys -Q -T -c scripts/map_dl_basic_control.tcl
# Outputs: generic.json/stats, mapped.v/json and area.json; existing outputs are never overwritten.
# Next: same-configuration full mapping proof and exact-library five-corner STA.
foreach key {UALINK_CLOCK_PERIOD_PS UALINK_LIBERTY UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_CLOCK_PERIOD_PS) ni {640 6400}} {error "Undeclared physical timer profile"}
set root [file dirname [file dirname [file normalize [info script]]]]
set top dl_basic_message_control
set result [file normalize $env(UALINK_BUILD_DIR)]
set cell_lib [file normalize $env(UALINK_LIBERTY)]
if {![file isfile $cell_lib]} {error "Missing authorized Liberty"}
foreach name {generic.json generic_stats.json mapped.v mapped.json area.json} {
    if {![catch {file type [file join $result $name]}]} {error "Refusing to overwrite $name"}
}
file mkdir $result
yosys read_verilog [file join $root rtl dl dl_basic_message_control.v]
yosys chparam -set C_CLOCK_PERIOD_PS $env(UALINK_CLOCK_PERIOD_PS) $top
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
yosys select -assert-none $top/t:KD28_SRAM_*
yosys select -clear
yosys tee -o [file join $result area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $result mapped.v]
yosys write_json [file join $result mapped.json]
puts "DL_BASIC_LIBRARY_MAPPING_COMPLETE configured_period_ps=$env(UALINK_CLOCK_PERIOD_PS) declared_state_bits=156"
