`timescale 1ns/1ps
`default_nettype none

// Per-lane fair arbiter between GEMM post-processing beats and an independent
// local-SRAM Vector stream. Payload and command metadata move atomically.
module npu_vector_source_arbiter16 #(
    parameter int unsigned CHANNELS = 16
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic [CHANNELS-1:0] gemm_valid_i,
    output logic [CHANNELS-1:0] gemm_ready_o,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_result_i,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_command_i,

    input  logic [CHANNELS-1:0] standalone_valid_i,
    output logic [CHANNELS-1:0] standalone_ready_o,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 standalone_result_i,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 standalone_command_i,

    output logic [CHANNELS-1:0] output_valid_o,
    input  logic [CHANNELS-1:0] output_ready_i,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 output_result_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 output_command_o
);

    logic [CHANNELS-1:0] prefer_standalone_q;
    logic [CHANNELS-1:0] select_standalone;
    logic [CHANNELS-1:0] output_fire;

    always_comb begin
        gemm_ready_o = '0;
        standalone_ready_o = '0;
        output_valid_o = '0;
        select_standalone = '0;
        output_fire = '0;

        for (integer lane = 0; lane < CHANNELS; lane++) begin
            select_standalone[lane] = standalone_valid_i[lane] &&
                (!gemm_valid_i[lane] || prefer_standalone_q[lane]);
            output_valid_o[lane] = select_standalone[lane] ?
                standalone_valid_i[lane] : gemm_valid_i[lane];
            output_result_o[
                lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                npu_scheduler_pkg::NPU_POST_RESULT_WIDTH] =
                select_standalone[lane] ? standalone_result_i[
                    lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_RESULT_WIDTH] : gemm_result_i[
                    lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_RESULT_WIDTH];
            output_command_o[
                lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH] =
                select_standalone[lane] ? standalone_command_i[
                    lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH] : gemm_command_i[
                    lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH];
            standalone_ready_o[lane] = output_ready_i[lane] &&
                select_standalone[lane];
            gemm_ready_o[lane] = output_ready_i[lane] &&
                !select_standalone[lane] && gemm_valid_i[lane];
            output_fire[lane] = output_valid_o[lane] && output_ready_i[lane];
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            prefer_standalone_q <= '0;
        end else begin
            for (integer lane = 0; lane < CHANNELS; lane++) begin
                if (output_fire[lane] && gemm_valid_i[lane] &&
                    standalone_valid_i[lane]) begin
                    prefer_standalone_q[lane] <= !select_standalone[lane];
                end
            end
        end
    end

endmodule

`default_nettype wire
