# Run: UALINK_LIBERTY=... UALINK_BUILD_DIR=... UALINK_WIDTH=8|16 yosys -c scripts/map_tl_control_partition.tcl
# Outputs: mapped.v, mapped.json, area.json; libraries remain external/private.
# Next: equivalence and all five process corners on this exact mapped netlist.
foreach key {UALINK_LIBERTY UALINK_BUILD_DIR UALINK_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_WIDTH) ni {8 16}} {error "Undeclared WIDTH"}
if {![file isfile $env(UALINK_LIBERTY)]} {error "Missing Liberty"}
set root [file dirname [file dirname [file normalize [info script]]]]
set result [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $result
foreach name {tl_control_partition tl_credit_admission tl_control_decode tl_control_tenure} {
    yosys read_verilog [file join $root rtl tl $name.v]
}
yosys chparam -set WIDTH $env(UALINK_WIDTH) tl_control_partition
yosys synth -flatten -noabc -top tl_control_partition
yosys rename -top tl_control_partition
yosys dfflibmap -liberty $env(UALINK_LIBERTY)
# ABC optimization target is not an STA period change. Load is 5 fF.
# Clean mapped dangling nodes before buffer, as required by this ABC backend.
yosys abc -script {+strash;dretime;retime,-o,-D,350;map,-D,350;cleanup,-i,-o;buffer;upsize,-D,350;dnsize,-D,350;stime,-p} -liberty $env(UALINK_LIBERTY) -constr [file join $root scripts credit_abc.constr]
yosys clean
yosys read_liberty -lib -ignore_miss_func $env(UALINK_LIBERTY)
yosys hierarchy -check -top tl_control_partition
yosys check -assert
yosys tee -o [file join $result area.json] stat -json -liberty $env(UALINK_LIBERTY)
yosys write_verilog -noattr -noexpr [file join $result mapped.v]
yosys write_json [file join $result mapped.json]
