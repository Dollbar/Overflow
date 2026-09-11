# Run: yosys -Q -T -c scripts/prove_uart_tx_source.tcl
# Outputs: actual reset-base and full-induction results, with counterexamples on failure.
# Next: use run_uart_tx_proof.py for exact snapshots, then real integration/mapping.
set project_root [file dirname [file dirname [file normalize [info script]]]]
yosys read_verilog [file join $project_root rtl dl dl_uart_tx_source.v]
yosys read_verilog [file join $project_root verification formal uart_tx_properties.v]
yosys hierarchy -check -top uart_tx_properties
yosys proc
yosys flatten
yosys select -module uart_tx_properties
yosys select -assert-count 1 w:observed_state
yosys select -assert-count 1 w:observed_payload
foreach {name low high} {reg_busy 0 0 reg_ready 1 1 reg_payload_count 2 7 cnt_loaded 8 13 cnt_word_index 14 19 cnt_held 20 25 cnt_tx 26 37 reg_latest_fc 38 49} {
    set source Source_Inst.$name
    set sink [format {observed_state[%d:%d]} $high $low]
    yosys select -assert-count 1 w:$source
    yosys connect -nomap -nounset -set $sink $source
}
yosys select -assert-count 1 w:Source_Inst.staged_payload
yosys select -assert-count 32 w:Source_Inst.*.reg_word
yosys connect -nomap -nounset -set observed_payload Source_Inst.staged_payload
yosys select -clear
yosys opt
yosys wreduce
yosys techmap
yosys opt -full
yosys check -assert
yosys select -assert-none {t:$assume} {t:$anyseq} {t:$anyconst} a:blackbox=1
yosys select -assert-count 9 uart_tx_properties/i:*
yosys select -clear
# Both queries prove the full state/data/output invariant, not a selected output
# or a current-cycle relation assumed in place of its transition proof.
yosys sat -verify -seq 2 -timeout 120 -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 -show o_groups uart_tx_properties
puts "UART_TX_RESET_BASE_PROVED"
yosys sat -verify -seq 2 -timeout 120 -set-at 1 o_violation 0 -prove o_violation 0 -prove-skip 1 -show o_groups uart_tx_properties
puts "UART_TX_FULL_INDUCTION_PROVED"
puts "UART_TX_FUNCTIONAL_PROVED groups=5 payload_bits=1024"
