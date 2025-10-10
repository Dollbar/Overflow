`timescale 1ns/1ps
`default_nettype none

// 256个16x16 FP8 Tile组成的最终计算阵列，共包含65536个PE。
// 直接模式使用A向东、B向南的数据通路；路由模式使用每Tile一个双VC XY Router。
module GEMM_65536 #(
    parameter integer ARRAY_X = 16,
    parameter integer ARRAY_Y = 16,
    parameter bit DAZ = 1'b0,
    parameter bit FTZ = 1'b0,
    parameter bit STATIC_WEIGHT_MODE = 1'b0,
    parameter bit ENABLE_K_ACCUMULATION = 1'b1,
    parameter integer CONTROL_TREE_FANOUT = 16,
    parameter integer ACTIVE_CONTEXTS = 16,
    parameter bit ROOT_ONLY_INJECTION = 1'b1
) (
    input  logic                         clk_i,
    input  logic                         rst_i,
    input  logic                         clear_i,

    input  logic [ARRAY_X*ARRAY_Y-1:0]  routed_mode_i,
    output logic [ARRAY_X*ARRAY_Y-1:0]  routed_mode_o,

    input  logic [ARRAY_Y-1:0]          direct_a_valid_i,
    output logic [ARRAY_Y-1:0]          direct_a_ready_o,
    input  logic [ARRAY_Y*128-1:0]      direct_a_data_i,
    input  logic [ARRAY_Y-1:0]          direct_a_format_i,
    input  logic [ARRAY_Y*2-1:0]        direct_a_rounding_i,
    input  logic [ARRAY_X-1:0]          direct_b_valid_i,
    output logic [ARRAY_X-1:0]          direct_b_ready_o,
    input  logic [ARRAY_X*128-1:0]      direct_b_data_i,
    input  logic [ARRAY_X-1:0]          direct_b_format_i,

    input  logic [ARRAY_Y-1:0]          direct_a_east_ready_i,
    output logic [ARRAY_Y-1:0]          direct_a_east_valid_o,
    output logic [ARRAY_Y*128-1:0]      direct_a_east_data_o,
    output logic [ARRAY_Y-1:0]          direct_a_east_format_o,
    output logic [ARRAY_Y*2-1:0]        direct_a_east_rounding_o,
    output logic [ARRAY_Y*8-1:0]        direct_a_east_tag_o,
    output logic [ARRAY_Y*5-1:0]        direct_a_east_tiles_left_o,
    input  logic [ARRAY_X-1:0]          direct_b_south_ready_i,
    output logic [ARRAY_X-1:0]          direct_b_south_valid_o,
    output logic [ARRAY_X*128-1:0]      direct_b_south_data_o,
    output logic [ARRAY_X-1:0]          direct_b_south_format_o,
    output logic [ARRAY_X*4-1:0]        direct_b_south_column_o,
    output logic [ARRAY_X*8-1:0]        direct_b_south_tag_o,
    output logic [ARRAY_X*5-1:0]        direct_b_south_tiles_left_o,

    // Bits above zero are retained only for ROOT_ONLY_INJECTION=0 legacy
    // integration; the production root-only configuration intentionally
    // ignores them.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [ARRAY_X*ARRAY_Y-1:0]  noc_tx_valid_i,
    output logic [ARRAY_X*ARRAY_Y-1:0]  noc_tx_ready_o,
    input  logic [ARRAY_X*ARRAY_Y-1:0]  noc_tx_vc_i,
    input  logic [ARRAY_X*ARRAY_Y*160-1:0] noc_tx_flit_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [ARRAY_X*ARRAY_Y-1:0]  noc_rx_valid_o,
    input  logic [ARRAY_X*ARRAY_Y-1:0]  noc_rx_ready_i,
    output logic [ARRAY_X*ARRAY_Y-1:0]  noc_rx_vc_o,
    output logic [ARRAY_X*ARRAY_Y*160-1:0] noc_rx_flit_o,
    output logic                         root_protocol_error_o,
    output logic                         root_context_full_o,

    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [ARRAY_X*ARRAY_Y-1:0]  accumulate_start_i,
    input  logic [ARRAY_X*ARRAY_Y*5-1:0] accumulate_rows_i,
    input  logic [ARRAY_X*ARRAY_Y*16-1:0] accumulate_k_blocks_i,
    input  logic [ARRAY_X*ARRAY_Y*2-1:0] accumulate_rounding_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [ARRAY_X*ARRAY_Y-1:0]  accumulate_start_ready_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  accumulate_busy_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  accumulate_block_done_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  accumulate_done_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  accumulate_protocol_error_o,

    input  logic [ARRAY_X*ARRAY_Y-1:0]  result_ready_i,
    output logic [ARRAY_X*ARRAY_Y-1:0]  result_valid_o,
    output logic [ARRAY_X*ARRAY_Y*512-1:0] result_data_o,
    output logic [ARRAY_X*ARRAY_Y*16-1:0] result_invalid_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  input_pair_issue_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  weights_loaded_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  weight_block_loaded_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  resident_weight_tag_valid_o,
    output logic [ARRAY_X*ARRAY_Y*8-1:0] resident_weight_tag_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  tile_tag_protocol_error_o,
    output logic [ARRAY_X*ARRAY_Y-1:0]  output_overflow_o,
    output logic                         boundary_error_o
);

    localparam integer NODE_COUNT = ARRAY_X * ARRAY_Y;
    localparam integer DIR_NORTH = 0;
    localparam integer DIR_EAST = 1;
    localparam integer DIR_SOUTH = 2;
    localparam integer DIR_WEST = 3;

    logic [NODE_COUNT-1:0] tile_a_ready;
    logic [NODE_COUNT-1:0] tile_a_east_ready;
    logic [NODE_COUNT-1:0] tile_a_east_valid;
    logic [NODE_COUNT*128-1:0] tile_a_east_data;
    logic [NODE_COUNT-1:0] tile_a_east_format;
    logic [NODE_COUNT*2-1:0] tile_a_east_rounding;
    logic [NODE_COUNT*8-1:0] tile_a_east_tag;
    logic [NODE_COUNT*5-1:0] tile_a_east_tiles_left;
    logic [NODE_COUNT-1:0] tile_b_ready;
    logic [NODE_COUNT-1:0] tile_b_south_ready;
    logic [NODE_COUNT-1:0] tile_b_south_valid;
    logic [NODE_COUNT*128-1:0] tile_b_south_data;
    logic [NODE_COUNT-1:0] tile_b_south_format;
    logic [NODE_COUNT*8-1:0] tile_b_south_tag;
    logic [NODE_COUNT*5-1:0] tile_b_south_tiles_left;
    // 中间行只转发B数据；column计数仅在最南边界作为可观察状态输出。
    /* verilator lint_off UNUSEDSIGNAL */
    logic [NODE_COUNT*4-1:0] tile_b_south_column;
    /* verilator lint_on UNUSEDSIGNAL */

    logic [3:0] noc_in_valid [0:NODE_COUNT-1];
    logic [7:0] noc_in_ready [0:NODE_COUNT-1];
    logic [3:0] noc_in_vc [0:NODE_COUNT-1];
    logic [639:0] noc_in_flit [0:NODE_COUNT-1];
    logic [3:0] noc_out_valid [0:NODE_COUNT-1];
    logic [3:0] noc_out_ready [0:NODE_COUNT-1];
    logic [3:0] noc_out_vc [0:NODE_COUNT-1];
    logic [639:0] noc_out_flit [0:NODE_COUNT-1];
    logic [NODE_COUNT-1:0] boundary_escape;
    logic [NODE_COUNT-1:0] tile_rst;
    logic [NODE_COUNT-1:0] tile_clear;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [NODE_COUNT-1:0] tile_accumulator_rst;
    logic [NODE_COUNT-1:0] tile_accumulator_clear;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [NODE_COUNT-1:0] tile_noc_tx_valid;
    // Non-root ready bits are configuration-dependent for the same reason.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [NODE_COUNT-1:0] tile_noc_tx_ready;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [NODE_COUNT-1:0] tile_noc_tx_vc;
    logic [NODE_COUNT*160-1:0] tile_noc_tx_flit;

    generate
        if (ROOT_ONLY_INJECTION) begin : gen_root_dispatcher
            gemm_root_dispatcher #(
                .ARRAY_X (ARRAY_X),
                .ARRAY_Y (ARRAY_Y),
                .ACTIVE_CONTEXTS (ACTIVE_CONTEXTS)
            ) u_root_dispatcher (
                .clk_i            (clk_i),
                .rst_i            (rst_i),
                .clear_i          (clear_i),
                .in_valid_i       (noc_tx_valid_i[0]),
                .in_ready_o       (noc_tx_ready_o[0]),
                .in_vc_i          (noc_tx_vc_i[0]),
                .in_flit_i        (noc_tx_flit_i[0 +: 160]),
                .out_valid_o      (tile_noc_tx_valid[0]),
                .out_ready_i      (tile_noc_tx_ready[0]),
                .out_vc_o         (tile_noc_tx_vc[0]),
                .out_flit_o       (tile_noc_tx_flit[0 +: 160]),
                .protocol_error_o (root_protocol_error_o),
                .context_full_o   (root_context_full_o)
            );
        end else begin : gen_legacy_root_injection
            assign tile_noc_tx_valid[0] = noc_tx_valid_i[0];
            assign noc_tx_ready_o[0] = tile_noc_tx_ready[0];
            assign tile_noc_tx_vc[0] = noc_tx_vc_i[0];
            assign tile_noc_tx_flit[0 +: 160] = noc_tx_flit_i[0 +: 160];
            assign root_protocol_error_o = 1'b0;
            assign root_context_full_o = 1'b0;
        end
    endgenerate

    assign boundary_error_o = |boundary_escape;

    // rst_i and clear_i are synchronous controls.  Equal-depth registered
    // trees bound the top-level fanout and make every Tile observe each control
    // on the same cycle.  Inputs must remain asserted for at least one clk_i
    // cycle; a Tile observes the assertion three cycles after input sampling.
    gemm_control_tree #(
        .NODE_COUNT (NODE_COUNT),
        .BRANCH_FANOUT (CONTROL_TREE_FANOUT)
    ) u_rst_tree (
        .clk_i     (clk_i),
        .control_i (rst_i),
        .control_o (tile_rst)
    );

    gemm_control_tree #(
        .NODE_COUNT (NODE_COUNT),
        .BRANCH_FANOUT (CONTROL_TREE_FANOUT)
    ) u_clear_tree (
        .clk_i     (clk_i),
        .control_i (clear_i),
        .control_o (tile_clear)
    );

    generate
        if (ENABLE_K_ACCUMULATION) begin : gen_accumulator_control_trees
            // The exact K-state banks and final converters are a separate
            // physical reset domain branch.  Both trees have the same depth,
            // so Tile compute and accumulator controls still change together.
            gemm_control_tree #(
                .NODE_COUNT (NODE_COUNT),
                .BRANCH_FANOUT (CONTROL_TREE_FANOUT)
            ) u_accumulator_rst_tree (
                .clk_i     (clk_i),
                .control_i (rst_i),
                .control_o (tile_accumulator_rst)
            );

            gemm_control_tree #(
                .NODE_COUNT (NODE_COUNT),
                .BRANCH_FANOUT (CONTROL_TREE_FANOUT)
            ) u_accumulator_clear_tree (
                .clk_i     (clk_i),
                .control_i (clear_i),
                .control_o (tile_accumulator_clear)
            );
        end else begin : gen_no_accumulator_control_trees
            assign tile_accumulator_rst = '0;
            assign tile_accumulator_clear = '0;
        end
    endgenerate

    generate
        for (genvar tile_y = 0; tile_y < ARRAY_Y; tile_y = tile_y + 1) begin : gen_tile_y
            for (genvar tile_x = 0; tile_x < ARRAY_X; tile_x = tile_x + 1) begin : gen_tile_x
                localparam integer NODE_INDEX = tile_y * ARRAY_X + tile_x;
                localparam logic [3:0] NODE_X = tile_x[3:0];
                localparam logic [3:0] NODE_Y = tile_y[3:0];

                if (NODE_INDEX != 0) begin : gen_nonroot_injection
                    if (ROOT_ONLY_INJECTION) begin : gen_disable_external_injection
                        assign tile_noc_tx_valid[NODE_INDEX] = 1'b0;
                        assign noc_tx_ready_o[NODE_INDEX] = 1'b0;
                        assign tile_noc_tx_vc[NODE_INDEX] = 1'b0;
                        assign tile_noc_tx_flit[NODE_INDEX*160 +: 160] = 160'd0;
                    end else begin : gen_legacy_external_injection
                        assign tile_noc_tx_valid[NODE_INDEX] =
                            noc_tx_valid_i[NODE_INDEX];
                        assign noc_tx_ready_o[NODE_INDEX] =
                            tile_noc_tx_ready[NODE_INDEX];
                        assign tile_noc_tx_vc[NODE_INDEX] =
                            noc_tx_vc_i[NODE_INDEX];
                        assign tile_noc_tx_flit[NODE_INDEX*160 +: 160] =
                            noc_tx_flit_i[NODE_INDEX*160 +: 160];
                    end
                end

                wire tile_a_valid;
                wire [127:0] tile_a_data;
                wire tile_a_format;
                wire [1:0] tile_a_rounding;
                wire [7:0] tile_a_tag;
                wire [4:0] tile_a_tiles_left;
                wire tile_b_valid;
                wire [127:0] tile_b_data;
                wire tile_b_format;
                wire [7:0] tile_b_tag;
                wire [4:0] tile_b_tiles_left;
                wire tile_raw_result_ready;
                /* verilator lint_off UNUSEDSIGNAL */
                wire tile_raw_result_valid;
                wire [511:0] tile_raw_result_data;
                wire [15:0] tile_raw_result_invalid;
                /* verilator lint_on UNUSEDSIGNAL */
                wire tile_exact_result_ready;
                // These Tile outputs are intentionally unused when the
                // ENABLE_K_ACCUMULATION generate branch is disabled.
                /* verilator lint_off UNUSEDSIGNAL */
                wire tile_exact_result_valid;
                wire [1103:0] tile_exact_result_sum;
                wire [31:0] tile_exact_result_special;
                wire [31:0] tile_exact_result_zero_sign;
                wire [15:0] tile_exact_result_invalid;
                wire [31:0] tile_exact_result_rounding;
                /* verilator lint_on UNUSEDSIGNAL */
                if (tile_x == 0) begin : gen_a_west_boundary
                    assign tile_a_valid = direct_a_valid_i[tile_y];
                    assign tile_a_data = direct_a_data_i[tile_y*128 +: 128];
                    assign tile_a_format = direct_a_format_i[tile_y];
                    assign tile_a_rounding = direct_a_rounding_i[tile_y*2 +: 2];
                    assign tile_a_tag = 8'd0;
                    assign tile_a_tiles_left = ARRAY_X[4:0];
                    assign direct_a_ready_o[tile_y] = tile_a_ready[NODE_INDEX];
                end else begin : gen_a_from_west
                    localparam integer WEST_NODE = NODE_INDEX - 1;
                    wire [143:0] a_link_input_payload;
                    wire [143:0] a_link_output_payload;

                    assign a_link_input_payload = {
                        tile_a_east_tag[WEST_NODE*8 +: 8],
                        tile_a_east_tiles_left[WEST_NODE*5 +: 5],
                        tile_a_east_rounding[WEST_NODE*2 +: 2],
                        tile_a_east_format[WEST_NODE],
                        tile_a_east_data[WEST_NODE*128 +: 128]
                    };
                    assign tile_a_data = a_link_output_payload[127:0];
                    assign tile_a_format = a_link_output_payload[128];
                    assign tile_a_rounding = a_link_output_payload[130:129];
                    assign tile_a_tiles_left = a_link_output_payload[135:131];
                    assign tile_a_tag = a_link_output_payload[143:136];

                    tile_direct_link_buffer #(
                        .WIDTH (144)
                    ) u_a_link_buffer (
                        .clk_i          (clk_i),
                        .rst_i          (tile_rst[NODE_INDEX]),
                        .clear_i        (tile_clear[NODE_INDEX]),
                        .input_valid_i  (tile_a_east_valid[WEST_NODE]),
                        .input_ready_o  (tile_a_east_ready[WEST_NODE]),
                        .input_data_i   (a_link_input_payload),
                        .output_valid_o (tile_a_valid),
                        .output_ready_i (tile_a_ready[NODE_INDEX]),
                        .output_data_o  (a_link_output_payload)
                    );
                end

                if (tile_x == ARRAY_X-1) begin : gen_a_east_boundary
                    assign tile_a_east_ready[NODE_INDEX] =
                        direct_a_east_ready_i[tile_y];
                    assign direct_a_east_valid_o[tile_y] = tile_a_east_valid[NODE_INDEX];
                    assign direct_a_east_data_o[tile_y*128 +: 128] =
                        tile_a_east_data[NODE_INDEX*128 +: 128];
                    assign direct_a_east_format_o[tile_y] = tile_a_east_format[NODE_INDEX];
                    assign direct_a_east_rounding_o[tile_y*2 +: 2] =
                        tile_a_east_rounding[NODE_INDEX*2 +: 2];
                    assign direct_a_east_tag_o[tile_y*8 +: 8] =
                        tile_a_east_tag[NODE_INDEX*8 +: 8];
                    assign direct_a_east_tiles_left_o[tile_y*5 +: 5] =
                        tile_a_east_tiles_left[NODE_INDEX*5 +: 5];
                end

                if (tile_y == 0) begin : gen_b_north_boundary
                    assign tile_b_valid = direct_b_valid_i[tile_x];
                    assign tile_b_data = direct_b_data_i[tile_x*128 +: 128];
                    assign tile_b_format = direct_b_format_i[tile_x];
                    assign tile_b_tag = 8'd0;
                    assign tile_b_tiles_left = ARRAY_Y[4:0];
                    assign direct_b_ready_o[tile_x] = tile_b_ready[NODE_INDEX];
                end else begin : gen_b_from_north
                    localparam integer NORTH_NODE = NODE_INDEX - ARRAY_X;
                    wire [141:0] b_link_input_payload;
                    wire [141:0] b_link_output_payload;

                    assign b_link_input_payload = {
                        tile_b_south_tag[NORTH_NODE*8 +: 8],
                        tile_b_south_tiles_left[NORTH_NODE*5 +: 5],
                        tile_b_south_format[NORTH_NODE],
                        tile_b_south_data[NORTH_NODE*128 +: 128]
                    };
                    assign tile_b_data = b_link_output_payload[127:0];
                    assign tile_b_format = b_link_output_payload[128];
                    assign tile_b_tiles_left = b_link_output_payload[133:129];
                    assign tile_b_tag = b_link_output_payload[141:134];

                    tile_direct_link_buffer #(
                        .WIDTH (142)
                    ) u_b_link_buffer (
                        .clk_i          (clk_i),
                        .rst_i          (tile_rst[NODE_INDEX]),
                        .clear_i        (tile_clear[NODE_INDEX]),
                        .input_valid_i  (tile_b_south_valid[NORTH_NODE]),
                        .input_ready_o  (tile_b_south_ready[NORTH_NODE]),
                        .input_data_i   (b_link_input_payload),
                        .output_valid_o (tile_b_valid),
                        .output_ready_i (tile_b_ready[NODE_INDEX]),
                        .output_data_o  (b_link_output_payload)
                    );
                end

                if (tile_y == ARRAY_Y-1) begin : gen_b_south_boundary
                    assign tile_b_south_ready[NODE_INDEX] =
                        direct_b_south_ready_i[tile_x];
                    assign direct_b_south_valid_o[tile_x] = tile_b_south_valid[NODE_INDEX];
                    assign direct_b_south_data_o[tile_x*128 +: 128] =
                        tile_b_south_data[NODE_INDEX*128 +: 128];
                    assign direct_b_south_format_o[tile_x] = tile_b_south_format[NODE_INDEX];
                    assign direct_b_south_column_o[tile_x*4 +: 4] =
                        tile_b_south_column[NODE_INDEX*4 +: 4];
                    assign direct_b_south_tag_o[tile_x*8 +: 8] =
                        tile_b_south_tag[NODE_INDEX*8 +: 8];
                    assign direct_b_south_tiles_left_o[tile_x*5 +: 5] =
                        tile_b_south_tiles_left[NODE_INDEX*5 +: 5];
                end

                if (tile_y == 0) begin : gen_noc_north_boundary
                    assign noc_in_valid[NODE_INDEX][DIR_NORTH] = 1'b0;
                    assign noc_in_vc[NODE_INDEX][DIR_NORTH] = 1'b0;
                    assign noc_in_flit[NODE_INDEX][DIR_NORTH*160 +: 160] = '0;
                    assign noc_out_ready[NODE_INDEX][DIR_NORTH] = 1'b1;
                end else begin : gen_noc_north_link
                    localparam integer NORTH_NODE = NODE_INDEX - ARRAY_X;
                    assign noc_in_valid[NODE_INDEX][DIR_NORTH] =
                        noc_out_valid[NORTH_NODE][DIR_SOUTH];
                    assign noc_in_vc[NODE_INDEX][DIR_NORTH] =
                        noc_out_vc[NORTH_NODE][DIR_SOUTH];
                    assign noc_in_flit[NODE_INDEX][DIR_NORTH*160 +: 160] =
                        noc_out_flit[NORTH_NODE][DIR_SOUTH*160 +: 160];
                    assign noc_out_ready[NODE_INDEX][DIR_NORTH] =
                        noc_in_ready[NORTH_NODE]
                            [DIR_SOUTH*2 + noc_out_vc[NODE_INDEX][DIR_NORTH]];
                end

                if (tile_x == ARRAY_X-1) begin : gen_noc_east_boundary
                    assign noc_in_valid[NODE_INDEX][DIR_EAST] = 1'b0;
                    assign noc_in_vc[NODE_INDEX][DIR_EAST] = 1'b0;
                    assign noc_in_flit[NODE_INDEX][DIR_EAST*160 +: 160] = '0;
                    assign noc_out_ready[NODE_INDEX][DIR_EAST] = 1'b1;
                end else begin : gen_noc_east_link
                    localparam integer EAST_NODE = NODE_INDEX + 1;
                    assign noc_in_valid[NODE_INDEX][DIR_EAST] =
                        noc_out_valid[EAST_NODE][DIR_WEST];
                    assign noc_in_vc[NODE_INDEX][DIR_EAST] =
                        noc_out_vc[EAST_NODE][DIR_WEST];
                    assign noc_in_flit[NODE_INDEX][DIR_EAST*160 +: 160] =
                        noc_out_flit[EAST_NODE][DIR_WEST*160 +: 160];
                    assign noc_out_ready[NODE_INDEX][DIR_EAST] =
                        noc_in_ready[EAST_NODE]
                            [DIR_WEST*2 + noc_out_vc[NODE_INDEX][DIR_EAST]];
                end

                if (tile_y == ARRAY_Y-1) begin : gen_noc_south_boundary
                    assign noc_in_valid[NODE_INDEX][DIR_SOUTH] = 1'b0;
                    assign noc_in_vc[NODE_INDEX][DIR_SOUTH] = 1'b0;
                    assign noc_in_flit[NODE_INDEX][DIR_SOUTH*160 +: 160] = '0;
                    assign noc_out_ready[NODE_INDEX][DIR_SOUTH] = 1'b1;
                end else begin : gen_noc_south_link
                    localparam integer SOUTH_NODE = NODE_INDEX + ARRAY_X;
                    assign noc_in_valid[NODE_INDEX][DIR_SOUTH] =
                        noc_out_valid[SOUTH_NODE][DIR_NORTH];
                    assign noc_in_vc[NODE_INDEX][DIR_SOUTH] =
                        noc_out_vc[SOUTH_NODE][DIR_NORTH];
                    assign noc_in_flit[NODE_INDEX][DIR_SOUTH*160 +: 160] =
                        noc_out_flit[SOUTH_NODE][DIR_NORTH*160 +: 160];
                    assign noc_out_ready[NODE_INDEX][DIR_SOUTH] =
                        noc_in_ready[SOUTH_NODE]
                            [DIR_NORTH*2 + noc_out_vc[NODE_INDEX][DIR_SOUTH]];
                end

                if (tile_x == 0) begin : gen_noc_west_boundary
                    assign noc_in_valid[NODE_INDEX][DIR_WEST] = 1'b0;
                    assign noc_in_vc[NODE_INDEX][DIR_WEST] = 1'b0;
                    assign noc_in_flit[NODE_INDEX][DIR_WEST*160 +: 160] = '0;
                    assign noc_out_ready[NODE_INDEX][DIR_WEST] = 1'b1;
                end else begin : gen_noc_west_link
                    localparam integer WEST_NODE = NODE_INDEX - 1;
                    assign noc_in_valid[NODE_INDEX][DIR_WEST] =
                        noc_out_valid[WEST_NODE][DIR_EAST];
                    assign noc_in_vc[NODE_INDEX][DIR_WEST] =
                        noc_out_vc[WEST_NODE][DIR_EAST];
                    assign noc_in_flit[NODE_INDEX][DIR_WEST*160 +: 160] =
                        noc_out_flit[WEST_NODE][DIR_EAST*160 +: 160];
                    assign noc_out_ready[NODE_INDEX][DIR_WEST] =
                        noc_in_ready[WEST_NODE]
                            [DIR_EAST*2 + noc_out_vc[NODE_INDEX][DIR_WEST]];
                end

                assign boundary_escape[NODE_INDEX] =
                    ((tile_y == 0) && noc_out_valid[NODE_INDEX][DIR_NORTH]) ||
                    ((tile_x == ARRAY_X-1) && noc_out_valid[NODE_INDEX][DIR_EAST]) ||
                    ((tile_y == ARRAY_Y-1) && noc_out_valid[NODE_INDEX][DIR_SOUTH]) ||
                    ((tile_x == 0) && noc_out_valid[NODE_INDEX][DIR_WEST]);

                if (ENABLE_K_ACCUMULATION) begin : gen_k_accumulator
                    wire accumulator_partial_ready;
                    wire accumulator_result_valid;
                    wire [511:0] accumulator_result_data;
                    wire [15:0] accumulator_result_invalid;

                    assign tile_raw_result_ready = 1'b1;
                    assign tile_exact_result_ready = accumulator_partial_ready;
                    assign result_valid_o[NODE_INDEX] = accumulator_result_valid;
                    assign result_data_o[NODE_INDEX*512 +: 512] =
                        accumulator_result_data;
                    assign result_invalid_o[NODE_INDEX*16 +: 16] =
                        accumulator_result_invalid;

                    tile_fp32_k_accumulator #(
                        .FTZ (FTZ)
                    ) u_k_accumulator (
                        .clk_i            (clk_i),
                        .rst_i            (tile_accumulator_rst[NODE_INDEX]),
                        .clear_i          (tile_accumulator_clear[NODE_INDEX]),
                        .start_i          (accumulate_start_i[NODE_INDEX]),
                        .start_ready_o    (accumulate_start_ready_o[NODE_INDEX]),
                        .rows_i           (accumulate_rows_i[NODE_INDEX*5 +: 5]),
                        .k_blocks_i       (accumulate_k_blocks_i[
                                                NODE_INDEX*16 +: 16]),
                        .rounding_i       (fp8_pkg::fp8_rounding_e'(
                                              accumulate_rounding_i[NODE_INDEX*2 +: 2])),
                        .partial_valid_i  (tile_exact_result_valid),
                        .partial_ready_o  (accumulator_partial_ready),
                        .partial_exact_i  (tile_exact_result_sum),
                        .partial_special_i(tile_exact_result_special),
                        .partial_zero_sign_i(tile_exact_result_zero_sign),
                        .partial_invalid_i(tile_exact_result_invalid),
                        .result_ready_i   (result_ready_i[NODE_INDEX]),
                        .result_valid_o   (accumulator_result_valid),
                        .result_data_o    (accumulator_result_data),
                        .result_invalid_o (accumulator_result_invalid),
                        .busy_o           (accumulate_busy_o[NODE_INDEX]),
                        .block_done_o     (accumulate_block_done_o[NODE_INDEX]),
                        .done_o           (accumulate_done_o[NODE_INDEX]),
                        .protocol_error_o (accumulate_protocol_error_o[NODE_INDEX])
                    );
                end else begin : gen_no_k_accumulator
                    assign tile_raw_result_ready = result_ready_i[NODE_INDEX];
                    assign tile_exact_result_ready = 1'b1;
                    assign result_valid_o[NODE_INDEX] = tile_raw_result_valid;
                    assign result_data_o[NODE_INDEX*512 +: 512] =
                        tile_raw_result_data;
                    assign result_invalid_o[NODE_INDEX*16 +: 16] =
                        tile_raw_result_invalid;
                    assign accumulate_busy_o[NODE_INDEX] = 1'b0;
                    assign accumulate_start_ready_o[NODE_INDEX] = 1'b1;
                    assign accumulate_block_done_o[NODE_INDEX] = 1'b0;
                    assign accumulate_done_o[NODE_INDEX] = 1'b0;
                    assign accumulate_protocol_error_o[NODE_INDEX] = 1'b0;
                end

                TILE_FP8_16_NOC #(
                    .DAZ (DAZ),
                    .FTZ (FTZ),
                    .RUNTIME_COORDINATES (1'b1),
                    .STATIC_WEIGHT_MODE (STATIC_WEIGHT_MODE),
                    .EXACT_OUTPUT_MODE (ENABLE_K_ACCUMULATION)
                ) u_tile (
                    .clk_i                       (clk_i),
                    .rst_i                       (tile_rst[NODE_INDEX]),
                    .clear_i                     (tile_clear[NODE_INDEX]),
                    .local_x_i                   (NODE_X),
                    .local_y_i                   (NODE_Y),
                    .routed_mode_i               (routed_mode_i[NODE_INDEX]),
                    .routed_mode_o               (routed_mode_o[NODE_INDEX]),
                    .direct_a_valid_i            (tile_a_valid),
                    .direct_a_ready_o            (tile_a_ready[NODE_INDEX]),
                    .direct_a_data_i             (tile_a_data),
                    .direct_a_format_i           (fp8_pkg::fp8_format_e'(tile_a_format)),
                    .direct_a_rounding_i         (fp8_pkg::fp8_rounding_e'(tile_a_rounding)),
                    .direct_a_tag_i              (tile_a_tag),
                    .direct_a_tiles_left_i       (tile_a_tiles_left),
                    .direct_b_valid_i            (tile_b_valid),
                    .direct_b_ready_o            (tile_b_ready[NODE_INDEX]),
                    .direct_b_data_i             (tile_b_data),
                    .direct_b_format_i           (fp8_pkg::fp8_format_e'(tile_b_format)),
                    .direct_b_tag_i              (tile_b_tag),
                    .direct_b_tiles_left_i       (tile_b_tiles_left),
                    .direct_a_east_ready_i       (tile_a_east_ready[NODE_INDEX]),
                    .direct_a_east_valid_o       (tile_a_east_valid[NODE_INDEX]),
                    .direct_a_east_data_o        (tile_a_east_data[NODE_INDEX*128 +: 128]),
                    .direct_a_east_format_o      (tile_a_east_format[NODE_INDEX]),
                    .direct_a_east_rounding_o    (tile_a_east_rounding[NODE_INDEX*2 +: 2]),
                    .direct_a_east_tag_o         (tile_a_east_tag[NODE_INDEX*8 +: 8]),
                    .direct_a_east_tiles_left_o  (tile_a_east_tiles_left[NODE_INDEX*5 +: 5]),
                    .direct_b_south_ready_i      (tile_b_south_ready[NODE_INDEX]),
                    .direct_b_south_valid_o      (tile_b_south_valid[NODE_INDEX]),
                    .direct_b_south_data_o       (tile_b_south_data[NODE_INDEX*128 +: 128]),
                    .direct_b_south_format_o     (tile_b_south_format[NODE_INDEX]),
                    .direct_b_south_column_o     (tile_b_south_column[NODE_INDEX*4 +: 4]),
                    .direct_b_south_tag_o        (tile_b_south_tag[NODE_INDEX*8 +: 8]),
                    .direct_b_south_tiles_left_o (tile_b_south_tiles_left[NODE_INDEX*5 +: 5]),
                    .noc_in_valid_i              (noc_in_valid[NODE_INDEX]),
                    .noc_in_ready_o              (noc_in_ready[NODE_INDEX]),
                    .noc_in_vc_i                 (noc_in_vc[NODE_INDEX]),
                    .noc_in_flit_i               (noc_in_flit[NODE_INDEX]),
                    .noc_out_valid_o             (noc_out_valid[NODE_INDEX]),
                    .noc_out_ready_i             (noc_out_ready[NODE_INDEX]),
                    .noc_out_vc_o                (noc_out_vc[NODE_INDEX]),
                    .noc_out_flit_o              (noc_out_flit[NODE_INDEX]),
                    .noc_tx_valid_i              (tile_noc_tx_valid[NODE_INDEX]),
                    .noc_tx_ready_o              (tile_noc_tx_ready[NODE_INDEX]),
                    .noc_tx_vc_i                 (tile_noc_tx_vc[NODE_INDEX]),
                    .noc_tx_flit_i               (tile_noc_tx_flit[NODE_INDEX*160 +: 160]),
                    .noc_rx_valid_o              (noc_rx_valid_o[NODE_INDEX]),
                    .noc_rx_ready_i              (noc_rx_ready_i[NODE_INDEX]),
                    .noc_rx_vc_o                 (noc_rx_vc_o[NODE_INDEX]),
                    .noc_rx_flit_o               (noc_rx_flit_o[NODE_INDEX*160 +: 160]),
                    .result_ready_i              (tile_raw_result_ready),
                    .result_valid_o              (tile_raw_result_valid),
                    .result_data_o               (tile_raw_result_data),
                    .result_invalid_o            (tile_raw_result_invalid),
                    .exact_result_ready_i        (tile_exact_result_ready),
                    .exact_result_valid_o        (tile_exact_result_valid),
                    .exact_result_sum_o          (tile_exact_result_sum),
                    .exact_result_special_o      (tile_exact_result_special),
                    .exact_result_zero_sign_o    (tile_exact_result_zero_sign),
                    .exact_result_invalid_o      (tile_exact_result_invalid),
                    .exact_result_rounding_o     (tile_exact_result_rounding),
                    .input_pair_issue_o          (input_pair_issue_o[NODE_INDEX]),
                    .weights_loaded_o            (weights_loaded_o[NODE_INDEX]),
                    .weight_block_loaded_o       (weight_block_loaded_o[NODE_INDEX]),
                    .resident_weight_tag_valid_o (resident_weight_tag_valid_o[NODE_INDEX]),
                    .resident_weight_tag_o       (resident_weight_tag_o[NODE_INDEX*8 +: 8]),
                    .tag_protocol_error_o        (tile_tag_protocol_error_o[NODE_INDEX]),
                    .output_overflow_o           (output_overflow_o[NODE_INDEX])
                );
            end
        end
    endgenerate

endmodule

`default_nettype wire
