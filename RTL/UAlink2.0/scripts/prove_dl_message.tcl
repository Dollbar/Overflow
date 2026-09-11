# Run: yosys -Q -T -c scripts/prove_dl_message.tcl
# Outputs: exact reset and complete induction results on stdout.
# Next: check strict completion/source identity with run_dl_message_proof.py,
# then actual mapped equivalence and physical characterization.
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl dl dl_message_arbiter.v]
yosys read_verilog [file join $project_root verification formal dl_message_properties.v]
yosys hierarchy -check -top dl_message_properties
yosys proc
yosys flatten
yosys select -module dl_message_properties
yosys select -assert-count 1 w:observed_state
foreach {name low high} {reg_group_next 0 1 reg_basic_next 2 4 reg_control_next 5 5 reg_uart_next 6 7 reg_uart_locked 8 8 cnt_uart_index 9 14 reg_uart_last 15 20} {
    set source Arbiter_Inst.$name
    set sink [format {observed_state[%d:%d]} $high $low]
    yosys select -assert-count 1 w:$source
    yosys connect -nomap -nounset -set $sink $source
}
yosys select -clear
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys select -assert-count 6 dl_message_properties/i:*
yosys select -clear
# Binary symbolic states/inputs. A sampled reset establishes every invariant;
# the hypothesis is the full prior-cycle invariant, never current-cycle cuts.
yosys sat -verify -seq 2 -timeout 90 -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 dl_message_properties
puts "DL_MESSAGE_RESET_BASE_PROVED"
yosys sat -verify -seq 2 -timeout 90 -set-at 1 o_violation 0 -prove o_violation 0 -prove-skip 1 dl_message_properties
puts "DL_MESSAGE_FULL_INDUCTION_PROVED"
puts "DL_MESSAGE_FUNCTIONAL_PROVED groups=6"
