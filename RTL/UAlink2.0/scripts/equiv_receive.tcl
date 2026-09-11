# Run: make -f scripts/receive.mk equiv-receive DEPTH=5 WIDTH=32 LIB_ROOT=/path/to/authorized/NLDM
# Output: reports/receive_equiv_*.log with reset and binary-induction outcomes.
# Next: actual-library STA on this exact controller netlist; not macro equivalence.
foreach key {UALINK_NETLIST UALINK_LIBERTY UALINK_DEPTH UALINK_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set depth $env(UALINK_DEPTH)
set width $env(UALINK_WIDTH)
if {![string is integer -strict $depth] || $depth < 1 || $depth > 65535} {error "depth must be 1..65535"}
if {![string is integer -strict $width] || $width < 8 || $width % 8 != 0} {error "width must be a positive byte multiple"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl upli upli_receive_fifo.v]
yosys chparam -set C_DEPTH $depth -set C_DATA_WIDTH $width upli_receive_fifo
yosys prep -top upli_receive_fifo
yosys rename upli_receive_fifo gold
yosys design -stash gold_design
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top upli_receive_fifo -flatten
yosys rename upli_receive_fifo gate
yosys design -copy-from gold_design gold
# Observe real hidden caches/counters as additional compared outputs, not cuts.
foreach signal {cnt_total cnt_unread reg_write_addr reg_read_addr cnt_cached reg_pending reg_head reg_tail} {
    yosys select -assert-count 1 gold/w:$signal
    yosys select -assert-count 1 gate/w:$signal
    yosys expose gold/w:$signal gate/w:$signal
}
yosys miter -equiv -make_outputs -flatten gold gate receive_miter
yosys hierarchy -top receive_miter
yosys opt_clean
yosys sat -verify -seq 4 -timeout 45 -set-def-inputs -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 receive_miter
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 45 -set-def-inputs -set-init-zero -prove trigger 0 receive_miter
