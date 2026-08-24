set clock_period $::env(CLOCK_PERIOD_NS)
set clock_uncertainty $::env(CLOCK_UNCERTAINTY_NS)
set input_delay $::env(INPUT_DELAY_NS)
set output_delay $::env(OUTPUT_DELAY_NS)
set output_load $::env(OUTPUT_LOAD_PF)

create_clock -name clk_i -period $clock_period [get_ports clk_i]
set_clock_transition 0.030 [get_clocks clk_i]
set_clock_uncertainty $clock_uncertainty [get_clocks clk_i]
set_case_analysis 0 [get_ports {rst_i clear_i}]

set synchronous_inputs [get_ports {
    input_valid_i* input_result_i* input_command_i* output_ready_i*
    completion_ready_i
}]
set_input_delay $input_delay -clock clk_i $synchronous_inputs
set_driving_cell -lib_cell BUFFD1BWP40P140 -pin Z $synchronous_inputs
set_output_delay $output_delay -clock clk_i [all_outputs]
set_load $output_load [all_outputs]
