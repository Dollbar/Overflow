# Run: UALINK_DEPTH=128 UALINK_CONTENT=1 UALINK_PROOF_BIT=0 UALINK_KD28_ROOT=/authorized/models UALINK_BUILD_DIR=/new/proof yosys -Q -T -c scripts/prove_uart_rx_content.tcl
# Outputs: actual-memory instrumentation, reset/induction logs and counterexample VCDs on failure.
# Next: run all32 declared planes with the matrix entry before claiming complete word contents.
foreach key {UALINK_DEPTH UALINK_CONTENT UALINK_KD28_ROOT UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set depth $env(UALINK_DEPTH)
set content $env(UALINK_CONTENT)
set proof_bit -1
if {[info exists env(UALINK_PROOF_BIT)]} {set proof_bit $env(UALINK_PROOF_BIT)}
if {![string is integer -strict $proof_bit] || $proof_bit < 0 || $proof_bit > 31} {error "Proof bit must be0..31"}
if {![string is integer -strict $depth] || $depth < 1 || $depth > 4095} {error "Depth must be 1..4095"}
if {$content ne "1"} {error "Actual content mode is required"}
set root [file dirname [file dirname [file normalize [info script]]]]
set result [file normalize $env(UALINK_BUILD_DIR)]
foreach name {instrumented.v instrumented.json properties.json reset_counterexample.vcd induction_counterexample.vcd} {
    if {![catch {file type [file join $result $name]}]} {error "Refusing to overwrite $name"}
}
file mkdir $result
set dep [file normalize $env(UALINK_KD28_ROOT)]
foreach name {sram/rtl/kd28_sram_sdp_model.v sram/rtl/kd28_sram_cells.v fifo/rtl/kd28_fifo_sdp_storage_map.v} {
    yosys read_verilog [file join $dep Library models kd28 $name]
}
foreach name {upli/upli_receive_fifo.v upli/upli_receive_storage.v dl/dl_uart_rx_path.v} {
    yosys read_verilog [file join $root rtl $name]
}
yosys chparam -set C_RX_DEPTH $depth dl_uart_rx_path
yosys prep -top dl_uart_rx_path -flatten
# Actual SRAM row and registered-Q semantics are retained. No cutpoint, free Q,
# internal state input, memory replacement or initialized-memory assumption.
yosys memory_map
yosys opt_clean
yosys select -module dl_uart_rx_path
set count_bits 1
while {(1 << $count_bits) <= $depth} {incr count_bits}
foreach {output source width} {
    count Storage_Inst.Fifo_Inst.cnt_total 12
    unread Storage_Inst.Fifo_Inst.cnt_unread 12
    read_addr Storage_Inst.read_addr 12
    write_addr Storage_Inst.write_addr 12
    pending Storage_Inst.Fifo_Inst.reg_pending 1
    cached Storage_Inst.Fifo_Inst.cnt_cached 2
    head Storage_Inst.Fifo_Inst.reg_head 32
    tail Storage_Inst.Fifo_Inst.reg_tail 32
    read_result Storage_Inst.read_data 32
    storage_reset storage_rstn 1
} {
    yosys select -assert-count 1 w:$source
    yosys add -output o_formal_$output $width
    if {$width == 12 && $count_bits < 12} {
        yosys connect -nounset -set [format {o_formal_%s[%d:0]} $output [expr {$count_bits-1}]] $source
        yosys connect -nounset -set [format {o_formal_%s[11:%d]} $output $count_bits] [expr {12-$count_bits}]'d0
    } else {
        yosys connect -nounset -set o_formal_$output $source
    }
}
yosys add -output o_formal_state 20
foreach {source low high} {cnt_remaining 0 5 reg_drop 6 6 reg_initialized 7 7 cnt_rx_credit 8 19} {
    yosys select -assert-count 1 w:$source
    yosys connect -nounset -set [format {o_formal_state[%d:%d]} $high $low] $source
}
yosys add -output o_formal_memory [expr {$depth*32}]
if {$content} {
    set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
    set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
    for {set address 0} {$address < $depth} {incr address} {
        set bank [expr {$address/$macro_depth}]
        set row [expr {$address%$macro_depth}]
        set source [format {Storage_Inst.Storage_Inst.gen_depth_bank[%d].gen_width_lane[0].gen_sdp_%dx%d.u_sram.u_model.memory[%d]} $bank $macro_depth $macro_width $row]
        yosys select -assert-count 1 w:$source
        yosys connect -nounset -set [format {o_formal_memory[%d:%d]} [expr {$address*32+31}] [expr {$address*32}]] [format {%s[31:0]} $source]
    }
} else {
    yosys connect -nounset -set o_formal_memory [expr {$depth*32}]'d0
}
yosys select -clear
yosys check -assert
yosys write_json [file join $result instrumented.json]
yosys write_verilog -noattr [file join $result instrumented.v]
yosys read_verilog [file join $root verification formal uart_rx_word_invariant.v]
yosys read_verilog [file join $root verification formal uart_rx_content_properties.v]
yosys chparam -set C_DEPTH $depth -set C_CONTENT $content -set C_PROOF_BIT $proof_bit uart_rx_content_properties
yosys prep -top uart_rx_content_properties -flatten
yosys opt -full
yosys check -assert
yosys select -assert-none t:KD28_* {t:$mem*} {t:$any*} {t:$assume} a:blackbox=1
yosys select -assert-count 7 uart_rx_content_properties/i:*
yosys select -clear
yosys write_json [file join $result properties.json]
yosys sat -verify -seq 3 -timeout 300 -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 -show-inputs -show o_groups -dump_vcd [file join $result reset_counterexample.vcd] uart_rx_content_properties
puts "UART_RX_CONTENT_RESET_BASE_PROVED"
yosys sat -verify -seq 2 -timeout 300 -set-at 1 o_violation 0 -prove o_violation 0 -prove-skip 1 -show-inputs -show o_groups -dump_vcd [file join $result induction_counterexample.vcd] uart_rx_content_properties
puts "UART_RX_CONTENT_INDUCTION_PROVED"
puts "UART_RX_CONTENT_PLANE_PROVED depth=$depth bit=$proof_bit compared_outputs=93 memory_rows=$depth data_bits=1"
