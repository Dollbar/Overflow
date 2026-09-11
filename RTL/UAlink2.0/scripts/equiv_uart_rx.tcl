# Run: UALINK_TARGET=path UALINK_LIBERTY=/authorized/cold.lib UALINK_NETLIST=/exact/mapped.v yosys -Q -T -c scripts/equiv_uart_rx.tcl
# Path additionally requires explicit UALINK_KD28_ROOT and matching UALINK_DEPTH.
# Outputs: complete binary reset-base and one-step induction markers/counterexamples.
# Next: verify hashes and same-netlist STA. Shared macro Q proves mapping, not SRAM contents.
foreach key {UALINK_TARGET UALINK_LIBERTY UALINK_NETLIST} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_TARGET) ne "path"} {error "Unknown UART target"}
foreach key {UALINK_LIBERTY UALINK_NETLIST} {
    if {![file isfile $env($key)]} {error "Missing $key file"}
}
set root [file dirname [file dirname [file normalize [info script]]]]
set top dl_uart_rx_$env(UALINK_TARGET)
set source_prefix ""
set comparisons 21
set inputs 9
if {$env(UALINK_TARGET) eq "path"} {
    foreach key {UALINK_KD28_ROOT UALINK_DEPTH} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    set depth $env(UALINK_DEPTH)
    if {![string is integer -strict $depth] || $depth < 1 || $depth > 4095} {error "UART depth must be1..4095"}
    set dep [file normalize $env(UALINK_KD28_ROOT)]
    set macro_rtl [file join $dep Library models kd28 sram rtl kd28_sram_blackboxes.v]
    yosys read_verilog -lib $macro_rtl
    yosys read_verilog [file join $dep Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
    foreach name {upli/upli_receive_fifo.v upli/upli_receive_storage.v dl/dl_uart_rx_path.v} {
        yosys read_verilog [file join $root rtl $name]
    }
    yosys chparam -set C_RX_DEPTH $depth $top
}
yosys prep -top $top -flatten
yosys rename $top gold
yosys design -stash gold_design
if {$env(UALINK_TARGET) eq "path"} {yosys read_verilog -lib $macro_rtl}
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top $top -flatten
yosys rename $top gate
yosys design -copy-from gold_design gold
foreach name {cnt_remaining reg_drop reg_initialized cnt_rx_credit} {
    foreach side {gold gate} {
        yosys select -assert-count 1 $side/w:$source_prefix$name
        yosys expose $side/w:$source_prefix$name
    }
}
if {$env(UALINK_TARGET) eq "path"} {
    set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
    set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
    set count [expr {($depth+$macro_depth-1)/$macro_depth}]
    foreach side {gold gate} {
        yosys select -assert-count $count $side/t:KD28_SRAM_SDP_${macro_depth}X${macro_width}
        yosys select -assert-count $count $side/t:KD28_SRAM_*
        yosys expose -evert $side/t:KD28_SRAM_*
    }
    foreach name {cnt_total cnt_unread reg_write_addr reg_read_addr cnt_cached reg_pending reg_head reg_tail} {
        foreach side {gold gate} {
            yosys select -assert-count 1 $side/w:Storage_Inst.Fifo_Inst.$name
            yosys expose $side/w:Storage_Inst.Fifo_Inst.$name
        }
    }
    set comparisons [expr {22+4+8+8*$count}]
    set inputs [expr {7+$count}]
    if {$count > 1} {
        # The authorized bank-select flop has no reset. Its value matters only
        # when the FIFO has an outstanding SRAM read. Prove that active relation
        # while preserving both actual flop drivers and every other comparison.
        set proof_dir [file dirname [file normalize $env(UALINK_NETLIST)]]
        set bank_input [file join $proof_dir bank_observation_input.json]
        set bank_output [file join $proof_dir bank_observation_output.json]
        foreach path [list $bank_input $bank_output] {
            if {![catch {file type $path}]} {error "Refusing to overwrite bank observation artifact"}
        }
        yosys select -clear
        yosys write_json $bank_input
        puts [exec python3 [file join $root scripts add_uart_bank_observation.py] $bank_input $bank_output]
        yosys design -reset
        yosys read_json $bank_output
        incr comparisons
    }
    puts "UART_RX_MAPPING_MACRO_PORT_SCOPE count=$count shared_q_buses=$count transaction_ports=[expr {8*$count}]"
}
yosys miter -equiv -make_outputs -make_outcmp -flatten gold gate uart_rx_mapping_miter
yosys hierarchy -check -top uart_rx_mapping_miter
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys select -assert-count $comparisons uart_rx_mapping_miter/o:cmp_*
yosys select -assert-count $inputs uart_rx_mapping_miter/i:*
yosys select -clear
yosys sat -verify -seq 2 -timeout 120 -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 uart_rx_mapping_miter
puts "UART_RX_MAPPING_RESET_PROVED"
yosys sat -verify -seq 2 -timeout 120 -set-at 1 trigger 0 -prove trigger 0 -prove-skip 1 uart_rx_mapping_miter
puts "UART_RX_MAPPING_INDUCTION_PROVED"
puts "UART_RX_MAPPING_PROVED target=$env(UALINK_TARGET) comparisons=$comparisons"
