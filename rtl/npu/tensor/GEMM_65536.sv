`timescale 1ns/1ps
`default_nettype none

// Hierarchical 2-D Tile array. Each 16x16 Tile contributes 256 exact-product
// PEs; the default 16x16 Tile grid therefore contains 65,536 multipliers.
// A enters only at the west array boundary and propagates east. B enters only
// at the north array boundary and propagates south. There is intentionally no
// Tile-level packet router, alternate injection path, or PE-local accumulator.
module GEMM_65536 #(
    parameter int unsigned ARRAY_X = 16,
    parameter int unsigned ARRAY_Y = 16,
    parameter bit DAZ = 1'b0,
    parameter bit FTZ = 1'b0,
    parameter int unsigned CONTROL_TREE_FANOUT = 16
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

    localparam int unsigned NODE_COUNT = ARRAY_X * ARRAY_Y;
    localparam int unsigned A_LANES = ARRAY_Y * 16;
    localparam int unsigned B_LANES = ARRAY_X * 16;
    localparam int unsigned A_PAYLOAD_WIDTH = 30;
    localparam int unsigned B_PAYLOAD_WIDTH = 18;

    logic [A_LANES*A_PAYLOAD_WIDTH-1:0] a_boundary_payload;
    logic [A_LANES*A_PAYLOAD_WIDTH-1:0] a_skewed_payload;
    logic [A_LANES-1:0] a_skewed_valid;
    logic [A_LANES*8-1:0] a_skewed_data;
    logic [A_LANES*2-1:0] a_skewed_format;
    logic [A_LANES*8-1:0] a_skewed_scale;
    logic [A_LANES-1:0] a_skewed_block_first;
    logic [A_LANES-1:0] a_skewed_block_last;
    logic [A_LANES-1:0] a_skewed_matrix_first;
    logic [A_LANES-1:0] a_skewed_matrix_last;
    logic [A_LANES*8-1:0] a_skewed_tag;

    logic [B_LANES*B_PAYLOAD_WIDTH-1:0] b_boundary_payload;
    logic [B_LANES*B_PAYLOAD_WIDTH-1:0] b_skewed_payload;
    logic [B_LANES-1:0] b_skewed_valid;
    logic [B_LANES*8-1:0] b_skewed_data;
    logic [B_LANES*2-1:0] b_skewed_format;
    logic [B_LANES*8-1:0] b_skewed_scale;
    logic [ARRAY_Y-1:0] a_group_valid;
    logic [ARRAY_Y-1:0] a_group_skewed_valid;
    logic [ARRAY_X-1:0] b_group_valid;
    logic [ARRAY_X-1:0] b_group_skewed_valid;

    logic [NODE_COUNT*16-1:0] tile_a_east_valid;
    logic [NODE_COUNT*128-1:0] tile_a_east_data;
    logic [NODE_COUNT*32-1:0] tile_a_east_format;
    logic [NODE_COUNT*128-1:0] tile_a_east_scale;
    logic [NODE_COUNT*16-1:0] tile_a_east_block_first;
    logic [NODE_COUNT*16-1:0] tile_a_east_block_last;
    logic [NODE_COUNT*16-1:0] tile_a_east_matrix_first;
    logic [NODE_COUNT*16-1:0] tile_a_east_matrix_last;
    logic [NODE_COUNT*128-1:0] tile_a_east_tag;

    logic [NODE_COUNT*16-1:0] tile_b_south_valid;
    logic [NODE_COUNT*128-1:0] tile_b_south_data;
    logic [NODE_COUNT*32-1:0] tile_b_south_format;
    logic [NODE_COUNT*128-1:0] tile_b_south_scale;
    logic [NODE_COUNT-1:0] tile_rst;
    logic [NODE_COUNT-1:0] tile_clear;

    generate
        for (genvar a_lane = 0; a_lane < A_LANES; a_lane++) begin : g_pack_a
            always_comb begin
                a_boundary_payload[a_lane*A_PAYLOAD_WIDTH +: A_PAYLOAD_WIDTH] = {
                    direct_a_tag_i[a_lane*8 +: 8],
                    direct_a_matrix_last_i[a_lane],
                    direct_a_matrix_first_i[a_lane],
                    direct_a_block_last_i[a_lane],
                    direct_a_block_first_i[a_lane],
                    direct_a_scale_i[a_lane*8 +: 8],
                    direct_a_format_i[a_lane*2 +: 2],
                    direct_a_data_i[a_lane*8 +: 8]
                };
                {
                    a_skewed_tag[a_lane*8 +: 8],
                    a_skewed_matrix_last[a_lane],
                    a_skewed_matrix_first[a_lane],
                    a_skewed_block_last[a_lane],
                    a_skewed_block_first[a_lane],
                    a_skewed_scale[a_lane*8 +: 8],
                    a_skewed_format[a_lane*2 +: 2],
                    a_skewed_data[a_lane*8 +: 8]
                } = a_skewed_payload[a_lane*A_PAYLOAD_WIDTH +: A_PAYLOAD_WIDTH];
            end
        end

        for (genvar a_group = 0; a_group < ARRAY_Y;
             a_group++) begin : g_a_group_valid
            assign a_group_valid[a_group] =
                &direct_a_valid_i[a_group*16 +: 16];
            assign a_skewed_valid[a_group*16 +: 16] =
                {16{a_group_skewed_valid[a_group]}};
        end

        for (genvar b_lane = 0; b_lane < B_LANES; b_lane++) begin : g_pack_b
            always_comb begin
                b_boundary_payload[b_lane*B_PAYLOAD_WIDTH +: B_PAYLOAD_WIDTH] = {
                    direct_b_scale_i[b_lane*8 +: 8],
                    direct_b_format_i[b_lane*2 +: 2],
                    direct_b_data_i[b_lane*8 +: 8]
                };
                {
                    b_skewed_scale[b_lane*8 +: 8],
                    b_skewed_format[b_lane*2 +: 2],
                    b_skewed_data[b_lane*8 +: 8]
                } = b_skewed_payload[b_lane*B_PAYLOAD_WIDTH +: B_PAYLOAD_WIDTH];
            end
        end


        for (genvar b_group = 0; b_group < ARRAY_X;
             b_group++) begin : g_b_group_valid
            assign b_group_valid[b_group] =
                &direct_b_valid_i[b_group*16 +: 16];
            assign b_skewed_valid[b_group*16 +: 16] =
                {16{b_group_skewed_valid[b_group]}};
        end
    endgenerate

    // Tile groups, rather than individual operands, are skewed. A group for
    // Tile row y is delayed y cycles and a B group for Tile column x is delayed
    // x cycles. After x east hops and y south hops both operands therefore
    // reach Tile(x,y) on cycle x+y while every 16-lane block remains atomic.
    gemm_boundary_skew #(
        .LANES(ARRAY_Y),
        .PAYLOAD_WIDTH(16*A_PAYLOAD_WIDTH)
    ) u_a_group_skew (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(a_group_valid), .payload_i(a_boundary_payload),
        .valid_o(a_group_skewed_valid), .payload_o(a_skewed_payload)
    );

    gemm_boundary_skew #(
        .LANES(ARRAY_X),
        .PAYLOAD_WIDTH(16*B_PAYLOAD_WIDTH)
    ) u_b_group_skew (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(b_group_valid), .payload_i(b_boundary_payload),
        .valid_o(b_group_skewed_valid), .payload_o(b_skewed_payload)
    );

    wire _unused_edge_observability = &{
        1'b0, tile_a_east_valid, tile_a_east_data, tile_a_east_format,
        tile_a_east_scale, tile_a_east_block_first, tile_a_east_block_last,
        tile_a_east_matrix_first, tile_a_east_matrix_last,
        tile_a_east_tag, tile_b_south_valid,
        tile_b_south_data, tile_b_south_format, tile_b_south_scale
    };

    gemm_control_tree #(
        .NODE_COUNT    (NODE_COUNT),
        .BRANCH_FANOUT (CONTROL_TREE_FANOUT)
    ) u_rst_tree (
        .clk_i     (clk_i),
        .control_i (rst_i),
        .control_o (tile_rst)
    );

    gemm_control_tree #(
        .NODE_COUNT    (NODE_COUNT),
        .BRANCH_FANOUT (CONTROL_TREE_FANOUT)
    ) u_clear_tree (
        .clk_i     (clk_i),
        .control_i (clear_i),
        .control_o (tile_clear)
    );

    generate
        for (genvar tile_y = 0; tile_y < ARRAY_Y; tile_y++) begin : gen_tile_rows
            for (genvar tile_x = 0; tile_x < ARRAY_X; tile_x++) begin : gen_tile_columns
                localparam int unsigned NODE_INDEX = tile_y*ARRAY_X + tile_x;

                logic [15:0] tile_a_valid;
                logic [127:0] tile_a_data;
                logic [31:0] tile_a_format;
                logic [127:0] tile_a_scale;
                logic [15:0] tile_a_block_first;
                logic [15:0] tile_a_block_last;
                logic [15:0] tile_a_matrix_first;
                logic [15:0] tile_a_matrix_last;
                logic [127:0] tile_a_tag;
                logic [15:0] tile_b_valid;
                logic [127:0] tile_b_data;
                logic [31:0] tile_b_format;
                logic [127:0] tile_b_scale;

                if (tile_x == 0) begin : gen_a_array_boundary
                    assign tile_a_valid = a_skewed_valid[tile_y*16 +: 16];
                    assign tile_a_data = a_skewed_data[tile_y*128 +: 128];
                    assign tile_a_format = a_skewed_format[tile_y*32 +: 32];
                    assign tile_a_scale = a_skewed_scale[tile_y*128 +: 128];
                    assign tile_a_block_first =
                        a_skewed_block_first[tile_y*16 +: 16];
                    assign tile_a_block_last =
                        a_skewed_block_last[tile_y*16 +: 16];
                    assign tile_a_matrix_first =
                        a_skewed_matrix_first[tile_y*16 +: 16];
                    assign tile_a_matrix_last =
                        a_skewed_matrix_last[tile_y*16 +: 16];
                    assign tile_a_tag = a_skewed_tag[tile_y*128 +: 128];
                end else begin : gen_a_from_west_tile
                    localparam int unsigned WEST_NODE = NODE_INDEX - 1;
                    assign tile_a_valid = tile_a_east_valid[WEST_NODE*16 +: 16];
                    assign tile_a_data = tile_a_east_data[WEST_NODE*128 +: 128];
                    assign tile_a_format =
                        tile_a_east_format[WEST_NODE*32 +: 32];
                    assign tile_a_scale = tile_a_east_scale[WEST_NODE*128 +: 128];
                    assign tile_a_block_first =
                        tile_a_east_block_first[WEST_NODE*16 +: 16];
                    assign tile_a_block_last =
                        tile_a_east_block_last[WEST_NODE*16 +: 16];
                    assign tile_a_matrix_first =
                        tile_a_east_matrix_first[WEST_NODE*16 +: 16];
                    assign tile_a_matrix_last =
                        tile_a_east_matrix_last[WEST_NODE*16 +: 16];
                    assign tile_a_tag = tile_a_east_tag[WEST_NODE*128 +: 128];
                end

                if (tile_y == 0) begin : gen_b_array_boundary
                    assign tile_b_valid = b_skewed_valid[tile_x*16 +: 16];
                    assign tile_b_data = b_skewed_data[tile_x*128 +: 128];
                    assign tile_b_format = b_skewed_format[tile_x*32 +: 32];
                    assign tile_b_scale = b_skewed_scale[tile_x*128 +: 128];
                end else begin : gen_b_from_north_tile
                    localparam int unsigned NORTH_NODE = NODE_INDEX - ARRAY_X;
                    assign tile_b_valid =
                        tile_b_south_valid[NORTH_NODE*16 +: 16];
                    assign tile_b_data =
                        tile_b_south_data[NORTH_NODE*128 +: 128];
                    assign tile_b_format =
                        tile_b_south_format[NORTH_NODE*32 +: 32];
                    assign tile_b_scale =
                        tile_b_south_scale[NORTH_NODE*128 +: 128];
                end

                TILE_FP8_16_FIFO #(
                    .DAZ (DAZ),
                    .FTZ (FTZ)
                ) u_tile (
                    .clk_i                  (clk_i),
                    .rst_i                  (tile_rst[NODE_INDEX]),
                    .clear_i                (tile_clear[NODE_INDEX]),
                    .a_valid_i              (tile_a_valid),
                    .a_data_i               (tile_a_data),
                    .a_format_i             (tile_a_format),
                    .a_scale_i              (tile_a_scale),
                    .a_block_first_i        (tile_a_block_first),
                    .a_block_last_i         (tile_a_block_last),
                    .a_matrix_first_i       (tile_a_matrix_first),
                    .a_matrix_last_i        (tile_a_matrix_last),
                    .a_tag_i                (tile_a_tag),
                    .b_valid_i              (tile_b_valid),
                    .b_data_i               (tile_b_data),
                    .b_format_i             (tile_b_format),
                    .b_scale_i              (tile_b_scale),
                    .a_east_valid_o         (
                        tile_a_east_valid[NODE_INDEX*16 +: 16]),
                    .a_east_data_o          (
                        tile_a_east_data[NODE_INDEX*128 +: 128]),
                    .a_east_format_o        (
                        tile_a_east_format[NODE_INDEX*32 +: 32]),
                    .a_east_scale_o         (
                        tile_a_east_scale[NODE_INDEX*128 +: 128]),
                    .a_east_block_first_o   (
                        tile_a_east_block_first[NODE_INDEX*16 +: 16]),
                    .a_east_block_last_o    (
                        tile_a_east_block_last[NODE_INDEX*16 +: 16]),
                    .a_east_matrix_first_o  (
                        tile_a_east_matrix_first[NODE_INDEX*16 +: 16]),
                    .a_east_matrix_last_o   (
                        tile_a_east_matrix_last[NODE_INDEX*16 +: 16]),
                    .a_east_tag_o           (
                        tile_a_east_tag[NODE_INDEX*128 +: 128]),
                    .b_south_valid_o        (
                        tile_b_south_valid[NODE_INDEX*16 +: 16]),
                    .b_south_data_o         (
                        tile_b_south_data[NODE_INDEX*128 +: 128]),
                    .b_south_format_o       (
                        tile_b_south_format[NODE_INDEX*32 +: 32]),
                    .b_south_scale_o        (
                        tile_b_south_scale[NODE_INDEX*128 +: 128]),
                    .result_ready_i         (result_ready_i[NODE_INDEX]),
                    .result_valid_o         (result_valid_o[NODE_INDEX]),
                    .result_data_o          (
                        result_data_o[NODE_INDEX*512 +: 512]),
                    .result_invalid_o       (
                        result_invalid_o[NODE_INDEX*16 +: 16]),
                    .result_tag_o           (result_tag_o[NODE_INDEX*8 +: 8]),
                    .result_row_o           (result_row_o[NODE_INDEX*4 +: 4]),
                    .result_level_o         (
                        result_level_o[NODE_INDEX*6 +: 6]),
                    .input_issue_o          (input_pair_issue_o[NODE_INDEX]),
                    .output_overflow_o      (output_overflow_o[NODE_INDEX])
                );
            end
        end
    endgenerate

    initial begin
        assert ((ARRAY_X > 0) && (ARRAY_X <= 16))
            else $error("GEMM_65536 ARRAY_X must be in 1..16");
        assert ((ARRAY_Y > 0) && (ARRAY_Y <= 16))
            else $error("GEMM_65536 ARRAY_Y must be in 1..16");
    end

endmodule

`default_nettype wire
