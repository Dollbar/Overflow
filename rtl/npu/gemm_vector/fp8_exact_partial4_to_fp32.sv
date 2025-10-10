`timescale 1ns/1ps

module fp8_exact_partial4_to_fp32 #( // 将四个67位精确部分和融合为一次舍入的FP32列结果
    parameter bit FTZ = 1'b0
) (
    input  logic                           clk_i,
    input  logic                           rst_i,
    input  logic                           clear_i,
    input  logic                           valid_i,
    input  logic signed             [66:0] exact0_i,
    input  logic signed             [66:0] exact1_i,
    input  logic signed             [66:0] exact2_i,
    input  logic signed             [66:0] exact3_i,
    input  fp8_pkg::fp8_reduce_special_e   special0_i,
    input  fp8_pkg::fp8_reduce_special_e   special1_i,
    input  fp8_pkg::fp8_reduce_special_e   special2_i,
    input  fp8_pkg::fp8_reduce_special_e   special3_i,
    input  fp8_pkg::fp8_reduce_zero_sign_e zero_sign0_i,
    input  fp8_pkg::fp8_reduce_zero_sign_e zero_sign1_i,
    input  fp8_pkg::fp8_reduce_zero_sign_e zero_sign2_i,
    input  fp8_pkg::fp8_reduce_zero_sign_e zero_sign3_i,
    input  logic                     [3:0] invalid_i,
    input  fp8_pkg::fp8_rounding_e         rounding_i,
    output logic                           valid_o,
    output logic                    [31:0] result_o,
    output logic                           invalid_o
);

    localparam logic [31:0] FP32_CANONICAL_NAN = 32'h7fc00000;
    localparam logic [31:0] FP32_POSITIVE_INF = 32'h7f800000;
    localparam logic [31:0] FP32_NEGATIVE_INF = 32'hff800000;

    logic [68:0] exact_extended_comb [0:3];
    logic [68:0] csa_sum_l1_comb;
    logic [68:0] csa_carry_l1_comb;
    logic [68:0] csa_sum_l1_s1_q;
    logic [68:0] csa_carry_l1_s1_q;
    logic [68:0] exact3_s1_q;
    fp8_pkg::fp8_reduce_special_e special_state_comb;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_comb;
    fp8_pkg::fp8_reduce_special_e special_state_s1_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s1_q;
    logic invalid_comb;
    logic invalid_s1_q;
    fp8_pkg::fp8_rounding_e rounding_s1_q;
    logic valid_s1_q;

    logic [68:0] csa_sum_l2_comb;
    logic [68:0] csa_carry_l2_comb;
    logic [68:0] csa_sum_s2_q;
    logic [68:0] csa_carry_s2_q;
    fp8_pkg::fp8_reduce_special_e special_state_s2_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s2_q;
    logic invalid_s2_q;
    fp8_pkg::fp8_rounding_e rounding_s2_q;
    logic valid_s2_q;

    logic [68:0] exact_sum_comb;
    logic [68:0] exact_sum_s3_q;
    fp8_pkg::fp8_reduce_special_e special_state_s3_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_state_s3_q;
    logic invalid_s3_q;
    fp8_pkg::fp8_rounding_e rounding_s3_q;
    logic valid_s3_q;

    logic [68:0] abs_input_comb;
    logic [68:0] magnitude_comb;
    logic finite_sign_comb;
    logic [68:0] magnitude_s4_q;
    logic finite_sign_s4_q;
    fp8_pkg::fp8_reduce_special_e special_state_s4_q;
    logic invalid_s4_q;
    fp8_pkg::fp8_rounding_e rounding_s4_q;
    logic valid_s4_q;

    logic nonzero_comb;
    logic [6:0] msb_index_comb;
    logic [68:0] magnitude_s5_q;
    logic [6:0] msb_index_s5_q;
    logic nonzero_s5_q;
    logic finite_sign_s5_q;
    fp8_pkg::fp8_reduce_special_e special_state_s5_q;
    logic invalid_s5_q;
    fp8_pkg::fp8_rounding_e rounding_s5_q;
    logic valid_s5_q;

    logic [68:0] coarse_magnitude_comb;
    logic [2:0] normalize_fine_shift_comb;
    logic normalize_shift_right_comb;
    logic normalize_sticky_comb;
    logic signed [10:0] normalized_exponent_comb;
    logic [68:0] coarse_magnitude_s6_q;
    logic [2:0] normalize_fine_shift_s6_q;
    logic normalize_shift_right_s6_q;
    logic normalize_sticky_s6_q;
    logic signed [10:0] normalized_exponent_s6_q;
    logic finite_sign_s6_q;
    fp8_pkg::fp8_reduce_special_e special_state_s6_q;
    logic invalid_s6_q;
    fp8_pkg::fp8_rounding_e rounding_s6_q;
    logic valid_s6_q;

    logic [26:0] normalized_significand_comb;
    logic [26:0] normalized_significand_s7_q;
    logic signed [10:0] normalized_exponent_s7_q;
    logic finite_sign_s7_q;
    fp8_pkg::fp8_reduce_special_e special_state_s7_q;
    logic invalid_s7_q;
    fp8_pkg::fp8_rounding_e rounding_s7_q;
    logic valid_s7_q;

    logic [22:0] round_main_comb;
    logic [5:0] round_group_all_ones_comb;
    logic round_increment_comb;
    logic exponent_in_range_comb;
    logic [22:0] round_main_s8_q;
    logic [5:0] round_group_all_ones_s8_q;
    logic round_increment_s8_q;
    logic signed [7:0] normalized_exponent_s8_q;
    logic exponent_in_range_s8_q;
    logic zero_s8_q;
    logic finite_sign_s8_q;
    fp8_pkg::fp8_reduce_special_e special_state_s8_q;
    logic invalid_s8_q;
    logic valid_s8_q;

    logic special_valid_s8_comb;
    logic [31:0] special_result_s8_comb;
    logic [31:0] packed_result_comb;

    assign exact_extended_comb[0] = {{2{exact0_i[66]}}, exact0_i};
    assign exact_extended_comb[1] = {{2{exact1_i[66]}}, exact1_i};
    assign exact_extended_comb[2] = {{2{exact2_i[66]}}, exact2_i};
    assign exact_extended_comb[3] = {{2{exact3_i[66]}}, exact3_i};
    assign csa_sum_l1_comb = exact_extended_comb[0] ^ exact_extended_comb[1] ^
                             exact_extended_comb[2];
    assign csa_carry_l1_comb = ((exact_extended_comb[0] & exact_extended_comb[1]) |
                                (exact_extended_comb[0] & exact_extended_comb[2]) |
                                (exact_extended_comb[1] & exact_extended_comb[2])) << 1;
    assign csa_sum_l2_comb = csa_sum_l1_s1_q ^ csa_carry_l1_s1_q ^ exact3_s1_q;
    assign csa_carry_l2_comb = ((csa_sum_l1_s1_q & csa_carry_l1_s1_q) |
                                (csa_sum_l1_s1_q & exact3_s1_q) |
                                (csa_carry_l1_s1_q & exact3_s1_q)) << 1;

    always_comb begin // 将四组特殊值合并为整列IEEE结果状态
        invalid_comb = (|invalid_i) ||
                       (((special0_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                         (special1_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                         (special2_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                         (special3_i == fp8_pkg::FP8_REDUCE_POS_INF)) &&
                        ((special0_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                         (special1_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                         (special2_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                         (special3_i == fp8_pkg::FP8_REDUCE_NEG_INF)));
        special_state_comb = fp8_pkg::FP8_REDUCE_NORMAL;
        if ((special0_i == fp8_pkg::FP8_REDUCE_NAN) ||
            (special1_i == fp8_pkg::FP8_REDUCE_NAN) ||
            (special2_i == fp8_pkg::FP8_REDUCE_NAN) ||
            (special3_i == fp8_pkg::FP8_REDUCE_NAN) ||
            (((special0_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
              (special1_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
              (special2_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
              (special3_i == fp8_pkg::FP8_REDUCE_POS_INF)) &&
             ((special0_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
              (special1_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
              (special2_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
              (special3_i == fp8_pkg::FP8_REDUCE_NEG_INF)))) begin
            special_state_comb = fp8_pkg::FP8_REDUCE_NAN;
        end else if ((special0_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                     (special1_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                     (special2_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                     (special3_i == fp8_pkg::FP8_REDUCE_POS_INF)) begin
            special_state_comb = fp8_pkg::FP8_REDUCE_POS_INF;
        end else if ((special0_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                     (special1_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                     (special2_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                     (special3_i == fp8_pkg::FP8_REDUCE_NEG_INF)) begin
            special_state_comb = fp8_pkg::FP8_REDUCE_NEG_INF;
        end
        zero_sign_state_comb = fp8_pkg::FP8_ZERO_SIGN_ROUNDING;
        if ((zero_sign0_i == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE) &&
            (zero_sign1_i == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE) &&
            (zero_sign2_i == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE) &&
            (zero_sign3_i == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE)) begin
            zero_sign_state_comb = fp8_pkg::FP8_ZERO_SIGN_NEGATIVE;
        end else if ((zero_sign0_i == fp8_pkg::FP8_ZERO_SIGN_POSITIVE) &&
                     (zero_sign1_i == fp8_pkg::FP8_ZERO_SIGN_POSITIVE) &&
                     (zero_sign2_i == fp8_pkg::FP8_ZERO_SIGN_POSITIVE) &&
                     (zero_sign3_i == fp8_pkg::FP8_ZERO_SIGN_POSITIVE)) begin
            zero_sign_state_comb = fp8_pkg::FP8_ZERO_SIGN_POSITIVE;
        end
    end

    kogge_stone_adder_69 u_exact_sum_adder (
        .a_i   (csa_sum_s2_q),
        .b_i   (csa_carry_s2_q),
        .cin_i (1'b0),
        .sum_o (exact_sum_comb)
    );

    assign abs_input_comb = exact_sum_s3_q ^ {69{exact_sum_s3_q[68]}};

    kogge_stone_adder_69 u_absolute_value_adder (
        .a_i   (abs_input_comb),
        .b_i   (69'd0),
        .cin_i (exact_sum_s3_q[68]),
        .sum_o (magnitude_comb)
    );

    always_comb begin // 精确抵消为零时按原始零符号集合和舍入方向恢复符号
        finite_sign_comb = exact_sum_s3_q[68];
        if (exact_sum_s3_q == 69'd0) begin
            case (zero_sign_state_s3_q)
                fp8_pkg::FP8_ZERO_SIGN_NEGATIVE: finite_sign_comb = 1'b1;
                fp8_pkg::FP8_ZERO_SIGN_POSITIVE: finite_sign_comb = 1'b0;
                default: finite_sign_comb = (rounding_s3_q == fp8_pkg::RDN);
            endcase
        end
    end

    fp8_partial_fixed69_lzc u_fixed69_lzc (
        .magnitude_i (magnitude_s4_q),
        .nonzero_o   (nonzero_comb),
        .msb_index_o (msb_index_comb)
    );

    fp8_partial_fixed69_normalize_coarse u_normalize_coarse (
        .magnitude_i        (magnitude_s5_q),
        .msb_index_i        (msb_index_s5_q),
        .nonzero_i          (nonzero_s5_q),
        .coarse_magnitude_o (coarse_magnitude_comb),
        .fine_shift_o       (normalize_fine_shift_comb),
        .shift_right_o      (normalize_shift_right_comb),
        .sticky_o           (normalize_sticky_comb),
        .exponent_o         (normalized_exponent_comb)
    );

    fp8_partial_fixed69_normalize_fine u_normalize_fine (
        .coarse_magnitude_i (coarse_magnitude_s6_q),
        .fine_shift_i       (normalize_fine_shift_s6_q),
        .shift_right_i      (normalize_shift_right_s6_q),
        .sticky_i           (normalize_sticky_s6_q),
        .significand_o      (normalized_significand_comb)
    );

    fp8_partial_round_prepare u_round_prepare (
        .sign_i                 (finite_sign_s7_q),
        .significand_i          (normalized_significand_s7_q),
        .exponent_i             (normalized_exponent_s7_q),
        .rounding_i             (rounding_s7_q),
        .round_main_o           (round_main_comb),
        .round_group_all_ones_o (round_group_all_ones_comb),
        .round_increment_o      (round_increment_comb),
        .exponent_in_range_o    (exponent_in_range_comb)
    );

    always_comb begin // 将列级特殊状态转换为统一FP32旁路编码
        special_valid_s8_comb = 1'b1;
        case (special_state_s8_q)
            fp8_pkg::FP8_REDUCE_NAN: special_result_s8_comb = FP32_CANONICAL_NAN;
            fp8_pkg::FP8_REDUCE_POS_INF: special_result_s8_comb = FP32_POSITIVE_INF;
            fp8_pkg::FP8_REDUCE_NEG_INF: special_result_s8_comb = FP32_NEGATIVE_INF;
            default: begin
                special_valid_s8_comb = 1'b0;
                special_result_s8_comb = 32'h00000000;
            end
        endcase
    end

    fp8_reduce4_round_pack #(.FTZ(FTZ)) u_round_pack (
        .sign_i                 (finite_sign_s8_q),
        .round_main_i           (round_main_s8_q),
        .round_group_all_ones_i (round_group_all_ones_s8_q),
        .round_increment_i      (round_increment_s8_q),
        .exponent_i             (normalized_exponent_s8_q),
        .exponent_in_range_i    (exponent_in_range_s8_q),
        .zero_i                 (zero_s8_q),
        .special_valid_i        (special_valid_s8_comb),
        .special_result_i       (special_result_s8_comb),
        .result_o               (packed_result_comb)
    );

    always_ff @(posedge clk_i) begin // 八级内部流水覆盖CSA、CPA、绝对值、LZC、规格化和舍入准备
        csa_sum_l1_s1_q <= csa_sum_l1_comb;
        csa_carry_l1_s1_q <= csa_carry_l1_comb;
        exact3_s1_q <= exact_extended_comb[3];
        special_state_s1_q <= special_state_comb;
        zero_sign_state_s1_q <= zero_sign_state_comb;
        invalid_s1_q <= invalid_comb;
        rounding_s1_q <= rounding_i;
        csa_sum_s2_q <= csa_sum_l2_comb;
        csa_carry_s2_q <= csa_carry_l2_comb;
        special_state_s2_q <= special_state_s1_q;
        zero_sign_state_s2_q <= zero_sign_state_s1_q;
        invalid_s2_q <= invalid_s1_q;
        rounding_s2_q <= rounding_s1_q;
        exact_sum_s3_q <= exact_sum_comb;
        special_state_s3_q <= special_state_s2_q;
        zero_sign_state_s3_q <= zero_sign_state_s2_q;
        invalid_s3_q <= invalid_s2_q;
        rounding_s3_q <= rounding_s2_q;
        magnitude_s4_q <= magnitude_comb;
        finite_sign_s4_q <= finite_sign_comb;
        special_state_s4_q <= special_state_s3_q;
        invalid_s4_q <= invalid_s3_q;
        rounding_s4_q <= rounding_s3_q;
        magnitude_s5_q <= magnitude_s4_q;
        msb_index_s5_q <= msb_index_comb;
        nonzero_s5_q <= nonzero_comb;
        finite_sign_s5_q <= finite_sign_s4_q;
        special_state_s5_q <= special_state_s4_q;
        invalid_s5_q <= invalid_s4_q;
        rounding_s5_q <= rounding_s4_q;
        coarse_magnitude_s6_q <= coarse_magnitude_comb;
        normalize_fine_shift_s6_q <= normalize_fine_shift_comb;
        normalize_shift_right_s6_q <= normalize_shift_right_comb;
        normalize_sticky_s6_q <= normalize_sticky_comb;
        normalized_exponent_s6_q <= normalized_exponent_comb;
        finite_sign_s6_q <= finite_sign_s5_q;
        special_state_s6_q <= special_state_s5_q;
        invalid_s6_q <= invalid_s5_q;
        rounding_s6_q <= rounding_s5_q;
        normalized_significand_s7_q <= normalized_significand_comb;
        normalized_exponent_s7_q <= normalized_exponent_s6_q;
        finite_sign_s7_q <= finite_sign_s6_q;
        special_state_s7_q <= special_state_s6_q;
        invalid_s7_q <= invalid_s6_q;
        rounding_s7_q <= rounding_s6_q;
        round_main_s8_q <= round_main_comb;
        round_group_all_ones_s8_q <= round_group_all_ones_comb;
        round_increment_s8_q <= round_increment_comb;
        normalized_exponent_s8_q <= normalized_exponent_s7_q[7:0];
        exponent_in_range_s8_q <= exponent_in_range_comb;
        zero_s8_q <= (normalized_significand_s7_q == 27'd0);
        finite_sign_s8_q <= finite_sign_s7_q;
        special_state_s8_q <= special_state_s7_q;
        invalid_s8_q <= invalid_s7_q;
    end

    always_ff @(posedge clk_i) begin // reset或clear清除有效推进但不复位宽数据流水寄存器
        if (rst_i || clear_i) begin
            valid_s1_q <= 1'b0;
            valid_s2_q <= 1'b0;
            valid_s3_q <= 1'b0;
            valid_s4_q <= 1'b0;
            valid_s5_q <= 1'b0;
            valid_s6_q <= 1'b0;
            valid_s7_q <= 1'b0;
            valid_s8_q <= 1'b0;
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
            valid_o <= valid_s8_q;
        end
    end

    always_ff @(posedge clk_i) begin // 第九级寄存最终FP32编码并对齐invalid状态
        if (rst_i) begin
            result_o <= 32'h00000000;
            invalid_o <= 1'b0;
        end else begin
            result_o <= packed_result_comb;
            invalid_o <= clear_i ? 1'b0 : (valid_s8_q && invalid_s8_q);
        end
    end

endmodule
