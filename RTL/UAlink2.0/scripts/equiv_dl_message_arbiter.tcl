# Run: UALINK_NETLIST=mapped.v UALINK_LIBERTY=/authorized/cold.lib
#      yosys -Q -T -c scripts/equiv_dl_message_arbiter.tcl
# Outputs: complete binary reset and induction proofs for actual mapped logic.
# Next: require every marker/source identity, then analyze this exact netlist.
foreach key {UALINK_NETLIST UALINK_LIBERTY} {
    if {![info exists env($key)] || ![file isfile $env($key)]} {error "Missing $key file"}
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl dl dl_message_arbiter.v]
yosys prep -top dl_message_arbiter -flatten
yosys rename dl_message_arbiter gold
yosys design -stash gold_design
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top dl_message_arbiter -flatten
yosys rename dl_message_arbiter gate
yosys design -copy-from gold_design gold
foreach name {reg_group_next reg_basic_next reg_control_next reg_uart_next reg_uart_locked cnt_uart_index reg_uart_last} {
    yosys select -assert-count 1 gold/w:$name
    yosys select -assert-count 1 gate/w:$name
    yosys expose gold/w:$name gate/w:$name
}
yosys miter -equiv -make_outputs -make_outcmp -flatten gold gate dl_message_mapping_miter
yosys hierarchy -check -top dl_message_mapping_miter
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
# Ten original output ports plus all seven state objects. Miter trigger covers
# all seventeen, including stale idle captured length; no free-state inputs.
yosys select -assert-count 17 dl_message_mapping_miter/o:cmp_*
yosys select -assert-count 6 dl_message_mapping_miter/i:*
yosys select -clear
yosys sat -verify -seq 2 -timeout 90 -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 dl_message_mapping_miter
puts "DL_MESSAGE_MAPPING_RESET_PROVED"
yosys sat -verify -seq 2 -timeout 90 -set-at 1 trigger 0 -prove trigger 0 -prove-skip 1 dl_message_mapping_miter
puts "DL_MESSAGE_MAPPING_INDUCTION_PROVED"
puts "DL_MESSAGE_MAPPING_PROVED comparisons=17"
