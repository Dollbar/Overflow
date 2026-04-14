set liberty $::env(LIBERTY)
set rtl $::env(RTL)
set top $::env(TOP)
set cell_map $::env(CELL_MAP)
set netlist $::env(NETLIST)
set json $::env(JSON)

yosys read_liberty -lib $liberty
foreach rtl_file $rtl {
    yosys read_verilog -sv $rtl_file
}
yosys hierarchy -check -top $top
yosys proc
yosys opt
yosys memory_map
yosys techmap
yosys opt
yosys dffunmap
yosys opt
yosys dfflibmap -liberty $liberty
yosys techmap -map $cell_map
yosys clean
yosys check
yosys stat -liberty $liberty
yosys write_verilog -noattr -noexpr $netlist
yosys write_json $json
