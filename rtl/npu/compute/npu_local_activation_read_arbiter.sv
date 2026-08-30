`timescale 1ns/1ps
`default_nettype none

// Shares the registered Activation Buffer read port. Both clients retain a
// request until ready, and round-robin selection provides bounded service when
// GEMM and standalone Vector remain continuously active.
module npu_local_activation_read_arbiter #(
    parameter int unsigned DATA_WIDTH = 2048,
    parameter int unsigned BUFFER_ID_WIDTH = 4,
    parameter int unsigned OFFSET_WIDTH = 32
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic gemm_valid_i,
    output logic gemm_ready_o,
    input  logic [BUFFER_ID_WIDTH-1:0] gemm_buffer_id_i,
    input  logic [OFFSET_WIDTH-1:0] gemm_offset_i,
    output logic gemm_response_valid_o,
    output logic [DATA_WIDTH-1:0] gemm_response_data_o,
    output logic [DATA_WIDTH-1:0] gemm_response_scale_o,

    input  logic vector_valid_i,
    output logic vector_ready_o,
    input  logic [BUFFER_ID_WIDTH-1:0] vector_buffer_id_i,
    input  logic [OFFSET_WIDTH-1:0] vector_offset_i,
    output logic vector_response_valid_o,
    output logic [DATA_WIDTH-1:0] vector_response_data_o,
    output logic [DATA_WIDTH-1:0] vector_response_scale_o,

    output logic sram_read_enable_o,
    output logic [BUFFER_ID_WIDTH-1:0] sram_read_buffer_id_o,
    output logic [OFFSET_WIDTH-1:0] sram_read_offset_o,
    input  logic sram_read_valid_i,
    input  logic [DATA_WIDTH-1:0] sram_read_data_i,
    input  logic [DATA_WIDTH-1:0] sram_read_scale_i,

    output logic protocol_error_o
);

    logic response_vector_q;
    logic response_pending_q;
    logic prefer_vector_q;
    logic select_vector;
    logic grant_gemm;
    logic grant_vector;

    always_comb begin
        gemm_ready_o = !rst_i && !clear_i &&
            (!vector_valid_i || !prefer_vector_q);
        vector_ready_o = !rst_i && !clear_i &&
            (!gemm_valid_i || prefer_vector_q);
        grant_gemm = gemm_valid_i && gemm_ready_o;
        grant_vector = vector_valid_i && vector_ready_o;
        select_vector = grant_vector;
        sram_read_enable_o = grant_gemm || grant_vector;
        sram_read_buffer_id_o = select_vector ? vector_buffer_id_i :
            gemm_buffer_id_i;
        sram_read_offset_o = select_vector ? vector_offset_i : gemm_offset_i;

        gemm_response_valid_o = sram_read_valid_i && response_pending_q &&
            !response_vector_q;
        vector_response_valid_o = sram_read_valid_i && response_pending_q &&
            response_vector_q;
        gemm_response_data_o = sram_read_data_i;
        gemm_response_scale_o = sram_read_scale_i;
        vector_response_data_o = sram_read_data_i;
        vector_response_scale_o = sram_read_scale_i;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            response_vector_q <= 1'b0;
            response_pending_q <= 1'b0;
            prefer_vector_q <= 1'b0;
            protocol_error_o <= 1'b0;
        end else begin
            response_pending_q <= sram_read_enable_o;
            if (sram_read_enable_o) begin
                response_vector_q <= select_vector;
            end
            if (grant_gemm) begin
                prefer_vector_q <= 1'b1;
            end else if (grant_vector) begin
                prefer_vector_q <= 1'b0;
            end
            if (sram_read_valid_i != response_pending_q) begin
                protocol_error_o <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
