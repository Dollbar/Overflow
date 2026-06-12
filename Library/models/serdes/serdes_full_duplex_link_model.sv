`timescale 1ns/1ps
module serdes_full_duplex_link_model #(
 parameter integer LANES=1,parameter integer BLOCK_WIDTH=serdes_212g5_pam4_profile_pkg::SERDES_212G5_PCS_BLOCK_BITS,
 parameter integer PROPAGATION_CYCLES=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_PROPAGATION_CYCLES,
 parameter integer MAX_LANE_SKEW_CYCLES=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_MAX_LANE_SKEW_CYCLES,
 parameter integer CDR_LOCK_CYCLES=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_CDR_LOCK_CYCLES,
 parameter integer BLOCK_LOCK_CYCLES=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_BLOCK_LOCK_CYCLES,
 parameter integer JITTER_PERIOD_BLOCKS=0,parameter integer JITTER_EXTRA_CYCLES=0,
 parameter integer BURST_ERROR_LENGTH_BLOCKS=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_BURST_ERROR_LENGTH_BLOCKS,
 parameter integer ELASTIC_DEPTH=serdes_212g5_pam4_profile_pkg::SERDES_DEFAULT_ELASTIC_DEPTH,
 parameter[63:0]LINE_RATE_BPS=serdes_212g5_pam4_profile_pkg::SERDES_212G5_LINE_RATE_BPS,
 parameter integer MODULATION_BITS_PER_SYMBOL=serdes_212g5_pam4_profile_pkg::SERDES_212G5_BITS_PER_SYMBOL
)(
 input wire clk_i,input wire rst_n_i,input wire a_to_b_admin_up_i,input wire b_to_a_admin_up_i,
 input wire[LANES-1:0]a_to_b_signal_detect_i,input wire[LANES-1:0]b_to_a_signal_detect_i,input wire[LANES-1:0]a_to_b_force_loss_of_lock_i,input wire[LANES-1:0]b_to_a_force_loss_of_lock_i,
 input wire a_tx_valid_i,output wire a_tx_ready_o,input wire[LANES*BLOCK_WIDTH-1:0]a_tx_blocks_i,input wire b_tx_valid_i,output wire b_tx_ready_o,input wire[LANES*BLOCK_WIDTH-1:0]b_tx_blocks_i,
 output wire[LANES-1:0]a_rx_valid_o,input wire[LANES-1:0]a_rx_ready_i,output wire[LANES*BLOCK_WIDTH-1:0]a_rx_blocks_o,
 output wire[LANES-1:0]b_rx_valid_o,input wire[LANES-1:0]b_rx_ready_i,output wire[LANES*BLOCK_WIDTH-1:0]b_rx_blocks_o,
 input wire[LANES-1:0]inject_a_to_b_drop_i,input wire[LANES-1:0]inject_a_to_b_corrupt_i,input wire[LANES-1:0]inject_a_to_b_burst_i,
 input wire[LANES-1:0]inject_b_to_a_drop_i,input wire[LANES-1:0]inject_b_to_a_corrupt_i,input wire[LANES-1:0]inject_b_to_a_burst_i,
 input wire[31:0]a_to_b_error_period_blocks_i,input wire[31:0]b_to_a_error_period_blocks_i,input wire[((LANES<=2)?1:$clog2(LANES))-1:0]a_to_b_error_lane_i,input wire[((LANES<=2)?1:$clog2(LANES))-1:0]b_to_a_error_lane_i,
 output wire[LANES-1:0]a_to_b_lane_ready_o,output wire[LANES-1:0]b_to_a_lane_ready_o,output wire full_duplex_up_o,
 output wire[63:0]offered_blocks_o,output wire[63:0]delivered_blocks_o,output wire[63:0]dropped_blocks_o,output wire[63:0]corrupted_blocks_o,output wire[63:0]overflow_blocks_o,output wire[63:0]retrain_events_o
);
 wire a_up,b_up;wire[1:0]a_state,b_state;wire[LANES-1:0]a_cdr_unused,b_cdr_unused,a_block_unused,b_block_unused;wire[63:0]a_groups,b_groups,a_offered,b_offered,a_delivered,b_delivered,a_dropped,b_dropped,a_corrupted,b_corrupted,a_overflow,b_overflow,a_retrain,b_retrain;
 assign full_duplex_up_o=a_up&&b_up;assign offered_blocks_o=a_offered+b_offered;assign delivered_blocks_o=a_delivered+b_delivered;assign dropped_blocks_o=a_dropped+b_dropped;assign corrupted_blocks_o=a_corrupted+b_corrupted;assign overflow_blocks_o=a_overflow+b_overflow;assign retrain_events_o=a_retrain+b_retrain;
 serdes_channel_model #(.LANES(LANES),.BLOCK_WIDTH(BLOCK_WIDTH),.PROPAGATION_CYCLES(PROPAGATION_CYCLES),.MAX_LANE_SKEW_CYCLES(MAX_LANE_SKEW_CYCLES),.CDR_LOCK_CYCLES(CDR_LOCK_CYCLES),.BLOCK_LOCK_CYCLES(BLOCK_LOCK_CYCLES),.JITTER_PERIOD_BLOCKS(JITTER_PERIOD_BLOCKS),.JITTER_EXTRA_CYCLES(JITTER_EXTRA_CYCLES),.BURST_ERROR_LENGTH_BLOCKS(BURST_ERROR_LENGTH_BLOCKS),.ELASTIC_DEPTH(ELASTIC_DEPTH),.LINE_RATE_BPS(LINE_RATE_BPS),.MODULATION_BITS_PER_SYMBOL(MODULATION_BITS_PER_SYMBOL))u_a_to_b(
  .clk_i(clk_i),.rst_n_i(rst_n_i),.admin_up_i(a_to_b_admin_up_i),.signal_detect_i(a_to_b_signal_detect_i),.force_loss_of_lock_i(a_to_b_force_loss_of_lock_i),.tx_group_valid_i(a_tx_valid_i),.tx_group_ready_o(a_tx_ready_o),.tx_group_blocks_i(a_tx_blocks_i),.inject_drop_i(inject_a_to_b_drop_i),.inject_corrupt_i(inject_a_to_b_corrupt_i),.inject_burst_i(inject_a_to_b_burst_i),.error_period_blocks_i(a_to_b_error_period_blocks_i),.error_lane_i(a_to_b_error_lane_i),.rx_lane_valid_o(b_rx_valid_o),.rx_lane_ready_i(b_rx_ready_i),.rx_lane_blocks_o(b_rx_blocks_o),.cdr_locked_o(a_cdr_unused),.block_locked_o(a_block_unused),.lane_ready_o(a_to_b_lane_ready_o),.link_state_o(a_state),.link_up_o(a_up),.offered_groups_o(a_groups),.offered_blocks_o(a_offered),.delivered_blocks_o(a_delivered),.dropped_blocks_o(a_dropped),.corrupted_blocks_o(a_corrupted),.overflow_blocks_o(a_overflow),.retrain_events_o(a_retrain));
 serdes_channel_model #(.LANES(LANES),.BLOCK_WIDTH(BLOCK_WIDTH),.PROPAGATION_CYCLES(PROPAGATION_CYCLES),.MAX_LANE_SKEW_CYCLES(MAX_LANE_SKEW_CYCLES),.CDR_LOCK_CYCLES(CDR_LOCK_CYCLES),.BLOCK_LOCK_CYCLES(BLOCK_LOCK_CYCLES),.JITTER_PERIOD_BLOCKS(JITTER_PERIOD_BLOCKS),.JITTER_EXTRA_CYCLES(JITTER_EXTRA_CYCLES),.BURST_ERROR_LENGTH_BLOCKS(BURST_ERROR_LENGTH_BLOCKS),.ELASTIC_DEPTH(ELASTIC_DEPTH),.LINE_RATE_BPS(LINE_RATE_BPS),.MODULATION_BITS_PER_SYMBOL(MODULATION_BITS_PER_SYMBOL))u_b_to_a(
  .clk_i(clk_i),.rst_n_i(rst_n_i),.admin_up_i(b_to_a_admin_up_i),.signal_detect_i(b_to_a_signal_detect_i),.force_loss_of_lock_i(b_to_a_force_loss_of_lock_i),.tx_group_valid_i(b_tx_valid_i),.tx_group_ready_o(b_tx_ready_o),.tx_group_blocks_i(b_tx_blocks_i),.inject_drop_i(inject_b_to_a_drop_i),.inject_corrupt_i(inject_b_to_a_corrupt_i),.inject_burst_i(inject_b_to_a_burst_i),.error_period_blocks_i(b_to_a_error_period_blocks_i),.error_lane_i(b_to_a_error_lane_i),.rx_lane_valid_o(a_rx_valid_o),.rx_lane_ready_i(a_rx_ready_i),.rx_lane_blocks_o(a_rx_blocks_o),.cdr_locked_o(b_cdr_unused),.block_locked_o(b_block_unused),.lane_ready_o(b_to_a_lane_ready_o),.link_state_o(b_state),.link_up_o(b_up),.offered_groups_o(b_groups),.offered_blocks_o(b_offered),.delivered_blocks_o(b_delivered),.dropped_blocks_o(b_dropped),.corrupted_blocks_o(b_corrupted),.overflow_blocks_o(b_overflow),.retrain_events_o(b_retrain));
 wire unused=^{a_state,b_state,a_groups,b_groups,a_cdr_unused,b_cdr_unused,a_block_unused,b_block_unused};
endmodule
