`timescale 1ns/1ps
`default_nettype none

// 16x16 MX Tile using the original reduction architecture. Each input block is
// received over 16 cycles. While one A/B bank feeds all 256 exact multipliers,
// the other bank accepts the next block, so steady-state issue has no bubbles.
// The 16 products in each output column are reduced inside the Tile and only
// sixteen 85-bit long-K lanes are instantiated for the complete Tile.
module TILE_FP8_16 #(
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

    output logic                  [15:0] a_right_valid_o,
    output logic                 [127:0] a_right_data_o,
    output logic                  [31:0] a_right_format_o,
    output logic                 [127:0] a_right_scale_o,
    output logic                  [15:0] a_right_block_first_o,
    output logic                  [15:0] a_right_block_last_o,
    output logic                  [15:0] a_right_matrix_first_o,
    output logic                  [15:0] a_right_matrix_last_o,
    output logic                 [127:0] a_right_tag_o,

    output logic                  [15:0] b_bottom_valid_o,
    output logic                 [127:0] b_bottom_data_o,
    output logic                  [31:0] b_bottom_format_o,
    output logic                 [127:0] b_bottom_scale_o,

    output logic                         result_valid_o,
    output logic                 [511:0] result_data_o,
    output logic                  [15:0] result_invalid_o,
    output logic                   [7:0] result_tag_o,
    output logic                   [3:0] result_row_o
);

    localparam int unsigned TILE_SIZE = 16;
    localparam int unsigned GROUP_SIZE = 4;
    localparam int unsigned GROUPS_PER_COLUMN = TILE_SIZE / GROUP_SIZE;
    localparam int unsigned META_PIPELINE = 9;
    localparam int unsigned SCALE_PIPELINE = 8;

    logic [7:0] a_data_bank [0:1][0:TILE_SIZE-1][0:TILE_SIZE-1];
    mxfp_pkg::mxfp_format_e
        a_format_bank [0:1][0:TILE_SIZE-1][0:TILE_SIZE-1];
    mxfp_pkg::mxfp_scale_t
        a_scale_bank [0:1][0:TILE_SIZE-1][0:TILE_SIZE-1];
    logic a_first_bank [0:1][0:TILE_SIZE-1];
    logic a_last_bank [0:1][0:TILE_SIZE-1];
    logic [7:0] a_tag_bank [0:1][0:TILE_SIZE-1];

    logic [7:0] b_data_bank [0:1][0:TILE_SIZE-1][0:TILE_SIZE-1];
    mxfp_pkg::mxfp_format_e
        b_format_bank [0:1][0:TILE_SIZE-1][0:TILE_SIZE-1];
    mxfp_pkg::mxfp_scale_t
        b_scale_bank [0:1][0:TILE_SIZE-1][0:TILE_SIZE-1];

    logic [1:0] bank_full_q;
    logic load_bank_q;
    logic [3:0] load_row_q;
    logic compute_active_q;
    logic compute_bank_q;
    logic [3:0] compute_row_q;
    logic load_fire;
    logic load_finishing;
    logic compute_issue;
    logic next_compute_bank_available;

    mxfp_pkg::mxfp_product_t pe_product [0:TILE_SIZE-1][0:TILE_SIZE-1];
    fp8_pkg::fp8_product_t pe_element_product [0:TILE_SIZE-1][0:TILE_SIZE-1];
    logic pe_product_valid [0:TILE_SIZE-1][0:TILE_SIZE-1];
    logic pe_product_invalid [0:TILE_SIZE-1][0:TILE_SIZE-1];

    logic group_input_valid [0:TILE_SIZE-1][0:GROUPS_PER_COLUMN-1];
    logic group_valid [0:TILE_SIZE-1][0:GROUPS_PER_COLUMN-1];
    logic signed [66:0] group_exact [0:TILE_SIZE-1][0:GROUPS_PER_COLUMN-1];
    fp8_pkg::fp8_reduce_special_e
        group_special [0:TILE_SIZE-1][0:GROUPS_PER_COLUMN-1];
    fp8_pkg::fp8_reduce_zero_sign_e
        group_zero_sign [0:TILE_SIZE-1][0:GROUPS_PER_COLUMN-1];
    logic group_invalid [0:TILE_SIZE-1][0:GROUPS_PER_COLUMN-1];
    fp8_pkg::fp8_rounding_e
        group_rounding [0:TILE_SIZE-1][0:GROUPS_PER_COLUMN-1];

    logic [15:0] column_exact_valid;
    logic signed [68:0] column_exact [0:TILE_SIZE-1];
    fp8_pkg::fp8_reduce_special_e column_special [0:TILE_SIZE-1];
    fp8_pkg::fp8_reduce_zero_sign_e column_zero_sign [0:TILE_SIZE-1];
    logic [15:0] column_invalid;
    fp8_pkg::fp8_rounding_e column_rounding [0:TILE_SIZE-1];

    logic [META_PIPELINE-1:0] meta_valid_q;
    logic [META_PIPELINE-1:0] meta_first_q;
    logic [META_PIPELINE-1:0] meta_last_q;
    logic [3:0] meta_row_q [0:META_PIPELINE-1];
    logic [7:0] meta_tag_q [0:META_PIPELINE-1];
    logic signed [9:0]
        scale_pipeline_q [0:TILE_SIZE-1][0:SCALE_PIPELINE-1];

    logic accumulator_partial_ready;
    logic [1119:0] accumulator_partial_exact;
    logic [31:0] accumulator_partial_special;
    logic [31:0] accumulator_partial_zero_sign;
    logic [159:0] accumulator_partial_scale;
    logic accumulator_protocol_error;

    wire _unused_block_markers = &{1'b0, a_block_first_i, a_block_last_i};
    wire _unused_accumulator_status = &{1'b0, accumulator_partial_ready,
                                         accumulator_protocol_error,
                                         column_rounding};

    assign load_fire = (&a_valid_i) && (&b_valid_i) && !rst_i && !clear_i;
    assign load_finishing = load_fire && (load_row_q == 4'd15);
    assign compute_issue = compute_active_q;
    assign next_compute_bank_available = bank_full_q[~compute_bank_q] ||
        (load_finishing && (load_bank_q == ~compute_bank_q));

    // Direct array links are one registered Tile hop. No packet router or
    // per-PE systolic skew remains in this path.
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            a_right_valid_o <= '0;
            a_right_data_o <= '0;
            a_right_format_o <= '0;
            a_right_scale_o <= '0;
            a_right_block_first_o <= '0;
            a_right_block_last_o <= '0;
            a_right_matrix_first_o <= '0;
            a_right_matrix_last_o <= '0;
            a_right_tag_o <= '0;
            b_bottom_valid_o <= '0;
            b_bottom_data_o <= '0;
            b_bottom_format_o <= '0;
            b_bottom_scale_o <= '0;
        end else if (clear_i) begin
            a_right_valid_o <= '0;
            b_bottom_valid_o <= '0;
        end else begin
            a_right_valid_o <= a_valid_i;
            b_bottom_valid_o <= b_valid_i;
            if (|a_valid_i) begin
                a_right_data_o <= a_data_i;
                a_right_format_o <= a_format_i;
                a_right_scale_o <= a_scale_i;
                a_right_block_first_o <= a_block_first_i;
                a_right_block_last_o <= a_block_last_i;
                a_right_matrix_first_o <= a_matrix_first_i;
                a_right_matrix_last_o <= a_matrix_last_i;
                a_right_tag_o <= a_tag_i;
            end
            if (|b_valid_i) begin
                b_bottom_data_o <= b_data_i;
                b_bottom_format_o <= b_format_i;
                b_bottom_scale_o <= b_scale_i;
            end
        end
    end

    // The two banks alternate every 16 accepted beats. A bank being consumed
    // is released on the same edge on which the opposite bank completes load,
    // allowing both selectors to toggle without an inter-block bubble.
    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            bank_full_q <= 2'b00;
            load_bank_q <= 1'b0;
            load_row_q <= 4'd0;
            compute_active_q <= 1'b0;
            compute_bank_q <= 1'b0;
            compute_row_q <= 4'd0;
        end else begin
            if (load_fire) begin
                for (integer lane = 0; lane < TILE_SIZE; lane++) begin
                    a_data_bank[load_bank_q][load_row_q][lane] <=
                        a_data_i[lane*8 +: 8];
                    a_format_bank[load_bank_q][load_row_q][lane] <=
                        mxfp_pkg::mxfp_format_e'(a_format_i[lane*2 +: 2]);
                    a_scale_bank[load_bank_q][load_row_q][lane] <=
                        a_scale_i[lane*8 +: 8];
                    b_data_bank[load_bank_q][load_row_q][lane] <=
                        b_data_i[lane*8 +: 8];
                    b_format_bank[load_bank_q][load_row_q][lane] <=
                        mxfp_pkg::mxfp_format_e'(b_format_i[lane*2 +: 2]);
                    b_scale_bank[load_bank_q][load_row_q][lane] <=
                        b_scale_i[lane*8 +: 8];
                end
                a_first_bank[load_bank_q][load_row_q] <=
                    &a_matrix_first_i;
                a_last_bank[load_bank_q][load_row_q] <=
                    &a_matrix_last_i;
                a_tag_bank[load_bank_q][load_row_q] <= a_tag_i[7:0];
                if (load_row_q == 4'd15) begin
                    bank_full_q[load_bank_q] <= 1'b1;
                    load_bank_q <= ~load_bank_q;
                    load_row_q <= 4'd0;
                end else begin
                    load_row_q <= load_row_q + 4'd1;
                end
            end

            if (!compute_active_q) begin
                if (bank_full_q[0]) begin
                    compute_active_q <= 1'b1;
                    compute_bank_q <= 1'b0;
                    compute_row_q <= 4'd0;
                    bank_full_q[0] <= 1'b0;
                end else if (bank_full_q[1]) begin
                    compute_active_q <= 1'b1;
                    compute_bank_q <= 1'b1;
                    compute_row_q <= 4'd0;
                    bank_full_q[1] <= 1'b0;
                end
            end else if (compute_issue) begin
                if (compute_row_q == 4'd15) begin
                    if (next_compute_bank_available) begin
                        compute_bank_q <= ~compute_bank_q;
                        compute_row_q <= 4'd0;
                        bank_full_q[~compute_bank_q] <= 1'b0;
                    end else begin
                        compute_active_q <= 1'b0;
                    end
                end else begin
                    compute_row_q <= compute_row_q + 4'd1;
                end
            end
        end
    end

    generate
        for (genvar row = 0; row < TILE_SIZE; row++) begin : gen_pe_rows
            for (genvar column = 0; column < TILE_SIZE;
                 column++) begin : gen_pe_columns
                // Forward outputs are intentionally unused because Tile-level
                // registered links carry the complete 16-lane block.
                /* verilator lint_off PINCONNECTEMPTY */
                PE_FP8 #(.DAZ(DAZ), .FTZ(FTZ)) u_pe (
                    .clk_i(clk_i),
                    .rst_i(rst_i),
                    .clear_i(clear_i),
                    .a_valid_i(compute_issue),
                    .a_i(a_data_bank[compute_bank_q][compute_row_q][row]),
                    .a_format_i(a_format_bank[compute_bank_q][compute_row_q][row]),
                    .a_scale_i(a_scale_bank[compute_bank_q][compute_row_q][row]),
                    .a_block_first_i(1'b0),
                    .a_block_last_i(1'b0),
                    .a_matrix_first_i(1'b0),
                    .a_matrix_last_i(1'b0),
                    .a_tag_i(8'd0),
                    .b_valid_i(compute_issue),
                    .b_i(b_data_bank[compute_bank_q][row][column]),
                    .b_format_i(b_format_bank[compute_bank_q][row][column]),
                    .b_scale_i(b_scale_bank[compute_bank_q][row][column]),
                    .a_valid_o(), .a_o(), .a_format_o(), .a_scale_o(),
                    .a_block_first_o(), .a_block_last_o(),
                    .a_matrix_first_o(), .a_matrix_last_o(), .a_tag_o(),
                    .b_valid_o(), .b_o(), .b_format_o(), .b_scale_o(),
                    .product_valid_o(pe_product_valid[row][column]),
                    .product_o(pe_product[row][column]),
                    .product_invalid_o(pe_product_invalid[row][column])
                );
                /* verilator lint_on PINCONNECTEMPTY */

                assign pe_element_product[row][column].sign =
                    pe_product[row][column].sign;
                assign pe_element_product[row][column].exponent =
                    pe_product[row][column].element_exponent;
                assign pe_element_product[row][column].significand =
                    pe_product[row][column].significand;
                assign pe_element_product[row][column].is_zero =
                    pe_product[row][column].is_zero;
                assign pe_element_product[row][column].is_inf =
                    pe_product[row][column].is_inf;
                assign pe_element_product[row][column].is_nan =
                    pe_product[row][column].is_nan;
            end
        end

        for (genvar column = 0; column < TILE_SIZE;
             column++) begin : gen_column_reduction
            for (genvar group = 0; group < GROUPS_PER_COLUMN;
                 group++) begin : gen_group_reduction
                localparam int unsigned BASE_ROW = group * GROUP_SIZE;
                assign group_input_valid[column][group] =
                    pe_product_valid[BASE_ROW+0][column] &&
                    pe_product_valid[BASE_ROW+1][column] &&
                    pe_product_valid[BASE_ROW+2][column] &&
                    pe_product_valid[BASE_ROW+3][column];

                fp8_exact_reduce4 u_reduce4 (
                    .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
                    .valid_i(group_input_valid[column][group]),
                    .product0_i(pe_element_product[BASE_ROW+0][column]),
                    .product1_i(pe_element_product[BASE_ROW+1][column]),
                    .product2_i(pe_element_product[BASE_ROW+2][column]),
                    .product3_i(pe_element_product[BASE_ROW+3][column]),
                    .invalid_i({pe_product_invalid[BASE_ROW+3][column],
                                pe_product_invalid[BASE_ROW+2][column],
                                pe_product_invalid[BASE_ROW+1][column],
                                pe_product_invalid[BASE_ROW+0][column]}),
                    .rounding_i(fp8_pkg::RNE),
                    .valid_o(group_valid[column][group]),
                    .exact_sum_o(group_exact[column][group]),
                    .special_o(group_special[column][group]),
                    .zero_sign_o(group_zero_sign[column][group]),
                    .invalid_o(group_invalid[column][group]),
                    .rounding_o(group_rounding[column][group])
                );
            end

            fp8_exact_partial4_reduce u_final_reduce4 (
                .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
                .valid_i(group_valid[column][0] && group_valid[column][1] &&
                         group_valid[column][2] && group_valid[column][3]),
                .exact0_i(group_exact[column][0]),
                .exact1_i(group_exact[column][1]),
                .exact2_i(group_exact[column][2]),
                .exact3_i(group_exact[column][3]),
                .special0_i(group_special[column][0]),
                .special1_i(group_special[column][1]),
                .special2_i(group_special[column][2]),
                .special3_i(group_special[column][3]),
                .zero_sign0_i(group_zero_sign[column][0]),
                .zero_sign1_i(group_zero_sign[column][1]),
                .zero_sign2_i(group_zero_sign[column][2]),
                .zero_sign3_i(group_zero_sign[column][3]),
                .invalid_i({group_invalid[column][3],
                            group_invalid[column][2],
                            group_invalid[column][1],
                            group_invalid[column][0]}),
                .rounding_i(group_rounding[column][0]),
                .valid_o(column_exact_valid[column]),
                .exact_sum_o(column_exact[column]),
                .special_o(column_special[column]),
                .zero_sign_o(column_zero_sign[column]),
                .invalid_o(column_invalid[column]),
                .rounding_o(column_rounding[column])
            );
        end
    endgenerate

    // Metadata launched with the 256 products traverses one multiplier stage,
    // five first-level reduction stages, and three final reduction stages.
    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            meta_valid_q <= '0;
            meta_first_q <= '0;
            meta_last_q <= '0;
        end else begin
            meta_valid_q[0] <= compute_issue;
            meta_first_q[0] <=
                a_first_bank[compute_bank_q][compute_row_q];
            meta_last_q[0] <= a_last_bank[compute_bank_q][compute_row_q];
            meta_row_q[0] <= compute_row_q;
            meta_tag_q[0] <= a_tag_bank[compute_bank_q][compute_row_q];
            for (integer stage = 1; stage < META_PIPELINE; stage++) begin
                meta_valid_q[stage] <= meta_valid_q[stage-1];
                meta_first_q[stage] <= meta_first_q[stage-1];
                meta_last_q[stage] <= meta_last_q[stage-1];
                meta_row_q[stage] <= meta_row_q[stage-1];
                meta_tag_q[stage] <= meta_tag_q[stage-1];
            end
        end
    end

    // Product scale appears with the PE output and needs the remaining eight
    // reduction cycles to remain aligned with the final 69-bit exact sum.
    always_ff @(posedge clk_i) begin
        for (integer column = 0; column < TILE_SIZE; column++) begin
            scale_pipeline_q[column][0] <=
                pe_product[0][column].scale_exponent;
            for (integer stage = 1; stage < SCALE_PIPELINE; stage++) begin
                scale_pipeline_q[column][stage] <=
                    scale_pipeline_q[column][stage-1];
            end
        end
    end

    always_comb begin
        accumulator_partial_exact = '0;
        accumulator_partial_special = '0;
        accumulator_partial_zero_sign = '0;
        accumulator_partial_scale = '0;
        for (integer column = 0; column < TILE_SIZE; column++) begin
            accumulator_partial_exact[column*70 +: 70] =
                {{1{column_exact[column][68]}}, column_exact[column]};
            accumulator_partial_special[column*2 +: 2] =
                column_special[column];
            accumulator_partial_zero_sign[column*2 +: 2] =
                column_zero_sign[column];
            accumulator_partial_scale[column*10 +: 10] =
                scale_pipeline_q[column][SCALE_PIPELINE-1];
        end
    end

    /* verilator lint_off PINCONNECTEMPTY */
    tile_fp32_k_accumulator #(
        .FTZ(FTZ),
        .STREAM_METADATA_MODE(1'b1)
    ) u_k_accumulator (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .start_i(1'b0), .start_ready_o(), .rows_i(5'd16),
        .k_blocks_i(16'd0),
        .stream_first_i(meta_first_q[META_PIPELINE-1]),
        .stream_last_i(meta_last_q[META_PIPELINE-1]),
        .stream_row_i(meta_row_q[META_PIPELINE-1]),
        .stream_tag_i(meta_tag_q[META_PIPELINE-1]),
        .partial_valid_i((&column_exact_valid) &&
                         meta_valid_q[META_PIPELINE-1]),
        .partial_ready_o(accumulator_partial_ready),
        .partial_exact_i(accumulator_partial_exact),
        .partial_special_i(accumulator_partial_special),
        .partial_zero_sign_i(accumulator_partial_zero_sign),
        .partial_invalid_i(column_invalid),
        .partial_scale_exponent_i(accumulator_partial_scale),
        .result_ready_i(1'b1),
        .result_valid_o(result_valid_o),
        .result_data_o(result_data_o),
        .result_invalid_o(result_invalid_o),
        .result_tag_o(result_tag_o),
        .result_row_o(result_row_o),
        .busy_o(), .block_done_o(), .done_o(),
        .protocol_error_o(accumulator_protocol_error)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    initial begin
        assert (META_PIPELINE == 9)
            else $error("TILE_FP8_16 metadata pipeline must match reduction latency");
    end

endmodule

`default_nettype wire
