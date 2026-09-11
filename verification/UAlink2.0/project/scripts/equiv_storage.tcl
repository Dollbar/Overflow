# Run: make -f scripts/storage.mk equiv-storage with explicit roots and matching DEPTH/WIDTH.
# Output: reset/induction comparison of mapped logic plus every macro transaction port.
# Next: actual SRAM functional simulation and integrated synthetic-macro timing.
# Macro contents are outside this Boolean proof: matched Q inputs are arbitrary;
# compare all original macro clocks/control/address/write-data ports as outputs.
foreach key {UALINK_NETLIST UALINK_LIBERTY UALINK_KD28_ROOT UALINK_DEPTH UALINK_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set depth $env(UALINK_DEPTH)
set width $env(UALINK_WIDTH)
if {![string is integer -strict $depth] || $depth < 1 || $depth > 65535} {error "depth must be 1..65535"}
if {![string is integer -strict $width] || $width < 8 || $width % 8 != 0} {error "width must be a positive byte multiple"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set macro_rtl [file join $env(UALINK_KD28_ROOT) Library models kd28 sram rtl kd28_sram_blackboxes.v]
set mapping_rtl [file join $env(UALINK_KD28_ROOT) Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
yosys read_verilog -lib $macro_rtl
yosys read_verilog $mapping_rtl [file join $project_root rtl upli upli_receive_fifo.v] [file join $project_root rtl upli upli_receive_storage.v]
yosys chparam -set C_DEPTH $depth -set C_DATA_WIDTH $width upli_receive_storage
yosys prep -top upli_receive_storage -flatten
yosys rename upli_receive_storage gold
yosys design -stash gold_design
yosys read_verilog -lib $macro_rtl
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top upli_receive_storage -flatten
yosys rename upli_receive_storage gate
yosys design -copy-from gold_design gold
set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
set count [expr {(($depth+$macro_depth-1)/$macro_depth)*(($width+$macro_width-1)/$macro_width)}]
foreach side {gold gate} {
    yosys select -assert-count $count $side/t:KD28_SRAM_SDP_${macro_depth}X${macro_width}
    yosys select -assert-count $count $side/t:KD28_SRAM_*
    yosys expose -evert $side/t:KD28_SRAM_*
}
# Preserve controller state drivers; extra observation is not a formal cut.
foreach signal {cnt_total cnt_unread reg_write_addr reg_read_addr cnt_cached reg_pending reg_head reg_tail} {
    foreach side {gold gate} {
        yosys select -assert-count 1 $side/w:Fifo_Inst.$signal
        yosys expose $side/w:Fifo_Inst.$signal
    }
}
yosys miter -equiv -make_outputs -flatten gold gate storage_miter
yosys hierarchy -top storage_miter
yosys opt_clean
yosys sat -verify -seq 4 -timeout 60 -set-def-inputs -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 storage_miter
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 60 -set-def-inputs -set-init-zero -prove trigger 0 storage_miter
