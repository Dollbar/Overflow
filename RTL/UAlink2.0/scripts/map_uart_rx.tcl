# Run: UALINK_TARGET=path UALINK_LIBERTY=/authorized/cold.lib UALINK_BUILD_DIR=/new/result yosys -Q -T -c scripts/map_uart_rx.tcl
# Path target additionally requires UALINK_KD28_ROOT and UALINK_DEPTH=128.
# Outputs: exact mapped.v, mapped.json and area.json, never overwritten.
# Next: full state/macro-port equivalence and unchanged-budget five-corner STA.
foreach key {UALINK_TARGET UALINK_LIBERTY UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_TARGET) ne "path"} {error "Unknown UART target"}
set top dl_uart_rx_$env(UALINK_TARGET)
set root [file dirname [file dirname [file normalize [info script]]]]
set result [file normalize $env(UALINK_BUILD_DIR)]
set cell_lib [file normalize $env(UALINK_LIBERTY)]
if {![file isfile $cell_lib]} {error "Missing authorized Liberty"}
foreach name {mapped.v mapped.json area.json} {
    if {![catch {file type [file join $result $name]}]} {error "Refusing to overwrite $name"}
}
file mkdir $result
if {$env(UALINK_TARGET) eq "path"} {
    foreach key {UALINK_KD28_ROOT UALINK_DEPTH} {
        if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
    }
    set depth $env(UALINK_DEPTH)
    if {![string is integer -strict $depth] || $depth < 1 || $depth > 4095} {error "UART depth must be1..4095"}
    set dep [file normalize $env(UALINK_KD28_ROOT)]
    yosys read_verilog -lib [file join $dep Library models kd28 sram rtl kd28_sram_blackboxes.v]
    yosys read_verilog [file join $dep Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
    foreach name {upli/upli_receive_fifo.v upli/upli_receive_storage.v dl/dl_uart_rx_path.v} {
        yosys read_verilog [file join $root rtl $name]
    }
    yosys chparam -set C_RX_DEPTH $depth $top
}
yosys synth -top $top -flatten -nofsm -noabc
yosys dfflibmap -liberty $cell_lib
yosys abc -liberty $cell_lib -constr [file join $root scripts burst_abc.constr] -D 300
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
yosys hierarchy -check -top $top
yosys check -assert
if {$env(UALINK_TARGET) eq "path"} {
    set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
    set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
    set count [expr {($depth+$macro_depth-1)/$macro_depth}]
    yosys select -assert-count $count $top/t:KD28_SRAM_SDP_${macro_depth}X${macro_width}
    yosys select -assert-count $count $top/t:KD28_SRAM_*
    puts "UART_RX_MAPPED_MACROS depth=$depth count=$count cell=KD28_SRAM_SDP_${macro_depth}X${macro_width}"
} else {
    yosys select -assert-none $top/t:KD28_SRAM_*
}
yosys select -clear
yosys tee -o [file join $result area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $result mapped.v]
yosys write_json [file join $result mapped.json]
puts "UART_RX_LIBRARY_MAPPING_COMPLETE target=$env(UALINK_TARGET)"
