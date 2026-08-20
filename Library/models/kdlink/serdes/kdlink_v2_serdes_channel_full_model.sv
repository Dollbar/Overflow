module kdlink_v2_serdes_channel_full_model #(
    parameter integer LANES = 10,
    parameter integer PROPAGATION_CYCLES = 3,
    parameter integer MAX_LANE_SKEW_CYCLES = 2,
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
    input wire admin_up_i,
    input wire [LANES-1:0] signal_detect_i,
    input wire [LANES-1:0] rx_ready_i,
    input wire [LANES-1:0] force_loss_of_lock_i,
    input wire tx_group_valid_i,
    input wire [LANES*66-1:0] tx_group_blocks_i,
    input wire [LANES-1:0] inject_drop_i,
    input wire [LANES-1:0] inject_corrupt_i,
    input wire [LANES-1:0] inject_burst_i,
    input wire [31:0] error_period_blocks_i,
    input wire [((LANES <= 2) ? 1 : $clog2(LANES))-1:0] error_lane_i,
    output wire [LANES-1:0] rx_lane_valid_o,
    output wire [LANES*66-1:0] rx_lane_blocks_o,
    output wire [LANES-1:0] cdr_locked_o,
    output wire [LANES-1:0] block_locked_o,
    output wire [LANES-1:0] lane_ready_o,
    output wire [LANES*3-1:0] lane_state_o,
    output reg [1:0] link_state_o,
    output wire link_up_o,
    output reg [63:0] offered_groups_o,
    output wire [63:0] delivered_blocks_o,
    output wire [63:0] dropped_blocks_o,
    output wire [63:0] corrupted_blocks_o,
    output wire [63:0] overflow_blocks_o,
    output wire [63:0] retrain_events_o
);
    localparam [1:0] LINK_DOWN = 2'd0;
    localparam [1:0] LINK_TRAINING = 2'd1;
    localparam [1:0] LINK_UP = 2'd2;
    localparam [1:0] LINK_DEGRADED = 2'd3;

    wire [31:0] lane_delivered [0:LANES-1];
    wire [31:0] lane_dropped [0:LANES-1];
    wire [31:0] lane_corrupted [0:LANES-1];
    wire [31:0] lane_overflow [0:LANES-1];
    wire [31:0] lane_retrain [0:LANES-1];
    wire [31:0] lane_offered [0:LANES-1];
    reg [63:0] delivered_sum;
    reg [63:0] dropped_sum;
    reg [63:0] corrupted_sum;
    reg [63:0] overflow_sum;
    reg [63:0] retrain_sum;
    integer sum_lane;

    assign link_up_o = (link_state_o == LINK_UP);
    assign delivered_blocks_o = delivered_sum;
    assign dropped_blocks_o = dropped_sum;
    assign corrupted_blocks_o = corrupted_sum;
    assign overflow_blocks_o = overflow_sum;
    assign retrain_events_o = retrain_sum;

    initial begin
        if (LANES < 1) $fatal(1, "LANES must be positive");
        if (MAX_LANE_SKEW_CYCLES < 0) $fatal(1, "MAX_LANE_SKEW_CYCLES must be non-negative");
        if (LINE_RATE_KBPS <= 0) $fatal(1, "LINE_RATE_KBPS must be positive");
        if (MODULATION_BITS_PER_SYMBOL != 1 && MODULATION_BITS_PER_SYMBOL != 2) begin
            $fatal(1, "modulation must be NRZ (1) or PAM4 (2)");
        end
    end

    always @* begin
        delivered_sum = 64'd0;
        dropped_sum = 64'd0;
        corrupted_sum = 64'd0;
        overflow_sum = 64'd0;
        retrain_sum = 64'd0;
        for (sum_lane = 0; sum_lane < LANES; sum_lane = sum_lane + 1) begin
            delivered_sum = delivered_sum + {32'd0, lane_delivered[sum_lane]};
            dropped_sum = dropped_sum + {32'd0, lane_dropped[sum_lane]};
            corrupted_sum = corrupted_sum + {32'd0, lane_corrupted[sum_lane]};
            overflow_sum = overflow_sum + {32'd0, lane_overflow[sum_lane]};
            retrain_sum = retrain_sum + {32'd0, lane_retrain[sum_lane]};
        end
    end

    always @* begin
        if (!admin_up_i || !(|signal_detect_i)) link_state_o = LINK_DOWN;
        else if (&lane_ready_o) link_state_o = LINK_UP;
        else if (|lane_ready_o) link_state_o = LINK_DEGRADED;
        else link_state_o = LINK_TRAINING;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) offered_groups_o <= 64'd0;
        else if (admin_up_i && tx_group_valid_i && (|lane_ready_o)) begin
            offered_groups_o <= offered_groups_o + 64'd1;
        end
    end

    genvar lane;
    generate
        for (lane = 0; lane < LANES; lane = lane + 1) begin : g_lane
            localparam integer LANE_SKEW = (MAX_LANE_SKEW_CYCLES == 0) ? 0 :
                (lane % (MAX_LANE_SKEW_CYCLES + 1));
            wire [31:0] lane_error_period;
            assign lane_error_period = (error_lane_i == lane) ? error_period_blocks_i : 32'd0;
            kdlink_v2_serdes_lane_full_model #(
                .PROPAGATION_CYCLES(PROPAGATION_CYCLES),
                .STATIC_SKEW_CYCLES(LANE_SKEW),
                .CDR_LOCK_CYCLES(CDR_LOCK_CYCLES),
                .BLOCK_LOCK_CYCLES(BLOCK_LOCK_CYCLES),
                .JITTER_PERIOD_BLOCKS(JITTER_PERIOD_BLOCKS),
                .JITTER_EXTRA_CYCLES(JITTER_EXTRA_CYCLES),
                .BURST_ERROR_LENGTH_BLOCKS(BURST_ERROR_LENGTH_BLOCKS),
                .ELASTIC_DEPTH(ELASTIC_DEPTH)
            ) u_lane (
                .clk_i(clk_i), .rst_n_i(rst_n_i), .admin_up_i(admin_up_i),
                .signal_detect_i(signal_detect_i[lane]), .rx_ready_i(rx_ready_i[lane]),
                .force_loss_of_lock_i(force_loss_of_lock_i[lane]),
                .tx_block_valid_i(tx_group_valid_i),
                .tx_block_i(tx_group_blocks_i[lane*66 +: 66]),
                .inject_drop_i(inject_drop_i[lane]),
                .inject_corrupt_i(inject_corrupt_i[lane]),
                .inject_burst_i(inject_burst_i[lane]),
                .error_period_blocks_i(lane_error_period),
                .rx_block_valid_o(rx_lane_valid_o[lane]),
                .rx_block_o(rx_lane_blocks_o[lane*66 +: 66]),
                .cdr_locked_o(cdr_locked_o[lane]),
                .block_locked_o(block_locked_o[lane]),
                .lane_ready_o(lane_ready_o[lane]),
                .lane_state_o(lane_state_o[lane*3 +: 3]),
                .offered_blocks_o(lane_offered[lane]),
                .delivered_blocks_o(lane_delivered[lane]),
                .dropped_blocks_o(lane_dropped[lane]),
                .corrupted_blocks_o(lane_corrupted[lane]),
                .overflow_blocks_o(lane_overflow[lane]),
                .retrain_events_o(lane_retrain[lane])
            );
        end
    endgenerate
endmodule
