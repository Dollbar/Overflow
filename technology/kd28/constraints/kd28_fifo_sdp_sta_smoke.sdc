# Apache-2.0 constraints for independent-clock KD28 FIFO storage macro STA smoke checks.
create_clock -name KD28_FIFO_WRITE_CLK -period 2.000 [get_ports write_clk_i]
create_clock -name KD28_FIFO_READ_CLK -period 2.600 [get_ports read_clk_i]
set_clock_groups -asynchronous -group KD28_FIFO_WRITE_CLK -group KD28_FIFO_READ_CLK
set_input_delay 0.100 -clock KD28_FIFO_WRITE_CLK [get_ports {write_cs_i write_addr_i write_data_i write_mask_i}]
set_input_delay 0.100 -clock KD28_FIFO_READ_CLK [get_ports {read_cs_i read_addr_i}]
set_output_delay 0.100 -clock KD28_FIFO_READ_CLK [get_ports read_data_o]
set_load 0.010 [get_ports read_data_o]
