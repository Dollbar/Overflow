# Run through make -f scripts/burst.mk synth-burst-control with explicit LIB_ROOT.
# Outputs: mapped.v, mapped.json and area.json in the selected burst build.
# Next: mapped equivalence and five-corner/two-period STA; no PHY/macros here.
foreach key {UALINK_LIBERTY UALINK_BUILD_DIR UALINK_PORTS UALINK_CREDIT_WIDTH UALINK_STA} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "Undeclared port count"}
if {![string is integer -strict $env(UALINK_CREDIT_WIDTH)] || $env(UALINK_CREDIT_WIDTH) < 3 || $env(UALINK_CREDIT_WIDTH) > 16} {error "Invalid credit width"}
set project_root [file dirname [file dirname [file normalize [info script]]]]
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
set cell_lib [file normalize $env(UALINK_LIBERTY)]
set abc_tool yosys-abc
if {[info exists env(UALINK_ABC)] && $env(UALINK_ABC) ne ""} {set abc_tool $env(UALINK_ABC)}
if {![file isfile $cell_lib]} {error "Missing Liberty"}
file mkdir $run_dir
yosys read_verilog [file join $project_root rtl upli upli_burst_control.v]
yosys chparam -set C_NUM_PORTS $env(UALINK_PORTS) -set C_CREDIT_WIDTH $env(UALINK_CREDIT_WIDTH) upli_burst_control
yosys hierarchy -check -top upli_burst_control
yosys synth -top upli_burst_control
yosys dfflibmap -liberty $cell_lib
# Balance combinational cones before mapping; the stricter 300ps optimization
# objective does not change the 640ps clock or the independently checked IO budgets.
yosys abc -exe $abc_tool -script {+strash;balance;rewrite;refactor;balance;dretime;retime,-o,-D,300;map,-D,300;cleanup,-i,-o;buffer;upsize,-D,300;dnsize,-D,300;stime,-p} -liberty $cell_lib -constr [file join $project_root scripts burst_abc.constr]
yosys clean
yosys read_liberty -lib -ignore_miss_func $cell_lib
yosys hierarchy -check -top upli_burst_control
yosys check -assert
# Retain every pre-sizing graph/journal in an isolated attempt directory. The
# build guard keeps the primary outputs unavailable until this whole flow ends.
set sizing_dir [file join $run_dir sizing_[pid]_[clock clicks]]
file mkdir $sizing_dir
set env(UALINK_NETLIST) [file join $sizing_dir before.v]
set env(UALINK_SIZE_OUT) [file join $sizing_dir sized.v]
set env(UALINK_SIZE_CHANGES) [file join $sizing_dir changes.list]
yosys write_verilog -noattr -noexpr $env(UALINK_NETLIST)
exec $env(UALINK_STA) -exit [file join $project_root scripts size_burst_control.tcl] > [file join $sizing_dir sizing.log] 2>@1
set sizing_log [open [file join $sizing_dir sizing.log] r]
puts [read $sizing_log]
close $sizing_log
# Apply only checked cell replacements to the original graph. In particular,
# preserve original constant output bits that the OpenSTA exporter may omit.
source [file join $project_root scripts apply_burst_sizing.tcl]
yosys hierarchy -check -top upli_burst_control
yosys check -assert
yosys tee -o [file join $run_dir area.json] stat -json -liberty $cell_lib
yosys write_verilog -noattr -noexpr [file join $run_dir mapped.v]
yosys write_json [file join $run_dir mapped.json]
