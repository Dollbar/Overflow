`timescale 1ns/1ps
`default_nettype none

module fp8_exact_partial4_reduce (
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
    output logic signed             [68:0] exact_sum_o,
    output fp8_pkg::fp8_reduce_special_e   special_o,
    output fp8_pkg::fp8_reduce_zero_sign_e zero_sign_o,
    output logic                           invalid_o,
    output fp8_pkg::fp8_rounding_e         rounding_o
);

    logic [68:0] exact_extended [0:3];
    logic [68:0] csa_sum_l1;
    logic [68:0] csa_carry_l1;
    logic [68:0] csa_sum_l1_q;
    logic [68:0] csa_carry_l1_q;
    logic [68:0] exact3_q;
    logic [68:0] csa_sum_l2;
    logic [68:0] csa_carry_l2;
    logic [68:0] csa_sum_l2_q;
    logic [68:0] csa_carry_l2_q;
    logic [68:0] exact_sum;
    fp8_pkg::fp8_reduce_special_e special_comb;
    fp8_pkg::fp8_reduce_special_e special_s1_q;
    fp8_pkg::fp8_reduce_special_e special_s2_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_comb;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_s1_q;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_s2_q;
    logic invalid_comb;
    logic invalid_s1_q;
    logic invalid_s2_q;
    fp8_pkg::fp8_rounding_e rounding_s1_q;
    fp8_pkg::fp8_rounding_e rounding_s2_q;
    logic valid_s1_q;
    logic valid_s2_q;

    assign exact_extended[0] = {{2{exact0_i[66]}}, exact0_i};
    assign exact_extended[1] = {{2{exact1_i[66]}}, exact1_i};
    assign exact_extended[2] = {{2{exact2_i[66]}}, exact2_i};
    assign exact_extended[3] = {{2{exact3_i[66]}}, exact3_i};
    assign csa_sum_l1 = exact_extended[0] ^ exact_extended[1] ^ exact_extended[2];
    assign csa_carry_l1 = ((exact_extended[0] & exact_extended[1]) |
                           (exact_extended[0] & exact_extended[2]) |
                           (exact_extended[1] & exact_extended[2])) << 1;
    assign csa_sum_l2 = csa_sum_l1_q ^ csa_carry_l1_q ^ exact3_q;
    assign csa_carry_l2 = ((csa_sum_l1_q & csa_carry_l1_q) |
                           (csa_sum_l1_q & exact3_q) |
                           (csa_carry_l1_q & exact3_q)) << 1;

    always_comb begin
        invalid_comb = (|invalid_i) ||
            (((special0_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
              (special1_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
              (special2_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
              (special3_i == fp8_pkg::FP8_REDUCE_POS_INF)) &&
             ((special0_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
              (special1_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
              (special2_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
              (special3_i == fp8_pkg::FP8_REDUCE_NEG_INF)));
        special_comb = fp8_pkg::FP8_REDUCE_NORMAL;
        if ((special0_i == fp8_pkg::FP8_REDUCE_NAN) ||
            (special1_i == fp8_pkg::FP8_REDUCE_NAN) ||
            (special2_i == fp8_pkg::FP8_REDUCE_NAN) ||
            (special3_i == fp8_pkg::FP8_REDUCE_NAN) || invalid_comb) begin
            special_comb = fp8_pkg::FP8_REDUCE_NAN;
        end else if ((special0_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                     (special1_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                     (special2_i == fp8_pkg::FP8_REDUCE_POS_INF) ||
                     (special3_i == fp8_pkg::FP8_REDUCE_POS_INF)) begin
            special_comb = fp8_pkg::FP8_REDUCE_POS_INF;
        end else if ((special0_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                     (special1_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                     (special2_i == fp8_pkg::FP8_REDUCE_NEG_INF) ||
                     (special3_i == fp8_pkg::FP8_REDUCE_NEG_INF)) begin
            special_comb = fp8_pkg::FP8_REDUCE_NEG_INF;
        end

        zero_sign_comb = fp8_pkg::FP8_ZERO_SIGN_ROUNDING;
        if ((zero_sign0_i == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE) &&
            (zero_sign1_i == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE) &&
            (zero_sign2_i == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE) &&
            (zero_sign3_i == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE)) begin
            zero_sign_comb = fp8_pkg::FP8_ZERO_SIGN_NEGATIVE;
        end else if ((zero_sign0_i == fp8_pkg::FP8_ZERO_SIGN_POSITIVE) &&
                     (zero_sign1_i == fp8_pkg::FP8_ZERO_SIGN_POSITIVE) &&
                     (zero_sign2_i == fp8_pkg::FP8_ZERO_SIGN_POSITIVE) &&
                     (zero_sign3_i == fp8_pkg::FP8_ZERO_SIGN_POSITIVE)) begin
            zero_sign_comb = fp8_pkg::FP8_ZERO_SIGN_POSITIVE;
        end
    end

    kogge_stone_adder_69 u_exact_sum_adder (
        .a_i   (csa_sum_l2_q),
        .b_i   (csa_carry_l2_q),
        .cin_i (1'b0),
        .sum_o (exact_sum)
    );

    always_ff @(posedge clk_i) begin
        csa_sum_l1_q <= csa_sum_l1;
        csa_carry_l1_q <= csa_carry_l1;
        exact3_q <= exact_extended[3];
        special_s1_q <= special_comb;
        zero_sign_s1_q <= zero_sign_comb;
        invalid_s1_q <= invalid_comb;
        rounding_s1_q <= rounding_i;
        csa_sum_l2_q <= csa_sum_l2;
        csa_carry_l2_q <= csa_carry_l2;
        special_s2_q <= special_s1_q;
        zero_sign_s2_q <= zero_sign_s1_q;
        invalid_s2_q <= invalid_s1_q;
        rounding_s2_q <= rounding_s1_q;
        exact_sum_o <= $signed(exact_sum);
        special_o <= special_s2_q;
        zero_sign_o <= zero_sign_s2_q;
        invalid_o <= invalid_s2_q;
        rounding_o <= rounding_s2_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_s1_q <= 1'b0;
            valid_s2_q <= 1'b0;
            valid_o <= 1'b0;
        end else begin
            valid_s1_q <= valid_i;
            valid_s2_q <= valid_s1_q;
            valid_o <= valid_s2_q;
        end
    end

endmodule

`default_nettype wire
