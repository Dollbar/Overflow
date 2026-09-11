# Run: UALINK_LIBERTY=... UALINK_BUILD_DIR=... UALINK_PORTS=4 yosys -c scripts/synth_return.tcl
# Outputs: mapped.v, mapped.json, area.json; default depth4 retired-metadata queue, ports1/2/4.
# Next: analyze this SSG-mapped netlist at all declared corners with sta_return.tcl.
foreach key {UALINK_LIBERTY UALINK_BUILD_DIR UALINK_PORTS} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "UALINK_PORTS must be 1, 2 or 4"}
set cell_lib [file normalize $env(UALINK_LIBERTY)]
if {![file isfile $cell_lib]} {error "Liberty does not exist"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
yosys read_verilog [file join $project_root rtl upli upli_credit_return_queue.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) upli_credit_return_queue
yosys hierarchy -check -top upli_credit_return_queue
yosys synth -top upli_credit_return_queue
yosys dfflibmap -liberty $cell_lib
# ABC local drive/load approximation enables its default buffering and sizing.
# The load is 5 fF, matching the 0.005 pF STA output budget; OpenSTA remains the gate.
# 350 ps is a combinational mapping objective, not a changed 640 ps clock period.
# Reserve headroom for IO delay, FF setup, uncertainty and cold-corner slowdown.
# ABC map can leave fanout-free logic; buffer rejects it. Clean only dangling
# logic before buffering, explicitly preserving primary inputs/outputs (-i -o).
# Reproduced against the failed extracted network; mapped equivalence still required.
yosys abc -script {+strash;dretime;retime,-o,-D,350;map,-D,350;cleanup,-i,-o;buffer;upsize,-D,350;dnsize,-D,350;stime,-p} -liberty $cell_lib -constr [file join $project_root scripts credit_abc.constr]
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
yosys hierarchy -check -top upli_credit_return_queue
yosys check -assert
yosys tee -o [file join $run_dir area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $run_dir mapped.v]
yosys write_json [file join $run_dir mapped.json]
