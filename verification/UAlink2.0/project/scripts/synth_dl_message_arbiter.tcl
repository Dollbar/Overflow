# Run: UALINK_BUILD_DIR=build/dl_arbiter_synth yosys -Q -T -c scripts/synth_dl_message_arbiter.tcl
# Outputs: synth.v, synth.json, stat.json in the explicitly selected directory.
# Next: inspect generic-cell structure; use independent formal/Liberty mapping
# and real STA before claiming equivalence, area in square microns or timing.
if {![info exists env(UALINK_BUILD_DIR)] || $env(UALINK_BUILD_DIR) eq ""} {
    error "UALINK_BUILD_DIR is required"
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set result_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $result_dir
yosys read_verilog [file join $project_root rtl dl dl_message_arbiter.v]
yosys hierarchy -check -top dl_message_arbiter
yosys synth -top dl_message_arbiter
yosys check -assert
yosys select -assert-none {t:*LATCH*} {t:$dlatch} {t:$adlatch} a:blackbox=1
yosys select -clear
yosys tee -o [file join $result_dir stat.json] stat -json
yosys write_verilog -noattr -noexpr [file join $result_dir synth.v]
yosys write_json [file join $result_dir synth.json]
puts "DL_MESSAGE_GENERIC_SYNTHESIS_COMPLETE"
