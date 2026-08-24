`timescale 1ns/1ps
`default_nettype none

// Verification-only full-array transport model.  It preserves the production
// GEMM boundary widths, tags, per-Tile ready/valid behavior, and sixteen result
// rows per Tile while replacing the 65,536 arithmetic PEs.  Production GEMM
// arithmetic is covered independently by the full-array K=4096 regression.
/* verilator lint_off DECLFILENAME */
module GEMM_65536 #(
    parameter int unsigned ARRAY_X = 16,
    parameter int unsigned ARRAY_Y = 16,
    parameter bit DAZ = 1'b0,
    parameter bit FTZ = 1'b0,
    parameter int unsigned CONTROL_TREE_FANOUT = 16,
    parameter logic [31:0] RESULT_FP32 = 32'h46000000
) (
    input  logic                         clk_i,
    input  logic                         rst_i,
    input  logic                         clear_i,
    input  logic          [ARRAY_Y*16-1:0] direct_a_valid_i,
    input  logic         [ARRAY_Y*128-1:0] direct_a_data_i,
    input  logic          [ARRAY_Y*32-1:0] direct_a_format_i,
    input  logic         [ARRAY_Y*128-1:0] direct_a_scale_i,
    input  logic          [ARRAY_Y*16-1:0] direct_a_block_first_i,
    input  logic          [ARRAY_Y*16-1:0] direct_a_block_last_i,
    input  logic          [ARRAY_Y*16-1:0] direct_a_matrix_first_i,
    input  logic          [ARRAY_Y*16-1:0] direct_a_matrix_last_i,
    input  logic         [ARRAY_Y*128-1:0] direct_a_tag_i,
    input  logic          [ARRAY_X*16-1:0] direct_b_valid_i,
    input  logic         [ARRAY_X*128-1:0] direct_b_data_i,
    input  logic          [ARRAY_X*32-1:0] direct_b_format_i,
    input  logic         [ARRAY_X*128-1:0] direct_b_scale_i,
    input  logic      [ARRAY_X*ARRAY_Y-1:0] result_ready_i,
    output logic      [ARRAY_X*ARRAY_Y-1:0] result_valid_o,
    output logic [ARRAY_X*ARRAY_Y*512-1:0] result_data_o,
    output logic  [ARRAY_X*ARRAY_Y*16-1:0] result_invalid_o,
    output logic   [ARRAY_X*ARRAY_Y*8-1:0] result_tag_o,
    output logic   [ARRAY_X*ARRAY_Y*4-1:0] result_row_o,
    output logic   [ARRAY_X*ARRAY_Y*6-1:0] result_level_o,
    output logic      [ARRAY_X*ARRAY_Y-1:0] input_pair_issue_o,
    output logic      [ARRAY_X*ARRAY_Y-1:0] output_overflow_o
);
    localparam int unsigned NODE_COUNT = ARRAY_X*ARRAY_Y;

    logic [NODE_COUNT-1:0] result_valid_q;
    logic [NODE_COUNT*4-1:0] result_row_q;
    logic [7:0] result_tag_q;
    logic dense_input;
    logic final_input;

    always_comb begin
        dense_input = (&direct_a_valid_i) && (&direct_b_valid_i);
        final_input = dense_input && (&direct_a_matrix_last_i);
        result_valid_o = result_valid_q;
        result_data_o = {NODE_COUNT*16{RESULT_FP32}};
        result_invalid_o = '0;
        result_tag_o = {NODE_COUNT{result_tag_q}};
        result_row_o = result_row_q;
        result_level_o = '0;
        input_pair_issue_o = {NODE_COUNT{dense_input}};
        output_overflow_o = '0;
        for (integer node = 0; node < NODE_COUNT; node++) begin
            result_level_o[node*6 +: 6] =
                result_valid_q[node] ? 6'd1 : 6'd0;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            result_valid_q <= '0;
            result_row_q <= '0;
            result_tag_q <= '0;
        end else begin
            for (integer node = 0; node < NODE_COUNT; node++) begin
                if (result_valid_q[node] && result_ready_i[node]) begin
                    if (result_row_q[node*4 +: 4] == 4'd15) begin
                        result_valid_q[node] <= 1'b0;
                    end else begin
                        result_row_q[node*4 +: 4] <=
                            result_row_q[node*4 +: 4] + 4'd1;
                    end
                end
            end
            if (final_input) begin
                result_valid_q <= '1;
                result_row_q <= '0;
                result_tag_q <= direct_a_tag_i[7:0];
            end
        end
    end

    wire _unused_inputs = &{1'b0, direct_a_data_i, direct_a_format_i,
        direct_a_scale_i, direct_a_block_first_i, direct_a_block_last_i,
        direct_a_matrix_first_i,
        direct_a_tag_i[ARRAY_Y*128-1:8], direct_b_data_i,
        direct_b_format_i, direct_b_scale_i, DAZ, FTZ,
        CONTROL_TREE_FANOUT};

endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
