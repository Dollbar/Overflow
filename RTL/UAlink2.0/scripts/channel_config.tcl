# Source from channel synthesis/equivalence/STA scripts with UALINK_* parameters.
# Outputs: validated channel_* variables including exact per-account macro inventory.
# Next: check actual macro instances and their timing paths, not only these expectations.
foreach key {UALINK_PORTS UALINK_WIDTH UALINK_CREDIT_WIDTH UALINK_CAP_HEX UALINK_RETURN_DEPTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set channel_ports $env(UALINK_PORTS)
set channel_width $env(UALINK_WIDTH)
set channel_credit_width $env(UALINK_CREDIT_WIDTH)
set channel_return_depth $env(UALINK_RETURN_DEPTH)
foreach value [list $channel_ports $channel_width $channel_credit_width $channel_return_depth] {
    if {![string is integer -strict $value]} {error "Channel numeric parameters must be integers"}
}
if {$channel_ports ni {1 2 4} || $channel_width < 1 || $channel_credit_width < 3 || $channel_credit_width > 16 || $channel_return_depth < 1 || $channel_return_depth > 16} {error "Invalid channel parameter range"}
set channel_cap_hex [string tolower $env(UALINK_CAP_HEX)]
if {![regexp {^[0-9a-f]+$} $channel_cap_hex]} {error "Capacity must be unsigned hexadecimal digits"}
set channel_cap_value [expr "0x$channel_cap_hex"]
set channel_cap_bits [expr {$channel_ports*5*$channel_credit_width}]
if {$channel_cap_value >= (1 << $channel_cap_bits)} {error "Capacity vector would be truncated"}
# Retain validated digits for wide vectors; avoid fixed-width format conversion.
set channel_cap_hex [string trimleft [string tolower $env(UALINK_CAP_HEX)] 0]
if {$channel_cap_hex eq ""} {set channel_cap_hex 0}
set channel_yosys_capacity "${channel_cap_bits}'h${channel_cap_hex}"
set channel_word_width [expr {(($channel_width+3+7)/8)*8}]
set channel_capacities {}; set channel_macro_counts {}; set channel_macro_total 0
for {set slot 0} {$slot < $channel_ports*5} {incr slot} {
    set depth [expr {($channel_cap_value >> ($slot*$channel_credit_width)) & ((1 << $channel_credit_width)-1)}]
    lappend channel_capacities $depth
    if {$depth == 0} {continue}
    set macro_depth [expr {$depth <= 256 ? 256 : $depth <= 512 ? 512 : $depth <= 1024 ? 1024 : 2048}]
    set macro_width [expr {$macro_depth == 256 ? 32 : $macro_depth == 512 ? 64 : $macro_depth == 1024 ? 128 : 256}]
    set count [expr {(($depth+$macro_depth-1)/$macro_depth)*(($channel_word_width+$macro_width-1)/$macro_width)}]
    dict incr channel_macro_counts KD28_SRAM_SDP_${macro_depth}X${macro_width} $count
    incr channel_macro_total $count
}
set channel_project_root [file dirname [file dirname [file normalize [info script]]]]
