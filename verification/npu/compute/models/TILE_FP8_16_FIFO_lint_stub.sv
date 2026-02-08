`timescale 1ns/1ps
`default_nettype none

// Verification-only interface model for system integration lint. The
// production Tile is linted independently; this lightweight model lets the
// 2x2 system lint elaborate every east/south inter-Tile connection without
// flattening four complete 16x16 PE arrays into one Verilator process.
// verilator lint_off DECLFILENAME
module TILE_FP8_16_FIFO #(
    parameter bit DAZ = 1'b0,
    parameter bit FTZ = 1'b0
) (
    input  logic                         clk_i,
    input  logic                         rst_i,
    input  logic                         clear_i,
    input  logic                  [15:0] a_valid_i,
    input  logic                 [127:0] a_data_i,
    input  logic                  [31:0] a_format_i,
    input  logic                 [127:0] a_scale_i,
    input  logic                  [15:0] a_block_first_i,
    input  logic                  [15:0] a_block_last_i,
    input  logic                  [15:0] a_matrix_first_i,
    input  logic                  [15:0] a_matrix_last_i,
    input  logic                 [127:0] a_tag_i,
    input  logic                  [15:0] b_valid_i,
    input  logic                 [127:0] b_data_i,
    input  logic                  [31:0] b_format_i,
    input  logic                 [127:0] b_scale_i,
    output logic                  [15:0] a_east_valid_o,
    output logic                 [127:0] a_east_data_o,
    output logic                  [31:0] a_east_format_o,
    output logic                 [127:0] a_east_scale_o,
    output logic                  [15:0] a_east_block_first_o,
    output logic                  [15:0] a_east_block_last_o,
    output logic                  [15:0] a_east_matrix_first_o,
    output logic                  [15:0] a_east_matrix_last_o,
    output logic                 [127:0] a_east_tag_o,
    output logic                  [15:0] b_south_valid_o,
    output logic                 [127:0] b_south_data_o,
    output logic                  [31:0] b_south_format_o,
    output logic                 [127:0] b_south_scale_o,
    input  logic                         result_ready_i,
    output logic                         result_valid_o,
    output logic                 [511:0] result_data_o,
    output logic                  [15:0] result_invalid_o,
    output logic                   [7:0] result_tag_o,
    output logic                   [3:0] result_row_o,
    output logic                   [5:0] result_level_o,
    output logic                         input_issue_o,
    output logic                         output_overflow_o
);

    wire _unused_control = &{
        1'b0, clk_i, rst_i, clear_i, result_ready_i, DAZ, FTZ
    };

    assign a_east_valid_o = a_valid_i;
    assign a_east_data_o = a_data_i;
    assign a_east_format_o = a_format_i;
    assign a_east_scale_o = a_scale_i;
    assign a_east_block_first_o = a_block_first_i;
    assign a_east_block_last_o = a_block_last_i;
    assign a_east_matrix_first_o = a_matrix_first_i;
    assign a_east_matrix_last_o = a_matrix_last_i;
    assign a_east_tag_o = a_tag_i;
    assign b_south_valid_o = b_valid_i;
    assign b_south_data_o = b_data_i;
    assign b_south_format_o = b_format_i;
    assign b_south_scale_o = b_scale_i;

    assign result_valid_o = 1'b0;
    assign result_data_o = '0;
    assign result_invalid_o = '0;
    assign result_tag_o = '0;
    assign result_row_o = '0;
    assign result_level_o = '0;
    assign input_issue_o = (|a_valid_i) && (|b_valid_i);
    assign output_overflow_o = 1'b0;

endmodule
// verilator lint_on DECLFILENAME

`default_nettype wire
