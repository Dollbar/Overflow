`timescale 1ns/1ps

module fp8_exact_reduce4 ( // 将四个FP8精确乘积归约为统一Q32定点和且不执行FP32舍入
    input  logic                           clk_i,
    input  logic                           rst_i,
    input  logic                           clear_i,
    input  logic                           valid_i,
    input  fp8_pkg::fp8_product_t          product0_i,
    input  fp8_pkg::fp8_product_t          product1_i,
    input  fp8_pkg::fp8_product_t          product2_i,
    input  fp8_pkg::fp8_product_t          product3_i,
    input  logic                     [3:0] invalid_i,
    input  fp8_pkg::fp8_rounding_e         rounding_i,
    output logic                           valid_o,
    output logic signed             [66:0] exact_sum_o,
    output fp8_pkg::fp8_reduce_special_e   special_o,
    output fp8_pkg::fp8_reduce_zero_sign_e zero_sign_o,
    output logic                           invalid_o,
    output fp8_pkg::fp8_rounding_e         rounding_o
);

    logic [3:0] prepare_sign_comb;
    logic [7:0] prepare_significand_comb [0:3];
    logic [5:0] prepare_left_shift_comb [0:3];
    logic [3:0] product_nan_comb;
    logic [3:0] product_pos_inf_comb;
    logic [3:0] product_neg_inf_comb;
    logic [3:0] product_zero_comb;
    logic [3:0] product_zero_sign_comb;
    logic any_nan_comb;
    logic any_pos_inf_comb;
    logic any_neg_inf_comb;
    fp8_pkg::fp8_reduce_special_e special_state_comb;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_comb;
    logic invalid_comb;

    logic [3:0] sign_s1_q;
    logic [7:0] significand_s1_q [0:3];
    logic [5:0] left_shift_s1_q [0:3];
    fp8_pkg::fp8_reduce_special_e special_state_s1_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s1_q;
    logic invalid_s1_q;
    fp8_pkg::fp8_rounding_e rounding_s1_q;
    logic valid_s1_q;

    logic [14:0] fine_aligned_comb [0:3];
    logic [2:0] coarse_shift_comb [0:3];
    logic [3:0] sign_s2_q;
    logic [14:0] fine_aligned_s2_q [0:3];
    logic [2:0] coarse_shift_s2_q [0:3];
    fp8_pkg::fp8_reduce_special_e special_state_s2_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s2_q;
    logic invalid_s2_q;
    fp8_pkg::fp8_rounding_e rounding_s2_q;
    logic valid_s2_q;

    logic [66:0] aligned_magnitude_comb [0:3];
    logic [66:0] signed_pattern_comb [0:3];
    logic [2:0] negative_count_comb;
    logic [66:0] csa_sum_l1_comb;
    logic [66:0] csa_carry_l1_comb;
    logic [66:0] csa_sum_l1_s3_q;
    logic [66:0] csa_carry_l1_s3_q;
    logic [66:0] signed_pattern3_s3_q;
    logic [2:0] negative_count_s3_q;
    fp8_pkg::fp8_reduce_special_e special_state_s3_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s3_q;
    logic invalid_s3_q;
    fp8_pkg::fp8_rounding_e rounding_s3_q;
    logic valid_s3_q;

    logic [66:0] correction_s3_comb;
    logic [66:0] csa_sum_l2_comb;
    logic [66:0] csa_carry_l2_comb;
    logic [66:0] csa_sum_l3_comb;
    logic [66:0] csa_carry_l3_comb;
    logic [66:0] csa_sum_s4_q;
    logic [66:0] csa_carry_s4_q;
    fp8_pkg::fp8_reduce_special_e special_state_s4_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s4_q;
    logic invalid_s4_q;
    fp8_pkg::fp8_rounding_e rounding_s4_q;
    logic valid_s4_q;

    logic [66:0] exact_sum_comb;
    logic [66:0] exact_sum_s5_q;
    fp8_pkg::fp8_reduce_special_e special_state_s5_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s5_q;
    logic invalid_s5_q;
    fp8_pkg::fp8_rounding_e rounding_s5_q;
    logic valid_s5_q;
    integer lane_index;

    fp8_product_prepare u_prepare_product0 (
        .product_i     (product0_i),
        .sign_o        (prepare_sign_comb[0]),
        .significand_o (prepare_significand_comb[0]),
        .left_shift_o  (prepare_left_shift_comb[0]),
        .is_nan_o      (product_nan_comb[0]),
        .is_pos_inf_o  (product_pos_inf_comb[0]),
        .is_neg_inf_o  (product_neg_inf_comb[0]),
        .is_zero_o     (product_zero_comb[0]),
        .zero_sign_o   (product_zero_sign_comb[0])
    );

    fp8_product_prepare u_prepare_product1 (
        .product_i     (product1_i),
        .sign_o        (prepare_sign_comb[1]),
        .significand_o (prepare_significand_comb[1]),
        .left_shift_o  (prepare_left_shift_comb[1]),
        .is_nan_o      (product_nan_comb[1]),
        .is_pos_inf_o  (product_pos_inf_comb[1]),
        .is_neg_inf_o  (product_neg_inf_comb[1]),
        .is_zero_o     (product_zero_comb[1]),
        .zero_sign_o   (product_zero_sign_comb[1])
    );

    fp8_product_prepare u_prepare_product2 (
        .product_i     (product2_i),
        .sign_o        (prepare_sign_comb[2]),
        .significand_o (prepare_significand_comb[2]),
        .left_shift_o  (prepare_left_shift_comb[2]),
        .is_nan_o      (product_nan_comb[2]),
        .is_pos_inf_o  (product_pos_inf_comb[2]),
        .is_neg_inf_o  (product_neg_inf_comb[2]),
        .is_zero_o     (product_zero_comb[2]),
        .zero_sign_o   (product_zero_sign_comb[2])
    );

    fp8_product_prepare u_prepare_product3 (
        .product_i     (product3_i),
        .sign_o        (prepare_sign_comb[3]),
        .significand_o (prepare_significand_comb[3]),
        .left_shift_o  (prepare_left_shift_comb[3]),
        .is_nan_o      (product_nan_comb[3]),
        .is_pos_inf_o  (product_pos_inf_comb[3]),
        .is_neg_inf_o  (product_neg_inf_comb[3]),
        .is_zero_o     (product_zero_comb[3]),
        .zero_sign_o   (product_zero_sign_comb[3])
    );

    always_comb begin // 合并四个乘积的IEEE特殊值、无效标志和精确零符号语义
        any_nan_comb = |product_nan_comb;
        any_pos_inf_comb = |product_pos_inf_comb;
        any_neg_inf_comb = |product_neg_inf_comb;
        invalid_comb = (|invalid_i) || (any_pos_inf_comb && any_neg_inf_comb);
        zero_sign_state_comb = fp8_pkg::FP8_ZERO_SIGN_ROUNDING;
        if (&product_zero_comb) begin
            if (&product_zero_sign_comb) begin
                zero_sign_state_comb = fp8_pkg::FP8_ZERO_SIGN_NEGATIVE;
            end else if (!(|product_zero_sign_comb)) begin
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

    generate
        for (genvar lane = 0; lane < 4; lane = lane + 1) begin : gen_product_alignment
            fp8_product_align_fine u_align_fine (
                .significand_i  (significand_s1_q[lane]),
                .left_shift_i   (left_shift_s1_q[lane]),
                .fine_aligned_o (fine_aligned_comb[lane]),
                .coarse_shift_o (coarse_shift_comb[lane])
            );

            fp8_product_align_coarse u_align_coarse (
                .fine_aligned_i (fine_aligned_s2_q[lane]),
                .coarse_shift_i (coarse_shift_s2_q[lane]),
                .magnitude_o    (aligned_magnitude_comb[lane])
            );

            assign signed_pattern_comb[lane] = aligned_magnitude_comb[lane] ^
                                                {67{sign_s2_q[lane]}};
        end
    endgenerate

    assign negative_count_comb = {2'd0, sign_s2_q[0]} +
                                 {2'd0, sign_s2_q[1]} +
                                 {2'd0, sign_s2_q[2]} +
                                 {2'd0, sign_s2_q[3]};
    assign correction_s3_comb = {64'd0, negative_count_s3_q};
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

    kogge_stone_adder_67 u_exact_sum_adder (
        .a_i   (csa_sum_s4_q),
        .b_i   (csa_carry_s4_q),
        .cin_i (1'b0),
        .sum_o (exact_sum_comb)
    );

    always_ff @(posedge clk_i) begin // 五级流水仅保留精确定点和及其控制元数据
        for (lane_index = 0; lane_index < 4; lane_index = lane_index + 1) begin
            sign_s1_q[lane_index] <= prepare_sign_comb[lane_index];
            significand_s1_q[lane_index] <= prepare_significand_comb[lane_index];
            left_shift_s1_q[lane_index] <= prepare_left_shift_comb[lane_index];
            sign_s2_q[lane_index] <= sign_s1_q[lane_index];
            fine_aligned_s2_q[lane_index] <= fine_aligned_comb[lane_index];
            coarse_shift_s2_q[lane_index] <= coarse_shift_comb[lane_index];
        end
        special_state_s1_q <= special_state_comb;
        zero_sign_state_s1_q <= zero_sign_state_comb;
        invalid_s1_q <= invalid_comb;
        rounding_s1_q <= rounding_i;
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
    end

    always_ff @(posedge clk_i) begin // reset或clear只清除有效链以降低宽数据寄存器的控制扇出
        if (rst_i || clear_i) begin
            valid_s1_q <= 1'b0;
            valid_s2_q <= 1'b0;
            valid_s3_q <= 1'b0;
            valid_s4_q <= 1'b0;
            valid_s5_q <= 1'b0;
        end else begin
            valid_s1_q <= valid_i;
            valid_s2_q <= valid_s1_q;
            valid_s3_q <= valid_s2_q;
            valid_s4_q <= valid_s3_q;
            valid_s5_q <= valid_s4_q;
        end
    end

    assign valid_o = valid_s5_q;
    assign exact_sum_o = $signed(exact_sum_s5_q);
    assign special_o = special_state_s5_q;
    assign zero_sign_o = zero_sign_state_s5_q;
    assign invalid_o = valid_s5_q && invalid_s5_q;
    assign rounding_o = rounding_s5_q;

endmodule
