# Run: make -f scripts/storage.mk synth-storage with explicit authorized dependency roots.
# Outputs: full flattened storage mapped.v/mapped.json/area.json and synthesis log.
# Next: integrated macro timing, mapping equivalence and functional regression.
foreach key {UALINK_LIBERTY UALINK_KD28_ROOT UALINK_BUILD_DIR UALINK_DEPTH UALINK_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set depth $env(UALINK_DEPTH)
set width $env(UALINK_WIDTH)
if {![string is integer -strict $depth] || $depth < 1 || $depth > 65535} {error "depth must be 1..65535"}
if {![string is integer -strict $width] || $width < 8 || $width % 8 != 0} {error "width must be a positive byte multiple"}
set cell_lib [file normalize $env(UALINK_LIBERTY)]
set dependency [file normalize $env(UALINK_KD28_ROOT)]
set macro_rtl [file join $dependency Library models kd28 sram rtl kd28_sram_blackboxes.v]
set mapping_rtl [file join $dependency Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
foreach path [list $cell_lib $macro_rtl $mapping_rtl] {
    if {![file isfile $path]} {error "Missing dependency: $path"}
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
yosys read_verilog -lib $macro_rtl
yosys read_verilog $mapping_rtl [file join $project_root rtl upli upli_receive_fifo.v] [file join $project_root rtl upli upli_receive_storage.v]
yosys chparam -set C_DEPTH $depth -set C_DATA_WIDTH $width upli_receive_storage
yosys hierarchy -check -top upli_receive_storage
yosys synth -flatten -top upli_receive_storage
yosys dfflibmap -liberty $cell_lib
yosys abc -script {+strash;dretime;retime,-o,-D,350;map,-D,350;cleanup,-i,-o;buffer;upsize,-D,350;dnsize,-D,350;stime,-p} -liberty $cell_lib -constr [file join $project_root scripts credit_abc.constr]
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
# Internal aliases are not sink reconnections: insbuf on a named internal wire
# can leave the actual SRAM loads bypassing those cells. Transform exact macro
# port connections in generated JSON, then re-read and check the actual netlist.
yosys write_json [file join $run_dir unbuffered.json]
set python python3
if {[info exists env(UALINK_PYTHON)] && $env(UALINK_PYTHON) ne ""} {set python $env(UALINK_PYTHON)}
puts [exec $python [file join $project_root scripts buffer_storage.py] [file join $run_dir unbuffered.json] [file join $run_dir buffered.json]]
yosys design -reset
yosys read_json [file join $run_dir buffered.json]
# Keep actual fixed macro instances; never synthesize the behavioral SRAM arrays.
set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
set count [expr {(($depth+$macro_depth-1)/$macro_depth)*(($width+$macro_width-1)/$macro_width)}]
yosys select -assert-count $count upli_receive_storage/t:KD28_SRAM_SDP_${macro_depth}X${macro_width}
yosys select -assert-count $count upli_receive_storage/t:KD28_SRAM_*
yosys hierarchy -check -top upli_receive_storage
yosys check -assert
yosys tee -o [file join $run_dir area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $run_dir mapped.v]
yosys write_json [file join $run_dir mapped.json]
