`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "true" *)
module npu_dma_hbm_egress #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned HBM_LANES = 5,
    parameter int unsigned PARTITION_BITS = 3,
    parameter int unsigned PARTITION_ID = 0,
    parameter int unsigned ADDRESS_WIDTH = 35,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned AGE_PROMOTION_CYCLES = 256,
    parameter int unsigned CHANNEL_INDEX_WIDTH =
        (CHANNELS <= 1) ? 1 : $clog2(CHANNELS),
    parameter int unsigned HBM_TAG_WIDTH =
        CHANNEL_INDEX_WIDTH + LOCAL_TAG_WIDTH
) (
    input  logic clk_i,
    input  logic rst_i,

    input  logic [CHANNELS-1:0] request_valid_i,
    output logic [CHANNELS-1:0] request_ready_o,
    input  logic [CHANNELS-1:0] request_write_i,
    input  logic [CHANNELS*ADDRESS_WIDTH-1:0] request_address_i,
    input  logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] request_local_tag_i,
    input  logic [CHANNELS*DATA_BYTES*8-1:0] request_write_data_i,
    input  logic [CHANNELS*DATA_BYTES-1:0] request_byte_enable_i,
    input  logic [CHANNELS*2-1:0] request_qos_i,

    output logic [HBM_LANES-1:0] hbm_request_valid_o,
    input  logic [HBM_LANES-1:0] hbm_request_ready_i,
    output logic [HBM_LANES-1:0] hbm_request_write_o,
    output logic [HBM_LANES*PARTITION_BITS-1:0] hbm_request_partition_o,
    output logic [HBM_LANES*ADDRESS_WIDTH-1:0] hbm_request_address_o,
    output logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_request_tag_o,
    output logic [HBM_LANES*DATA_BYTES*8-1:0] hbm_request_write_data_o,
    output logic [HBM_LANES*DATA_BYTES-1:0] hbm_request_byte_enable_o,

    output logic busy_o,
    output logic [63:0] accepted_beats_o,
    output logic [63:0] issued_beats_o,
    output logic [63:0] backpressure_cycles_o
);
    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned AGE_PHASE_WIDTH =
        (AGE_PROMOTION_CYCLES <= 1) ? 1 : $clog2(AGE_PROMOTION_CYCLES);
    localparam int unsigned PAYLOAD_WRITE_LSB = 0;
    localparam int unsigned PAYLOAD_ADDRESS_LSB = PAYLOAD_WRITE_LSB + 1;
    localparam int unsigned PAYLOAD_TAG_LSB = PAYLOAD_ADDRESS_LSB + ADDRESS_WIDTH;
    localparam int unsigned PAYLOAD_DATA_LSB = PAYLOAD_TAG_LSB + HBM_TAG_WIDTH;
    localparam int unsigned PAYLOAD_ENABLE_LSB = PAYLOAD_DATA_LSB + DATA_WIDTH;
    localparam int unsigned PAYLOAD_WIDTH = PAYLOAD_ENABLE_LSB + DATA_BYTES;
    localparam int unsigned SELECT_FANOUT_BITS = 32;
    localparam int unsigned ARBITRATION_FANOUT_GROUP = 4;
    localparam int unsigned ARBITRATION_CONTROL_COPIES =
        CHANNELS / ARBITRATION_FANOUT_GROUP;

    logic [CHANNEL_INDEX_WIDTH-1:0] round_robin_q;
    logic [CHANNEL_INDEX_WIDTH-1:0] round_robin_d;
    logic [CHANNELS*AGE_PHASE_WIDTH-1:0] age_phase_q;
    logic [CHANNELS-1:0] request_seen_q;
    logic [CHANNELS*2-1:0] effective_priority_q;
    logic [CHANNELS*2-1:0] effective_priority;
    logic [ARBITRATION_CONTROL_COPIES*CHANNEL_INDEX_WIDTH-1:0]
        round_robin_channel_copy;
    logic [CHANNELS*CHANNEL_INDEX_WIDTH-1:0] rotation_distance;
    logic [CHANNELS*ARBITRATION_CONTROL_COPIES*CHANNEL_INDEX_WIDTH-1:0]
        rotation_distance_compare_copy;
    logic [CHANNELS*CHANNELS-1:0] outranking_channel;
    logic [CHANNELS*CHANNELS-1:0] outranking_channel_q;
    logic [CHANNELS*5-1:0] channel_rank_d;
    logic [CHANNELS*5-1:0] channel_rank_q;
    logic [CHANNELS-1:0] rank_valid_d;
    logic [CHANNELS-1:0] rank_candidate_valid_q;
    logic [CHANNELS-1:0] rank_valid_q;
    logic [CHANNELS-1:0] channel_dequeue;
    logic [HBM_LANES-1:0] slot_available;
    logic [HBM_LANES*3-1:0] lane_available_rank;
    logic [1:0] available_pair01;
    logic [1:0] available_pair23;
    logic [2:0] available_count;
    logic [HBM_LANES*CHANNELS-1:0] lane_channel_select;
    logic [HBM_LANES*CHANNELS-1:0] lane_channel_select_buffered;
    logic [CHANNELS-1:0] last_grant_channel;
    logic [CHANNELS-1:0] last_grant_channel_q;
    logic [CHANNEL_INDEX_WIDTH-1:0] last_selected_channel;
    logic any_grant;
    logic [CHANNELS*PAYLOAD_WIDTH-1:0] channel_payload;
    logic [HBM_LANES*PAYLOAD_WIDTH-1:0] slot_payload;
    logic [HBM_LANES-1:0] issued_handshake;
    logic [1:0] issued_pair01;
    logic [1:0] issued_pair23;
    logic [4:0] accepted_increment;
    logic [2:0] issued_increment;
    logic [CHANNELS-1:0] accepted_handshake_q;
    logic [4:0] accepted_increment_q;
    logic [2:0] issued_increment_q;
    logic backpressure_increment;
    logic backpressure_increment_q;
    logic [63:0] accepted_beats_next;
    logic [63:0] issued_beats_next;
    logic [63:0] backpressure_cycles_next;

    generate
        for (genvar channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin : g_channel_rank
            assign channel_dequeue[channel_index] =
                lane_channel_select_buffered[0*CHANNELS + channel_index] |
                lane_channel_select_buffered[1*CHANNELS + channel_index] |
                lane_channel_select_buffered[2*CHANNELS + channel_index] |
                lane_channel_select_buffered[3*CHANNELS + channel_index] |
                lane_channel_select_buffered[4*CHANNELS + channel_index];
            assign request_ready_o[channel_index] = channel_dequeue[channel_index];
            assign rank_valid_d[channel_index] =
                request_valid_i[channel_index] && request_seen_q[channel_index];
            assign effective_priority[channel_index*2 +: 2] =
                effective_priority_q[channel_index*2 +: 2];
            assign rotation_distance[
                channel_index*CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH] =
                CHANNEL_INDEX_WIDTH'(channel_index) -
                round_robin_channel_copy[
                    (channel_index/ARBITRATION_FANOUT_GROUP)*
                    CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH];

            if (channel_index < ARBITRATION_CONTROL_COPIES) begin : g_rr_copy
                for (genvar bit_index = 0; bit_index < CHANNEL_INDEX_WIDTH;
                     bit_index = bit_index + 1) begin : g_bit
                    npu_dma_hbm_control_buffer u_control_buffer (
                        .data_i(round_robin_q[bit_index]),
                        .data_o(round_robin_channel_copy[
                            channel_index*CHANNEL_INDEX_WIDTH + bit_index])
                    );
                end
            end

            for (genvar other_channel_index = 0;
                 other_channel_index < CHANNELS;
                 other_channel_index = other_channel_index + 1) begin : g_other
                if (other_channel_index < ARBITRATION_CONTROL_COPIES) begin : g_copy
                    for (genvar bit_index = 0; bit_index < CHANNEL_INDEX_WIDTH;
                         bit_index = bit_index + 1) begin : g_bit
                        npu_dma_hbm_control_buffer u_control_buffer (
                            .data_i(rotation_distance[
                                channel_index*CHANNEL_INDEX_WIDTH + bit_index]),
                            .data_o(rotation_distance_compare_copy[
                                (channel_index*ARBITRATION_CONTROL_COPIES +
                                 other_channel_index)*CHANNEL_INDEX_WIDTH +
                                bit_index])
                        );
                    end
                end

                assign outranking_channel[
                    channel_index*CHANNELS + other_channel_index] =
                    rank_valid_d[other_channel_index] &&
                    ((effective_priority[other_channel_index*2 +: 2] >
                      effective_priority[channel_index*2 +: 2]) ||
                     ((effective_priority[other_channel_index*2 +: 2] ==
                      effective_priority[channel_index*2 +: 2]) &&
                      (rotation_distance_compare_copy[
                          (other_channel_index*ARBITRATION_CONTROL_COPIES +
                           channel_index/ARBITRATION_FANOUT_GROUP)*
                          CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH] <
                       rotation_distance_compare_copy[
                          (channel_index*ARBITRATION_CONTROL_COPIES +
                           other_channel_index/ARBITRATION_FANOUT_GROUP)*
                          CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH])));
            end

            npu_dma_hbm_rank_count16 u_rank_count (
                .bits_i(outranking_channel_q[
                    channel_index*CHANNELS +: CHANNELS]),
                .count_o(channel_rank_d[channel_index*5 +: 5])
            );

            assign last_grant_channel[channel_index] =
                channel_dequeue[channel_index] && (available_count != 3'd0) &&
                (channel_rank_q[channel_index*5 +: 5] ==
                 {2'b00, (available_count - 3'd1)});
            assign channel_payload[
                channel_index*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] = {
                    request_byte_enable_i[channel_index*DATA_BYTES +: DATA_BYTES],
                    request_write_data_i[channel_index*DATA_WIDTH +: DATA_WIDTH],
                    CHANNEL_INDEX_WIDTH'(channel_index),
                    request_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH],
                    request_address_i[channel_index*ADDRESS_WIDTH +: ADDRESS_WIDTH],
                    request_write_i[channel_index]
                };
        end

        for (genvar lane_index = 0; lane_index < HBM_LANES;
             lane_index = lane_index + 1) begin : g_lane
            assign slot_available[lane_index] =
                !hbm_request_valid_o[lane_index] || hbm_request_ready_i[lane_index];
            for (genvar channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin : g_channel_select
                assign lane_channel_select[lane_index*CHANNELS + channel_index] =
                    slot_available[lane_index] &&
                    rank_valid_q[channel_index] &&
                    request_valid_i[channel_index] &&
                    (channel_rank_q[channel_index*5 +: 5] ==
                     {2'b00, lane_available_rank[lane_index*3 +: 3]});
                npu_dma_hbm_wide_control_buffer u_control_buffer (
                    .data_i(lane_channel_select[
                        lane_index*CHANNELS + channel_index]),
                    .data_o(lane_channel_select_buffered[
                        lane_index*CHANNELS + channel_index])
                );
            end
            npu_dma_hbm_request_slot #(
                .CHANNELS(CHANNELS),
                .PAYLOAD_WIDTH(PAYLOAD_WIDTH),
                .SELECT_FANOUT_BITS(SELECT_FANOUT_BITS)
            ) u_request_slot (
                .clk_i,
                .rst_i,
                .channel_select_i(lane_channel_select_buffered[
                    lane_index*CHANNELS +: CHANNELS]),
                .channel_payload_i(channel_payload),
                .slot_ready_i(hbm_request_ready_i[lane_index]),
                .slot_valid_o(hbm_request_valid_o[lane_index]),
                .slot_payload_o(slot_payload[
                    lane_index*PAYLOAD_WIDTH +: PAYLOAD_WIDTH])
            );

            assign hbm_request_write_o[lane_index] =
                slot_payload[lane_index*PAYLOAD_WIDTH + PAYLOAD_WRITE_LSB];
            assign hbm_request_address_o[
                lane_index*ADDRESS_WIDTH +: ADDRESS_WIDTH] =
                slot_payload[lane_index*PAYLOAD_WIDTH + PAYLOAD_ADDRESS_LSB +:
                             ADDRESS_WIDTH];
            assign hbm_request_tag_o[lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH] =
                slot_payload[lane_index*PAYLOAD_WIDTH + PAYLOAD_TAG_LSB +:
                             HBM_TAG_WIDTH];
            assign hbm_request_write_data_o[
                lane_index*DATA_WIDTH +: DATA_WIDTH] =
                slot_payload[lane_index*PAYLOAD_WIDTH + PAYLOAD_DATA_LSB +:
                             DATA_WIDTH];
            assign hbm_request_byte_enable_o[
                lane_index*DATA_BYTES +: DATA_BYTES] =
                slot_payload[lane_index*PAYLOAD_WIDTH + PAYLOAD_ENABLE_LSB +:
                             DATA_BYTES];
            assign hbm_request_partition_o[
                lane_index*PARTITION_BITS +: PARTITION_BITS] =
                PARTITION_ID[PARTITION_BITS-1:0];
        end
    endgenerate

    assign available_pair01 = {1'b0, slot_available[0]} +
                              {1'b0, slot_available[1]};
    assign available_pair23 = {1'b0, slot_available[2]} +
                              {1'b0, slot_available[3]};
    assign lane_available_rank[0*3 +: 3] = 3'd0;
    assign lane_available_rank[1*3 +: 3] = {2'b00, slot_available[0]};
    assign lane_available_rank[2*3 +: 3] = {1'b0, available_pair01};
    assign lane_available_rank[3*3 +: 3] =
        {1'b0, available_pair01} + {2'b00, slot_available[2]};
    assign lane_available_rank[4*3 +: 3] =
        {1'b0, available_pair01} + {1'b0, available_pair23};
    assign available_count = {1'b0, available_pair01} +
                             {1'b0, available_pair23} +
                             {2'b00, slot_available[4]};

    assign any_grant = |last_grant_channel_q;
    assign last_selected_channel[0] =
        |(last_grant_channel_q & 16'b1010_1010_1010_1010);
    assign last_selected_channel[1] =
        |(last_grant_channel_q & 16'b1100_1100_1100_1100);
    assign last_selected_channel[2] =
        |(last_grant_channel_q & 16'b1111_0000_1111_0000);
    assign last_selected_channel[3] =
        |(last_grant_channel_q & 16'b1111_1111_0000_0000);
    assign round_robin_d = any_grant ? last_selected_channel + 1'b1 :
                                      round_robin_q;

    assign issued_handshake = hbm_request_valid_o & hbm_request_ready_i;
    npu_dma_hbm_rank_count16 u_accepted_count (
        .bits_i(accepted_handshake_q),
        .count_o(accepted_increment)
    );
    assign issued_pair01 = {1'b0, issued_handshake[0]} +
                           {1'b0, issued_handshake[1]};
    assign issued_pair23 = {1'b0, issued_handshake[2]} +
                           {1'b0, issued_handshake[3]};
    assign issued_increment = {1'b0, issued_pair01} +
                              {1'b0, issued_pair23} +
                              {2'b00, issued_handshake[4]};
    assign backpressure_increment = |(request_valid_i & ~request_ready_o);
    assign busy_o = |hbm_request_valid_o;

    npu_dma_carry_select_adder #(
        .WIDTH(64),
        .BLOCK_WIDTH(10)
    ) u_accepted_beats_adder (
        .a_i(accepted_beats_o),
        .b_i({{59{1'b0}}, accepted_increment_q}),
        .cin_i(1'b0),
        .sum_o(accepted_beats_next)
    );
    npu_dma_carry_select_adder #(
        .WIDTH(64),
        .BLOCK_WIDTH(10)
    ) u_issued_beats_adder (
        .a_i(issued_beats_o),
        .b_i({{61{1'b0}}, issued_increment_q}),
        .cin_i(1'b0),
        .sum_o(issued_beats_next)
    );
    npu_dma_carry_select_adder #(
        .WIDTH(64),
        .BLOCK_WIDTH(10)
    ) u_backpressure_cycles_adder (
        .a_i(backpressure_cycles_o),
        .b_i({{63{1'b0}}, backpressure_increment_q}),
        .cin_i(1'b0),
        .sum_o(backpressure_cycles_next)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            round_robin_q <= '0;
            outranking_channel_q <= '0;
            channel_rank_q <= '0;
            rank_candidate_valid_q <= '0;
            rank_valid_q <= '0;
            last_grant_channel_q <= '0;
            accepted_handshake_q <= '0;
            accepted_increment_q <= '0;
            issued_increment_q <= '0;
            backpressure_increment_q <= 1'b0;
            accepted_beats_o <= 64'd0;
            issued_beats_o <= 64'd0;
            backpressure_cycles_o <= 64'd0;
            for (int channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                age_phase_q[
                    channel_index*AGE_PHASE_WIDTH +: AGE_PHASE_WIDTH] <= '0;
                request_seen_q[channel_index] <= 1'b0;
                effective_priority_q[channel_index*2 +: 2] <= 2'd0;
            end
        end else begin
            round_robin_q <= round_robin_d;
            outranking_channel_q <= outranking_channel;
            channel_rank_q <= channel_rank_d;
            rank_candidate_valid_q <= rank_valid_d;
            rank_valid_q <= rank_candidate_valid_q;
            last_grant_channel_q <= last_grant_channel;
            accepted_handshake_q <= request_ready_o;
            accepted_increment_q <= accepted_increment;
            issued_increment_q <= issued_increment;
            backpressure_increment_q <= backpressure_increment;
            accepted_beats_o <= accepted_beats_next;
            issued_beats_o <= issued_beats_next;
            backpressure_cycles_o <= backpressure_cycles_next;

            for (int channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (!request_valid_i[channel_index] ||
                    channel_dequeue[channel_index]) begin
                    age_phase_q[
                        channel_index*AGE_PHASE_WIDTH +: AGE_PHASE_WIDTH] <= '0;
                    request_seen_q[channel_index] <= 1'b0;
                    effective_priority_q[channel_index*2 +: 2] <= 2'd0;
                end else if (!request_seen_q[channel_index]) begin
                    age_phase_q[
                        channel_index*AGE_PHASE_WIDTH +: AGE_PHASE_WIDTH] <= '0;
                    request_seen_q[channel_index] <= 1'b1;
                    effective_priority_q[channel_index*2 +: 2] <=
                        request_qos_i[channel_index*2 +: 2];
                end else if (effective_priority_q[
                        channel_index*2 +: 2] != 2'd3) begin
                    if (age_phase_q[
                            channel_index*AGE_PHASE_WIDTH +: AGE_PHASE_WIDTH] ==
                        AGE_PHASE_WIDTH'(AGE_PROMOTION_CYCLES-1)) begin
                        age_phase_q[
                            channel_index*AGE_PHASE_WIDTH +: AGE_PHASE_WIDTH] <= '0;
                        effective_priority_q[channel_index*2 +: 2] <=
                            effective_priority_q[channel_index*2 +: 2] + 1'b1;
                    end else begin
                        age_phase_q[
                            channel_index*AGE_PHASE_WIDTH +: AGE_PHASE_WIDTH] <=
                            age_phase_q[
                                channel_index*AGE_PHASE_WIDTH +: AGE_PHASE_WIDTH] +
                            1'b1;
                    end
                end
            end
        end
    end

    initial begin
        if ((CHANNELS != 16) || (HBM_LANES != 5) ||
            (CHANNELS != (1 << CHANNEL_INDEX_WIDTH)) ||
            ((CHANNELS % ARBITRATION_FANOUT_GROUP) != 0)) begin
            $error("NPU DMA HBM channel/lane geometry is invalid");
        end
        if ((PARTITION_BITS < 1) || (PARTITION_ID >= (1 << PARTITION_BITS)) ||
            (ADDRESS_WIDTH < 7) || (LOCAL_TAG_WIDTH < 1) ||
            (DATA_BYTES != 128) || (AGE_PROMOTION_CYCLES < 1)) begin
            $error("NPU DMA HBM interface parameters violate the v0.1 contract");
        end
        if (HBM_TAG_WIDTH != CHANNEL_INDEX_WIDTH + LOCAL_TAG_WIDTH) begin
            $error("NPU DMA HBM tag width must contain channel and local tag fields");
        end
    end
endmodule

`default_nettype wire
