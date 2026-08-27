set clock_period $::env(CLOCK_PERIOD_NS)
set clock_uncertainty $::env(CLOCK_UNCERTAINTY_NS)
set input_delay $::env(INPUT_DELAY_NS)
set output_delay $::env(OUTPUT_DELAY_NS)
set output_load $::env(OUTPUT_LOAD_PF)

create_clock -name clk_i -period $clock_period [get_ports clk_i]
set_clock_transition 0.030 [get_clocks clk_i]
set_clock_uncertainty $clock_uncertainty [get_clocks clk_i]
set_case_analysis 0 [get_ports rst_i]

set synchronous_inputs [get_ports {
    channel_request_valid_i* channel_request_write_i*
    channel_request_address_i* channel_request_write_data_i*
    channel_request_byte_enable_i* channel_request_qos_i*
    hbm_request_ready_i* hbm_response_valid_i* hbm_response_write_i*
    hbm_response_partition_i* hbm_response_tag_i*
    hbm_response_read_data_i* hbm_response_status_i*
    channel_response_ready_i* quiesce_i
}]
set_input_delay $input_delay -clock clk_i $synchronous_inputs
set_driving_cell -lib_cell $::env(DRIVING_CELL) -pin $::env(DRIVING_PIN) $synchronous_inputs
set_output_delay $output_delay -clock clk_i [all_outputs]
set_load $output_load [all_outputs]
