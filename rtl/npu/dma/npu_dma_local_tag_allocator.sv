`timescale 1ns/1ps
`default_nettype none

module npu_dma_local_tag_allocator #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned TAGS_PER_CHANNEL = 1 << LOCAL_TAG_WIDTH,
    parameter int unsigned TOTAL_TAGS = CHANNELS * TAGS_PER_CHANNEL
) (
    input  logic clk_i,
    input  logic rst_i,

    input  logic [CHANNELS-1:0] allocation_request_i,
    output logic [CHANNELS-1:0] allocation_available_o,
    output logic [CHANNELS-1:0] allocation_grant_o,
    output logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] allocation_local_tag_o,

    input  logic [CHANNELS-1:0] release_commit_i,
    input  logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] release_local_tag_i,
    output logic [CHANNELS-1:0] release_known_o,

    output logic [CHANNELS-1:0] allocation_failure_o,
    output logic [CHANNELS-1:0] unknown_release_o,
    output logic protocol_error_o
);
    localparam int unsigned PRIORITY_GROUPS = 16;
    localparam int unsigned TAGS_PER_PRIORITY_GROUP = 16;
    localparam int unsigned STATE_CONTROL_GROUP_BITS = 32;
    localparam int unsigned STATE_CONTROL_COPIES =
        TAGS_PER_CHANNEL / STATE_CONTROL_GROUP_BITS;

    logic [TOTAL_TAGS-1:0] free_q;
    logic [TOTAL_TAGS-1:0] release_onehot;
    logic [TOTAL_TAGS-1:0] allocation_candidate;
    logic [TOTAL_TAGS-1:0] allocation_selected_onehot;
    logic [CHANNELS*PRIORITY_GROUPS-1:0] priority_group_nonempty;
    logic [CHANNELS*PRIORITY_GROUPS-1:0] priority_group_selected;
    logic [CHANNELS*4*PRIORITY_GROUPS-1:0] low_tag_bit_partial;
    logic [CHANNELS*STATE_CONTROL_COPIES-1:0] allocation_control_copy;
    logic [CHANNELS*STATE_CONTROL_COPIES-1:0] release_control_copy;
    logic [CHANNELS-1:0] protocol_error_event_q;

    generate
        for (genvar channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin : g_channel
            logic [15:0] release_low_decode;
            logic [15:0] release_high_decode;

            for (genvar nibble_value = 0; nibble_value < 16;
                 nibble_value = nibble_value + 1) begin : g_release_decode
                assign release_low_decode[nibble_value] =
                    release_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: 4] == 4'(nibble_value);
                assign release_high_decode[nibble_value] =
                    release_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH + 4 +: 4] ==
                    4'(nibble_value);
            end

            for (genvar tag_index = 0; tag_index < TAGS_PER_CHANNEL;
                 tag_index = tag_index + 1) begin : g_release_onehot
                assign release_onehot[
                    channel_index*TAGS_PER_CHANNEL + tag_index] =
                    release_high_decode[tag_index/16] &&
                    release_low_decode[tag_index%16];
            end

            assign release_known_o[channel_index] =
                |((~free_q[
                       channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL]) &
                  release_onehot[
                       channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL]);
            assign unknown_release_o[channel_index] =
                release_commit_i[channel_index] &&
                !release_known_o[channel_index];

            assign allocation_candidate[
                channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL] =
                free_q[channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL];

            for (genvar group_index = 0; group_index < PRIORITY_GROUPS;
                 group_index = group_index + 1) begin : g_priority_group
                assign priority_group_nonempty[
                    channel_index*PRIORITY_GROUPS + group_index] =
                    |allocation_candidate[
                        channel_index*TAGS_PER_CHANNEL +
                        group_index*TAGS_PER_PRIORITY_GROUP +:
                        TAGS_PER_PRIORITY_GROUP];

                if (group_index == 0) begin : g_first_group
                    assign priority_group_selected[
                        channel_index*PRIORITY_GROUPS + group_index] =
                        priority_group_nonempty[
                            channel_index*PRIORITY_GROUPS + group_index];
                end else begin : g_later_group
                    assign priority_group_selected[
                        channel_index*PRIORITY_GROUPS + group_index] =
                        priority_group_nonempty[
                            channel_index*PRIORITY_GROUPS + group_index] &&
                        !(|priority_group_nonempty[
                            channel_index*PRIORITY_GROUPS +: group_index]);
                end

                for (genvar group_tag_index = 0;
                     group_tag_index < TAGS_PER_PRIORITY_GROUP;
                     group_tag_index = group_tag_index + 1) begin : g_group_tag
                    if (group_tag_index == 0) begin : g_first_tag
                        assign allocation_selected_onehot[
                            channel_index*TAGS_PER_CHANNEL +
                            group_index*TAGS_PER_PRIORITY_GROUP +
                            group_tag_index] =
                            priority_group_selected[
                                channel_index*PRIORITY_GROUPS + group_index] &&
                            allocation_candidate[
                                channel_index*TAGS_PER_CHANNEL +
                                group_index*TAGS_PER_PRIORITY_GROUP +
                                group_tag_index];
                    end else begin : g_later_tag
                        assign allocation_selected_onehot[
                            channel_index*TAGS_PER_CHANNEL +
                            group_index*TAGS_PER_PRIORITY_GROUP +
                            group_tag_index] =
                            priority_group_selected[
                                channel_index*PRIORITY_GROUPS + group_index] &&
                            allocation_candidate[
                                channel_index*TAGS_PER_CHANNEL +
                                group_index*TAGS_PER_PRIORITY_GROUP +
                                group_tag_index] &&
                            !(|allocation_candidate[
                                channel_index*TAGS_PER_CHANNEL +
                                group_index*TAGS_PER_PRIORITY_GROUP +:
                                group_tag_index]);
                    end
                end

                assign low_tag_bit_partial[
                    (channel_index*4 + 0)*PRIORITY_GROUPS + group_index] =
                    |(allocation_selected_onehot[
                          channel_index*TAGS_PER_CHANNEL +
                          group_index*TAGS_PER_PRIORITY_GROUP +:
                          TAGS_PER_PRIORITY_GROUP] & 16'haaaa);
                assign low_tag_bit_partial[
                    (channel_index*4 + 1)*PRIORITY_GROUPS + group_index] =
                    |(allocation_selected_onehot[
                          channel_index*TAGS_PER_CHANNEL +
                          group_index*TAGS_PER_PRIORITY_GROUP +:
                          TAGS_PER_PRIORITY_GROUP] & 16'hcccc);
                assign low_tag_bit_partial[
                    (channel_index*4 + 2)*PRIORITY_GROUPS + group_index] =
                    |(allocation_selected_onehot[
                          channel_index*TAGS_PER_CHANNEL +
                          group_index*TAGS_PER_PRIORITY_GROUP +:
                          TAGS_PER_PRIORITY_GROUP] & 16'hf0f0);
                assign low_tag_bit_partial[
                    (channel_index*4 + 3)*PRIORITY_GROUPS + group_index] =
                    |(allocation_selected_onehot[
                          channel_index*TAGS_PER_CHANNEL +
                          group_index*TAGS_PER_PRIORITY_GROUP +:
                          TAGS_PER_PRIORITY_GROUP] & 16'hff00);
            end

            assign allocation_available_o[channel_index] =
                |priority_group_nonempty[
                    channel_index*PRIORITY_GROUPS +: PRIORITY_GROUPS];
            assign allocation_grant_o[channel_index] =
                allocation_request_i[channel_index] &&
                allocation_available_o[channel_index];
            assign allocation_failure_o[channel_index] =
                allocation_request_i[channel_index] &&
                !allocation_available_o[channel_index];

            assign allocation_local_tag_o[
                channel_index*LOCAL_TAG_WIDTH + 0] =
                |low_tag_bit_partial[
                    (channel_index*4 + 0)*PRIORITY_GROUPS +: PRIORITY_GROUPS];
            assign allocation_local_tag_o[
                channel_index*LOCAL_TAG_WIDTH + 1] =
                |low_tag_bit_partial[
                    (channel_index*4 + 1)*PRIORITY_GROUPS +: PRIORITY_GROUPS];
            assign allocation_local_tag_o[
                channel_index*LOCAL_TAG_WIDTH + 2] =
                |low_tag_bit_partial[
                    (channel_index*4 + 2)*PRIORITY_GROUPS +: PRIORITY_GROUPS];
            assign allocation_local_tag_o[
                channel_index*LOCAL_TAG_WIDTH + 3] =
                |low_tag_bit_partial[
                    (channel_index*4 + 3)*PRIORITY_GROUPS +: PRIORITY_GROUPS];
            assign allocation_local_tag_o[
                channel_index*LOCAL_TAG_WIDTH + 4] =
                |(priority_group_selected[
                       channel_index*PRIORITY_GROUPS +: PRIORITY_GROUPS] &
                  16'haaaa);
            assign allocation_local_tag_o[
                channel_index*LOCAL_TAG_WIDTH + 5] =
                |(priority_group_selected[
                       channel_index*PRIORITY_GROUPS +: PRIORITY_GROUPS] &
                  16'hcccc);
            assign allocation_local_tag_o[
                channel_index*LOCAL_TAG_WIDTH + 6] =
                |(priority_group_selected[
                       channel_index*PRIORITY_GROUPS +: PRIORITY_GROUPS] &
                  16'hf0f0);
            assign allocation_local_tag_o[
                channel_index*LOCAL_TAG_WIDTH + 7] =
                |(priority_group_selected[
                       channel_index*PRIORITY_GROUPS +: PRIORITY_GROUPS] &
                  16'hff00);

            for (genvar control_copy_index = 0;
                 control_copy_index < STATE_CONTROL_COPIES;
                 control_copy_index = control_copy_index + 1) begin : g_state_control
                npu_dma_hbm_control_buffer u_allocation_control_buffer (
                    .data_i(allocation_grant_o[channel_index]),
                    .data_o(allocation_control_copy[
                        channel_index*STATE_CONTROL_COPIES + control_copy_index])
                );

                npu_dma_hbm_control_buffer u_release_control_buffer (
                    .data_i(release_commit_i[channel_index] &&
                            release_known_o[channel_index]),
                    .data_o(release_control_copy[
                        channel_index*STATE_CONTROL_COPIES + control_copy_index])
                );

                always_ff @(posedge clk_i) begin
                    if (rst_i) begin
                        free_q[
                            channel_index*TAGS_PER_CHANNEL +
                            control_copy_index*STATE_CONTROL_GROUP_BITS +:
                            STATE_CONTROL_GROUP_BITS] <= '1;
                    end else begin
                        free_q[
                            channel_index*TAGS_PER_CHANNEL +
                            control_copy_index*STATE_CONTROL_GROUP_BITS +:
                            STATE_CONTROL_GROUP_BITS] <=
                            (free_q[
                                 channel_index*TAGS_PER_CHANNEL +
                                 control_copy_index*STATE_CONTROL_GROUP_BITS +:
                                 STATE_CONTROL_GROUP_BITS] |
                             (release_onehot[
                                  channel_index*TAGS_PER_CHANNEL +
                                  control_copy_index*STATE_CONTROL_GROUP_BITS +:
                                  STATE_CONTROL_GROUP_BITS] &
                              {STATE_CONTROL_GROUP_BITS{
                                  release_control_copy[
                                      channel_index*STATE_CONTROL_COPIES +
                                      control_copy_index]}})) &
                            ~(allocation_selected_onehot[
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

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            protocol_error_event_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            protocol_error_event_q <= allocation_failure_o | unknown_release_o;
            if (|protocol_error_event_q) begin
                protocol_error_o <= 1'b1;
            end
        end
    end

    initial begin
        if ((CHANNELS != 16) || (LOCAL_TAG_WIDTH != 8) ||
            (TAGS_PER_CHANNEL != 256) || (TOTAL_TAGS != 4096) ||
            (PRIORITY_GROUPS != 16) ||
            (TAGS_PER_PRIORITY_GROUP != 16) ||
            ((TAGS_PER_CHANNEL % STATE_CONTROL_GROUP_BITS) != 0)) begin
            $error("NPU DMA local-tag allocator violates the v0.1 tag contract");
        end
    end
endmodule

`default_nettype wire
