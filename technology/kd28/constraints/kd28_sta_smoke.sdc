# Apache-2.0 constraints for the generated KD28 synthetic SRAM STA smoke design.
create_clock -name KD28_CLK -period 2.000 [get_ports clk_i]
set_input_delay 0.100 -clock KD28_CLK [get_ports {sp_*_i sdp_*_i tdp_*_i}]
set_output_delay 0.100 -clock KD28_CLK [get_ports *_o]
set_load 0.010 [get_ports *_o]
