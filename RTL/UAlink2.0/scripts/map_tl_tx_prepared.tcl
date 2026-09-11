# Run: explicit UALINK_LIBERTY, UALINK_KD28_ROOT, UALINK_BUILD_DIR, UALINK_WIDTH=8|16,
# UALINK_SOURCE_DIR pointing to the source snapshot; yosys -c scripts/map_tl_tx_prepared.tcl.
# Outputs: mapped.v, mapped.json, area.json and actual fixed SRAM inventory.
# Next: mapped equivalence and five-corner STA; area excludes uncharacterized SRAM.
foreach key {UALINK_LIBERTY UALINK_KD28_ROOT UALINK_BUILD_DIR UALINK_WIDTH UALINK_SOURCE_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_WIDTH) ni {8 16}} {error "Undeclared WIDTH"}
set root [file dirname [file dirname [file normalize [info script]]]]
set result [file normalize $env(UALINK_BUILD_DIR)]
set dependency [file normalize $env(UALINK_KD28_ROOT)]
set macro_rtl [file join $dependency Library models kd28 sram rtl kd28_sram_blackboxes.v]
set mapping_rtl [file join $dependency Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
foreach path [list $env(UALINK_LIBERTY) $macro_rtl $mapping_rtl] {
    if {![file isfile $path]} {error "Missing dependency: $path"}
}
file mkdir $result
yosys read_verilog -lib $macro_rtl
yosys read_verilog $mapping_rtl
foreach name {tl_tx_prepared tl_prepared_partition tl_tx_buffered tl_tx_data_fifo tl_tx_channels tl_tx_packer tl_tx_packer_core tl_credit_admission tl_control_decode tl_control_tenure upli_receive_fifo upli_receive_storage} {
    yosys read_verilog [file join $env(UALINK_SOURCE_DIR) $name.v]
}
yosys chparam -set WIDTH $env(UALINK_WIDTH) -set HEADER_DEPTH 2 -set BANK_DEPTH 3 tl_tx_prepared
yosys synth -flatten -noabc -top tl_tx_prepared
yosys dfflibmap -liberty $env(UALINK_LIBERTY)
yosys abc -script {+strash;dretime;retime,-o,-D,350;map,-D,350;cleanup,-i,-o;buffer;upsize,-D,350;dnsize,-D,350;stime,-p} -liberty $env(UALINK_LIBERTY) -constr [file join $root scripts credit_abc.constr]
yosys clean
yosys read_liberty -lib -ignore_miss_func $env(UALINK_LIBERTY)
yosys select -assert-count 64 tl_tx_prepared/t:KD28_SRAM_SDP_256X32
yosys select -assert-count 64 tl_tx_prepared/t:KD28_SRAM_*
yosys hierarchy -check -top tl_tx_prepared
yosys check -assert
yosys tee -o [file join $result area.json] stat -json -liberty $env(UALINK_LIBERTY)
yosys write_verilog -noattr -noexpr [file join $result mapped.v]
yosys write_json [file join $result mapped.json]
