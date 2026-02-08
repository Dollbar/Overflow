`timescale 1ns/1ps
`default_nettype none

// Double-bank reduction Tile wrapper. The Tile accepts one atomic 16-lane A/B
// beat per cycle; five 128-bit SRAM FIFO slices absorb completed 512-bit rows
// plus row/tag/invalid metadata atomically.
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

    localparam int unsigned RESULT_SLICES = 5;

    logic core_result_valid;
    logic [511:0] core_result_data;
    logic [15:0] core_result_invalid;
    logic [7:0] core_result_tag;
    logic [3:0] core_result_row;
    logic [RESULT_SLICES-1:0] fifo_write_ready;
    logic [RESULT_SLICES-1:0] fifo_read_valid;
    logic [RESULT_SLICES*128-1:0] fifo_read_data;
    logic [RESULT_SLICES*6-1:0] fifo_level;
    logic fifo_write;
    logic fifo_read;
    logic [127:0] fifo_write_data [0:RESULT_SLICES-1];

    wire _unused_fifo_bus = &{1'b0, fifo_read_data[639:540], fifo_level[29:6]};

    assign input_issue_o = (|a_valid_i) && (|b_valid_i) && !rst_i && !clear_i;
    assign fifo_write = core_result_valid && (&fifo_write_ready);
    assign result_valid_o = &fifo_read_valid;
    assign fifo_read = result_valid_o && result_ready_i;
    assign result_data_o = fifo_read_data[511:0];
    assign result_invalid_o = fifo_read_data[512 +: 16];
    assign result_tag_o = fifo_read_data[528 +: 8];
    assign result_row_o = fifo_read_data[536 +: 4];
    assign result_level_o = fifo_level[5:0];

    always_comb begin
        fifo_write_data[0] = core_result_data[0 +: 128];
        fifo_write_data[1] = core_result_data[128 +: 128];
        fifo_write_data[2] = core_result_data[256 +: 128];
        fifo_write_data[3] = core_result_data[384 +: 128];
        fifo_write_data[4] = {
            100'd0, core_result_row, core_result_tag, core_result_invalid
        };
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            output_overflow_o <= 1'b0;
        end else if (core_result_valid && !(&fifo_write_ready)) begin
            output_overflow_o <= 1'b1;
        end
    end

    TILE_FP8_16 #(
        .DAZ (DAZ),
        .FTZ (FTZ)
    ) u_compute_core (
        .clk_i                  (clk_i),
        .rst_i                  (rst_i),
        .clear_i                (clear_i),
        .a_valid_i              (a_valid_i),
        .a_data_i               (a_data_i),
        .a_format_i             (a_format_i),
        .a_scale_i              (a_scale_i),
        .a_block_first_i        (a_block_first_i),
        .a_block_last_i         (a_block_last_i),
        .a_matrix_first_i       (a_matrix_first_i),
        .a_matrix_last_i        (a_matrix_last_i),
        .a_tag_i                (a_tag_i),
        .b_valid_i              (b_valid_i),
        .b_data_i               (b_data_i),
        .b_format_i             (b_format_i),
        .b_scale_i              (b_scale_i),
        .a_right_valid_o        (a_east_valid_o),
        .a_right_data_o         (a_east_data_o),
        .a_right_format_o       (a_east_format_o),
        .a_right_scale_o        (a_east_scale_o),
        .a_right_block_first_o  (a_east_block_first_o),
        .a_right_block_last_o   (a_east_block_last_o),
        .a_right_matrix_first_o (a_east_matrix_first_o),
        .a_right_matrix_last_o  (a_east_matrix_last_o),
        .a_right_tag_o          (a_east_tag_o),
        .b_bottom_valid_o       (b_south_valid_o),
        .b_bottom_data_o        (b_south_data_o),
        .b_bottom_format_o      (b_south_format_o),
        .b_bottom_scale_o       (b_south_scale_o),
        .result_valid_o         (core_result_valid),
        .result_data_o          (core_result_data),
        .result_invalid_o       (core_result_invalid),
        .result_tag_o           (core_result_tag),
        .result_row_o           (core_result_row)
    );

    generate
        for (genvar slice = 0; slice < RESULT_SLICES; slice++) begin : gen_result_slices
            logic fifo_full;
            logic fifo_empty;

            FIFO_SYNC_32_128 u_result_fifo (
                .clk_i      (clk_i),
                .rst_i      (rst_i),
                .clear_i    (clear_i),
                .wr_valid_i (fifo_write),
                .wr_ready_o (fifo_write_ready[slice]),
                .wr_data_i  (fifo_write_data[slice]),
                .rd_ready_i (fifo_read),
                .rd_valid_o (fifo_read_valid[slice]),
                .rd_data_o  (fifo_read_data[slice*128 +: 128]),
                .full_o     (fifo_full),
                .empty_o    (fifo_empty),
                .level_o    (fifo_level[slice*6 +: 6])
            );

            wire _unused_fifo_status = &{1'b0, fifo_full, fifo_empty};
        end
    endgenerate

endmodule

`default_nettype wire
