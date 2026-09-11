# Run: make -f scripts/receive.mk synth-receive DEPTH=5 WIDTH=32 LIB_ROOT=/path/to/authorized/NLDM
# Outputs: build/receive_synth_*/mapped.v, mapped.json, area.json, synthesis log.
# Next: mapped controller equivalence then actual-library STA; no SRAM macro signoff.
foreach key {UALINK_LIBERTY UALINK_BUILD_DIR UALINK_DEPTH UALINK_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set depth $env(UALINK_DEPTH)
set width $env(UALINK_WIDTH)
if {![string is integer -strict $depth] || $depth < 1 || $depth > 65535} {error "depth must be 1..65535"}
if {![string is integer -strict $width] || $width < 8 || $width % 8 != 0} {error "width must be a positive byte multiple"}
set cell_lib [file normalize $env(UALINK_LIBERTY)]
if {![file isfile $cell_lib]} {error "Liberty does not exist"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
yosys read_verilog [file join $project_root rtl upli upli_receive_fifo.v]
yosys chparam -set C_DEPTH $depth -set C_DATA_WIDTH $width upli_receive_fifo
yosys hierarchy -check -top upli_receive_fifo
yosys synth -top upli_receive_fifo
yosys dfflibmap -liberty $cell_lib
# Same fixed IO mapping objective and fanout-free cleanup as the return queue.
# This is the controller, including two output words, not the external SRAM.
yosys abc -script {+strash;dretime;retime,-o,-D,350;map,-D,350;cleanup,-i,-o;buffer;upsize,-D,350;dnsize,-D,350;stime,-p} -liberty $cell_lib -constr [file join $project_root scripts credit_abc.constr]
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
# Direct write-data pass-through violates the fixed 10ps hold budget without
# a physical delay cell. Insert only on this explicit output bus, not all aliases.
# Actual-library equivalence and all STA corners remain mandatory afterwards.
yosys select -assert-count 1 upli_receive_fifo/w:o_sram_write_data
yosys insbuf -buf BUFFD0BWP40P140 I Z upli_receive_fifo/w:o_sram_write_data
yosys hierarchy -check -top upli_receive_fifo
yosys check -assert
yosys tee -o [file join $run_dir area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $run_dir mapped.v]
yosys write_json [file join $run_dir mapped.json]
