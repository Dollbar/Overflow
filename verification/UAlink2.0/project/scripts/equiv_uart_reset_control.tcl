# Run: UALINK_CLOCK_PERIOD_PS=640 UALINK_LIBERTY=/authorized/cold.lib UALINK_NETLIST=/exact/mapped.v yosys -Q -T -c scripts/equiv_uart_reset_control.tcl
# Outputs: actual reset-base and full state/output one-step mapping induction markers.
# Next: exact-netlist STA at the same configured clock, then integrated UART validation.
foreach key {UALINK_CLOCK_PERIOD_PS UALINK_LIBERTY UALINK_NETLIST} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_CLOCK_PERIOD_PS) ni {640 6400}} {error "Undeclared physical timer profile"}
foreach key {UALINK_LIBERTY UALINK_NETLIST} {
    if {![file isfile $env($key)]} {error "Missing $key file"}
}
set root [file dirname [file dirname [file normalize [info script]]]]
set top dl_uart_reset_control
yosys read_verilog [file join $root rtl dl dl_uart_reset_control.v]
yosys chparam -set C_CLOCK_PERIOD_PS $env(UALINK_CLOCK_PERIOD_PS) $top
yosys prep -top $top -flatten
yosys rename $top gold
yosys design -stash gold_design
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top $top -flatten
yosys rename $top gate
yosys design -copy-from gold_design gold
foreach name {sta_local cnt_noops cnt_wait reg_local_all cnt_response reg_response_scope reg_fault} {
    foreach side {gold gate} {
        yosys select -assert-count 1 $side/w:$name
        yosys expose $side/w:$name
    }
}
yosys miter -equiv -make_outputs -make_outcmp -flatten gold gate uart_reset_mapping_miter
yosys hierarchy -check -top uart_reset_mapping_miter
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys select -assert-count 22 uart_reset_mapping_miter/o:cmp_*
yosys select -assert-count 9 uart_reset_mapping_miter/i:*
yosys select -clear
yosys sat -verify -seq 2 -timeout 120 -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 uart_reset_mapping_miter
puts "UART_RESET_MAPPING_RESET_PROVED"
yosys sat -verify -seq 2 -timeout 120 -set-at 1 trigger 0 -prove trigger 0 -prove-skip 1 uart_reset_mapping_miter
puts "UART_RESET_MAPPING_INDUCTION_PROVED"
puts "UART_RESET_MAPPING_PROVED configured_period_ps=$env(UALINK_CLOCK_PERIOD_PS) comparisons=22"
