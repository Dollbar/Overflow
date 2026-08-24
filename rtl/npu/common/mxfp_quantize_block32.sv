`timescale 1ns/1ps
`default_nettype none

// Two-beat block quantizer. The first 16-lane FP32 beat is retained until the
// second arrives, then one E8M0 scale is selected for all 32 elements.
module mxfp_quantize_block32 (
    input  logic                           clk_i,
    input  logic                           rst_i,
    input  logic                           clear_i,
    input  logic                           input_valid_i,
    output logic                           input_ready_o,
    input  logic [511:0]                   input_data_i,
    input  logic [15:0]                    input_invalid_i,
    input  logic                           input_last_i,
    input  mxfp_pkg::mxfp_format_e         format_i,
    output logic                           output_valid_o,
    input  logic                           output_ready_i,
    output logic [255:0]                   output_data_o,
    output mxfp_pkg::mxfp_scale_t          output_scale_o,
    output logic [31:0]                    output_invalid_o,
    output logic [31:0]                    output_overflow_o,
    output logic [31:0]                    output_inexact_o,
    output logic                           output_last_o
);

    logic first_valid_q;
    logic [511:0] first_data_q;
    logic [15:0] first_invalid_q;
    logic first_last_q;
    logic output_valid_q;
    logic [255:0] output_data_q;
    logic [7:0] output_scale_q;
    logic [31:0] output_invalid_q;
    logic [31:0] output_overflow_q;
    logic [31:0] output_inexact_q;
    logic output_last_q;
    logic accept;
    logic complete_pair;
    logic [1023:0] block_data;
    logic [255:0] quantized_data;
    logic [31:0] quantized_overflow;
    logic [31:0] quantized_inexact;
    mxfp_pkg::mxfp_scale_t selected_scale;

    assign input_ready_o = !rst_i && !clear_i &&
        (!first_valid_q || !output_valid_q || output_ready_i);
    assign accept = input_valid_i && input_ready_o;
    assign complete_pair = accept && first_valid_q;
    assign block_data = {input_data_i, first_data_q};

    mxfp_quantize_block32_comb u_quantize_block (
        .block_data_i(block_data),
        .format_i(format_i),
        .block_data_o(quantized_data),
        .scale_o(selected_scale),
        .overflow_o(quantized_overflow),
        .inexact_o(quantized_inexact)
    );

    assign output_valid_o = output_valid_q;
    assign output_data_o = output_data_q;
    assign output_scale_o = output_scale_q;
    assign output_invalid_o = output_invalid_q;
    assign output_overflow_o = output_overflow_q;
    assign output_inexact_o = output_inexact_q;
    assign output_last_o = output_last_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            first_valid_q <= 1'b0;
            output_valid_q <= 1'b0;
        end else begin
            if (output_valid_q && output_ready_i) begin
                output_valid_q <= 1'b0;
            end
            if (accept && !first_valid_q) begin
                first_valid_q <= 1'b1;
                first_data_q <= input_data_i;
                first_invalid_q <= input_invalid_i;
                first_last_q <= input_last_i;
            end else if (complete_pair) begin
                first_valid_q <= 1'b0;
                output_valid_q <= 1'b1;
                output_scale_q <= selected_scale;
                output_invalid_q <= {input_invalid_i, first_invalid_q};
                output_overflow_q <= quantized_overflow;
                output_inexact_q <= quantized_inexact;
                output_last_q <= input_last_i || first_last_q;
                output_data_q <= quantized_data;
            end
        end
    end

endmodule

`default_nettype wire
