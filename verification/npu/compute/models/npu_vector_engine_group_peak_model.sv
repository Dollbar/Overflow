`timescale 1ns/1ps
`default_nettype none

// Verification-only zero-latency Vector group used to isolate coupler
// transport throughput. The production vector_engine16 numerical pipelines
// remain covered by tb_vector_engine16.
// The filename differs deliberately because this model replaces, rather than
// accompanies, the production module in this one verification source list.
/* verilator lint_off DECLFILENAME */
module npu_vector_engine_group #(
    parameter int unsigned CHANNELS = 4,
    parameter bit FTZ = 1'b0,
    parameter logic [31:0] FP32_RESULT = 32'h46000000
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic [CHANNELS-1:0] request_valid_i,
    output logic [CHANNELS-1:0] request_ready_o,
    input  logic [CHANNELS*vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH-1:0]
                 request_i,
    output logic [CHANNELS-1:0] response_valid_o,
    input  logic [CHANNELS-1:0] response_ready_i,
    output logic [CHANNELS*vector_pkg::VECTOR_ENGINE_RESULT_WIDTH-1:0]
                 response_o
);

    logic [CHANNELS-1:0] request_observation;

    always_comb begin
        request_ready_o = !rst_i && !clear_i ? response_ready_i : '0;
        response_valid_o = !rst_i && !clear_i ? request_valid_i : '0;
        response_o = '0;
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            vector_pkg::vector_engine_request_t request_lane;
            vector_pkg::vector_engine_result_t response_lane;
            request_lane = vector_pkg::vector_engine_request_t'(
                request_i[
                    lane*vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH +:
                    vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH]);
            request_observation[lane] = ^request_lane;
            response_lane = '0;
            if (request_lane.control.output_format ==
                vector_pkg::EPILOGUE_OUT_MX) begin
                response_lane.mx_vector = {16{8'h78}};
                response_lane.mx_scale =
                    (request_lane.data_a[31:0] == FP32_RESULT) ?
                    8'd132 : 8'd119;
                response_lane.control = {
                    request_lane.control,
                    vector_pkg::VECTOR_ENGINE_RESULT_MX_VECTOR
                };
            end else begin
                response_lane.fp32_vector = {16{FP32_RESULT}};
                response_lane.control = {
                    request_lane.control,
                    vector_pkg::VECTOR_ENGINE_RESULT_FP32_VECTOR
                };
            end
            response_o[
                lane*vector_pkg::VECTOR_ENGINE_RESULT_WIDTH +:
                vector_pkg::VECTOR_ENGINE_RESULT_WIDTH] = response_lane;
        end
    end

    wire _unused = &{1'b0, clk_i, FTZ, request_observation};

endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
