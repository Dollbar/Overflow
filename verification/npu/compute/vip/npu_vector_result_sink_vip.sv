`timescale 1ns/1ps
`default_nettype none

// Multi-lane ready/valid sink for independent Vector result streams. It keeps
// accepted result/command pairs atomic and checks payload stability while any
// lane is backpressured.
module npu_vector_result_sink_vip #(
    parameter int unsigned CHANNELS = 16
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic [CHANNELS-1:0] accept_enable_i,

    input  logic [CHANNELS-1:0] source_valid_i,
    output logic [CHANNELS-1:0] source_ready_o,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 source_result_i,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 source_command_i,

    output logic [CHANNELS-1:0] monitor_valid_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 monitor_result_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 monitor_command_o,
    output logic [31:0] transaction_count_o,
    output logic protocol_error_o
);

    localparam int unsigned LANE_WIDTH =
        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +
        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH;

    logic [CHANNELS-1:0] held_valid_q;
    logic [LANE_WIDTH-1:0] held_payload_q [0:CHANNELS-1];
    logic [$clog2(CHANNELS+1)-1:0] accepted_count;

    always_comb begin
        source_ready_o = accept_enable_i & {CHANNELS{!rst_i && !clear_i}};
        accepted_count = '0;
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            accepted_count = accepted_count +
                $bits(accepted_count)'(source_valid_i[lane] &&
                                       source_ready_o[lane]);
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            monitor_valid_o <= '0;
            monitor_result_o <= '0;
            monitor_command_o <= '0;
            transaction_count_o <= 32'd0;
            held_valid_q <= '0;
            protocol_error_o <= 1'b0;
            for (integer lane = 0; lane < CHANNELS; lane++) begin
                held_payload_q[lane] <= '0;
            end
        end else begin
            monitor_valid_o <= source_valid_i & source_ready_o;
            transaction_count_o <= transaction_count_o + 32'(accepted_count);
            for (integer lane = 0; lane < CHANNELS; lane++) begin
                logic [LANE_WIDTH-1:0] source_payload;
                source_payload = {
                    source_command_i[
                        lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH],
                    source_result_i[
                            lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]};
                if (held_valid_q[lane] &&
                    (!source_valid_i[lane] ||
                     (held_payload_q[lane] != source_payload))) begin
                    protocol_error_o <= 1'b1;
                end
                if (source_valid_i[lane] && source_ready_o[lane]) begin
                    monitor_result_o[
                        lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH] <=
                        source_result_i[
                            lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_RESULT_WIDTH];
                    monitor_command_o[
                        lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH] <=
                        source_command_i[
                            lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH];
                    held_valid_q[lane] <= 1'b0;
                end else if (source_valid_i[lane]) begin
                    held_valid_q[lane] <= 1'b1;
                    held_payload_q[lane] <= source_payload;
                end else begin
                    held_valid_q[lane] <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
