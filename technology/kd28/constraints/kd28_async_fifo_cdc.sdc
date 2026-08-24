# Apache-2.0 integration template for one synthesized kd28_async_fifo instance named u_async_fifo.
# Replace clock periods and confirm synthesized register names before signing off a consuming design.
create_clock -name KD28_FIFO_WRITE_CLK -period 2.000 [get_ports write_clk_i]
create_clock -name KD28_FIFO_READ_CLK -period 2.600 [get_ports read_clk_i]
set_clock_groups -asynchronous -allow_paths -group KD28_FIFO_WRITE_CLK -group KD28_FIFO_READ_CLK
set_false_path -from [get_ports write_rst_n_i]
set_false_path -from [get_ports read_rst_n_i]
set_max_delay 2.000 -ignore_clock_latency -from [get_pins -hierarchical *read_consume_gray_q*/Q] -to [get_pins -hierarchical *read_gray_wsync1_q*/D]
set_max_delay 2.600 -ignore_clock_latency -from [get_pins -hierarchical *write_gray_q*/Q] -to [get_pins -hierarchical *write_gray_rsync1_q*/D]
if {[llength [info commands set_bus_skew]]} {
    set_bus_skew 2.000 -from [get_pins -hierarchical *read_consume_gray_q*/Q] -to [get_pins -hierarchical *read_gray_wsync1_q*/D]
    set_bus_skew 2.600 -from [get_pins -hierarchical *write_gray_q*/Q] -to [get_pins -hierarchical *write_gray_rsync1_q*/D]
}
