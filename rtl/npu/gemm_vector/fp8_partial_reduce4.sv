`timescale 1ns/1ps

module fp8_partial_reduce4 #(
    parameter bit FTZ = 1'b0
) (
    input  logic                    clk_i,
    input  logic                    rst_i,
    input  logic                    clear_i,
    input  logic                    valid_i,
    input  logic             [31:0] partial0_i,
    input  logic             [31:0] partial1_i,
    input  logic             [31:0] partial2_i,
    input  logic             [31:0] partial3_i,
    input  logic              [3:0] invalid_i,
    input  fp8_pkg::fp8_rounding_e rounding_i,
    output logic                    valid_o,
    output logic             [31:0] result_o,
    output logic                    invalid_o
);

    localparam logic [31:0] FP32_CANONICAL_NAN = 32'h7fc00000;
    localparam logic [31:0] FP32_POSITIVE_INF = 32'h7f800000;
    localparam logic [31:0] FP32_NEGATIVE_INF = 32'hff800000;

    logic [31:0] partial_input [0:3];
    logic  [3:0] prepare_sign_comb;
    logic [23:0] prepare_significand_comb [0:3];
    logic  [5:0] prepare_left_shift_comb [0:3];
    logic  [3:0] partial_nan_comb;
    logic  [3:0] partial_pos_inf_comb;
    logic  [3:0] partial_neg_inf_comb;
    logic  [3:0] partial_zero_comb;
    logic  [3:0] partial_zero_sign_comb;

    logic any_nan_comb;
    logic any_pos_inf_comb;
    logic any_neg_inf_comb;
    fp8_pkg::fp8_reduce_special_e special_state_comb;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_comb;
    logic invalid_comb;

    logic  [3:0] sign_s1_q;
    logic [23:0] significand_s1_q [0:3];
    logic  [5:0] left_shift_s1_q [0:3];
    fp8_pkg::fp8_reduce_special_e special_state_s1_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s1_q;
    logic invalid_s1_q;
    fp8_pkg::fp8_rounding_e rounding_s1_q;
    logic valid_s1_q;

    logic [30:0] fine_aligned_comb [0:3];
    logic  [2:0] coarse_shift_comb [0:3];
    logic  [3:0] sign_s2_q;
    logic [30:0] fine_aligned_s2_q [0:3];
    logic  [2:0] coarse_shift_s2_q [0:3];
    fp8_pkg::fp8_reduce_special_e special_state_s2_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s2_q;
    logic invalid_s2_q;
    fp8_pkg::fp8_rounding_e rounding_s2_q;
    logic valid_s2_q;

    logic [68:0] aligned_magnitude_comb [0:3];
    logic [68:0] signed_pattern_comb [0:3];
    logic  [2:0] negative_count_comb;
    logic [68:0] csa_sum_l1_s3_q;
    logic [68:0] csa_carry_l1_s3_q;
    logic [68:0] signed_pattern3_s3_q;
    logic  [2:0] negative_count_s3_q;
    fp8_pkg::fp8_reduce_special_e special_state_s3_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s3_q;
    logic invalid_s3_q;
    fp8_pkg::fp8_rounding_e rounding_s3_q;
    logic valid_s3_q;

    logic [68:0] correction_s3_comb;
    logic [68:0] csa_sum_l1_comb;
    logic [68:0] csa_carry_l1_comb;
    logic [68:0] csa_sum_l2_comb;
    logic [68:0] csa_carry_l2_comb;
    logic [68:0] csa_sum_l3_comb;
    logic [68:0] csa_carry_l3_comb;
    logic [68:0] csa_sum_s4_q;
    logic [68:0] csa_carry_s4_q;
    fp8_pkg::fp8_reduce_special_e special_state_s4_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s4_q;
    logic invalid_s4_q;
    fp8_pkg::fp8_rounding_e rounding_s4_q;
    logic valid_s4_q;

    logic [68:0] exact_sum_comb;
    logic [68:0] exact_sum_s5_q;
    fp8_pkg::fp8_reduce_special_e special_state_s5_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s5_q;
    logic invalid_s5_q;
    fp8_pkg::fp8_rounding_e rounding_s5_q;
    logic valid_s5_q;

    logic [68:0] abs_input_comb;
    logic [68:0] magnitude_comb;
    logic finite_sign_comb;
    logic [68:0] magnitude_s6_q;
    logic finite_sign_s6_q;
    fp8_pkg::fp8_reduce_special_e special_state_s6_q;
    logic invalid_s6_q;
    fp8_pkg::fp8_rounding_e rounding_s6_q;
    logic valid_s6_q;

    logic nonzero_comb;
    logic [6:0] msb_index_comb;
    logic [68:0] magnitude_s7_q;
    logic [6:0] msb_index_s7_q;
    logic nonzero_s7_q;
    logic finite_sign_s7_q;
    fp8_pkg::fp8_reduce_special_e special_state_s7_q;
    logic invalid_s7_q;
    fp8_pkg::fp8_rounding_e rounding_s7_q;
    logic valid_s7_q;

    logic [68:0] coarse_magnitude_comb;
    logic [2:0] normalize_fine_shift_comb;
    logic normalize_shift_right_comb;
    logic normalize_sticky_comb;
    logic signed [10:0] normalized_exponent_comb;
    logic [68:0] coarse_magnitude_s8_q;
    logic [2:0] normalize_fine_shift_s8_q;
    logic normalize_shift_right_s8_q;
    logic normalize_sticky_s8_q;
    logic signed [10:0] normalized_exponent_s8_q;
    logic finite_sign_s8_q;
    fp8_pkg::fp8_reduce_special_e special_state_s8_q;
    logic invalid_s8_q;
    fp8_pkg::fp8_rounding_e rounding_s8_q;
    logic valid_s8_q;

    logic [26:0] normalized_significand_comb;
    logic [26:0] normalized_significand_s9_q;
    logic signed [10:0] normalized_exponent_s9_q;
    logic finite_sign_s9_q;
    fp8_pkg::fp8_reduce_special_e special_state_s9_q;
    logic invalid_s9_q;
    fp8_pkg::fp8_rounding_e rounding_s9_q;
    logic valid_s9_q;

    logic [22:0] round_main_comb;
    logic [5:0] round_group_all_ones_comb;
    logic round_increment_comb;
    logic exponent_in_range_comb;
    logic [22:0] round_main_s10_q;
    logic [5:0] round_group_all_ones_s10_q;
    logic round_increment_s10_q;
    logic signed [7:0] normalized_exponent_s10_q;
    logic exponent_in_range_s10_q;
    logic zero_s10_q;
    logic finite_sign_s10_q;
    fp8_pkg::fp8_reduce_special_e special_state_s10_q;
    logic invalid_s10_q;
    logic valid_s10_q;

    logic [31:0] packed_result_comb;
    logic special_valid_s10_comb;
    logic [31:0] special_result_s10_comb;
    integer lane_index;

    assign partial_input[0] = partial0_i;
    assign partial_input[1] = partial1_i;
    assign partial_input[2] = partial2_i;
    assign partial_input[3] = partial3_i;

    generate
        for (genvar prepare_lane = 0; prepare_lane < 4;
             prepare_lane = prepare_lane + 1) begin : gen_partial_prepare
            logic [7:0] exponent_field;
            logic [22:0] fraction_field;
            logic [23:0] raw_significand;
            logic signed [10:0] unbiased_exponent;
            logic signed [10:0] binary_shift;
            logic [5:0] right_shift;

            always_comb begin
                exponent_field = partial_input[prepare_lane][30:23];
                fraction_field = partial_input[prepare_lane][22:0];
                raw_significand = {1'b1, fraction_field};
                unbiased_exponent = $signed({3'b000, exponent_field}) - 11'sd127;
                binary_shift = unbiased_exponent + 11'sd9;
                right_shift = 6'd0;
                prepare_sign_comb[prepare_lane] = partial_input[prepare_lane][31];
                prepare_significand_comb[prepare_lane] = 24'd0;
                prepare_left_shift_comb[prepare_lane] = 6'd0;
                partial_nan_comb[prepare_lane] = 1'b0;
                partial_pos_inf_comb[prepare_lane] = 1'b0;
                partial_neg_inf_comb[prepare_lane] = 1'b0;
                partial_zero_comb[prepare_lane] = 1'b0;
                partial_zero_sign_comb[prepare_lane] = partial_input[prepare_lane][31];

                if (exponent_field == 8'hff) begin
                    if (fraction_field == 23'd0) begin
                        partial_pos_inf_comb[prepare_lane] = !partial_input[prepare_lane][31];
                        partial_neg_inf_comb[prepare_lane] = partial_input[prepare_lane][31];
                    end else begin
                        partial_nan_comb[prepare_lane] = 1'b1;
                    end
                end else if (exponent_field == 8'h00) begin
                    partial_zero_comb[prepare_lane] = 1'b1;
                end else if (binary_shift < 11'sd0) begin
                    right_shift = 6'($unsigned(-binary_shift));
                    if (right_shift <= 6'd23) begin
                        prepare_significand_comb[prepare_lane] =
                            raw_significand >> right_shift[4:0];
                    end
                end else if (binary_shift <= 11'sd42) begin
                    prepare_significand_comb[prepare_lane] = raw_significand;
                    prepare_left_shift_comb[prepare_lane] = binary_shift[5:0];
                end
            end
        end

        for (genvar align_lane = 0; align_lane < 4;
             align_lane = align_lane + 1) begin : gen_partial_alignment
            always_comb begin
                fine_aligned_comb[align_lane] =
                    {7'd0, significand_s1_q[align_lane]} << left_shift_s1_q[align_lane][2:0];
                coarse_shift_comb[align_lane] = left_shift_s1_q[align_lane][5:3];
            end

            always_comb begin
                aligned_magnitude_comb[align_lane] = 69'd0;
                case (coarse_shift_s2_q[align_lane])
                    3'd0: aligned_magnitude_comb[align_lane] =
                            {38'd0, fine_aligned_s2_q[align_lane]};
                    3'd1: aligned_magnitude_comb[align_lane] =
                            {30'd0, fine_aligned_s2_q[align_lane], 8'd0};
                    3'd2: aligned_magnitude_comb[align_lane] =
                            {22'd0, fine_aligned_s2_q[align_lane], 16'd0};
                    3'd3: aligned_magnitude_comb[align_lane] =
                            {14'd0, fine_aligned_s2_q[align_lane], 24'd0};
                    3'd4: aligned_magnitude_comb[align_lane] =
                            {6'd0, fine_aligned_s2_q[align_lane], 32'd0};
                    3'd5: aligned_magnitude_comb[align_lane] =
                            {fine_aligned_s2_q[align_lane][28:0], 40'd0};
                    default: aligned_magnitude_comb[align_lane] = 69'd0;
                endcase
            end

            assign signed_pattern_comb[align_lane] =
                aligned_magnitude_comb[align_lane] ^ {69{sign_s2_q[align_lane]}};
        end
    endgenerate

    always_comb begin
        any_nan_comb = |partial_nan_comb;
        any_pos_inf_comb = |partial_pos_inf_comb;
        any_neg_inf_comb = |partial_neg_inf_comb;
        invalid_comb = (|invalid_i) || (any_pos_inf_comb && any_neg_inf_comb);
        zero_sign_state_comb = fp8_pkg::FP8_ZERO_SIGN_ROUNDING;
        if (&partial_zero_comb) begin
            if (&partial_zero_sign_comb) begin
                zero_sign_state_comb = fp8_pkg::FP8_ZERO_SIGN_NEGATIVE;
            end else if (!(|partial_zero_sign_comb)) begin
                zero_sign_state_comb = fp8_pkg::FP8_ZERO_SIGN_POSITIVE;
            end
        end
        special_state_comb = fp8_pkg::FP8_REDUCE_NORMAL;
        if (any_nan_comb || (any_pos_inf_comb && any_neg_inf_comb)) begin
            special_state_comb = fp8_pkg::FP8_REDUCE_NAN;
        end else if (any_pos_inf_comb) begin
            special_state_comb = fp8_pkg::FP8_REDUCE_POS_INF;
        end else if (any_neg_inf_comb) begin
            special_state_comb = fp8_pkg::FP8_REDUCE_NEG_INF;
        end
    end

    always_comb begin
        special_valid_s10_comb = 1'b1;
        case (special_state_s10_q)
            fp8_pkg::FP8_REDUCE_NAN: special_result_s10_comb = FP32_CANONICAL_NAN;
            fp8_pkg::FP8_REDUCE_POS_INF: special_result_s10_comb = FP32_POSITIVE_INF;
            fp8_pkg::FP8_REDUCE_NEG_INF: special_result_s10_comb = FP32_NEGATIVE_INF;
            default: begin
                special_valid_s10_comb = 1'b0;
                special_result_s10_comb = 32'h00000000;
            end
        endcase
    end

    assign negative_count_comb = {2'd0, sign_s2_q[0]} +
                                 {2'd0, sign_s2_q[1]} +
                                 {2'd0, sign_s2_q[2]} +
                                 {2'd0, sign_s2_q[3]};
    assign correction_s3_comb = {66'd0, negative_count_s3_q};
    assign csa_sum_l1_comb = signed_pattern_comb[0] ^ signed_pattern_comb[1] ^
                             signed_pattern_comb[2];
    assign csa_carry_l1_comb = ((signed_pattern_comb[0] & signed_pattern_comb[1]) |
                                (signed_pattern_comb[0] & signed_pattern_comb[2]) |
                                (signed_pattern_comb[1] & signed_pattern_comb[2])) << 1;
    assign csa_sum_l2_comb = csa_sum_l1_s3_q ^ csa_carry_l1_s3_q ^
                             signed_pattern3_s3_q;
    assign csa_carry_l2_comb = ((csa_sum_l1_s3_q & csa_carry_l1_s3_q) |
                                (csa_sum_l1_s3_q & signed_pattern3_s3_q) |
                                (csa_carry_l1_s3_q & signed_pattern3_s3_q)) << 1;
    assign csa_sum_l3_comb = csa_sum_l2_comb ^ csa_carry_l2_comb ^ correction_s3_comb;
    assign csa_carry_l3_comb = ((csa_sum_l2_comb & csa_carry_l2_comb) |
                                (csa_sum_l2_comb & correction_s3_comb) |
                                (csa_carry_l2_comb & correction_s3_comb)) << 1;

    kogge_stone_adder_69 u_exact_sum_adder (
        .a_i   (csa_sum_s4_q),
        .b_i   (csa_carry_s4_q),
        .cin_i (1'b0),
        .sum_o (exact_sum_comb)
    );

    assign abs_input_comb = exact_sum_s5_q ^ {69{exact_sum_s5_q[68]}};

    kogge_stone_adder_69 u_absolute_value_adder (
        .a_i   (abs_input_comb),
        .b_i   (69'd0),
        .cin_i (exact_sum_s5_q[68]),
        .sum_o (magnitude_comb)
    );

    always_comb begin
        finite_sign_comb = exact_sum_s5_q[68];
        if (exact_sum_s5_q == 69'd0) begin
            case (zero_sign_state_s5_q)
                fp8_pkg::FP8_ZERO_SIGN_NEGATIVE: finite_sign_comb = 1'b1;
                fp8_pkg::FP8_ZERO_SIGN_POSITIVE: finite_sign_comb = 1'b0;
                default: finite_sign_comb = (rounding_s5_q == fp8_pkg::RDN);
            endcase
        end
    end

    fp8_partial_fixed69_lzc u_fixed69_lzc (
        .magnitude_i (magnitude_s6_q),
        .nonzero_o   (nonzero_comb),
        .msb_index_o (msb_index_comb)
    );

    fp8_partial_fixed69_normalize_coarse u_normalize_coarse (
        .magnitude_i        (magnitude_s7_q),
        .msb_index_i        (msb_index_s7_q),
        .nonzero_i          (nonzero_s7_q),
        .coarse_magnitude_o (coarse_magnitude_comb),
        .fine_shift_o       (normalize_fine_shift_comb),
        .shift_right_o      (normalize_shift_right_comb),
        .sticky_o           (normalize_sticky_comb),
        .exponent_o         (normalized_exponent_comb)
    );

    fp8_partial_fixed69_normalize_fine u_normalize_fine (
        .coarse_magnitude_i (coarse_magnitude_s8_q),
        .fine_shift_i       (normalize_fine_shift_s8_q),
        .shift_right_i      (normalize_shift_right_s8_q),
        .sticky_i           (normalize_sticky_s8_q),
        .significand_o      (normalized_significand_comb)
    );

    fp8_partial_round_prepare u_round_prepare (
        .sign_i                 (finite_sign_s9_q),
        .significand_i          (normalized_significand_s9_q),
        .exponent_i             (normalized_exponent_s9_q),
        .rounding_i             (rounding_s9_q),
        .round_main_o           (round_main_comb),
        .round_group_all_ones_o (round_group_all_ones_comb),
        .round_increment_o      (round_increment_comb),
        .exponent_in_range_o    (exponent_in_range_comb)
    );

    fp8_reduce4_round_pack #(.FTZ(FTZ)) u_round_pack (
        .sign_i                 (finite_sign_s10_q),
        .round_main_i           (round_main_s10_q),
        .round_group_all_ones_i (round_group_all_ones_s10_q),
        .round_increment_i      (round_increment_s10_q),
        .exponent_i             (normalized_exponent_s10_q),
        .exponent_in_range_i    (exponent_in_range_s10_q),
        .zero_i                 (zero_s10_q),
        .special_valid_i        (special_valid_s10_comb),
        .special_result_i       (special_result_s10_comb),
        .result_o               (packed_result_comb)
    );

    always_ff @(posedge clk_i) begin
        for (lane_index = 0; lane_index < 4; lane_index = lane_index + 1) begin
            sign_s1_q[lane_index] <= prepare_sign_comb[lane_index];
            significand_s1_q[lane_index] <= prepare_significand_comb[lane_index];
            left_shift_s1_q[lane_index] <= prepare_left_shift_comb[lane_index];
        end
        special_state_s1_q <= special_state_comb;
        zero_sign_state_s1_q <= zero_sign_state_comb;
        invalid_s1_q <= invalid_comb;
        rounding_s1_q <= rounding_i;

        for (lane_index = 0; lane_index < 4; lane_index = lane_index + 1) begin
            sign_s2_q[lane_index] <= sign_s1_q[lane_index];
            fine_aligned_s2_q[lane_index] <= fine_aligned_comb[lane_index];
            coarse_shift_s2_q[lane_index] <= coarse_shift_comb[lane_index];
        end
        special_state_s2_q <= special_state_s1_q;
        zero_sign_state_s2_q <= zero_sign_state_s1_q;
        invalid_s2_q <= invalid_s1_q;
        rounding_s2_q <= rounding_s1_q;

        csa_sum_l1_s3_q <= csa_sum_l1_comb;
        csa_carry_l1_s3_q <= csa_carry_l1_comb;
        signed_pattern3_s3_q <= signed_pattern_comb[3];
        negative_count_s3_q <= negative_count_comb;
        special_state_s3_q <= special_state_s2_q;
        zero_sign_state_s3_q <= zero_sign_state_s2_q;
        invalid_s3_q <= invalid_s2_q;
        rounding_s3_q <= rounding_s2_q;

        csa_sum_s4_q <= csa_sum_l3_comb;
        csa_carry_s4_q <= csa_carry_l3_comb;
        special_state_s4_q <= special_state_s3_q;
        zero_sign_state_s4_q <= zero_sign_state_s3_q;
        invalid_s4_q <= invalid_s3_q;
        rounding_s4_q <= rounding_s3_q;

        exact_sum_s5_q <= exact_sum_comb;
        special_state_s5_q <= special_state_s4_q;
        zero_sign_state_s5_q <= zero_sign_state_s4_q;
        invalid_s5_q <= invalid_s4_q;
        rounding_s5_q <= rounding_s4_q;

        magnitude_s6_q <= magnitude_comb;
        finite_sign_s6_q <= finite_sign_comb;
        special_state_s6_q <= special_state_s5_q;
        invalid_s6_q <= invalid_s5_q;
        rounding_s6_q <= rounding_s5_q;

        magnitude_s7_q <= magnitude_s6_q;
        msb_index_s7_q <= msb_index_comb;
        nonzero_s7_q <= nonzero_comb;
        finite_sign_s7_q <= finite_sign_s6_q;
        special_state_s7_q <= special_state_s6_q;
        invalid_s7_q <= invalid_s6_q;
        rounding_s7_q <= rounding_s6_q;

        coarse_magnitude_s8_q <= coarse_magnitude_comb;
        normalize_fine_shift_s8_q <= normalize_fine_shift_comb;
        normalize_shift_right_s8_q <= normalize_shift_right_comb;
        normalize_sticky_s8_q <= normalize_sticky_comb;
        normalized_exponent_s8_q <= normalized_exponent_comb;
        finite_sign_s8_q <= finite_sign_s7_q;
        special_state_s8_q <= special_state_s7_q;
        invalid_s8_q <= invalid_s7_q;
        rounding_s8_q <= rounding_s7_q;

        normalized_significand_s9_q <= normalized_significand_comb;
        normalized_exponent_s9_q <= normalized_exponent_s8_q;
        finite_sign_s9_q <= finite_sign_s8_q;
        special_state_s9_q <= special_state_s8_q;
        invalid_s9_q <= invalid_s8_q;
        rounding_s9_q <= rounding_s8_q;

        round_main_s10_q <= round_main_comb;
        round_group_all_ones_s10_q <= round_group_all_ones_comb;
        round_increment_s10_q <= round_increment_comb;
        normalized_exponent_s10_q <= normalized_exponent_s9_q[7:0];
        exponent_in_range_s10_q <= exponent_in_range_comb;
        zero_s10_q <= (normalized_significand_s9_q == 27'd0);
        finite_sign_s10_q <= finite_sign_s9_q;
        special_state_s10_q <= special_state_s9_q;
        invalid_s10_q <= invalid_s9_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_s1_q <= 1'b0;
            valid_s2_q <= 1'b0;
            valid_s3_q <= 1'b0;
            valid_s4_q <= 1'b0;
            valid_s5_q <= 1'b0;
            valid_s6_q <= 1'b0;
            valid_s7_q <= 1'b0;
            valid_s8_q <= 1'b0;
            valid_s9_q <= 1'b0;
            valid_s10_q <= 1'b0;
            valid_o <= 1'b0;
        end else begin
            valid_s1_q <= valid_i;
            valid_s2_q <= valid_s1_q;
            valid_s3_q <= valid_s2_q;
            valid_s4_q <= valid_s3_q;
            valid_s5_q <= valid_s4_q;
            valid_s6_q <= valid_s5_q;
            valid_s7_q <= valid_s6_q;
            valid_s8_q <= valid_s7_q;
            valid_s9_q <= valid_s8_q;
            valid_s10_q <= valid_s9_q;
            valid_o <= valid_s10_q;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            result_o <= 32'h00000000;
            invalid_o <= 1'b0;
        end else begin
            result_o <= packed_result_comb;
            invalid_o <= clear_i ? 1'b0 : (valid_s10_q && invalid_s10_q);
        end
    end

endmodule
