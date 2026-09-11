# Run: yosys -c scripts/equiv_burst_sender.tcl with UALINK_NETLIST,
# UALINK_LIBERTY, UALINK_PORTS, UALINK_CREDIT_WIDTH, UALINK_REQUEST_WIDTH,
# UALINK_INIT_CYCLES matching the actual mapped sender.
# Outputs: full-state binary equivalence; comparator lists under build/equiv_payload_*.
# Next: analyze this exact netlist in all declared STA corners; no analog claim.
foreach key {UALINK_NETLIST UALINK_LIBERTY UALINK_PORTS UALINK_CREDIT_WIDTH UALINK_REQUEST_WIDTH UALINK_INIT_CYCLES} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
# Solver wall-time budget only; it does not change the two-cycle induction,
# input freedom or any hardware clock/STA requirement. Four-port real mappings
# exceeded the previous 90-second per-query budget in a retained reproduction.
set solver_seconds 180
foreach name {upli_credit_bank.v upli_burst_control.v upli_burst_sender.v} {
    yosys read_verilog [file join $project_root rtl upli $name]
}
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) -set C_CREDIT_WIDTH $env(UALINK_CREDIT_WIDTH) -set C_REQUEST_WIDTH $env(UALINK_REQUEST_WIDTH) -set C_INIT_CYCLES $env(UALINK_INIT_CYCLES) upli_burst_sender
yosys prep -top upli_burst_sender -flatten
yosys rename upli_burst_sender gold
yosys design -stash gold_design
yosys read_liberty -ignore_miss_func $env(UALINK_LIBERTY)
yosys read_verilog $env(UALINK_NETLIST)
yosys prep -top upli_burst_sender -flatten
yosys rename upli_burst_sender gate
yosys design -copy-from gold_design gold
# Expose actual state outputs, never create arbitrary balance/storage inputs.
# Independent reset and preservation checks must prove these states too.
foreach {suffix multiplier} {reg_active 1 reg_vc 1 reg_last 1 reg_pools 1 cnt_offset 1 reg_payload 3 cnt_balance_o 10 cnt_init 2 reg_init_o 2} {
    set expected [expr {$env(UALINK_PORTS)*$multiplier}]
    yosys select -assert-count $expected "gold/w:*.$suffix"
    yosys select -assert-count $expected "gate/w:*.$suffix"
    yosys expose "gold/w:*.$suffix" "gate/w:*.$suffix"
}
foreach {suffix expected} {reg_error_o 2 reg_phase_known 1 reg_phase 1} {
    yosys select -assert-count $expected "gold/w:*.$suffix"
    yosys select -assert-count $expected "gate/w:*.$suffix"
    yosys expose "gold/w:*.$suffix" "gate/w:*.$suffix"
}
yosys select -assert-count 1 gold/w:reg_credit_error
yosys select -assert-count 1 gate/w:reg_credit_error
yosys expose gold/w:reg_credit_error gate/w:reg_credit_error
yosys miter -equiv -make_outputs -make_outcmp -flatten gold gate payload_mapping_miter
yosys hierarchy -check -top payload_mapping_miter
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
# Enumerate every actual miter comparison, including the exposed state. There
# are 25 native/local outputs, five shared states, and 22 state objects per port.
set comparison_count [expr {30+22*$env(UALINK_PORTS)}]
yosys select -assert-count $comparison_count payload_mapping_miter/o:cmp_*
set proof_dir [file join $project_root build equiv_payload_[pid]_[clock clicks]]
if {[file exists $proof_dir]} {error "Proof directory already exists"}
file mkdir $proof_dir
set list_file [file join $proof_dir comparisons.txt]
yosys select -write $list_file payload_mapping_miter/o:cmp_*
set channel [open $list_file r]
set listed [split [string trim [read $channel]] "\n"]
close $channel
if {[llength $listed] != $comparison_count} {error "Incomplete comparator list"}
set group_count [expr {$env(UALINK_PORTS)+2}]
for {set group 0} {$group < $group_count} {incr group} {set groups($group) {}}
set all_names {}
foreach line $listed {
    if {![regexp {^payload_mapping_miter/(cmp_.+)$} $line unused name]} {error "Unexpected comparator name"}
    if {[regexp {^cmp_gen_ports\[([0-9]+)\]\.gen_tails\[[123]\]\.reg_payload$} $name unused port]} {
        if {$port >= $env(UALINK_PORTS)} {error "Out-of-range tail owner"}
        set group [expr {2+$port}]
    } elseif {$name in {cmp_o_data_payload cmp_o_data_byte_enable cmp_o_data_error}} {
        set group 1
    } else {
        set group 0
    }
    lappend groups($group) $name
    lappend all_names $name
}
if {[llength [lsort -unique $all_names]] != $comparison_count} {error "Duplicate comparator"}
if {[llength $groups(1)] != 3} {error "Missing complete external data comparison"}
for {set port 0} {$port < $env(UALINK_PORTS)} {incr port} {
    if {[llength $groups([expr {2+$port}])] != 3} {error "Missing complete port tail comparison"}
}
# Check both directions of trigger == NOT(AND(all cmp outputs)) on arbitrary
# binary states before using the same complete relation as induction hypothesis.
set prove_all {}
set set_all {}
foreach name $all_names {
    lappend prove_all -prove "\\$name" 1
    lappend set_all -set "\\$name" 1
}
yosys sat -verify -seq 1 -timeout $solver_seconds -set trigger 0 {*}$prove_all payload_mapping_miter
yosys sat -verify -seq 1 -timeout $solver_seconds {*}$set_all -prove trigger 0 payload_mapping_miter
puts "PAYLOAD_MAPPING_PARTITION_PROVED comparisons=$comparison_count"
# One actual synchronous reset from arbitrary state establishes all relations.
yosys sat -verify -seq 2 -timeout $solver_seconds -set-at 1 in_i_rstn 0 -prove trigger 0 -prove-skip 1 payload_mapping_miter
puts "PAYLOAD_MAPPING_RESET_PROVED"
# Split only the consequent. Full gold/gate state, all data bits and every
# input remain present; no current-cycle equality, free cut or protocol assume.
for {set group 0} {$group < $group_count} {incr group} {
    if {![llength $groups($group)]} {error "Empty equivalence group"}
    set conclusions {}
    foreach name $groups($group) {lappend conclusions -prove "\\$name" 1}
    puts "PAYLOAD_MAPPING_GROUP_BEGIN $group comparisons=[llength $groups($group)]"
    yosys sat -verify -seq 2 -timeout $solver_seconds -set-at 1 trigger 0 {*}$conclusions -prove-skip 1 payload_mapping_miter
    puts "PAYLOAD_MAPPING_GROUP_PROVED $group"
}
puts "PAYLOAD_MAPPING_PROVED groups=$group_count comparisons=$comparison_count"
