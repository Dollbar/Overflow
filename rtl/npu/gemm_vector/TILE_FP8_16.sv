`timescale 1ns/1ps

module TILE_FP8_16 #(
    parameter bit DAZ = 1'b0,
    parameter bit FTZ = 1'b0,
    parameter bit STATIC_WEIGHT_MODE = 1'b0,
    parameter bit FUSED16_REDUCTION = 1'b0,
    parameter bit EXACT_OUTPUT_MODE = 1'b0
) (
    input  logic                         clk_i,
    input  logic                         rst_i,
    input  logic                         clear_i,

    input  logic                         weight_load_valid_i,
    output logic                         weight_load_ready_o,
    input  logic                   [3:0] weight_load_column_i,
    input  logic                 [127:0] weight_load_data_i,
    input  fp8_pkg::fp8_format_e         weight_load_format_i,
    output logic                         weights_loaded_o,

    input  logic                         act_valid_i,
    output logic                         act_ready_o,
    input  logic                 [127:0] act_data_i,
    input  fp8_pkg::fp8_format_e         act_format_i,
    input  fp8_pkg::fp8_rounding_e       rounding_i,

    output logic                  [15:0] column_result_valid_o,
    output logic                 [511:0] column_result_data_o,
    output logic                  [15:0] column_result_invalid_o,

    output logic                  [15:0] column_exact_valid_o,
    output logic                [1103:0] column_exact_sum_o,
    output logic                  [31:0] column_exact_special_o,
    output logic                  [31:0] column_exact_zero_sign_o,
    output logic                  [15:0] column_exact_invalid_o,
    output logic                  [31:0] column_exact_rounding_o,

    output logic                  [15:0] act_right_valid_o,
    output logic                 [127:0] act_right_data_o,
    output logic                  [15:0] act_right_format_o
);

    localparam integer TILE_SIZE = 16;
    localparam integer PE_COUNT = TILE_SIZE * TILE_SIZE;
    localparam integer REDUCTION_GROUP_SIZE = 4;
    localparam integer GROUPS_PER_COLUMN = TILE_SIZE / REDUCTION_GROUP_SIZE;
    localparam integer REDUCER_COUNT = TILE_SIZE * GROUPS_PER_COLUMN;
    localparam integer PRODUCT_WIDTH = 21;
    localparam integer PE_CONTROL_GROUP_COUNT = 8;
    localparam integer PE_PER_CONTROL_GROUP = PE_COUNT / PE_CONTROL_GROUP_COUNT;
    localparam integer REDUCE_CONTROL_GROUP_COUNT = 8;
    localparam integer REDUCERS_PER_CONTROL_GROUP = REDUCER_COUNT /
                                                     REDUCE_CONTROL_GROUP_COUNT;
    localparam integer FINAL_REDUCER_COUNT = TILE_SIZE;
    localparam integer FINAL_CONTROL_GROUP_COUNT = 2;
    localparam integer FINAL_REDUCERS_PER_CONTROL_GROUP = FINAL_REDUCER_COUNT /
                                                           FINAL_CONTROL_GROUP_COUNT;

    logic [PE_CONTROL_GROUP_COUNT-1:0] pe_rst_group_q;
    logic [PE_CONTROL_GROUP_COUNT-1:0] pe_clear_group_q;
    logic [REDUCE_CONTROL_GROUP_COUNT-1:0] reduce_rst_group_q;
    logic [REDUCE_CONTROL_GROUP_COUNT-1:0] reduce_clear_group_q;
    logic [FINAL_CONTROL_GROUP_COUNT-1:0] final_rst_group_q;
    logic [FINAL_CONTROL_GROUP_COUNT-1:0] final_clear_group_q;

    logic tile_control_hold_q;
    logic stream_control_rst_q;
    logic stream_control_clear_q;
    logic tile_control_busy;
    logic stream_ready;
    logic weight_load_accept;
    logic act_issue_valid;
    logic [TILE_SIZE-1:0] weight_column_loaded_q;
    logic [TILE_SIZE-1:0] weight_format_q;
    logic [TILE_SIZE-1:0] pe_weight_format_bus;
    logic [TILE_SIZE-1:0] act_input_valid_q;
    logic [TILE_SIZE*8-1:0] act_input_data_q;
    logic [TILE_SIZE-1:0] act_input_format_q;
    logic [PE_COUNT-1:0] pe_act_valid_bus;
    logic [PE_COUNT*8-1:0] pe_act_data_bus;
    logic [PE_COUNT-1:0] pe_act_format_bus;
    logic [PE_COUNT-1:0] pe_product_valid_bus;
    logic [PE_COUNT*PRODUCT_WIDTH-1:0] pe_product_bus;
    logic [PE_COUNT-1:0] pe_invalid_bus;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [FINAL_REDUCER_COUNT-1:0] final_valid_bus;
    logic [FINAL_REDUCER_COUNT*32-1:0] final_data_bus;
    logic [FINAL_REDUCER_COUNT-1:0] final_invalid_bus;
    /* verilator lint_on UNUSEDSIGNAL */
    fp8_pkg::fp8_rounding_e rounding_tile_q;
    fp8_pkg::fp8_rounding_e rounding_column_q [0:TILE_SIZE-1];
    integer weight_format_index;
    integer rounding_column_index;

    generate
        (* keep = "true", dont_touch = "true" *)
        tile_control_replica #(
            .REPLICA_ID (PE_CONTROL_GROUP_COUNT + REDUCE_CONTROL_GROUP_COUNT +
                         FINAL_CONTROL_GROUP_COUNT)
        ) u_stream_control_replica (
            .clk_i   (clk_i),
            .rst_i   (rst_i),
            .clear_i (clear_i),
            .rst_o   (stream_control_rst_q),
            .clear_o (stream_control_clear_q)
        );

        for (genvar pe_control_group = 0;
             pe_control_group < PE_CONTROL_GROUP_COUNT;
             pe_control_group = pe_control_group + 1) begin : gen_pe_control_replicas
            (* keep = "true", dont_touch = "true" *)
            tile_control_replica #(
                .REPLICA_ID (pe_control_group)
            ) u_control_replica (
                .clk_i   (clk_i),
                .rst_i   (rst_i),
                .clear_i (clear_i),
                .rst_o   (pe_rst_group_q[pe_control_group]),
                .clear_o (pe_clear_group_q[pe_control_group])
            );
        end

        for (genvar reduce_control_group = 0;
             reduce_control_group < REDUCE_CONTROL_GROUP_COUNT;
             reduce_control_group = reduce_control_group + 1) begin : gen_reduce_control_replicas
            (* keep = "true", dont_touch = "true" *)
            tile_control_replica #(
                .REPLICA_ID (PE_CONTROL_GROUP_COUNT + reduce_control_group)
            ) u_control_replica (
                .clk_i   (clk_i),
                .rst_i   (rst_i),
                .clear_i (clear_i),
                .rst_o   (reduce_rst_group_q[reduce_control_group]),
                .clear_o (reduce_clear_group_q[reduce_control_group])
            );
        end

        for (genvar final_control_group = 0;
             final_control_group < FINAL_CONTROL_GROUP_COUNT;
             final_control_group = final_control_group + 1) begin : gen_final_control_replicas
            (* keep = "true", dont_touch = "true" *)
            tile_control_replica #(
                .REPLICA_ID (PE_CONTROL_GROUP_COUNT + REDUCE_CONTROL_GROUP_COUNT +
                             final_control_group)
            ) u_control_replica (
                .clk_i   (clk_i),
                .rst_i   (rst_i),
                .clear_i (clear_i),
                .rst_o   (final_rst_group_q[final_control_group]),
                .clear_o (final_clear_group_q[final_control_group])
            );
        end
    endgenerate

    generate
        for (genvar act_input_row = 0;
             act_input_row < TILE_SIZE;
             act_input_row = act_input_row + 1) begin : gen_act_input_slices
            (* keep = "true", dont_touch = "true" *)
            tile_act_input_slice #(
                .REPLICA_ID (act_input_row)
            ) u_act_input_slice (
                .clk_i    (clk_i),
                .rst_i    (rst_i),
                .clear_i  (clear_i),
                .hold_i   (tile_control_hold_q),
                .valid_i  (act_issue_valid),
                .data_i   (act_data_i[act_input_row*8 +: 8]),
                .format_i (act_format_i),
                .valid_o  (act_input_valid_q[act_input_row]),
                .data_o   (act_input_data_q[act_input_row*8 +: 8]),
                .format_o (act_input_format_q[act_input_row])
            );
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        tile_control_hold_q <= rst_i || clear_i;

        if (rst_i) begin
            weight_column_loaded_q <= '0;
            for (weight_format_index = 0;
                 weight_format_index < TILE_SIZE;
                 weight_format_index = weight_format_index + 1) begin
                weight_format_q[weight_format_index] <= fp8_pkg::FP8_E4M3;
            end
        end else if (weight_load_accept) begin
            weight_column_loaded_q[weight_load_column_i] <= 1'b1;
            weight_format_q[weight_load_column_i] <= weight_load_format_i;
        end

    end

    // Use the registered flush state for combinational handshakes.  The FIFO and
    // pipeline registers still sample rst_i/clear_i synchronously at the clock
    // edge, while this boundary prevents those high-fanout controls from being
    // placed directly on the ready path.
    assign tile_control_busy = stream_control_rst_q || stream_control_clear_q;
    assign stream_ready = !tile_control_busy;
    assign weights_loaded_o = (&weight_column_loaded_q) && !tile_control_busy;

    generate
        if (STATIC_WEIGHT_MODE) begin : gen_static_weight_protocol
            assign weight_load_ready_o = stream_ready;
            assign act_ready_o = weights_loaded_o && stream_ready &&
                                 !weight_load_valid_i;
            assign weight_load_accept = weight_load_valid_i &&
                                        weight_load_ready_o;
            assign act_issue_valid = act_valid_i && act_ready_o;
        end else begin : gen_dynamic_weight_protocol
            assign weight_load_ready_o = stream_ready && act_valid_i;
            assign act_ready_o = stream_ready && weight_load_valid_i;
            assign weight_load_accept = act_valid_i &&
                                        weight_load_valid_i && stream_ready;
            assign act_issue_valid = weight_load_accept;
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            rounding_tile_q <= fp8_pkg::RNE;
            for (rounding_column_index = 0;
                 rounding_column_index < TILE_SIZE;
                 rounding_column_index = rounding_column_index + 1) begin
                rounding_column_q[rounding_column_index] <= fp8_pkg::RNE;
            end
        end else begin
            rounding_tile_q <= rounding_i;
            rounding_column_q[0] <= rounding_tile_q;
            for (rounding_column_index = 1;
                 rounding_column_index < TILE_SIZE;
                 rounding_column_index = rounding_column_index + 1) begin
                rounding_column_q[rounding_column_index] <=
                    rounding_column_q[rounding_column_index-1];
            end
        end
    end

    generate
        for (genvar weight_format_column = 0;
             weight_format_column < TILE_SIZE;
             weight_format_column = weight_format_column + 1) begin : gen_weight_format_slices
            localparam logic [3:0] FORMAT_COLUMN_INDEX = weight_format_column;
            tile_weight_format_slice u_weight_format_slice (
                .select_i        (weight_load_accept &&
                                  (weight_load_column_i == FORMAT_COLUMN_INDEX)),
                .global_format_i (weight_load_format_i),
                .saved_format_i  (weight_format_q[weight_format_column]),
                .format_o        (pe_weight_format_bus[weight_format_column])
            );
        end

        for (genvar pe_row = 0; pe_row < TILE_SIZE; pe_row = pe_row + 1) begin : gen_pe_rows
            for (genvar pe_column = 0;
                 pe_column < TILE_SIZE;
                 pe_column = pe_column + 1) begin : gen_pe_columns
                localparam integer CELL_INDEX = pe_row * TILE_SIZE + pe_column;
                localparam integer CONTROL_GROUP = CELL_INDEX / PE_PER_CONTROL_GROUP;
                localparam logic [3:0] PE_COLUMN_INDEX = pe_column;
                logic weight_load_select;
                logic act_input_valid;
                logic [7:0] act_input_data;
                fp8_pkg::fp8_format_e act_input_format;

                assign weight_load_select = weight_load_accept &&
                                            (weight_load_column_i ==
                                             PE_COLUMN_INDEX);

                if (pe_column == 0) begin : gen_act_from_tile_boundary
                    assign act_input_valid = act_input_valid_q[pe_row];
                    assign act_input_data = act_input_data_q[pe_row*8 +: 8];
                    assign act_input_format =
                        fp8_pkg::fp8_format_e'(act_input_format_q[pe_row]);
                end else begin : gen_act_from_left_pe
                    assign act_input_valid = pe_act_valid_bus[CELL_INDEX-1];
                    assign act_input_data = pe_act_data_bus[(CELL_INDEX-1)*8 +: 8];
                    assign act_input_format =
                        fp8_pkg::fp8_format_e'(pe_act_format_bus[CELL_INDEX-1]);
                end

                PE_FP8 #(
                    .DAZ (DAZ)
                ) u_pe (
                    .clk_i           (clk_i),
                    .rst_i           (pe_rst_group_q[CONTROL_GROUP]),
                    .clear_i         (pe_clear_group_q[CONTROL_GROUP]),
                    .weight_load_i   (weight_load_select),
                    .weight_i        (weight_load_data_i[pe_row*8 +: 8]),
                    .weight_format_i (pe_weight_format_bus[pe_column]),
                    .act_valid_i     (act_input_valid),
                    .act_i           (act_input_data),
                    .act_format_i    (act_input_format),
                    /* verilator lint_off PINCONNECTEMPTY */
                    .weight_loaded_o (),
                    /* verilator lint_on PINCONNECTEMPTY */
                    .act_valid_o     (pe_act_valid_bus[CELL_INDEX]),
                    .act_o           (pe_act_data_bus[CELL_INDEX*8 +: 8]),
                    .act_format_o    (pe_act_format_bus[CELL_INDEX]),
                    .product_valid_o (pe_product_valid_bus[CELL_INDEX]),
                    .product_o       (pe_product_bus[CELL_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                    .invalid_o       (pe_invalid_bus[CELL_INDEX])
                );
            end
        end
    endgenerate

    generate
        if (FUSED16_REDUCTION || EXACT_OUTPUT_MODE) begin : gen_fused16_reduction
            logic [REDUCER_COUNT-1:0] reduce_valid_bus;
            logic [REDUCER_COUNT*67-1:0] reduce_exact_bus;
            logic [REDUCER_COUNT-1:0] reduce_invalid_bus;
            fp8_pkg::fp8_reduce_special_e reduce_special_bus [0:REDUCER_COUNT-1];
            fp8_pkg::fp8_reduce_zero_sign_e reduce_zero_sign_bus [0:REDUCER_COUNT-1];
            fp8_pkg::fp8_rounding_e reduce_rounding_bus [0:REDUCER_COUNT-1];

            for (genvar reduce_column = 0;
                 reduce_column < TILE_SIZE;
                 reduce_column = reduce_column + 1) begin : gen_reduce_columns
                for (genvar reduce_group = 0;
                     reduce_group < GROUPS_PER_COLUMN;
                     reduce_group = reduce_group + 1) begin : gen_reduce_groups
                    localparam integer NODE_INDEX = reduce_column * GROUPS_PER_COLUMN +
                                                    reduce_group;
                    localparam integer BASE_ROW = reduce_group * REDUCTION_GROUP_SIZE;
                    localparam integer PRODUCT0_INDEX = BASE_ROW * TILE_SIZE +
                                                        reduce_column;
                    localparam integer PRODUCT1_INDEX = (BASE_ROW + 1) * TILE_SIZE +
                                                        reduce_column;
                    localparam integer PRODUCT2_INDEX = (BASE_ROW + 2) * TILE_SIZE +
                                                        reduce_column;
                    localparam integer PRODUCT3_INDEX = (BASE_ROW + 3) * TILE_SIZE +
                                                        reduce_column;
                    localparam integer CONTROL_GROUP = NODE_INDEX /
                                                       REDUCERS_PER_CONTROL_GROUP;
                    logic group_product_valid;

                    assign group_product_valid = pe_product_valid_bus[PRODUCT0_INDEX] &&
                                                 pe_product_valid_bus[PRODUCT1_INDEX] &&
                                                 pe_product_valid_bus[PRODUCT2_INDEX] &&
                                                 pe_product_valid_bus[PRODUCT3_INDEX];

                    fp8_exact_reduce4 u_exact_reduce4 (
                        .clk_i       (clk_i),
                        .rst_i       (reduce_rst_group_q[CONTROL_GROUP]),
                        .clear_i     (reduce_clear_group_q[CONTROL_GROUP]),
                        .valid_i     (group_product_valid),
                        .product0_i  (pe_product_bus[PRODUCT0_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                        .product1_i  (pe_product_bus[PRODUCT1_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                        .product2_i  (pe_product_bus[PRODUCT2_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                        .product3_i  (pe_product_bus[PRODUCT3_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                        .invalid_i   ({pe_invalid_bus[PRODUCT3_INDEX],
                                       pe_invalid_bus[PRODUCT2_INDEX],
                                       pe_invalid_bus[PRODUCT1_INDEX],
                                       pe_invalid_bus[PRODUCT0_INDEX]}),
                        .rounding_i  (rounding_column_q[reduce_column]),
                        .valid_o     (reduce_valid_bus[NODE_INDEX]),
                        .exact_sum_o (reduce_exact_bus[NODE_INDEX*67 +: 67]),
                        .special_o   (reduce_special_bus[NODE_INDEX]),
                        .zero_sign_o (reduce_zero_sign_bus[NODE_INDEX]),
                        .invalid_o   (reduce_invalid_bus[NODE_INDEX]),
                        .rounding_o  (reduce_rounding_bus[NODE_INDEX])
                    );
                end

                localparam integer FINAL_CONTROL_GROUP = reduce_column /
                                                         FINAL_REDUCERS_PER_CONTROL_GROUP;
                localparam integer GROUP_BASE = reduce_column * GROUPS_PER_COLUMN;
                logic column_group_valid;

                assign column_group_valid = &reduce_valid_bus[GROUP_BASE +:
                                                               GROUPS_PER_COLUMN];

                if (EXACT_OUTPUT_MODE) begin : gen_exact_output
                    fp8_exact_partial4_reduce u_final_exact_reduce4 (
                        .clk_i        (clk_i),
                        .rst_i        (final_rst_group_q[FINAL_CONTROL_GROUP]),
                        .clear_i      (final_clear_group_q[FINAL_CONTROL_GROUP]),
                        .valid_i      (column_group_valid),
                        .exact0_i     ($signed(reduce_exact_bus[(GROUP_BASE + 0)*67 +: 67])),
                        .exact1_i     ($signed(reduce_exact_bus[(GROUP_BASE + 1)*67 +: 67])),
                        .exact2_i     ($signed(reduce_exact_bus[(GROUP_BASE + 2)*67 +: 67])),
                        .exact3_i     ($signed(reduce_exact_bus[(GROUP_BASE + 3)*67 +: 67])),
                        .special0_i   (reduce_special_bus[GROUP_BASE + 0]),
                        .special1_i   (reduce_special_bus[GROUP_BASE + 1]),
                        .special2_i   (reduce_special_bus[GROUP_BASE + 2]),
                        .special3_i   (reduce_special_bus[GROUP_BASE + 3]),
                        .zero_sign0_i (reduce_zero_sign_bus[GROUP_BASE + 0]),
                        .zero_sign1_i (reduce_zero_sign_bus[GROUP_BASE + 1]),
                        .zero_sign2_i (reduce_zero_sign_bus[GROUP_BASE + 2]),
                        .zero_sign3_i (reduce_zero_sign_bus[GROUP_BASE + 3]),
                        .invalid_i    (reduce_invalid_bus[GROUP_BASE +: GROUPS_PER_COLUMN]),
                        .rounding_i   (reduce_rounding_bus[GROUP_BASE]),
                        .valid_o      (column_exact_valid_o[reduce_column]),
                        .exact_sum_o  (column_exact_sum_o[reduce_column*69 +: 69]),
                        .special_o    (column_exact_special_o[reduce_column*2 +: 2]),
                        .zero_sign_o  (column_exact_zero_sign_o[reduce_column*2 +: 2]),
                        .invalid_o    (column_exact_invalid_o[reduce_column]),
                        .rounding_o   (column_exact_rounding_o[reduce_column*2 +: 2])
                    );

                    assign column_result_valid_o[reduce_column] = 1'b0;
                    assign column_result_data_o[reduce_column*32 +: 32] = 32'd0;
                    assign column_result_invalid_o[reduce_column] = 1'b0;
                end else begin : gen_fp32_output
                    fp8_exact_partial4_to_fp32 #(
                        .FTZ (FTZ)
                    ) u_final_exact_reduce4 (
                        .clk_i        (clk_i),
                        .rst_i        (final_rst_group_q[FINAL_CONTROL_GROUP]),
                        .clear_i      (final_clear_group_q[FINAL_CONTROL_GROUP]),
                        .valid_i      (column_group_valid),
                        .exact0_i     ($signed(reduce_exact_bus[(GROUP_BASE + 0)*67 +: 67])),
                        .exact1_i     ($signed(reduce_exact_bus[(GROUP_BASE + 1)*67 +: 67])),
                        .exact2_i     ($signed(reduce_exact_bus[(GROUP_BASE + 2)*67 +: 67])),
                        .exact3_i     ($signed(reduce_exact_bus[(GROUP_BASE + 3)*67 +: 67])),
                        .special0_i   (reduce_special_bus[GROUP_BASE + 0]),
                        .special1_i   (reduce_special_bus[GROUP_BASE + 1]),
                        .special2_i   (reduce_special_bus[GROUP_BASE + 2]),
                        .special3_i   (reduce_special_bus[GROUP_BASE + 3]),
                        .zero_sign0_i (reduce_zero_sign_bus[GROUP_BASE + 0]),
                        .zero_sign1_i (reduce_zero_sign_bus[GROUP_BASE + 1]),
                        .zero_sign2_i (reduce_zero_sign_bus[GROUP_BASE + 2]),
                        .zero_sign3_i (reduce_zero_sign_bus[GROUP_BASE + 3]),
                        .invalid_i    (reduce_invalid_bus[GROUP_BASE +: GROUPS_PER_COLUMN]),
                        .rounding_i   (reduce_rounding_bus[GROUP_BASE]),
                        .valid_o      (final_valid_bus[reduce_column]),
                        .result_o     (final_data_bus[reduce_column*32 +: 32]),
                        .invalid_o    (final_invalid_bus[reduce_column])
                    );

                    assign column_result_valid_o[reduce_column] =
                        final_valid_bus[reduce_column] && !tile_control_busy;
                    assign column_result_data_o[reduce_column*32 +: 32] =
                        final_data_bus[reduce_column*32 +: 32];
                    assign column_result_invalid_o[reduce_column] =
                        final_invalid_bus[reduce_column] &&
                        final_valid_bus[reduce_column] && !tile_control_busy;
                    assign column_exact_valid_o[reduce_column] = 1'b0;
                    assign column_exact_sum_o[reduce_column*69 +: 69] = 69'd0;
                    assign column_exact_special_o[reduce_column*2 +: 2] = 2'd0;
                    assign column_exact_zero_sign_o[reduce_column*2 +: 2] = 2'd0;
                    assign column_exact_invalid_o[reduce_column] = 1'b0;
                    assign column_exact_rounding_o[reduce_column*2 +: 2] = 2'd0;
                end
            end
        end else begin : gen_block_fp32_reduction
            logic [REDUCER_COUNT-1:0] reduce_valid_bus;
            logic [REDUCER_COUNT*32-1:0] reduce_data_bus;
            logic [REDUCER_COUNT-1:0] reduce_invalid_bus;
            fp8_pkg::fp8_rounding_e reduce_rounding_bus [0:REDUCER_COUNT-1];

            for (genvar reduce_column = 0;
                 reduce_column < TILE_SIZE;
                 reduce_column = reduce_column + 1) begin : gen_reduce_columns
                assign column_exact_valid_o[reduce_column] = 1'b0;
                assign column_exact_sum_o[reduce_column*69 +: 69] = 69'd0;
                assign column_exact_special_o[reduce_column*2 +: 2] = 2'd0;
                assign column_exact_zero_sign_o[reduce_column*2 +: 2] = 2'd0;
                assign column_exact_invalid_o[reduce_column] = 1'b0;
                assign column_exact_rounding_o[reduce_column*2 +: 2] = 2'd0;
                for (genvar reduce_group = 0;
                     reduce_group < GROUPS_PER_COLUMN;
                     reduce_group = reduce_group + 1) begin : gen_reduce_groups
                    localparam integer NODE_INDEX = reduce_column * GROUPS_PER_COLUMN +
                                                    reduce_group;
                    localparam integer BASE_ROW = reduce_group * REDUCTION_GROUP_SIZE;
                    localparam integer PRODUCT0_INDEX = BASE_ROW * TILE_SIZE +
                                                        reduce_column;
                    localparam integer PRODUCT1_INDEX = (BASE_ROW + 1) * TILE_SIZE +
                                                        reduce_column;
                    localparam integer PRODUCT2_INDEX = (BASE_ROW + 2) * TILE_SIZE +
                                                        reduce_column;
                    localparam integer PRODUCT3_INDEX = (BASE_ROW + 3) * TILE_SIZE +
                                                        reduce_column;
                    localparam integer CONTROL_GROUP = NODE_INDEX /
                                                       REDUCERS_PER_CONTROL_GROUP;
                    logic group_product_valid;

                    assign group_product_valid = pe_product_valid_bus[PRODUCT0_INDEX] &&
                                                 pe_product_valid_bus[PRODUCT1_INDEX] &&
                                                 pe_product_valid_bus[PRODUCT2_INDEX] &&
                                                 pe_product_valid_bus[PRODUCT3_INDEX];

                    fp8_fused_reduce4 #(
                        .FTZ (FTZ)
                    ) u_reduce4 (
                        .clk_i       (clk_i),
                        .rst_i       (reduce_rst_group_q[CONTROL_GROUP]),
                        .clear_i     (reduce_clear_group_q[CONTROL_GROUP]),
                        .valid_i     (group_product_valid),
                        .product0_i  (pe_product_bus[PRODUCT0_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                        .product1_i  (pe_product_bus[PRODUCT1_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                        .product2_i  (pe_product_bus[PRODUCT2_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                        .product3_i  (pe_product_bus[PRODUCT3_INDEX*PRODUCT_WIDTH +:
                                                    PRODUCT_WIDTH]),
                        .invalid_i   ({pe_invalid_bus[PRODUCT3_INDEX],
                                       pe_invalid_bus[PRODUCT2_INDEX],
                                       pe_invalid_bus[PRODUCT1_INDEX],
                                       pe_invalid_bus[PRODUCT0_INDEX]}),
                        .rounding_i  (rounding_column_q[reduce_column]),
                        .valid_o     (reduce_valid_bus[NODE_INDEX]),
                        .result_o    (reduce_data_bus[NODE_INDEX*32 +: 32]),
                        .invalid_o   (reduce_invalid_bus[NODE_INDEX]),
                        .rounding_o  (reduce_rounding_bus[NODE_INDEX])
                    );
                end

                localparam integer FINAL_CONTROL_GROUP = reduce_column /
                                                         FINAL_REDUCERS_PER_CONTROL_GROUP;
                localparam integer GROUP_BASE = reduce_column * GROUPS_PER_COLUMN;
                logic column_group_valid;

                assign column_group_valid = &reduce_valid_bus[GROUP_BASE +:
                                                               GROUPS_PER_COLUMN];

                fp8_partial_reduce4 #(
                    .FTZ (FTZ)
                ) u_final_reduce4 (
                    .clk_i      (clk_i),
                    .rst_i      (final_rst_group_q[FINAL_CONTROL_GROUP]),
                    .clear_i    (final_clear_group_q[FINAL_CONTROL_GROUP]),
                    .valid_i    (column_group_valid),
                    .partial0_i (reduce_data_bus[(GROUP_BASE + 0)*32 +: 32]),
                    .partial1_i (reduce_data_bus[(GROUP_BASE + 1)*32 +: 32]),
                    .partial2_i (reduce_data_bus[(GROUP_BASE + 2)*32 +: 32]),
                    .partial3_i (reduce_data_bus[(GROUP_BASE + 3)*32 +: 32]),
                    .invalid_i  (reduce_invalid_bus[GROUP_BASE +: GROUPS_PER_COLUMN]),
                    .rounding_i (reduce_rounding_bus[GROUP_BASE]),
                    .valid_o    (final_valid_bus[reduce_column]),
                    .result_o   (final_data_bus[reduce_column*32 +: 32]),
                    .invalid_o  (final_invalid_bus[reduce_column])
                );

                assign column_result_valid_o[reduce_column] =
                    final_valid_bus[reduce_column] && !tile_control_busy;
                assign column_result_data_o[reduce_column*32 +: 32] =
                    final_data_bus[reduce_column*32 +: 32];
                assign column_result_invalid_o[reduce_column] =
                    final_invalid_bus[reduce_column] && final_valid_bus[reduce_column] &&
                    !tile_control_busy;
            end
        end
    endgenerate

    generate
        for (genvar output_row = 0;
             output_row < TILE_SIZE;
             output_row = output_row + 1) begin : gen_right_outputs
            localparam integer RIGHT_CELL_INDEX = output_row * TILE_SIZE +
                                                  TILE_SIZE - 1;
            assign act_right_valid_o[output_row] =
                pe_act_valid_bus[RIGHT_CELL_INDEX] && !tile_control_busy;
            assign act_right_data_o[output_row*8 +: 8] =
                pe_act_data_bus[RIGHT_CELL_INDEX*8 +: 8];
            assign act_right_format_o[output_row] =
                pe_act_format_bus[RIGHT_CELL_INDEX];
        end
    endgenerate

endmodule
