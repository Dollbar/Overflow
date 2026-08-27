set liberty $::env(LIBERTY)
set rtl $::env(RTL)
set top $::env(TOP)
set cell_map $::env(CELL_MAP)
set netlist $::env(NETLIST)
set json $::env(JSON)
set abc_delay_ps $::env(ABC_DELAY_PS)
set abc_constr $::env(ABC_CONSTR)

yosys read_liberty -lib $liberty
foreach rtl_file $rtl {
    yosys read_verilog -sv $rtl_file
}
yosys hierarchy -check -top $top
yosys proc
yosys flatten
yosys opt
yosys memory_map
yosys techmap
yosys opt
yosys dffunmap
yosys opt
yosys dfflibmap -liberty $liberty
yosys abc -liberty $liberty -constr $abc_constr -D $abc_delay_ps
yosys techmap -map $cell_map
yosys clean
yosys check
yosys stat -liberty $liberty
yosys write_verilog -noattr -noexpr $netlist
yosys write_json $json
