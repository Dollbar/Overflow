# Run: yosys -c scripts/synth_burst_sender.tcl with explicit UALINK_LIBERTY,
# UALINK_BUILD_DIR, UALINK_PORTS, UALINK_CREDIT_WIDTH, UALINK_REQUEST_WIDTH,
# UALINK_INIT_CYCLES. UALINK_ABC optionally names the local ABC executable.
# Outputs: mapped.v, mapped.json and area.json in a fresh selected directory.
# Next: actual mapped equivalence and all-corner STA; mapping is not timing signoff.
foreach key {UALINK_LIBERTY UALINK_BUILD_DIR UALINK_PORTS UALINK_CREDIT_WIDTH UALINK_REQUEST_WIDTH UALINK_INIT_CYCLES} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "Undeclared port count"}
foreach {key low high} {UALINK_CREDIT_WIDTH 3 16 UALINK_REQUEST_WIDTH 1 1024 UALINK_INIT_CYCLES 2 15} {
    if {![string is integer -strict $env($key)] || $env($key) < $low || $env($key) > $high} {error "Invalid $key"}
}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
set cell_lib [file normalize $env(UALINK_LIBERTY)]
if {![file isfile $cell_lib]} {error "Missing authorized Liberty"}
foreach output {mapped.v mapped.json area.json} {
    if {![catch {file type [file join $run_dir $output]}]} {error "Refusing to overwrite existing $output"}
}
file mkdir $run_dir
set abc_tool yosys-abc
if {[info exists env(UALINK_ABC)] && $env(UALINK_ABC) ne ""} {set abc_tool $env(UALINK_ABC)}
foreach name {upli_credit_bank.v upli_burst_control.v upli_burst_sender.v} {
    yosys read_verilog [file join $project_root rtl upli $name]
}
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) -set C_CREDIT_WIDTH $env(UALINK_CREDIT_WIDTH) -set C_REQUEST_WIDTH $env(UALINK_REQUEST_WIDTH) -set C_INIT_CYCLES $env(UALINK_INIT_CYCLES) upli_burst_sender
yosys hierarchy -check -top upli_burst_sender
yosys synth -top upli_burst_sender -flatten
yosys dfflibmap -liberty $cell_lib
# Same declared 300ps mapper objective as the control baseline; it does not
# relax the independently applied 640ps/6400ps clocks or IO/uncertainty budgets.
yosys abc -exe $abc_tool -script {+strash;balance;rewrite;refactor;balance;dretime;retime,-o,-D,300;map,-D,300;cleanup,-i,-o;buffer;upsize,-D,300;dnsize,-D,300;stime,-p} -liberty $cell_lib -constr [file join $project_root scripts burst_abc.constr]
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
yosys hierarchy -check -top upli_burst_sender
yosys check -assert
yosys tee -o [file join $run_dir area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $run_dir mapped.v]
yosys write_json [file join $run_dir mapped.json]
