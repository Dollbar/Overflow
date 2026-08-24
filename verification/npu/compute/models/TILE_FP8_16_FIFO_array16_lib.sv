`timescale 1ns/1ps
`default_nettype none

// Verification-only adapter for the precompiled production Tile FIFO. It
// keeps the full 16x16 array regression tractable without changing RTL.
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

    initial begin
        assert (!DAZ && !FTZ)
            else $error("array16 Tile library parameter mismatch");
    end

    array16_tile_model u_precompiled_tile (.*);

endmodule

`default_nettype wire
