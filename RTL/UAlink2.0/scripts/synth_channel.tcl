# Run: make -f scripts/channel.mk synth-channel with explicit dependency roots.
# Outputs: whole-channel technology netlists and exact fixed SRAM inventory.
# Next: independent macro-port equivalence and unchanged-budget channel STA.
source [file join [file dirname [file normalize [info script]]] channel_config.tcl]
foreach key {UALINK_LIBERTY UALINK_KD28_ROOT UALINK_BUILD_DIR UALINK_HOLD UALINK_READ_CONTROL_BUFFERS} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_HOLD) ni {0 1}} {error "HOLD must be zero or one"}
if {$env(UALINK_READ_CONTROL_BUFFERS) ni {0 1}} {error "READ_CONTROL_BUFFERS must be zero or one"}
set macro_rtl [file join $env(UALINK_KD28_ROOT) Library models kd28 sram rtl kd28_sram_blackboxes.v]
set map_rtl [file join $env(UALINK_KD28_ROOT) Library models kd28 fifo rtl kd28_fifo_sdp_storage_map.v]
foreach path [list $env(UALINK_LIBERTY) $macro_rtl $map_rtl] {if {![file isfile $path]} {error "Missing $path"}}
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
yosys read_verilog -lib $macro_rtl
yosys read_verilog $map_rtl
foreach name {upli_receive_fifo upli_receive_storage upli_credit_initializer upli_credit_return_queue upli_receive_channel} {
    yosys read_verilog [file join $channel_project_root rtl upli ${name}.v]
}
yosys chparam -set C_NUM_PORTS $channel_ports -set C_PAYLOAD_WIDTH $channel_width -set C_CREDIT_WIDTH $channel_credit_width -set C_CAPACITIES $channel_yosys_capacity -set C_RETURN_DEPTH $channel_return_depth upli_receive_channel
yosys hierarchy -check -top upli_receive_channel
yosys synth -flatten -top upli_receive_channel
yosys dfflibmap -liberty $env(UALINK_LIBERTY)
# Combinational rewriting/balancing and timing-driven mapping. This 300 ps
# mapping objective is stricter than the earlier 350 ps heuristic; STA still
# uses the original 0.640/6.400 ns clocks and unchanged input/output budgets.
yosys abc -script {+strash;balance;rewrite;refactor;balance;dretime;retime,-o,-D,300;map,-D,300;cleanup,-i,-o;buffer;upsize,-D,300;dnsize,-D,300;stime,-p} -liberty $env(UALINK_LIBERTY) -constr [file join $channel_project_root scripts credit_abc.constr]
yosys clean
yosys read_liberty -lib -ignore_miss_func $env(UALINK_LIBERTY)
yosys write_json [file join $run_dir unbuffered.json]
yosys write_verilog -noattr -noexpr [file join $run_dir unbuffered.v]
if {$env(UALINK_HOLD) && $channel_macro_total > 0} {
    set python python3
    if {[info exists env(UALINK_PYTHON)] && $env(UALINK_PYTHON) ne ""} {set python $env(UALINK_PYTHON)}
    puts [exec $python [file join $channel_project_root scripts buffer_storage.py] [file join $run_dir unbuffered.json] [file join $run_dir buffered.json] --top upli_receive_channel --read-control-stages $env(UALINK_READ_CONTROL_BUFFERS)]
    yosys design -reset
    yosys read_json [file join $run_dir buffered.json]
}
set python python3
if {[info exists env(UALINK_PYTHON)] && $env(UALINK_PYTHON) ne ""} {set python $env(UALINK_PYTHON)}
yosys write_json [file join $run_dir before_sizing.json]
puts [exec $python [file join $channel_project_root scripts size_channel.py] [file join $run_dir before_sizing.json] [file join $run_dir sized.json]]
yosys design -reset
yosys read_json [file join $run_dir sized.json]
dict for {type count} $channel_macro_counts {yosys select -assert-count $count upli_receive_channel/t:$type}
yosys select -assert-count $channel_macro_total upli_receive_channel/t:KD28_SRAM_*
yosys hierarchy -check -top upli_receive_channel
yosys check -assert
yosys tee -o [file join $run_dir area.json] stat -json -liberty $env(UALINK_LIBERTY)
yosys write_verilog -noattr -noexpr [file join $run_dir mapped.v]
yosys write_json [file join $run_dir mapped.json]
