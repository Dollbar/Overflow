`timescale 1ns/1ps
`default_nettype none

module npu_dma_hbm_tag_tracker #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned TAGS_PER_CHANNEL = 1 << LOCAL_TAG_WIDTH,
    parameter int unsigned TOTAL_TAGS = CHANNELS * TAGS_PER_CHANNEL,
    parameter int unsigned COUNT_WIDTH = $clog2(TOTAL_TAGS + 1)
) (
    input  logic clk_i,
    input  logic rst_i,

    input  logic [CHANNELS-1:0] allocation_commit_i,
    input  logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] allocation_local_tag_i,
    output logic [CHANNELS-1:0] allocation_permitted_o,

    input  logic [CHANNELS-1:0] retirement_commit_i,
    input  logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] retirement_local_tag_i,
    output logic [CHANNELS-1:0] retirement_known_o,

    output logic [CHANNELS-1:0] duplicate_allocation_o,
    output logic [CHANNELS-1:0] unknown_retirement_o,
    output logic protocol_error_o,
    output logic empty_o,
    output logic full_o,
    output logic [COUNT_WIDTH-1:0] outstanding_count_o
);
    localparam int unsigned STATE_CONTROL_GROUP_BITS = 32;
    localparam int unsigned STATE_CONTROL_COPIES =
        TAGS_PER_CHANNEL / STATE_CONTROL_GROUP_BITS;

    logic [TOTAL_TAGS-1:0] outstanding_q;
    logic [CHANNELS-1:0] allocation_accepted;
    logic [CHANNELS-1:0] retirement_accepted;
    logic [CHANNELS-1:0] allocation_accepted_q;
    logic [CHANNELS-1:0] retirement_accepted_q;
    logic [CHANNELS*STATE_CONTROL_COPIES-1:0] allocation_control_copy;
    logic [CHANNELS*STATE_CONTROL_COPIES-1:0] retirement_control_copy;
    logic [TOTAL_TAGS-1:0] allocation_onehot;
    logic [TOTAL_TAGS-1:0] retirement_onehot;
    logic [4:0] allocation_increment;
    logic [4:0] retirement_increment;
    logic [4:0] allocation_increment_q;
    logic [4:0] retirement_increment_q;
    logic [CHANNELS-1:0] protocol_error_event_q;

    generate
        for (genvar channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin : g_channel
            logic [15:0] allocation_low_decode;
            logic [15:0] allocation_high_decode;
            logic [15:0] retirement_low_decode;
            logic [15:0] retirement_high_decode;
            logic [15:0] allocation_low_decode_buffered;
            logic [15:0] allocation_high_decode_buffered;
            logic [15:0] retirement_low_decode_buffered;
            logic [15:0] retirement_high_decode_buffered;

            for (genvar nibble_value = 0; nibble_value < 16;
                 nibble_value = nibble_value + 1) begin : g_nibble_decode
                assign allocation_low_decode[nibble_value] =
                    allocation_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: 4] == 4'(nibble_value);
                assign allocation_high_decode[nibble_value] =
                    allocation_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH + 4 +: 4] ==
                    4'(nibble_value);
                assign retirement_low_decode[nibble_value] =
                    retirement_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: 4] == 4'(nibble_value);
                assign retirement_high_decode[nibble_value] =
                    retirement_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH + 4 +: 4] ==
                    4'(nibble_value);
                npu_dma_hbm_control_buffer u_allocation_low_buffer (
                    .data_i(allocation_low_decode[nibble_value]),
                    .data_o(allocation_low_decode_buffered[nibble_value])
                );
                npu_dma_hbm_control_buffer u_allocation_high_buffer (
                    .data_i(allocation_high_decode[nibble_value]),
                    .data_o(allocation_high_decode_buffered[nibble_value])
                );
                npu_dma_hbm_control_buffer u_retirement_low_buffer (
                    .data_i(retirement_low_decode[nibble_value]),
                    .data_o(retirement_low_decode_buffered[nibble_value])
                );
                npu_dma_hbm_control_buffer u_retirement_high_buffer (
                    .data_i(retirement_high_decode[nibble_value]),
                    .data_o(retirement_high_decode_buffered[nibble_value])
                );
            end

            for (genvar tag_index = 0; tag_index < TAGS_PER_CHANNEL;
                 tag_index = tag_index + 1) begin : g_tag_decode
                assign allocation_onehot[
                    channel_index*TAGS_PER_CHANNEL + tag_index] =
                    allocation_high_decode_buffered[tag_index/16] &&
                    allocation_low_decode_buffered[tag_index%16];
                assign retirement_onehot[
                    channel_index*TAGS_PER_CHANNEL + tag_index] =
                    retirement_high_decode_buffered[tag_index/16] &&
                    retirement_low_decode_buffered[tag_index%16];
            end

            assign retirement_known_o[channel_index] =
                |(outstanding_q[
                      channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL] &
                  retirement_onehot[
                      channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL]);
            assign retirement_accepted[channel_index] =
                retirement_commit_i[channel_index] &&
                retirement_known_o[channel_index];
            assign allocation_permitted_o[channel_index] =
                !(|(outstanding_q[
                        channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL] &
                    allocation_onehot[
                        channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL])) ||
                (retirement_accepted[channel_index] &&
                 (retirement_local_tag_i[
                      channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] ==
                  allocation_local_tag_i[
                      channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]));
            assign allocation_accepted[channel_index] =
                allocation_commit_i[channel_index] &&
                allocation_permitted_o[channel_index];
            assign duplicate_allocation_o[channel_index] =
                allocation_commit_i[channel_index] &&
                !allocation_permitted_o[channel_index];
            assign unknown_retirement_o[channel_index] =
                retirement_commit_i[channel_index] &&
                !retirement_known_o[channel_index];

            for (genvar control_copy_index = 0;
                 control_copy_index < STATE_CONTROL_COPIES;
                 control_copy_index = control_copy_index + 1) begin : g_state_control
                npu_dma_hbm_control_buffer u_allocation_control_buffer (
                    .data_i(allocation_accepted[channel_index]),
                    .data_o(allocation_control_copy[
                        channel_index*STATE_CONTROL_COPIES + control_copy_index])
                );

                npu_dma_hbm_control_buffer u_retirement_control_buffer (
                    .data_i(retirement_accepted[channel_index]),
                    .data_o(retirement_control_copy[
                        channel_index*STATE_CONTROL_COPIES + control_copy_index])
                );

                always_ff @(posedge clk_i) begin
                    if (rst_i) begin
                        outstanding_q[
                            channel_index*TAGS_PER_CHANNEL +
                            control_copy_index*STATE_CONTROL_GROUP_BITS +:
                            STATE_CONTROL_GROUP_BITS] <= '0;
                    end else begin
                        outstanding_q[
                            channel_index*TAGS_PER_CHANNEL +
                            control_copy_index*STATE_CONTROL_GROUP_BITS +:
                            STATE_CONTROL_GROUP_BITS] <=
                            (outstanding_q[
                                 channel_index*TAGS_PER_CHANNEL +
                                 control_copy_index*STATE_CONTROL_GROUP_BITS +:
                                 STATE_CONTROL_GROUP_BITS] &
                             ~(retirement_onehot[
                                   channel_index*TAGS_PER_CHANNEL +
                                   control_copy_index*STATE_CONTROL_GROUP_BITS +:
                                   STATE_CONTROL_GROUP_BITS] &
                               {STATE_CONTROL_GROUP_BITS{
                                   retirement_control_copy[
                                       channel_index*STATE_CONTROL_COPIES +
                                       control_copy_index]}})) |
                            (allocation_onehot[
                                 channel_index*TAGS_PER_CHANNEL +
                                 control_copy_index*STATE_CONTROL_GROUP_BITS +:
                                 STATE_CONTROL_GROUP_BITS] &
                             {STATE_CONTROL_GROUP_BITS{
                                 allocation_control_copy[
                                     channel_index*STATE_CONTROL_COPIES +
                                     control_copy_index]}});
                    end
                end
            end
        end
    endgenerate

    npu_dma_hbm_rank_count16 u_allocation_count (
        .bits_i(allocation_accepted_q),
        .count_o(allocation_increment)
    );

    npu_dma_hbm_rank_count16 u_retirement_count (
        .bits_i(retirement_accepted_q),
        .count_o(retirement_increment)
    );

    assign empty_o = ~(|outstanding_q);
    assign full_o = &outstanding_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            allocation_accepted_q <= '0;
            retirement_accepted_q <= '0;
            allocation_increment_q <= '0;
            retirement_increment_q <= '0;
            protocol_error_event_q <= '0;
            outstanding_count_o <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            allocation_accepted_q <= allocation_accepted;
            retirement_accepted_q <= retirement_accepted;
            allocation_increment_q <= allocation_increment;
            retirement_increment_q <= retirement_increment;
            protocol_error_event_q <= duplicate_allocation_o |
                unknown_retirement_o;
            outstanding_count_o <= outstanding_count_o +
                COUNT_WIDTH'(allocation_increment_q) -
                COUNT_WIDTH'(retirement_increment_q);
            if (|protocol_error_event_q) begin
                protocol_error_o <= 1'b1;
            end
        end
    end

    initial begin
        if ((CHANNELS != 16) || (LOCAL_TAG_WIDTH != 8) ||
            (TAGS_PER_CHANNEL != 256) || (TOTAL_TAGS != 4096) ||
            (COUNT_WIDTH != 13) ||
            ((TAGS_PER_CHANNEL % STATE_CONTROL_GROUP_BITS) != 0)) begin
            $error("NPU DMA HBM tracker geometry violates the v0.1 tag contract");
        end
    end
endmodule

`default_nettype wire
