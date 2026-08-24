`timescale 1ns/1ps
`default_nettype none

module fp8_fixed_q32_to_fp32 #(
    parameter int unsigned WIDTH = 85,
    parameter bit FTZ = 1'b0
) (
    input  logic                           clk_i,
    input  logic                           rst_i,
    input  logic                           clear_i,
    input  logic                           valid_i,
    input  logic signed        [WIDTH-1:0] fixed_i,
    input  logic signed              [9:0] scale_exponent_i,
    input  fp8_pkg::fp8_reduce_special_e   special_i,
    input  fp8_pkg::fp8_reduce_zero_sign_e zero_sign_i,
    input  logic                           invalid_i,
    input  fp8_pkg::fp8_rounding_e         rounding_i,
    output logic                           valid_o,
    output logic                    [31:0] result_o,
    output logic                           invalid_o
);

    localparam logic [31:0] FP32_CANONICAL_NAN = 32'h7fc00000;
    localparam logic [31:0] FP32_POSITIVE_INF = 32'h7f800000;
    localparam logic [31:0] FP32_NEGATIVE_INF = 32'hff800000;

    logic [WIDTH-1:0] absolute_operand_comb;
    logic [11:0] absolute_low0_with_carry_comb;
    logic [11:0] absolute_low1_with_carry_comb;
    logic [21:0] absolute_middle_with_carry_comb;
    logic [41:0] absolute_high_comb;
    logic [10:0] absolute_low0_s000_q;
    logic [10:0] absolute_low1_operand_s000_q;
    logic [20:0] absolute_middle_operand_s000_q;
    logic [41:0] absolute_high_operand_s000_q;
    logic absolute_carry_s000_q;
    logic finite_sign_s000_q;
    fp8_pkg::fp8_reduce_special_e special_s000_q;
    logic invalid_s000_q;
    fp8_pkg::fp8_rounding_e rounding_s000_q;
    logic signed [9:0] scale_s000_q;
    logic valid_s000_q;
    logic [21:0] absolute_low_s00_q;
    logic [20:0] absolute_middle_operand_s00_q;
    logic [41:0] absolute_high_operand_s00_q;
    logic absolute_carry_s00_q;
    logic finite_sign_s00_q;
    fp8_pkg::fp8_reduce_special_e special_s00_q;
    logic invalid_s00_q;
    fp8_pkg::fp8_rounding_e rounding_s00_q;
    logic signed [9:0] scale_s00_q;
    logic valid_s00_q;
    logic [21:0] absolute_low_s0_q;
    logic [20:0] absolute_middle_s0_q;
    logic [41:0] absolute_high_operand_s0_q;
    logic absolute_carry_s0_q;
    logic finite_sign_s0_q;
    fp8_pkg::fp8_reduce_special_e special_s0_q;
    logic invalid_s0_q;
    fp8_pkg::fp8_rounding_e rounding_s0_q;
    logic signed [9:0] scale_s0_q;
    logic valid_s0_q;
    logic [WIDTH-1:0] magnitude_s1_q;
    logic finite_sign_comb;
    logic finite_sign_s1_q;
    fp8_pkg::fp8_reduce_special_e special_s1_q;
    logic invalid_s1_q;
    fp8_pkg::fp8_rounding_e rounding_s1_q;
    logic signed [9:0] scale_s1_q;
    logic valid_s1_q;

    logic nonzero_comb;
    logic [6:0] msb_index_comb;
    logic [WIDTH-1:0] magnitude_s2_q;
    logic [6:0] msb_index_s2_q;
    logic nonzero_s2_q;
    logic finite_sign_s2_q;
    fp8_pkg::fp8_reduce_special_e special_s2_q;
    logic invalid_s2_q;
    fp8_pkg::fp8_rounding_e rounding_s2_q;
    logic signed [9:0] scale_s2_q;
    logic valid_s2_q;

    logic [84:0] coarse_magnitude_comb;
    logic [2:0] fine_shift_comb;
    logic shift_right_comb;
    logic sticky_comb;
    logic signed [10:0] coarse_exponent_comb;
    logic [84:0] coarse_magnitude_s3_q;
    logic [2:0] fine_shift_s3_q;
    logic shift_right_s3_q;
    logic sticky_s3_q;
    logic signed [10:0] coarse_exponent_s3_q;
    logic finite_sign_s3_q;
    fp8_pkg::fp8_reduce_special_e special_s3_q;
    logic invalid_s3_q;
    fp8_pkg::fp8_rounding_e rounding_s3_q;
    logic signed [9:0] scale_s3_q;
    logic valid_s3_q;

    logic [26:0] normalized_significand_comb;
    logic [26:0] normalized_significand_s4_q;
    logic signed [10:0] normalized_exponent_s4_q;
    logic finite_sign_s4_q;
    fp8_pkg::fp8_reduce_special_e special_s4_q;
    logic invalid_s4_q;
    fp8_pkg::fp8_rounding_e rounding_s4_q;
    logic valid_s4_q;

    logic [22:0] round_main_comb;
    logic [5:0] round_group_all_ones_comb;
    logic round_increment_comb;
    logic [22:0] round_main_s5_q;
    logic [5:0] round_group_all_ones_s5_q;
    logic round_increment_s5_q;
    logic signed [7:0] normalized_exponent_s5_q;
    logic exponent_in_range_s5_q;
    logic zero_s5_q;
    logic finite_sign_s5_q;
    fp8_pkg::fp8_reduce_special_e special_s5_q;
    logic invalid_s5_q;
    logic valid_s5_q;
    logic special_valid_comb;
    logic [31:0] special_result_comb;
    logic [31:0] packed_result_comb;

    assign absolute_operand_comb = fixed_i ^ {WIDTH{fixed_i[WIDTH-1]}};

    kogge_stone_adder_48 #(.WIDTH(12)) u_absolute_low0_adder (
        .a_i   ({1'b0, absolute_operand_comb[10:0]}),
        .b_i   (12'd0),
        .cin_i (fixed_i[WIDTH-1]),
        .sum_o (absolute_low0_with_carry_comb)
    );

    kogge_stone_adder_48 #(.WIDTH(12)) u_absolute_low1_adder (
        .a_i   ({1'b0, absolute_low1_operand_s000_q}),
        .b_i   (12'd0),
        .cin_i (absolute_carry_s000_q),
        .sum_o (absolute_low1_with_carry_comb)
    );

    kogge_stone_adder_48 #(.WIDTH(22)) u_absolute_middle_adder (
        .a_i   ({1'b0, absolute_middle_operand_s00_q}),
        .b_i   (22'd0),
        .cin_i (absolute_carry_s00_q),
        .sum_o (absolute_middle_with_carry_comb)
    );

    kogge_stone_adder_48 #(.WIDTH(42)) u_absolute_high_adder (
        .a_i   (absolute_high_operand_s0_q),
        .b_i   (42'd0),
        .cin_i (absolute_carry_s0_q),
        .sum_o (absolute_high_comb)
    );

    always_comb begin
        finite_sign_comb = fixed_i[WIDTH-1];
        if (fixed_i == '0) begin
            case (zero_sign_i)
                fp8_pkg::FP8_ZERO_SIGN_NEGATIVE: finite_sign_comb = 1'b1;
                fp8_pkg::FP8_ZERO_SIGN_POSITIVE: finite_sign_comb = 1'b0;
                default: finite_sign_comb = (rounding_i == fp8_pkg::RDN);
            endcase
        end
    end

    fp8_fixed85_lzc u_lzc (
        .magnitude_i (magnitude_s1_q),
        .nonzero_o   (nonzero_comb),
        .msb_index_o (msb_index_comb)
    );

    fp8_fixed85_normalize_coarse u_normalize_coarse (
        .magnitude_i        (magnitude_s2_q),
        .msb_index_i        (msb_index_s2_q),
        .nonzero_i          (nonzero_s2_q),
        .coarse_magnitude_o (coarse_magnitude_comb),
        .fine_shift_o       (fine_shift_comb),
        .shift_right_o      (shift_right_comb),
        .sticky_o           (sticky_comb),
        .exponent_o         (coarse_exponent_comb)
    );

    fp8_fixed85_normalize_fine u_normalize_fine (
        .coarse_magnitude_i (coarse_magnitude_s3_q),
        .fine_shift_i       (fine_shift_s3_q),
        .shift_right_i      (shift_right_s3_q),
        .sticky_i           (sticky_s3_q),
        .significand_o      (normalized_significand_comb)
    );

    /* verilator lint_off PINCONNECTEMPTY */
    fp8_partial_round_prepare u_round_prepare (
        .sign_i                 (finite_sign_s4_q),
        .significand_i          (normalized_significand_s4_q),
        .exponent_i             (normalized_exponent_s4_q),
        .rounding_i             (rounding_s4_q),
        .round_main_o           (round_main_comb),
        .round_group_all_ones_o (round_group_all_ones_comb),
        .round_increment_o      (round_increment_comb),
        .exponent_in_range_o    ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always_comb begin
        special_valid_comb = 1'b1;
        case (special_s5_q)
            fp8_pkg::FP8_REDUCE_NAN: special_result_comb = FP32_CANONICAL_NAN;
            fp8_pkg::FP8_REDUCE_POS_INF: special_result_comb = FP32_POSITIVE_INF;
            fp8_pkg::FP8_REDUCE_NEG_INF: special_result_comb = FP32_NEGATIVE_INF;
            default: begin
                special_valid_comb = 1'b0;
                special_result_comb = 32'd0;
            end
        endcase
    end

    fp8_reduce4_round_pack #(.FTZ(FTZ)) u_round_pack (
        .sign_i                 (finite_sign_s5_q),
        .round_main_i           (round_main_s5_q),
        .round_group_all_ones_i (round_group_all_ones_s5_q),
        .round_increment_i      (round_increment_s5_q),
        .exponent_i             (normalized_exponent_s5_q),
        .exponent_in_range_i    (exponent_in_range_s5_q),
        .zero_i                 (zero_s5_q),
        .special_valid_i        (special_valid_comb),
        .special_result_i       (special_result_comb),
        .result_o               (packed_result_comb)
    );

    always_ff @(posedge clk_i) begin
        absolute_low0_s000_q <= absolute_low0_with_carry_comb[10:0];
        absolute_low1_operand_s000_q <= absolute_operand_comb[21:11];
        absolute_middle_operand_s000_q <= absolute_operand_comb[42:22];
        absolute_high_operand_s000_q <= absolute_operand_comb[84:43];
        absolute_carry_s000_q <= absolute_low0_with_carry_comb[11];
        finite_sign_s000_q <= finite_sign_comb;
        special_s000_q <= special_i;
        invalid_s000_q <= invalid_i;
        rounding_s000_q <= rounding_i;
        scale_s000_q <= scale_exponent_i;
        absolute_low_s00_q <= {absolute_low1_with_carry_comb[10:0],
                               absolute_low0_s000_q};
        absolute_middle_operand_s00_q <= absolute_middle_operand_s000_q;
        absolute_high_operand_s00_q <= absolute_high_operand_s000_q;
        absolute_carry_s00_q <= absolute_low1_with_carry_comb[11];
        finite_sign_s00_q <= finite_sign_s000_q;
        special_s00_q <= special_s000_q;
        invalid_s00_q <= invalid_s000_q;
        rounding_s00_q <= rounding_s000_q;
        scale_s00_q <= scale_s000_q;
        absolute_low_s0_q <= absolute_low_s00_q;
        absolute_middle_s0_q <= absolute_middle_with_carry_comb[20:0];
        absolute_high_operand_s0_q <= absolute_high_operand_s00_q;
        absolute_carry_s0_q <= absolute_middle_with_carry_comb[21];
        finite_sign_s0_q <= finite_sign_s00_q;
        special_s0_q <= special_s00_q;
        invalid_s0_q <= invalid_s00_q;
        rounding_s0_q <= rounding_s00_q;
        scale_s0_q <= scale_s00_q;
        magnitude_s1_q <= {absolute_high_comb, absolute_middle_s0_q,
                           absolute_low_s0_q};
        finite_sign_s1_q <= finite_sign_s0_q;
        special_s1_q <= special_s0_q;
        invalid_s1_q <= invalid_s0_q;
        rounding_s1_q <= rounding_s0_q;
        scale_s1_q <= scale_s0_q;
        magnitude_s2_q <= magnitude_s1_q;
        msb_index_s2_q <= msb_index_comb;
        nonzero_s2_q <= nonzero_comb;
        finite_sign_s2_q <= finite_sign_s1_q;
        special_s2_q <= special_s1_q;
        invalid_s2_q <= invalid_s1_q;
        rounding_s2_q <= rounding_s1_q;
        scale_s2_q <= scale_s1_q;
        coarse_magnitude_s3_q <= coarse_magnitude_comb;
        fine_shift_s3_q <= fine_shift_comb;
        shift_right_s3_q <= shift_right_comb;
        sticky_s3_q <= sticky_comb;
        coarse_exponent_s3_q <= coarse_exponent_comb;
        finite_sign_s3_q <= finite_sign_s2_q;
        special_s3_q <= special_s2_q;
        invalid_s3_q <= invalid_s2_q;
        rounding_s3_q <= rounding_s2_q;
        scale_s3_q <= scale_s2_q;
        normalized_significand_s4_q <= normalized_significand_comb;
        normalized_exponent_s4_q <= coarse_exponent_s3_q +
                                    $signed(scale_s3_q);
        finite_sign_s4_q <= finite_sign_s3_q;
        special_s4_q <= special_s3_q;
        invalid_s4_q <= invalid_s3_q;
        rounding_s4_q <= rounding_s3_q;
        round_main_s5_q <= round_main_comb;
        round_group_all_ones_s5_q <= round_group_all_ones_comb;
        round_increment_s5_q <= round_increment_comb;
        normalized_exponent_s5_q <= normalized_exponent_s4_q[7:0];
        exponent_in_range_s5_q <= (normalized_exponent_s4_q >= -11'sd126) &&
                                  (normalized_exponent_s4_q <= 11'sd127);
        zero_s5_q <= (normalized_significand_s4_q == 27'd0);
        finite_sign_s5_q <= finite_sign_s4_q;
        special_s5_q <= special_s4_q;
        invalid_s5_q <= invalid_s4_q;
        result_o <= packed_result_comb;
        invalid_o <= valid_s5_q && invalid_s5_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_s000_q <= 1'b0;
            valid_s00_q <= 1'b0;
            valid_s0_q <= 1'b0;
            valid_s1_q <= 1'b0;
            valid_s2_q <= 1'b0;
            valid_s3_q <= 1'b0;
            valid_s4_q <= 1'b0;
            valid_s5_q <= 1'b0;
            valid_o <= 1'b0;
        end else begin
            valid_s000_q <= valid_i;
            valid_s00_q <= valid_s000_q;
            valid_s0_q <= valid_s00_q;
            valid_s1_q <= valid_s0_q;
            valid_s2_q <= valid_s1_q;
            valid_s3_q <= valid_s2_q;
            valid_s4_q <= valid_s3_q;
            valid_s5_q <= valid_s4_q;
            valid_o <= valid_s5_q;
        end
    end

`ifndef YOSYS
    initial begin
        assert (WIDTH == 85)
            else $error("fp8_fixed_q32_to_fp32 WIDTH must be 85");
    end
`endif

endmodule

`default_nettype wire
