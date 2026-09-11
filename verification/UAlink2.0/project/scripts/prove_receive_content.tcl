# Run through content.mk with an explicit authorized model root.
# Outputs: actual-memory observations, SAT property netlist and failed counterexamples.
# Next: channel original-metadata proof; these memory-map FFs are verification, not ASIC PPA.
foreach key {UALINK_DEPTH UALINK_WIDTH UALINK_KD28_ROOT UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set depth $env(UALINK_DEPTH)
set width $env(UALINK_WIDTH)
if {![string is integer -strict $depth] || $depth < 1 || $depth > 65535} {error "depth must be 1..65535"}
if {![string is integer -strict $width] || $width < 8 || $width % 8 != 0} {error "width must be a positive byte multiple"}
set bits 1
while {(1 << $bits) <= $depth} {incr bits}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
set sram_dir [file join $env(UALINK_KD28_ROOT) Library models kd28 sram rtl]
yosys read_verilog [file join $sram_dir kd28_sram_sdp_model.v]
yosys read_verilog [file join $sram_dir kd28_sram_cells.v]
yosys read_verilog [file join $env(UALINK_KD28_ROOT) Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
yosys read_verilog [file join $project_root rtl upli upli_receive_fifo.v]
yosys read_verilog [file join $project_root rtl upli upli_receive_storage.v]
yosys chparam -set C_DEPTH $depth -set C_DATA_WIDTH $width upli_receive_storage
yosys prep -top upli_receive_storage -flatten
# Expand the actual memory semantics only for SAT. No macro output/state cut.
yosys memory_map
yosys opt_clean
yosys select -module upli_receive_storage
foreach {output signal count} [list o_formal_unread Fifo_Inst.cnt_unread $bits o_formal_pending Fifo_Inst.reg_pending 1 o_formal_cached Fifo_Inst.cnt_cached 2 o_formal_head Fifo_Inst.reg_head $width o_formal_tail Fifo_Inst.reg_tail $width o_formal_read_addr read_addr $bits o_formal_write_addr write_addr $bits o_formal_read_result read_data $width] {
    yosys select -assert-count 1 w:$signal
    yosys add -output $output $count
    yosys connect -nounset -set $output $signal
}
yosys add -output o_formal_memory [expr {$depth*$width}]
set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
for {set address 0} {$address < $depth} {incr address} {
    set bank [expr {$address/$macro_depth}]
    set row [expr {$address%$macro_depth}]
    for {set tile 0} {$tile*$macro_width < $width} {incr tile} {
        set chunk [expr {min($macro_width,$width-$tile*$macro_width)}]
        set signal [format {Storage_Inst.gen_depth_bank[%d].gen_width_lane[%d].gen_sdp_%dx%d.u_sram.u_model.memory[%d]} $bank $tile $macro_depth $macro_width $row]
        yosys select -assert-count 1 w:$signal
        set low [expr {$address*$width+$tile*$macro_width}]
        yosys connect -nounset -set [format {o_formal_memory[%d:%d]} [expr {$low+$chunk-1}] $low] [format {%s[%d:0]} $signal [expr {$chunk-1}]]
    }
}
yosys select -clear
yosys check -assert
yosys write_verilog -noattr [file join $run_dir instrumented.v]
yosys read_verilog [file join $project_root verification formal upli_receive_content_properties.v]
yosys chparam -set C_DEPTH $depth -set C_DATA_WIDTH $width upli_receive_content_properties
yosys prep -top upli_receive_content_properties -flatten
yosys opt -full
yosys check -assert
yosys select -assert-none t:KD28_* {t:$mem*} {t:$any*} {t:$assume}
yosys write_json [file join $run_dir properties.json]
# Four steps establish the post-reset invariant with arbitrary initial memory.
# The separate induction below proves preservation for all subsequent cycles;
# longer activity traces and mutation controls are supplementary, not assumptions.
yosys sat -verify -seq 4 -timeout 120 -set-def-inputs -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 -show-inputs -show o_violation -show bad_memory -show bad_control -show bad_cache -dump_vcd [file join $run_dir reset_counterexample.vcd] upli_receive_content_properties
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 120 -set-def-inputs -set-init-zero -prove o_violation 0 -show-inputs -show o_violation -show bad_memory -show bad_control -show bad_cache -dump_vcd [file join $run_dir induction_counterexample.vcd] upli_receive_content_properties
