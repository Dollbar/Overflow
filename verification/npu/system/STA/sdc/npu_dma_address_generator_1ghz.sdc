create_clock -name clk_i -period $::env(CLOCK_PERIOD_NS) [get_ports clk_i]
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_NS) [get_clocks clk_i]
set_case_analysis 0 [get_ports {rst_i clear_i}]

set_input_delay $::env(INPUT_DELAY_NS) -clock clk_i [get_ports {
    command_valid_i command_i* beat_ready_i sequence_done_ready_i
}]
set_driving_cell -lib_cell $::env(DRIVING_CELL) -pin $::env(DRIVING_PIN) [get_ports {
    command_valid_i command_i* beat_ready_i sequence_done_ready_i
}]
set_output_delay $::env(OUTPUT_DELAY_NS) -clock clk_i [get_ports {
    command_ready_o beat_valid_o beat_operation_o* beat_command_id_o*
    beat_hbm_address_o* beat_sram_address_o* beat_qos_o* beat_first_o
    beat_last_o sequence_done_valid_o sequence_done_command_id_o*
    sequence_done_error_o sequence_done_error_code_o* sequence_done_beats_o*
    busy_o protocol_error_o
}]
set_load $::env(OUTPUT_LOAD_PF) [get_ports {
    command_ready_o beat_valid_o beat_operation_o* beat_command_id_o*
    beat_hbm_address_o* beat_sram_address_o* beat_qos_o* beat_first_o
    beat_last_o sequence_done_valid_o sequence_done_command_id_o*
    sequence_done_error_o sequence_done_error_code_o* sequence_done_beats_o*
    busy_o protocol_error_o
}]
