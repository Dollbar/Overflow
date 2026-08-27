# Apache-2.0 constraints for one representative mapped NPU local SRAM bank.
create_clock -name NPU_LOCAL_SRAM_CLK -period 1.000 [get_ports clk_i]
set_input_delay 0.100 -clock NPU_LOCAL_SRAM_CLK [get_ports {write_cs_i read_cs_i write_addr_i read_addr_i write_data_i}]
set_output_delay 0.100 -clock NPU_LOCAL_SRAM_CLK [get_ports read_data_o]
set_load 0.010 [get_ports read_data_o]
