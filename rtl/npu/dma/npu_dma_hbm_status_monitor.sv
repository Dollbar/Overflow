`timescale 1ns/1ps
`default_nettype none

module npu_dma_hbm_status_monitor #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned COUNTER_WIDTH = 64
) (
    input  logic clk_i,
    input  logic rst_i,

    input  logic [CHANNELS-1:0] response_commit_i,
    input  logic [CHANNELS*2-1:0] response_status_i,

    output logic [COUNTER_WIDTH-1:0] ok_responses_o,
    output logic [COUNTER_WIDTH-1:0] corrected_responses_o,
    output logic [COUNTER_WIDTH-1:0] uncorrectable_responses_o,
    output logic [COUNTER_WIDTH-1:0] data_error_responses_o,
    output logic corrected_seen_o,
    output logic uncorrectable_seen_o,
    output logic data_error_seen_o
);
    logic [CHANNELS-1:0] ok_match;
    logic [CHANNELS-1:0] corrected_match;
    logic [CHANNELS-1:0] uncorrectable_match;
    logic [CHANNELS-1:0] data_error_match;
    logic [CHANNELS-1:0] ok_match_q;
    logic [CHANNELS-1:0] corrected_match_q;
    logic [CHANNELS-1:0] uncorrectable_match_q;
    logic [CHANNELS-1:0] data_error_match_q;
    logic [4:0] ok_increment;
    logic [4:0] corrected_increment;
    logic [4:0] uncorrectable_increment;
    logic [4:0] data_error_increment;
    logic [4:0] ok_increment_q;
    logic [4:0] corrected_increment_q;
    logic [4:0] uncorrectable_increment_q;
    logic [4:0] data_error_increment_q;

    generate
        for (genvar channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin : g_status_decode
            assign ok_match[channel_index] =
                response_commit_i[channel_index] &&
                (response_status_i[channel_index*2 +: 2] == 2'd0);
            assign corrected_match[channel_index] =
                response_commit_i[channel_index] &&
                (response_status_i[channel_index*2 +: 2] == 2'd1);
            assign uncorrectable_match[channel_index] =
                response_commit_i[channel_index] &&
                (response_status_i[channel_index*2 +: 2] == 2'd2);
            assign data_error_match[channel_index] =
                response_commit_i[channel_index] &&
                (response_status_i[channel_index*2 +: 2] == 2'd3);
        end
    endgenerate

    npu_dma_hbm_rank_count16 u_ok_count (
        .bits_i(ok_match_q),
        .count_o(ok_increment)
    );

    npu_dma_hbm_rank_count16 u_corrected_count (
        .bits_i(corrected_match_q),
        .count_o(corrected_increment)
    );

    npu_dma_hbm_rank_count16 u_uncorrectable_count (
        .bits_i(uncorrectable_match_q),
        .count_o(uncorrectable_increment)
    );

    npu_dma_hbm_rank_count16 u_data_error_count (
        .bits_i(data_error_match_q),
        .count_o(data_error_increment)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            ok_match_q <= '0;
            corrected_match_q <= '0;
            uncorrectable_match_q <= '0;
            data_error_match_q <= '0;
            ok_increment_q <= '0;
            corrected_increment_q <= '0;
            uncorrectable_increment_q <= '0;
            data_error_increment_q <= '0;
            ok_responses_o <= '0;
            corrected_responses_o <= '0;
            uncorrectable_responses_o <= '0;
            data_error_responses_o <= '0;
            corrected_seen_o <= 1'b0;
            uncorrectable_seen_o <= 1'b0;
            data_error_seen_o <= 1'b0;
        end else begin
            ok_match_q <= ok_match;
            corrected_match_q <= corrected_match;
            uncorrectable_match_q <= uncorrectable_match;
            data_error_match_q <= data_error_match;
            ok_increment_q <= ok_increment;
            corrected_increment_q <= corrected_increment;
            uncorrectable_increment_q <= uncorrectable_increment;
            data_error_increment_q <= data_error_increment;
            ok_responses_o <= ok_responses_o +
                              COUNTER_WIDTH'(ok_increment_q);
            corrected_responses_o <= corrected_responses_o +
                                     COUNTER_WIDTH'(corrected_increment_q);
            uncorrectable_responses_o <= uncorrectable_responses_o +
                                         COUNTER_WIDTH'(
                                             uncorrectable_increment_q);
            data_error_responses_o <= data_error_responses_o +
                                      COUNTER_WIDTH'(
                                          data_error_increment_q);
            corrected_seen_o <= corrected_seen_o ||
                                (|corrected_match_q);
            uncorrectable_seen_o <= uncorrectable_seen_o ||
                                    (|uncorrectable_match_q);
            data_error_seen_o <= data_error_seen_o ||
                                 (|data_error_match_q);
        end
    end

    initial begin
        if ((CHANNELS != 16) || (COUNTER_WIDTH != 64)) begin
            $error("NPU DMA HBM status monitor violates the v0.1 contract");
        end
    end
endmodule

`default_nettype wire
