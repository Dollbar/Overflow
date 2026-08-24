`timescale 1ns/1ps
`default_nettype none

module npu_dma_hbm_response_router #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned HBM_LANES = 5,
    parameter int unsigned PARTITION_BITS = 3,
    parameter int unsigned PARTITION_ID = 0,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned CHANNEL_INDEX_WIDTH =
        (CHANNELS <= 1) ? 1 : $clog2(CHANNELS),
    parameter int unsigned HBM_TAG_WIDTH =
        CHANNEL_INDEX_WIDTH + LOCAL_TAG_WIDTH
) (
    input  logic clk_i,
    input  logic rst_i,

    input  logic [HBM_LANES-1:0] hbm_response_valid_i,
    output logic [HBM_LANES-1:0] hbm_response_ready_o,
    input  logic [HBM_LANES-1:0] hbm_response_write_i,
    input  logic [HBM_LANES*PARTITION_BITS-1:0] hbm_response_partition_i,
    input  logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_response_tag_i,
    input  logic [HBM_LANES*DATA_BYTES*8-1:0] hbm_response_read_data_i,
    input  logic [HBM_LANES*2-1:0] hbm_response_status_i,

    output logic [CHANNELS-1:0] channel_response_valid_o,
    input  logic [CHANNELS-1:0] channel_response_ready_i,
    output logic [CHANNELS-1:0] channel_response_write_o,
    output logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] channel_response_local_tag_o,
    output logic [CHANNELS*DATA_BYTES*8-1:0] channel_response_read_data_o,
    output logic [CHANNELS*2-1:0] channel_response_status_o,

    output logic busy_o,
    output logic protocol_error_o,
    output logic [63:0] accepted_responses_o,
    output logic [63:0] delivered_responses_o,
    output logic [63:0] dropped_responses_o,
    output logic [63:0] backpressure_cycles_o
);
    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned CONTROL_COPY_BITS = 32;
    localparam int unsigned DATA_CONTROL_COPIES = DATA_WIDTH / CONTROL_COPY_BITS;
    localparam int unsigned CONTROL_COPIES = DATA_CONTROL_COPIES + 1;

    logic [HBM_LANES-1:0] lane_valid_q;
    logic [HBM_LANES-1:0] lane_write_q;
    logic [HBM_LANES*PARTITION_BITS-1:0] lane_partition_q;
    logic [HBM_LANES*HBM_TAG_WIDTH-1:0] lane_tag_q;
    logic [HBM_LANES*LOCAL_TAG_WIDTH-1:0] lane_local_tag;
    logic [HBM_LANES*DATA_WIDTH-1:0] lane_read_data_q;
    logic [HBM_LANES*2-1:0] lane_status_q;
    logic [HBM_LANES*HBM_LANES-1:0] lane_older_q;

    logic [HBM_LANES-1:0] lane_protocol_error;
    logic [HBM_LANES-1:0] route_lane;
    logic [HBM_LANES*HBM_LANES-1:0] older_same_channel;
    logic [HBM_LANES-1:0] lane_has_older;
    logic [HBM_LANES*CHANNELS-1:0] lane_channel_match;
    logic [CHANNELS-1:0] channel_available;
    logic [HBM_LANES-1:0] lane_destination_available;
    logic [CHANNELS*HBM_LANES-1:0] channel_lane_select;
    logic [HBM_LANES-1:0] lane_accept;
    logic [HBM_LANES-1:0] lane_survives;
    logic [HBM_LANES-1:0] accepted_handshake;
    logic [HBM_LANES*CONTROL_COPIES-1:0] accepted_control_copy;
    logic [CHANNELS-1:0] delivered_handshake;
    logic [2*2-1:0] accepted_pair;
    logic [2*2-1:0] dropped_pair;
    logic [2:0] accepted_increment;
    logic [2:0] dropped_increment;
    logic [2:0] accepted_increment_q;
    logic [2:0] dropped_increment_q;
    logic [8*2-1:0] delivered_pair;
    logic [4*3-1:0] delivered_quad;
    logic [2*4-1:0] delivered_oct;
    logic [4:0] delivered_increment;
    logic [4:0] delivered_increment_q;
    logic backpressure_increment;
    logic backpressure_increment_q;

    always_comb begin
        integer lane_index;

        lane_protocol_error = '0;
        for (lane_index = 0; lane_index < HBM_LANES; lane_index = lane_index + 1) begin
            if (lane_valid_q[lane_index] &&
                ((lane_partition_q[lane_index*PARTITION_BITS +: PARTITION_BITS] !=
                  PARTITION_ID[PARTITION_BITS-1:0]))) begin
                lane_protocol_error[lane_index] = 1'b1;
            end
        end
    end

    generate
        for (genvar channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin : g_channel_decode
            assign channel_available[channel_index] =
                !channel_response_valid_o[channel_index] ||
                channel_response_ready_i[channel_index];
            for (genvar lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin : g_lane_match
                assign lane_channel_match[lane_index*CHANNELS + channel_index] =
                    lane_tag_q[
                        lane_index*HBM_TAG_WIDTH + LOCAL_TAG_WIDTH +:
                        CHANNEL_INDEX_WIDTH] == CHANNEL_INDEX_WIDTH'(channel_index);
            end
        end

        for (genvar lane_index = 0; lane_index < HBM_LANES;
             lane_index = lane_index + 1) begin : g_lane_route
            assign lane_local_tag[
                lane_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                lane_tag_q[lane_index*HBM_TAG_WIDTH +: LOCAL_TAG_WIDTH];
            for (genvar other_lane_index = 0; other_lane_index < HBM_LANES;
                 other_lane_index = other_lane_index + 1) begin : g_older
                assign older_same_channel[lane_index*HBM_LANES + other_lane_index] =
                    lane_valid_q[other_lane_index] &&
                    !lane_protocol_error[other_lane_index] &&
                    lane_older_q[other_lane_index*HBM_LANES + lane_index] &&
                    (lane_tag_q[
                        other_lane_index*HBM_TAG_WIDTH + LOCAL_TAG_WIDTH +:
                        CHANNEL_INDEX_WIDTH] == lane_tag_q[
                            lane_index*HBM_TAG_WIDTH + LOCAL_TAG_WIDTH +:
                            CHANNEL_INDEX_WIDTH]);
            end
            assign lane_has_older[lane_index] =
                |older_same_channel[lane_index*HBM_LANES +: HBM_LANES];
            assign lane_destination_available[lane_index] =
                |(lane_channel_match[lane_index*CHANNELS +: CHANNELS] &
                  channel_available);
            assign route_lane[lane_index] = lane_valid_q[lane_index] &&
                !lane_protocol_error[lane_index] &&
                !lane_has_older[lane_index] &&
                lane_destination_available[lane_index];
        end
    endgenerate

    assign accepted_handshake = hbm_response_valid_i & hbm_response_ready_o;
    generate
        for (genvar copy_index = 0; copy_index < CONTROL_COPIES;
             copy_index = copy_index + 1) begin : g_accept_control_copy
            for (genvar lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin : g_lane
                npu_dma_hbm_control_buffer u_control_buffer (
                    .data_i(accepted_handshake[lane_index]),
                    .data_o(accepted_control_copy[
                        lane_index*CONTROL_COPIES + copy_index])
                );
            end
        end
    endgenerate
    assign accepted_pair[0 +: 2] = {1'b0, accepted_handshake[0]} +
                                   {1'b0, accepted_handshake[1]};
    assign accepted_pair[2 +: 2] = {1'b0, accepted_handshake[2]} +
                                   {1'b0, accepted_handshake[3]};
    assign accepted_increment = {1'b0, accepted_pair[0 +: 2]} +
                                {1'b0, accepted_pair[2 +: 2]} +
                                {{2{1'b0}}, accepted_handshake[4]};

    assign dropped_pair[0 +: 2] = {1'b0, lane_protocol_error[0]} +
                                  {1'b0, lane_protocol_error[1]};
    assign dropped_pair[2 +: 2] = {1'b0, lane_protocol_error[2]} +
                                  {1'b0, lane_protocol_error[3]};
    assign dropped_increment = {1'b0, dropped_pair[0 +: 2]} +
                               {1'b0, dropped_pair[2 +: 2]} +
                               {{2{1'b0}}, lane_protocol_error[4]};

    assign delivered_handshake = channel_response_valid_o &
                                  channel_response_ready_i;
    generate
        for (genvar pair_index = 0; pair_index < 8;
             pair_index = pair_index + 1) begin : g_delivered_pair
            assign delivered_pair[pair_index*2 +: 2] =
                {1'b0, delivered_handshake[pair_index*2]} +
                {1'b0, delivered_handshake[pair_index*2+1]};
        end
        for (genvar quad_index = 0; quad_index < 4;
             quad_index = quad_index + 1) begin : g_delivered_quad
            assign delivered_quad[quad_index*3 +: 3] =
                {1'b0, delivered_pair[quad_index*4 +: 2]} +
                {1'b0, delivered_pair[quad_index*4+2 +: 2]};
        end
        for (genvar oct_index = 0; oct_index < 2;
             oct_index = oct_index + 1) begin : g_delivered_oct
            assign delivered_oct[oct_index*4 +: 4] =
                {1'b0, delivered_quad[oct_index*6 +: 3]} +
                {1'b0, delivered_quad[oct_index*6+3 +: 3]};
        end
    endgenerate
    assign delivered_increment = {1'b0, delivered_oct[0 +: 4]} +
                                 {1'b0, delivered_oct[4 +: 4]};
    assign backpressure_increment =
        |(hbm_response_valid_i & ~hbm_response_ready_o) ||
        |(channel_response_valid_o & ~channel_response_ready_i);

    always_comb begin
        integer lane_index;

        hbm_response_ready_o = '0;
        lane_accept = '0;
        lane_survives = lane_valid_q & ~route_lane & ~lane_protocol_error;

        for (lane_index = 0; lane_index < HBM_LANES; lane_index = lane_index + 1) begin
            hbm_response_ready_o[lane_index] =
                !lane_valid_q[lane_index] || route_lane[lane_index] ||
                lane_protocol_error[lane_index];
            if (hbm_response_valid_i[lane_index] &&
                hbm_response_ready_o[lane_index]) begin
                lane_accept[lane_index] = 1'b1;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            lane_valid_q <= '0;
            lane_older_q <= '0;
            protocol_error_o <= 1'b0;
            accepted_increment_q <= '0;
            delivered_increment_q <= '0;
            dropped_increment_q <= '0;
            backpressure_increment_q <= 1'b0;
            accepted_responses_o <= 64'd0;
            delivered_responses_o <= 64'd0;
            dropped_responses_o <= 64'd0;
            backpressure_cycles_o <= 64'd0;
        end else begin
            accepted_increment_q <= accepted_increment;
            delivered_increment_q <= delivered_increment;
            dropped_increment_q <= dropped_increment;
            backpressure_increment_q <= backpressure_increment;
            accepted_responses_o <= accepted_responses_o +
                {{61{1'b0}}, accepted_increment_q};
            delivered_responses_o <= delivered_responses_o +
                {{59{1'b0}}, delivered_increment_q};
            dropped_responses_o <= dropped_responses_o +
                {{61{1'b0}}, dropped_increment_q};
            if (|lane_protocol_error) begin
                protocol_error_o <= 1'b1;
            end
            backpressure_cycles_o <= backpressure_cycles_o +
                {{63{1'b0}}, backpressure_increment_q};

            for (int lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin
                if (hbm_response_valid_i[lane_index] &&
                    hbm_response_ready_o[lane_index]) begin
                    lane_valid_q[lane_index] <= 1'b1;
                end else if (route_lane[lane_index] ||
                             lane_protocol_error[lane_index]) begin
                    lane_valid_q[lane_index] <= 1'b0;
                end

                if (accepted_control_copy[
                        lane_index*CONTROL_COPIES + DATA_CONTROL_COPIES]) begin
                    lane_write_q[lane_index] <= hbm_response_write_i[lane_index];
                    lane_partition_q[lane_index*PARTITION_BITS +: PARTITION_BITS] <=
                        hbm_response_partition_i[
                            lane_index*PARTITION_BITS +: PARTITION_BITS];
                    lane_tag_q[lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH] <=
                        hbm_response_tag_i[lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH];
                    lane_status_q[lane_index*2 +: 2] <=
                        hbm_response_status_i[lane_index*2 +: 2];
                end
                for (int copy_index = 0; copy_index < DATA_CONTROL_COPIES;
                     copy_index = copy_index + 1) begin
                    if (accepted_control_copy[
                            lane_index*CONTROL_COPIES + copy_index]) begin
                        lane_read_data_q[
                            lane_index*DATA_WIDTH +
                            copy_index*CONTROL_COPY_BITS +: CONTROL_COPY_BITS] <=
                            hbm_response_read_data_i[
                                lane_index*DATA_WIDTH +
                                copy_index*CONTROL_COPY_BITS +: CONTROL_COPY_BITS];
                    end
                end
            end

            for (int first_lane_index = 0; first_lane_index < HBM_LANES;
                 first_lane_index = first_lane_index + 1) begin
                for (int second_lane_index = 0; second_lane_index < HBM_LANES;
                     second_lane_index = second_lane_index + 1) begin
                    if (first_lane_index == second_lane_index) begin
                        lane_older_q[first_lane_index*HBM_LANES +
                                     second_lane_index] <= 1'b0;
                    end else if (lane_accept[first_lane_index] &&
                                 lane_accept[second_lane_index]) begin
                        lane_older_q[first_lane_index*HBM_LANES +
                                     second_lane_index] <=
                            (first_lane_index < second_lane_index);
                    end else if (lane_survives[first_lane_index] &&
                                 lane_accept[second_lane_index]) begin
                        lane_older_q[first_lane_index*HBM_LANES +
                                     second_lane_index] <= 1'b1;
                    end else if (lane_accept[first_lane_index] &&
                                 lane_survives[second_lane_index]) begin
                        lane_older_q[first_lane_index*HBM_LANES +
                                     second_lane_index] <= 1'b0;
                    end else if (!lane_survives[first_lane_index] ||
                                 !lane_survives[second_lane_index]) begin
                        lane_older_q[first_lane_index*HBM_LANES +
                                     second_lane_index] <= 1'b0;
                    end
                end
            end
        end
    end

    generate
        for (genvar channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin : g_response_channel
            for (genvar lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin : g_lane_select
                assign channel_lane_select[channel_index*HBM_LANES + lane_index] =
                    route_lane[lane_index] &&
                    lane_channel_match[lane_index*CHANNELS + channel_index];
            end

            npu_dma_hbm_response_channel #(
                .HBM_LANES(HBM_LANES),
                .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
                .DATA_BYTES(DATA_BYTES)
            ) u_response_channel (
                .clk_i,
                .rst_i,
                .lane_select_i(channel_lane_select[
                    channel_index*HBM_LANES +: HBM_LANES]),
                .lane_write_i(lane_write_q),
                .lane_local_tag_i(lane_local_tag),
                .lane_read_data_i(lane_read_data_q),
                .lane_status_i(lane_status_q),
                .response_valid_o(channel_response_valid_o[channel_index]),
                .response_ready_i(channel_response_ready_i[channel_index]),
                .response_write_o(channel_response_write_o[channel_index]),
                .response_local_tag_o(channel_response_local_tag_o[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]),
                .response_read_data_o(channel_response_read_data_o[
                    channel_index*DATA_WIDTH +: DATA_WIDTH]),
                .response_status_o(channel_response_status_o[
                    channel_index*2 +: 2])
            );
        end
    endgenerate

    always_comb begin
        busy_o = (|lane_valid_q) || (|channel_response_valid_o);
    end

    initial begin
        if ((CHANNELS != 16) || (HBM_LANES != 5) ||
            (CHANNELS != (1 << CHANNEL_INDEX_WIDTH))) begin
            $error("NPU DMA HBM response channel/lane geometry is invalid");
        end
        if ((PARTITION_BITS < 1) || (PARTITION_ID >= (1 << PARTITION_BITS)) ||
            (LOCAL_TAG_WIDTH < 1) || (DATA_BYTES != 128)) begin
            $error("NPU DMA HBM response parameters violate the v0.1 contract");
        end
        if (HBM_TAG_WIDTH != CHANNEL_INDEX_WIDTH + LOCAL_TAG_WIDTH) begin
            $error("NPU DMA HBM response tag width is invalid");
        end
    end
endmodule

`default_nettype wire
