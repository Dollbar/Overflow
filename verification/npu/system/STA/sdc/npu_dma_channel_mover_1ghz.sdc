create_clock -name clk_i -period $::env(CLOCK_PERIOD_NS) [get_ports clk_i]
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_NS) [get_clocks clk_i]
set_case_analysis 0 [get_ports {rst_i clear_i}]

set_input_delay $::env(INPUT_DELAY_NS) -clock clk_i [get_ports {
    command_valid_i command_i* hbm_request_ready_i hbm_request_local_tag_i*
    hbm_response_valid_i hbm_response_write_i hbm_response_local_tag_i*
    hbm_response_read_data_i* hbm_response_status_i*
    sram_read_request_ready_i sram_read_response_valid_i
    sram_read_response_data_i* sram_write_ready_i completion_ready_i
}]
set_driving_cell -lib_cell $::env(DRIVING_CELL) -pin $::env(DRIVING_PIN) [get_ports {
    command_valid_i command_i* hbm_request_ready_i hbm_request_local_tag_i*
    hbm_response_valid_i hbm_response_write_i hbm_response_local_tag_i*
    hbm_response_read_data_i* hbm_response_status_i*
    sram_read_request_ready_i sram_read_response_valid_i
    sram_read_response_data_i* sram_write_ready_i completion_ready_i
}]
set_output_delay $::env(OUTPUT_DELAY_NS) -clock clk_i [get_ports {
    command_ready_o hbm_request_valid_o hbm_request_write_o
    hbm_request_address_o* hbm_request_write_data_o*
    hbm_request_byte_enable_o* hbm_request_qos_o* hbm_response_ready_o
    sram_read_request_valid_o sram_read_request_address_o*
    sram_read_response_ready_o sram_write_valid_o sram_write_address_o*
    sram_write_data_o* sram_write_byte_enable_o* completion_valid_o
    completion_o* busy_o outstanding_o* protocol_error_o
}]
set_load $::env(OUTPUT_LOAD_PF) [get_ports {
    command_ready_o hbm_request_valid_o hbm_request_write_o
    hbm_request_address_o* hbm_request_write_data_o*
    hbm_request_byte_enable_o* hbm_request_qos_o* hbm_response_ready_o
    sram_read_request_valid_o sram_read_request_address_o*
    sram_read_response_ready_o sram_write_valid_o sram_write_address_o*
    sram_write_data_o* sram_write_byte_enable_o* completion_valid_o
    completion_o* busy_o outstanding_o* protocol_error_o
}]
