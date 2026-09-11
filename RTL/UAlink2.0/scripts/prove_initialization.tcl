# Run: make -f scripts/initialization.mk prove-initialization PORTS=4
# Outputs: reports/initialization_properties_*.log; actual-state instrumented DUT in build/.
# Next: functional simulation, actual-library equivalence and STA; no physical signoff here.
foreach key {UALINK_PORTS UALINK_CREDIT_WIDTH UALINK_CAPACITIES UALINK_BUILD_DIR} {
    if {![info exists env($key)] || $env($key) eq ""} {error "Missing $key"}
}
if {$env(UALINK_PORTS) ni {1 2 4}} {error "ports must be 1, 2 or 4"}
if {![string is integer -strict $env(UALINK_CREDIT_WIDTH)] || $env(UALINK_CREDIT_WIDTH) < 3 || $env(UALINK_CREDIT_WIDTH) > 16} {error "width must be 3..16"}
if {![regexp {^[0-9a-fA-F]+$} $env(UALINK_CAPACITIES)]} {error "capacities must be hex"}
set ports $env(UALINK_PORTS)
set width $env(UALINK_CREDIT_WIDTH)
set bits [expr {$ports*5*$width}]
if {[expr "0x$env(UALINK_CAPACITIES)"] >= (1 << $bits)} {error "capacity width overflow"}
set caps "${bits}'h$env(UALINK_CAPACITIES)"
set project_root [file dirname [file dirname [file normalize [info script]]]]
set run_dir [file normalize $env(UALINK_BUILD_DIR)]
file mkdir $run_dir
yosys read_verilog [file join $project_root rtl upli upli_credit_initializer.v]
yosys chparam -set C_NUM_PORTS $ports -set C_CREDIT_WIDTH $width -set C_DEFAULT_CAPACITY 0 -set C_CAPACITIES $caps upli_credit_initializer
yosys prep -top upli_credit_initializer
# Add only new observation outputs. Every original FF and functional driver stays.
yosys select -module upli_credit_initializer
yosys add -output o_formal_stages [expr {$ports*3}]
yosys add -output o_formal_issued [expr {$ports*$width}]
for {set port 0} {$port < $ports} {incr port} {
    set stage [format {gen_ports[%d].gen_active.state_current} $port]
    set count [format {gen_ports[%d].gen_active.cnt_issued} $port]
    yosys select -assert-count 1 w:$stage
    yosys select -assert-count 1 w:$count
    yosys connect -nounset -set [format {o_formal_stages[%d:%d]} [expr {$port*3+2}] [expr {$port*3}]] $stage
    yosys connect -nounset -set [format {o_formal_issued[%d:%d]} [expr {($port+1)*$width-1}] [expr {$port*$width}]] $count
}
yosys select -clear
yosys check -assert
yosys write_verilog -noattr [file join $run_dir instrumented.v]
yosys read_verilog [file join $project_root verification formal upli_credit_initialization_properties.v]
yosys chparam -set C_NUM_PORTS $ports -set C_CREDIT_WIDTH $width -set C_CAPACITIES $caps upli_credit_initialization_properties
yosys prep -top upli_credit_initialization_properties -flatten
yosys check -assert
yosys sat -verify -seq 4 -timeout 45 -set-def-inputs -set-at 1 i_rstn 0 -prove o_violation 0 -prove-skip 1 upli_credit_initialization_properties
yosys sat -verify -tempinduct-def -seq 2 -maxsteps 12 -timeout 45 -set-def-inputs -set-init-zero -prove o_violation 0 upli_credit_initialization_properties
