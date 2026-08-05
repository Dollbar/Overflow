module kdlink_serdes_link_model #(
    parameter integer PROPAGATION_CYCLES = 3,
    parameter integer MAX_LANE_SKEW_CYCLES = 2,
    parameter integer TRAINING_CYCLES = 16
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire admin_up_i,
    input wire [9:0] a_to_b_lane_up_i,
    input wire [9:0] b_to_a_lane_up_i,
    input wire a_tx_group_valid_i,
    input wire [659:0] a_tx_group_blocks_i,
    input wire b_tx_group_valid_i,
    input wire [659:0] b_tx_group_blocks_i,
    input wire [9:0] inject_a_to_b_drop_i,
    input wire [9:0] inject_a_to_b_corrupt_i,
    input wire [9:0] inject_b_to_a_drop_i,
    input wire [9:0] inject_b_to_a_corrupt_i,
    input wire [31:0] ber_period_groups_i,
    input wire [3:0] ber_lane_i,
    output wire [9:0] a_rx_lane_valid_o,
    output wire [659:0] a_rx_lane_blocks_o,
    output wire [9:0] b_rx_lane_valid_o,
    output wire [659:0] b_rx_lane_blocks_o,
    output wire [1:0] a_to_b_state_o,
    output wire [1:0] b_to_a_state_o,
    output wire full_duplex_up_o,
    output wire [31:0] a_to_b_groups_o,
    output wire [31:0] b_to_a_groups_o,
    output wire [31:0] dropped_blocks_o,
    output wire [31:0] corrupted_blocks_o
);
    wire a_to_b_up;
    wire b_to_a_up;
    wire [31:0] a_to_b_dropped;
    wire [31:0] b_to_a_dropped;
    wire [31:0] a_to_b_corrupted;
    wire [31:0] b_to_a_corrupted;
    assign full_duplex_up_o = a_to_b_up && b_to_a_up;
    assign dropped_blocks_o = a_to_b_dropped + b_to_a_dropped;
    assign corrupted_blocks_o = a_to_b_corrupted + b_to_a_corrupted;

    kdlink_serdes_channel_model #(
        .PROPAGATION_CYCLES(PROPAGATION_CYCLES),
        .MAX_LANE_SKEW_CYCLES(MAX_LANE_SKEW_CYCLES),
        .TRAINING_CYCLES(TRAINING_CYCLES)
    ) u_a_to_b (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .admin_up_i(admin_up_i), .lane_up_i(a_to_b_lane_up_i),
        .tx_group_valid_i(a_tx_group_valid_i), .tx_group_blocks_i(a_tx_group_blocks_i),
        .inject_drop_i(inject_a_to_b_drop_i), .inject_corrupt_i(inject_a_to_b_corrupt_i),
        .ber_period_groups_i(ber_period_groups_i), .ber_lane_i(ber_lane_i),
        .rx_lane_valid_o(b_rx_lane_valid_o), .rx_lane_blocks_o(b_rx_lane_blocks_o),
        .link_state_o(a_to_b_state_o), .link_up_o(a_to_b_up),
        .transmitted_groups_o(a_to_b_groups_o), .dropped_blocks_o(a_to_b_dropped),
        .corrupted_blocks_o(a_to_b_corrupted)
    );

    kdlink_serdes_channel_model #(
        .PROPAGATION_CYCLES(PROPAGATION_CYCLES),
        .MAX_LANE_SKEW_CYCLES(MAX_LANE_SKEW_CYCLES),
        .TRAINING_CYCLES(TRAINING_CYCLES)
    ) u_b_to_a (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .admin_up_i(admin_up_i), .lane_up_i(b_to_a_lane_up_i),
        .tx_group_valid_i(b_tx_group_valid_i), .tx_group_blocks_i(b_tx_group_blocks_i),
        .inject_drop_i(inject_b_to_a_drop_i), .inject_corrupt_i(inject_b_to_a_corrupt_i),
        .ber_period_groups_i(ber_period_groups_i), .ber_lane_i(ber_lane_i),
        .rx_lane_valid_o(a_rx_lane_valid_o), .rx_lane_blocks_o(a_rx_lane_blocks_o),
        .link_state_o(b_to_a_state_o), .link_up_o(b_to_a_up),
        .transmitted_groups_o(b_to_a_groups_o), .dropped_blocks_o(b_to_a_dropped),
        .corrupted_blocks_o(b_to_a_corrupted)
    );
endmodule
