# Apache-2.0 synthetic validation constraint; not a physical implementation clock.
create_clock -name model_clk -period 2.000 [get_ports clk_i]
set_input_delay 0.200 -clock model_clk [get_ports {
  hbm_req_valid_i hbm_req_write_i hbm_req_data_i serdes_tx_valid_i serdes_tx_block_i
}]
set_output_delay 0.200 -clock model_clk [get_ports {
  hbm_req_ready_o hbm_rsp_valid_o hbm_rsp_error_o hbm_rsp_data_o
  serdes_rx_valid_o serdes_rx_block_o serdes_link_up_o
}]
set_clock_uncertainty 0.050 [get_clocks model_clk]
set_input_transition 0.050 [all_inputs -no_clocks]
set_load 0.005 [all_outputs]
