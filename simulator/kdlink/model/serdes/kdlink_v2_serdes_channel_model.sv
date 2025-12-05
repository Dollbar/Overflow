module kdlink_v2_serdes_channel_model #(
    parameter integer PROPAGATION_CYCLES = 3,
    parameter integer MAX_LANE_SKEW_CYCLES = 2,
    parameter integer TRAINING_CYCLES = 16
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire admin_up_i,
    input wire [9:0] lane_up_i,
    input wire tx_group_valid_i,
    input wire [659:0] tx_group_blocks_i,
    input wire [9:0] inject_drop_i,
    input wire [9:0] inject_corrupt_i,
    input wire [31:0] ber_period_groups_i,
    input wire [3:0] ber_lane_i,
    output wire [9:0] rx_lane_valid_o,
    output wire [659:0] rx_lane_blocks_o,
    output wire [1:0] link_state_o,
    output wire link_up_o,
    output reg [31:0] transmitted_groups_o,
    output reg [31:0] dropped_blocks_o,
    output reg [31:0] corrupted_blocks_o
);
    localparam integer PIPE_STAGES = PROPAGATION_CYCLES + MAX_LANE_SKEW_CYCLES + 1;
    localparam [1:0] LINK_DOWN = 2'd0;
    localparam [1:0] LINK_TRAINING = 2'd1;
    localparam [1:0] LINK_UP = 2'd2;
    localparam [1:0] LINK_DEGRADED = 2'd3;
    reg [1:0] link_state_q;
    reg [31:0] training_count_q;
    reg [31:0] ber_group_count_q;
    reg lane_valid_pipe [0:9][0:PIPE_STAGES-1];
    reg [65:0] lane_data_pipe [0:9][0:PIPE_STAGES-1];
    integer lane_index;
    integer stage_index;
    wire all_lanes_up;
    wire any_lane_up;
    wire ber_event;
    wire [9:0] drop_event;
    wire [9:0] corrupt_event;
    wire [3:0] dropped_this_cycle;
    wire [3:0] corrupted_this_cycle;
    assign all_lanes_up = &lane_up_i;
    assign any_lane_up = |lane_up_i;
    assign ber_event = (ber_period_groups_i != 32'd0) &&
        (ber_group_count_q >= (ber_period_groups_i - 32'd1));
    assign drop_event = inject_drop_i & lane_up_i & {10{tx_group_valid_i && admin_up_i}};
    assign dropped_this_cycle = {3'd0, drop_event[0]} + {3'd0, drop_event[1]} +
        {3'd0, drop_event[2]} + {3'd0, drop_event[3]} + {3'd0, drop_event[4]} +
        {3'd0, drop_event[5]} + {3'd0, drop_event[6]} + {3'd0, drop_event[7]} +
        {3'd0, drop_event[8]} + {3'd0, drop_event[9]};
    assign corrupted_this_cycle = {3'd0, corrupt_event[0]} + {3'd0, corrupt_event[1]} +
        {3'd0, corrupt_event[2]} + {3'd0, corrupt_event[3]} + {3'd0, corrupt_event[4]} +
        {3'd0, corrupt_event[5]} + {3'd0, corrupt_event[6]} + {3'd0, corrupt_event[7]} +
        {3'd0, corrupt_event[8]} + {3'd0, corrupt_event[9]};
    assign link_state_o = link_state_q;
    assign link_up_o = (link_state_q == LINK_UP);

    genvar event_lane;
    generate
        for (event_lane = 0; event_lane < 10; event_lane = event_lane + 1) begin : g_fault_event
            assign corrupt_event[event_lane] = tx_group_valid_i && admin_up_i && lane_up_i[event_lane] &&
                (inject_corrupt_i[event_lane] || (ber_event && (ber_lane_i == event_lane[3:0])));
        end
    endgenerate

    genvar output_lane;
    generate
        for (output_lane = 0; output_lane < 10; output_lane = output_lane + 1) begin : g_channel_output
            localparam integer LANE_DELAY = PROPAGATION_CYCLES +
                ((MAX_LANE_SKEW_CYCLES == 0) ? 0 : (output_lane % (MAX_LANE_SKEW_CYCLES + 1)));
            assign rx_lane_valid_o[output_lane] = lane_valid_pipe[output_lane][LANE_DELAY];
            assign rx_lane_blocks_o[output_lane*66 +: 66] = lane_data_pipe[output_lane][LANE_DELAY];
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            link_state_q <= LINK_DOWN;
            training_count_q <= 32'd0;
            ber_group_count_q <= 32'd0;
            transmitted_groups_o <= 32'd0;
            dropped_blocks_o <= 32'd0;
            corrupted_blocks_o <= 32'd0;
            for (lane_index = 0; lane_index < 10; lane_index = lane_index + 1) begin
                for (stage_index = 0; stage_index < PIPE_STAGES; stage_index = stage_index + 1) begin
                    lane_valid_pipe[lane_index][stage_index] <= 1'b0;
                    lane_data_pipe[lane_index][stage_index] <= 66'd0;
                end
            end
        end else begin
            if (!admin_up_i || !any_lane_up) begin
                link_state_q <= LINK_DOWN;
                training_count_q <= 32'd0;
            end else if (!all_lanes_up) begin
                link_state_q <= LINK_DEGRADED;
                training_count_q <= 32'd0;
            end else if ((link_state_q == LINK_DOWN) || (link_state_q == LINK_DEGRADED)) begin
                link_state_q <= LINK_TRAINING;
                training_count_q <= 32'd1;
            end else if (link_state_q == LINK_TRAINING) begin
                if (training_count_q >= (TRAINING_CYCLES - 1)) begin
                    link_state_q <= LINK_UP;
                    training_count_q <= training_count_q;
                end else begin
                    training_count_q <= training_count_q + 32'd1;
                end
            end else begin
                link_state_q <= LINK_UP;
            end

            if (tx_group_valid_i && admin_up_i) begin
                transmitted_groups_o <= transmitted_groups_o + 32'd1;
                if (ber_event) begin
                    ber_group_count_q <= 32'd0;
                end else begin
                    ber_group_count_q <= ber_group_count_q + 32'd1;
                end
            end
            if (dropped_this_cycle != 4'd0) begin
                dropped_blocks_o <= dropped_blocks_o + {28'd0, dropped_this_cycle};
            end
            if (corrupted_this_cycle != 4'd0) begin
                corrupted_blocks_o <= corrupted_blocks_o + {28'd0, corrupted_this_cycle};
            end

            for (lane_index = 0; lane_index < 10; lane_index = lane_index + 1) begin
                lane_valid_pipe[lane_index][0] <= tx_group_valid_i && admin_up_i && lane_up_i[lane_index] &&
                    !inject_drop_i[lane_index];
                lane_data_pipe[lane_index][0] <= tx_group_blocks_i[lane_index*66 +: 66];
                if (corrupt_event[lane_index]) begin
                    lane_data_pipe[lane_index][0] <= tx_group_blocks_i[lane_index*66 +: 66] ^ 66'd3;
                end
                for (stage_index = 1; stage_index < PIPE_STAGES; stage_index = stage_index + 1) begin
                    lane_valid_pipe[lane_index][stage_index] <= lane_valid_pipe[lane_index][stage_index-1];
                    lane_data_pipe[lane_index][stage_index] <= lane_data_pipe[lane_index][stage_index-1];
                end
            end
        end
    end
endmodule
