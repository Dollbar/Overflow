module kdlink_serdes_link_full_model #(
    parameter integer LANES = 10,
    parameter integer PROPAGATION_CYCLES = 3,
    parameter integer MAX_LANE_SKEW_CYCLES = 2,
    parameter integer A_TO_B_PROPAGATION_CYCLES = PROPAGATION_CYCLES,
    parameter integer B_TO_A_PROPAGATION_CYCLES = PROPAGATION_CYCLES,
    parameter integer A_TO_B_MAX_LANE_SKEW_CYCLES = MAX_LANE_SKEW_CYCLES,
    parameter integer B_TO_A_MAX_LANE_SKEW_CYCLES = MAX_LANE_SKEW_CYCLES,
    parameter integer CDR_LOCK_CYCLES = 8,
    parameter integer BLOCK_LOCK_CYCLES = 8,
    parameter integer JITTER_PERIOD_BLOCKS = 0,
    parameter integer JITTER_EXTRA_CYCLES = 0,
    parameter integer BURST_ERROR_LENGTH_BLOCKS = 4,
    parameter integer ELASTIC_DEPTH = 64,
    parameter integer LINE_RATE_KBPS = 106250000,
    parameter integer MODULATION_BITS_PER_SYMBOL = 2
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire a_to_b_admin_up_i,
    input wire b_to_a_admin_up_i,
    input wire [LANES-1:0] a_to_b_signal_detect_i,
    input wire [LANES-1:0] b_to_a_signal_detect_i,
    input wire [LANES-1:0] a_to_b_rx_ready_i,
    input wire [LANES-1:0] b_to_a_rx_ready_i,
    input wire [LANES-1:0] a_to_b_force_loss_of_lock_i,
    input wire [LANES-1:0] b_to_a_force_loss_of_lock_i,
    input wire a_tx_group_valid_i,
    input wire [LANES*66-1:0] a_tx_group_blocks_i,
    input wire b_tx_group_valid_i,
    input wire [LANES*66-1:0] b_tx_group_blocks_i,
    input wire [LANES-1:0] inject_a_to_b_drop_i,
    input wire [LANES-1:0] inject_a_to_b_corrupt_i,
    input wire [LANES-1:0] inject_a_to_b_burst_i,
    input wire [LANES-1:0] inject_b_to_a_drop_i,
    input wire [LANES-1:0] inject_b_to_a_corrupt_i,
    input wire [LANES-1:0] inject_b_to_a_burst_i,
    input wire [31:0] a_to_b_error_period_blocks_i,
    input wire [31:0] b_to_a_error_period_blocks_i,
    input wire [((LANES <= 2) ? 1 : $clog2(LANES))-1:0] a_to_b_error_lane_i,
    input wire [((LANES <= 2) ? 1 : $clog2(LANES))-1:0] b_to_a_error_lane_i,
    output wire [LANES-1:0] a_rx_lane_valid_o,
    output wire [LANES*66-1:0] a_rx_lane_blocks_o,
    output wire [LANES-1:0] b_rx_lane_valid_o,
    output wire [LANES*66-1:0] b_rx_lane_blocks_o,
    output wire [LANES-1:0] a_to_b_cdr_locked_o,
    output wire [LANES-1:0] b_to_a_cdr_locked_o,
    output wire [LANES-1:0] a_to_b_block_locked_o,
    output wire [LANES-1:0] b_to_a_block_locked_o,
    output wire [LANES-1:0] a_to_b_lane_ready_o,
    output wire [LANES-1:0] b_to_a_lane_ready_o,
    output wire [1:0] a_to_b_state_o,
    output wire [1:0] b_to_a_state_o,
    output wire full_duplex_up_o,
    output wire [63:0] a_to_b_offered_groups_o,
    output wire [63:0] b_to_a_offered_groups_o,
    output wire [63:0] delivered_blocks_o,
    output wire [63:0] dropped_blocks_o,
    output wire [63:0] corrupted_blocks_o,
    output wire [63:0] overflow_blocks_o,
    output wire [63:0] retrain_events_o
);
    wire [LANES*3-1:0] unused_a_to_b_lane_state;
    wire [LANES*3-1:0] unused_b_to_a_lane_state;
    wire a_to_b_up;
    wire b_to_a_up;
    wire [63:0] a_to_b_delivered;
    wire [63:0] b_to_a_delivered;
    wire [63:0] a_to_b_dropped;
    wire [63:0] b_to_a_dropped;
    wire [63:0] a_to_b_corrupted;
    wire [63:0] b_to_a_corrupted;
    wire [63:0] a_to_b_overflow;
    wire [63:0] b_to_a_overflow;
    wire [63:0] a_to_b_retrain;
    wire [63:0] b_to_a_retrain;

    assign full_duplex_up_o = a_to_b_up && b_to_a_up;
    assign delivered_blocks_o = a_to_b_delivered + b_to_a_delivered;
    assign dropped_blocks_o = a_to_b_dropped + b_to_a_dropped;
    assign corrupted_blocks_o = a_to_b_corrupted + b_to_a_corrupted;
    assign overflow_blocks_o = a_to_b_overflow + b_to_a_overflow;
    assign retrain_events_o = a_to_b_retrain + b_to_a_retrain;

    kdlink_serdes_channel_full_model #(
        .LANES(LANES), .PROPAGATION_CYCLES(A_TO_B_PROPAGATION_CYCLES),
        .MAX_LANE_SKEW_CYCLES(A_TO_B_MAX_LANE_SKEW_CYCLES),
        .CDR_LOCK_CYCLES(CDR_LOCK_CYCLES), .BLOCK_LOCK_CYCLES(BLOCK_LOCK_CYCLES),
        .JITTER_PERIOD_BLOCKS(JITTER_PERIOD_BLOCKS),
        .JITTER_EXTRA_CYCLES(JITTER_EXTRA_CYCLES),
        .BURST_ERROR_LENGTH_BLOCKS(BURST_ERROR_LENGTH_BLOCKS),
        .ELASTIC_DEPTH(ELASTIC_DEPTH), .LINE_RATE_KBPS(LINE_RATE_KBPS),
        .MODULATION_BITS_PER_SYMBOL(MODULATION_BITS_PER_SYMBOL)
    ) u_a_to_b (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .admin_up_i(a_to_b_admin_up_i),
        .signal_detect_i(a_to_b_signal_detect_i), .rx_ready_i(a_to_b_rx_ready_i),
        .force_loss_of_lock_i(a_to_b_force_loss_of_lock_i),
        .tx_group_valid_i(a_tx_group_valid_i), .tx_group_blocks_i(a_tx_group_blocks_i),
        .inject_drop_i(inject_a_to_b_drop_i), .inject_corrupt_i(inject_a_to_b_corrupt_i),
        .inject_burst_i(inject_a_to_b_burst_i),
        .error_period_blocks_i(a_to_b_error_period_blocks_i),
        .error_lane_i(a_to_b_error_lane_i),
        .rx_lane_valid_o(b_rx_lane_valid_o), .rx_lane_blocks_o(b_rx_lane_blocks_o),
        .cdr_locked_o(a_to_b_cdr_locked_o), .block_locked_o(a_to_b_block_locked_o),
        .lane_ready_o(a_to_b_lane_ready_o), .lane_state_o(unused_a_to_b_lane_state),
        .link_state_o(a_to_b_state_o), .link_up_o(a_to_b_up),
        .offered_groups_o(a_to_b_offered_groups_o), .delivered_blocks_o(a_to_b_delivered),
        .dropped_blocks_o(a_to_b_dropped), .corrupted_blocks_o(a_to_b_corrupted),
        .overflow_blocks_o(a_to_b_overflow), .retrain_events_o(a_to_b_retrain)
    );

    kdlink_serdes_channel_full_model #(
        .LANES(LANES), .PROPAGATION_CYCLES(B_TO_A_PROPAGATION_CYCLES),
        .MAX_LANE_SKEW_CYCLES(B_TO_A_MAX_LANE_SKEW_CYCLES),
        .CDR_LOCK_CYCLES(CDR_LOCK_CYCLES), .BLOCK_LOCK_CYCLES(BLOCK_LOCK_CYCLES),
        .JITTER_PERIOD_BLOCKS(JITTER_PERIOD_BLOCKS),
        .JITTER_EXTRA_CYCLES(JITTER_EXTRA_CYCLES),
        .BURST_ERROR_LENGTH_BLOCKS(BURST_ERROR_LENGTH_BLOCKS),
        .ELASTIC_DEPTH(ELASTIC_DEPTH), .LINE_RATE_KBPS(LINE_RATE_KBPS),
        .MODULATION_BITS_PER_SYMBOL(MODULATION_BITS_PER_SYMBOL)
    ) u_b_to_a (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .admin_up_i(b_to_a_admin_up_i),
        .signal_detect_i(b_to_a_signal_detect_i), .rx_ready_i(b_to_a_rx_ready_i),
        .force_loss_of_lock_i(b_to_a_force_loss_of_lock_i),
        .tx_group_valid_i(b_tx_group_valid_i), .tx_group_blocks_i(b_tx_group_blocks_i),
        .inject_drop_i(inject_b_to_a_drop_i), .inject_corrupt_i(inject_b_to_a_corrupt_i),
        .inject_burst_i(inject_b_to_a_burst_i),
        .error_period_blocks_i(b_to_a_error_period_blocks_i),
        .error_lane_i(b_to_a_error_lane_i),
        .rx_lane_valid_o(a_rx_lane_valid_o), .rx_lane_blocks_o(a_rx_lane_blocks_o),
        .cdr_locked_o(b_to_a_cdr_locked_o), .block_locked_o(b_to_a_block_locked_o),
        .lane_ready_o(b_to_a_lane_ready_o), .lane_state_o(unused_b_to_a_lane_state),
        .link_state_o(b_to_a_state_o), .link_up_o(b_to_a_up),
        .offered_groups_o(b_to_a_offered_groups_o), .delivered_blocks_o(b_to_a_delivered),
        .dropped_blocks_o(b_to_a_dropped), .corrupted_blocks_o(b_to_a_corrupted),
        .overflow_blocks_o(b_to_a_overflow), .retrain_events_o(b_to_a_retrain)
    );
endmodule
