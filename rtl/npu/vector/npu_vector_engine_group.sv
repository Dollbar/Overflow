`timescale 1ns/1ps
`default_nettype none

// Small physical and simulation hierarchy for replicated Vector engines.
// The production 16-lane-row backend instantiates eight identical two-engine
// groups, preserving independent row backpressure and full aggregate issue.
module npu_vector_engine_group #(
    parameter int unsigned CHANNELS = 4,
    parameter bit FTZ = 1'b0
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
    /* verilator hier_block */

    generate
        for (genvar lane = 0; lane < CHANNELS; lane++) begin : g_engine
            vector_pkg::vector_engine_request_t request_lane;
            vector_pkg::vector_engine_result_t response_lane;

            always_comb begin
                request_lane = vector_pkg::vector_engine_request_t'(
                    request_i[
                        lane*vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH +:
                        vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH
                    ]
                );
                response_o[
                    lane*vector_pkg::VECTOR_ENGINE_RESULT_WIDTH +:
                    vector_pkg::VECTOR_ENGINE_RESULT_WIDTH
                ] = response_lane;
            end

            vector_engine16 #(
                .FTZ(FTZ)
            ) u_engine (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .clear_i(clear_i),
                .request_valid_i(request_valid_i[lane]),
                .request_ready_o(request_ready_o[lane]),
                .data_a_i(request_lane.data_a),
                .data_b_i(request_lane.data_b),
                .data_c_i(request_lane.data_c),
                .scalar_i(request_lane.scalar),
                .invalid_a_i(request_lane.invalid_a),
                .invalid_b_i(request_lane.invalid_b),
                .invalid_c_i(request_lane.invalid_c),
                .scalar_invalid_i(request_lane.scalar_invalid),
                .control_i(request_lane.control),
                .response_valid_o(response_valid_o[lane]),
                .response_ready_i(response_ready_i[lane]),
                .fp32_vector_o(response_lane.fp32_vector),
                .mx_vector_o(response_lane.mx_vector),
                .mx_scale_o(response_lane.mx_scale),
                .fp32_scalar_o(response_lane.fp32_scalar),
                .invalid_o(response_lane.invalid),
                .overflow_o(response_lane.overflow),
                .inexact_o(response_lane.inexact),
                .empty_o(response_lane.empty),
                .response_control_o(response_lane.control)
            );
        end
    endgenerate

    initial begin
        assert ((CHANNELS > 0) && (CHANNELS <= 4))
            else $error("npu_vector_engine_group CHANNELS must be in 1..4");
    end

endmodule

`default_nettype wire
