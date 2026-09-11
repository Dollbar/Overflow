# Run: UALINK_PORTS=1 UALINK_CREDIT_WIDTH=4 yosys -c scripts/prove_burst_payload.tcl.
# Outputs: partition-union, reset-base and every full-width one-step implication.
# Next: inspect real proof status, then mapped equivalence and whole-wrapper STA.
foreach key {UALINK_PORTS UALINK_CREDIT_WIDTH} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "Undeclared port count"}
if {![string is integer -strict $env(UALINK_CREDIT_WIDTH)] || $env(UALINK_CREDIT_WIDTH) < 3 || $env(UALINK_CREDIT_WIDTH) > 16} {error "Invalid credit width"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
foreach name {upli_credit_bank.v upli_burst_control.v upli_burst_sender.v} {
    yosys read_verilog [file join $project_root rtl upli $name]
}
yosys read_verilog [file join $project_root verification formal upli_payload_properties.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) -set C_CREDIT_WIDTH $env(UALINK_CREDIT_WIDTH) upli_payload_properties
yosys hierarchy -check -top upli_payload_properties
yosys proc
yosys flatten
# Only attach observational lemma wires to actual register outputs. These are
# not inputs/cuts, and every association is checked before optimization/SAT.
# This proof fixes the default two-cycle filter; cnt_init is exactly one bit.
yosys select -module upli_payload_properties
yosys select -assert-count 1 w:observed_init_stage
for {set channel 0} {$channel < 2} {incr channel} {
    set bank [lindex {Req Data} $channel]
    for {set port 0} {$port < $env(UALINK_PORTS)} {incr port} {
        set source [format {Sender_Inst.%s_Bank_Inst.gen_ports[%d].gen_active.cnt_init} $bank $port]
        set sink [format {observed_init_stage[%d]} [expr {$channel*$env(UALINK_PORTS)+$port}]]
        yosys select -assert-count 1 "w:$source"
        yosys connect -nomap -nounset -set $sink $source
    }
}
foreach sink_name {observed_descriptors observed_words} {
    yosys select -assert-count 1 "w:$sink_name"
}
for {set port 0} {$port < $env(UALINK_PORTS)} {incr port} {
    foreach {field offset width} {cnt_offset 0 2 reg_last 2 2 reg_vc 4 2 reg_pools 6 4} {
        set source [format {Sender_Inst.Control_Inst.gen_ports[%d].gen_active.%s} $port $field]
        set low [expr {$port*10+$offset}]
        set sink [format {observed_descriptors[%d:%d]} [expr {$low+$width-1}] $low]
        yosys select -assert-count 1 "w:$source"
        yosys connect -nomap -nounset -set $sink $source
    }
    for {set tail 1} {$tail <= 3} {incr tail} {
        set source [format {Sender_Inst.gen_ports[%d].gen_tails[%d].reg_payload} $port $tail]
        set low [expr {($port*3+$tail-1)*577}]
        set sink [format {observed_words[%d:%d]} [expr {$low+576}] $low]
        yosys select -assert-count 1 "w:$source"
        yosys connect -nomap -nounset -set $sink $source
    }
}
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys opt_clean
yosys check -assert
# One actual product, independent arithmetic/shift queue, no free-state cuts.
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys select -clear
# All checks use binary symbolic inputs/state, not X/Z propagation semantics.
# Prove the union on arbitrary state before using it as the induction conclusion.
yosys sat -verify -seq 1 -timeout 90 -prove o_partition_gap 0 upli_payload_properties
puts "PAYLOAD_PARTITION_UNION_PROVED"
# Start from arbitrary registers, clock reset once, and check all post-reset
# outputs/state. No initial-zero or permanent reset restriction is required.
yosys sat -verify -seq 2 -timeout 90 -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 upli_payload_properties
puts "PAYLOAD_RESET_BASE_PROVED"
# Mathematical induction, split only in the consequent: P(s,u) => P_i(s',u').
# The one prior-cycle P constraint is the induction hypothesis, not a protocol
# input assumption. Current-cycle P/P_i, inputs and every real register remain
# unconstrained. The union check plus ALL implications proves preservation of P.
set group_count [expr {12+$env(UALINK_PORTS)}]
for {set group 0} {$group < $group_count} {incr group} {
    set conclusion [format {o_groups[%d]} $group]
    puts "PAYLOAD_GROUP_BEGIN $group"
    yosys sat -verify -seq 2 -timeout 90 -set-at 1 o_violation 0 -prove $conclusion 0 -prove-skip 1 upli_payload_properties
    puts "PAYLOAD_GROUP_PROVED $group"
}
puts "PAYLOAD_ALL_GROUPS_PROVED $group_count"
