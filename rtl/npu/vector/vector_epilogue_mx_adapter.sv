`timescale 1ns/1ps
`default_nettype none

// Forms one 32-element MX block from two adjacent 16-lane epilogue beats.
// A 16-lane quantizer is reused on consecutive cycles, sustaining one output
// response per cycle while preserving the metadata of each source beat.
module vector_epilogue_mx_adapter (
    input  logic                               clk_i,
    input  logic                               rst_i,
    input  logic                               clear_i,
    input  logic                               input_valid_i,
    output logic                               input_ready_o,
    input  vector_pkg::vector_engine_result_t  input_result_i,
    output logic                               output_valid_o,
    input  logic                               output_ready_i,
    output vector_pkg::vector_engine_result_t  output_result_o
);

    vector_pkg::vector_engine_result_t first_result_q;
    vector_pkg::vector_engine_result_t second_result_q;
    vector_pkg::vector_engine_result_t output_result_q;
    logic first_valid_q;
    logic second_pending_q;
    logic output_valid_q;
    mxfp_pkg::mxfp_scale_t second_scale_q;

    logic input_is_mx;
    logic input_fire;
    logic complete_pair;
    logic output_slot_available;
    logic [1023:0] scale_block_data;
    mxfp_pkg::mxfp_scale_t pair_scale;
    vector_pkg::vector_fp32_data_t quantize_data;
    mxfp_pkg::mxfp_format_e quantize_format;
    mxfp_pkg::mxfp_scale_t quantize_scale;
    logic [7:0] quantized_lane [0:15];
    vector_pkg::vector_mx_data_t quantized_vector;
    vector_pkg::vector_lane_mask_t quantized_overflow;
    vector_pkg::vector_lane_mask_t quantized_inexact;
    vector_pkg::vector_engine_result_t quantized_result;

    always_comb begin
        output_valid_o = output_valid_q;
        output_result_o = output_result_q;
        output_slot_available = !output_valid_q || output_ready_i;
        input_is_mx = input_result_i.control.result_kind ==
            vector_pkg::VECTOR_ENGINE_RESULT_MX_VECTOR;

        input_ready_o = 1'b0;
        if (!rst_i && !clear_i) begin
            if (input_is_mx) begin
                input_ready_o = !first_valid_q ||
                    (output_slot_available && !second_pending_q);
            end else begin
                input_ready_o = !first_valid_q && !second_pending_q &&
                    output_slot_available;
            end
        end
        input_fire = input_valid_i && input_ready_o;
        complete_pair = input_fire && input_is_mx && first_valid_q;

        scale_block_data = {input_result_i.fp32_vector,
                            first_result_q.fp32_vector};
        quantize_data = second_result_q.fp32_vector;
        quantize_format = second_result_q.control.mx_format;
        quantize_scale = second_scale_q;
        quantized_result = second_result_q;
        if (complete_pair) begin
            quantize_data = first_result_q.fp32_vector;
            quantize_format = input_result_i.control.mx_format;
            quantize_scale = pair_scale;
            quantized_result = first_result_q;
        end

        quantized_vector = '0;
        for (integer lane = 0; lane < 16; lane++) begin
            if (quantize_format == mxfp_pkg::MXFP4_E2M1) begin
                quantized_vector[lane*4 +: 4] = quantized_lane[lane][3:0];
            end else begin
                quantized_vector[lane*8 +: 8] = quantized_lane[lane];
            end
        end
        quantized_result.mx_vector = quantized_vector;
        quantized_result.mx_scale = quantize_scale;
        quantized_result.overflow = quantized_overflow;
        quantized_result.inexact = quantized_inexact;
    end

    mxfp_scale_block32 u_scale (
        .block_data_i(scale_block_data),
        .format_i(input_result_i.control.mx_format),
        .scale_o(pair_scale)
    );

    generate
        for (genvar lane = 0; lane < 16; lane++) begin : g_lane
            mxfp_quantize_lane u_quantize_lane (
                .data_i(quantize_data[lane*32 +: 32]),
                .format_i(quantize_format),
                .scale_i(quantize_scale),
                .data_o(quantized_lane[lane]),
                .overflow_o(quantized_overflow[lane]),
                .inexact_o(quantized_inexact[lane])
            );
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            first_result_q <= '0;
            second_result_q <= '0;
            output_result_q <= '0;
            first_valid_q <= 1'b0;
            second_pending_q <= 1'b0;
            output_valid_q <= 1'b0;
            second_scale_q <= '0;
        end else begin
            if (output_valid_q && output_ready_i) begin
                output_valid_q <= 1'b0;
            end

            if (second_pending_q && output_slot_available) begin
                output_result_q <= quantized_result;
                output_valid_q <= 1'b1;
                second_pending_q <= 1'b0;
            end

            if (input_fire) begin
                if (!input_is_mx) begin
                    output_result_q <= input_result_i;
                    output_valid_q <= 1'b1;
                end else if (!first_valid_q) begin
                    first_result_q <= input_result_i;
                    first_valid_q <= 1'b1;
                end else begin
                    output_result_q <= quantized_result;
                    output_valid_q <= 1'b1;
                    second_result_q <= input_result_i;
                    second_scale_q <= pair_scale;
                    second_pending_q <= 1'b1;
                    first_valid_q <= 1'b0;
                end
            end
        end
    end

endmodule

`default_nettype wire
