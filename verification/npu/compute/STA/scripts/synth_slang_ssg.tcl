set liberty $::env(LIBERTY)
set rtl $::env(RTL)
set top $::env(TOP)
set abc_delay_ps $::env(ABC_DELAY_PS)
set abc_constr $::env(ABC_CONSTR)
set ff_techmap $::env(FF_TECHMAP)
set netlist $::env(NETLIST)
set json $::env(JSON)

yosys read_liberty -lib $liberty
eval yosys read_slang --std 1800-2017 --compat vcs \
    --allow-use-before-declare --relax-enum-conversions --top $top $rtl
yosys hierarchy -check -top $top
yosys chformal -remove
yosys flatten
yosys proc
yosys opt
yosys memory_map
yosys techmap
yosys opt
yosys techmap -map $ff_techmap
yosys techmap
yosys opt
yosys dffunmap -ce-only
yosys abc -liberty $liberty -constr $abc_constr -D $abc_delay_ps
yosys dfflibmap -liberty $liberty
yosys clean
yosys check
yosys stat -liberty $liberty
yosys write_verilog -noattr -noexpr $netlist
yosys write_json $json
