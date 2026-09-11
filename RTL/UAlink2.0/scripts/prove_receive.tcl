# Run: make -f scripts/receive.mk prove-receive DEPTH=5 WIDTH=32
# Outputs: reports/receive_properties_*.log, build/receive_proof_*/instrumented.v.
# Next: actual SRAM data tests and separately bounded mapped-equivalence/STA.
foreach key {UALINK_DEPTH UALINK_WIDTH UALINK_BUILD_DIR} {
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
yosys read_verilog [file join $project_root rtl upli upli_receive_fifo.v]
yosys chparam -set C_DEPTH $depth -set C_DATA_WIDTH $width -set C_COUNT_WIDTH $bits upli_receive_fifo
yosys prep -top upli_receive_fifo
# Add observations without unsetting any driver or substituting free state.
yosys select -module upli_receive_fifo
foreach {output signal signal_bits} [list o_formal_unread cnt_unread $bits o_formal_pending reg_pending 1 o_formal_cached cnt_cached 2] {
    yosys select -assert-count 1 w:$signal
    yosys add -output $output $signal_bits
    yosys connect -nounset -set $output $signal
}
yosys select -clear
yosys check -assert
yosys write_verilog -noattr [file join $run_dir instrumented.v]
yosys read_verilog [file join $project_root verification formal upli_receive_fifo_properties.v]
yosys chparam -set C_DEPTH $depth -set C_DATA_WIDTH $width upli_receive_fifo_properties
yosys prep -top upli_receive_fifo_properties -flatten
yosys check -assert
yosys sat -verify -seq 4 -timeout 45 -set-def-inputs -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 upli_receive_fifo_properties
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 45 -set-def-inputs -set-init-zero -prove o_violation 0 upli_receive_fifo_properties
