`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "yes" *)
module fp32_mul_pipeline #(
    parameter bit FTZ = 1'b0
) (
    input  logic                    clk_i,
    input  logic                    rst_i,
    input  logic                    clear_i,
    input  logic                    valid_i,
    input  logic             [31:0] a_i,
    input  logic             [31:0] b_i,
    input  logic              [1:0] invalid_i,
    input  fp8_pkg::fp8_rounding_e rounding_i,
    output logic                    valid_o,
    output logic             [31:0] result_o,
    output logic                    invalid_o
);

    localparam logic [31:0] FP32_CANONICAL_NAN = 32'h7fc00000;

    fp8_pkg::fp32_unpacked_t a_unpacked_comb;
    fp8_pkg::fp32_unpacked_t b_unpacked_comb;
    /* verilator lint_off UNUSEDSIGNAL */
    fp8_pkg::fp32_decoded_t a_decoded_s1;
    fp8_pkg::fp32_decoded_t b_decoded_s1;
    /* verilator lint_on UNUSEDSIGNAL */

    logic special_valid_comb;
    logic [31:0] special_result_comb;
    logic invalid_comb;
    logic special_valid_s1_q;
    logic [31:0] special_result_s1_q;
    logic invalid_s1_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s1_q;
    logic valid_s1_q;

    logic [23:0] a_significand_s1n_q;
    logic [23:0] b_significand_s1n_q;
    logic a_sign_s1n_q;
    logic b_sign_s1n_q;
    logic signed [9:0] a_exponent_s1n_q;
    logic signed [9:0] b_exponent_s1n_q;
    logic special_valid_s1n_q;
    logic [31:0] special_result_s1n_q;
    logic invalid_s1n_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s1n_q;
    logic valid_s1n_q;

    logic [11:0] partial6_comb [0:15];
    logic [11:0] partial6_s2_q [0:15];
    logic [47:0] partial_csa_comb [0:3];
    logic [47:0] partial_csa_s2r_q [0:3];
    logic sign_s2r_q;
    logic signed [10:0] exponent_s2r_q;
    logic special_valid_s2r_q;
    logic [31:0] special_result_s2r_q;
    logic invalid_s2r_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s2r_q;
    logic valid_s2r_q;
    logic [23:0] partial_ll_comb;
    logic [23:0] partial_lh_comb;
    logic [23:0] partial_hl_comb;
    logic [23:0] partial_hh_comb;
    logic [23:0] partial_ll_s2_q;
    logic [23:0] partial_lh_s2_q;
    logic [23:0] partial_hl_s2_q;
    logic [23:0] partial_hh_s2_q;
    logic sign_s2_q;
    logic signed [10:0] exponent_s2_q;
    logic special_valid_s2_q;
    logic [31:0] special_result_s2_q;
    logic invalid_s2_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s2_q;
    logic valid_s2_q;
    logic sign_s2c_q;
    logic signed [10:0] exponent_s2c_q;
    logic special_valid_s2c_q;
    logic [31:0] special_result_s2c_q;
    logic invalid_s2c_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s2c_q;
    logic valid_s2c_q;

    logic [47:0] term0_comb;
    logic [47:0] term1_comb;
    logic [47:0] term2_comb;
    logic [47:0] term3_comb;
    logic [47:0] csa_sum_l1_comb;
    logic [47:0] csa_carry_l1_comb;
    logic [47:0] csa_sum_l2_comb;
    logic [47:0] csa_carry_l2_comb;
    logic [47:0] csa_sum_s3_q;
    logic [47:0] csa_carry_s3_q;
    logic sign_s3_q;
    logic signed [10:0] exponent_s3_q;
    logic special_valid_s3_q;
    logic [31:0] special_result_s3_q;
    logic invalid_s3_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s3_q;
    logic valid_s3_q;

    logic [47:0] product_comb;
    logic [47:0] product_s4_q;
    logic sign_s4_q;
    logic signed [10:0] exponent_s4_q;
    logic special_valid_s4_q;
    logic [31:0] special_result_s4_q;
    logic invalid_s4_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s4_q;
    logic valid_s4_q;

    logic [47:0] normalized_product_comb;
    logic signed [10:0] normalized_exponent_comb;
    logic [47:0] normalized_product_s5_q;
    logic signed [10:0] normalized_exponent_s5_q;
    logic sign_s5_q;
    logic special_valid_s5_q;
    logic [31:0] special_result_s5_q;
    logic invalid_s5_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s5_q;
    logic valid_s5_q;

    logic [8:0] subnormal_shift_comb;
    logic [47:0] subnormal_coarse_product_comb;
    logic [3:0] subnormal_fine_shift_comb;
    logic subnormal_coarse_sticky_comb;
    logic subnormal_too_small_comb;
    logic [23:0] normal_main_s6_q;
    logic normal_guard_s6_q;
    logic normal_sticky_s6_q;
    logic [47:0] subnormal_coarse_product_s6_q;
    logic [3:0] subnormal_fine_shift_s6_q;
    logic subnormal_coarse_sticky_s6_q;
    logic subnormal_too_small_s6_q;
    logic signed [10:0] exponent_s6_q;
    logic sign_s6_q;
    logic special_valid_s6_q;
    logic [31:0] special_result_s6_q;
    logic invalid_s6_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s6_q;
    logic valid_s6_q;

    logic [23:0] subnormal_main_comb;
    logic subnormal_guard_comb;
    logic subnormal_sticky_comb;
    logic [23:0] normal_main_s7_q;
    logic normal_guard_s7_q;
    logic normal_sticky_s7_q;
    logic [23:0] subnormal_main_s7_q;
    logic subnormal_guard_s7_q;
    logic subnormal_sticky_s7_q;
    logic signed [10:0] exponent_s7_q;
    logic sign_s7_q;
    logic special_valid_s7_q;
    logic [31:0] special_result_s7_q;
    logic invalid_s7_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s7_q;
    logic valid_s7_q;

    logic [24:0] normal_rounded_comb;
    logic normal_carry_comb;
    logic [23:0] subnormal_rounded_comb;
    logic overflow_to_inf_comb;
    logic [24:0] normal_rounded_s8_q;
    logic normal_carry_s8_q;
    logic [23:0] subnormal_rounded_s8_q;
    logic overflow_to_inf_s8_q;
    logic signed [10:0] exponent_s8_q;
    logic sign_s8_q;
    logic special_valid_s8_q;
    logic [31:0] special_result_s8_q;
    logic invalid_s8_q;
    logic valid_s8_q;

    logic signed [11:0] normal_round_exponent_comb;
    logic [24:0] normal_rounded_s9_q;
    logic signed [11:0] normal_round_exponent_s9_q;
    logic [23:0] subnormal_rounded_s9_q;
    logic overflow_to_inf_s9_q;
    logic signed [10:0] exponent_s9_q;
    logic sign_s9_q;
    logic special_valid_s9_q;
    logic [31:0] special_result_s9_q;
    logic invalid_s9_q;
    logic valid_s9_q;
    logic [31:0] packed_result_comb;

    function automatic logic [47:0] reduce_partial6_csa(
        input logic [11:0] partial00,
        input logic [11:0] partial01,
        input logic [11:0] partial10,
        input logic [11:0] partial11
    );
        logic [23:0] local_term0;
        logic [23:0] local_term1;
        logic [23:0] local_term2;
        logic [23:0] local_term3;
        logic [23:0] local_sum1;
        logic [23:0] local_carry1;
        logic [23:0] local_sum2;
        logic [23:0] local_carry2;
        begin
            local_term0 = {12'd0, partial00};
            local_term1 = {6'd0, partial01, 6'd0};
            local_term2 = {6'd0, partial10, 6'd0};
            local_term3 = {partial11, 12'd0};
            local_sum1 = local_term0 ^ local_term1 ^ local_term2;
            local_carry1 = ((local_term0 & local_term1) |
                            (local_term0 & local_term2) |
                            (local_term1 & local_term2)) << 1;
            local_sum2 = local_sum1 ^ local_carry1 ^ local_term3;
            local_carry2 = ((local_sum1 & local_carry1) |
                            (local_sum1 & local_term3) |
                            (local_carry1 & local_term3)) << 1;
            reduce_partial6_csa = {local_carry2, local_sum2};
        end
    endfunction

    fp32_unpack u_unpack_a (.data_i(a_i), .unpacked_o(a_unpacked_comb));
    fp32_unpack u_unpack_b (.data_i(b_i), .unpacked_o(b_unpacked_comb));
    fp32_subnormal_normalize u_normalize_a (
        .clk_i(clk_i), .rst_i(rst_i || clear_i), .unpacked_i(a_unpacked_comb), .decoded_o(a_decoded_s1));
    fp32_subnormal_normalize u_normalize_b (
        .clk_i(clk_i), .rst_i(rst_i || clear_i), .unpacked_i(b_unpacked_comb), .decoded_o(b_decoded_s1));

    always_comb begin
        special_valid_comb = 1'b1;
        special_result_comb = FP32_CANONICAL_NAN;
        invalid_comb = |invalid_i;
        if (a_unpacked_comb.is_nan || b_unpacked_comb.is_nan) begin
            special_result_comb = FP32_CANONICAL_NAN;
        end else if ((a_unpacked_comb.is_inf && b_unpacked_comb.is_zero) ||
                     (a_unpacked_comb.is_zero && b_unpacked_comb.is_inf)) begin
            special_result_comb = FP32_CANONICAL_NAN;
            invalid_comb = 1'b1;
        end else if (a_unpacked_comb.is_inf || b_unpacked_comb.is_inf) begin
            special_result_comb = {a_unpacked_comb.sign ^ b_unpacked_comb.sign, 8'hff, 23'd0};
        end else if (a_unpacked_comb.is_zero || b_unpacked_comb.is_zero) begin
            special_result_comb = {a_unpacked_comb.sign ^ b_unpacked_comb.sign, 31'd0};
        end else begin
            special_valid_comb = 1'b0;
            special_result_comb = 32'd0;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s1_q <= 1'b0;
        else valid_s1_q <= valid_i;
        special_valid_s1_q <= special_valid_comb;
        special_result_s1_q <= special_result_comb;
        invalid_s1_q <= invalid_comb;
        rounding_s1_q <= rounding_i;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s1n_q <= 1'b0;
        else valid_s1n_q <= valid_s1_q;
        a_significand_s1n_q <= a_decoded_s1.significand;
        b_significand_s1n_q <= b_decoded_s1.significand;
        a_sign_s1n_q <= a_decoded_s1.sign;
        b_sign_s1n_q <= b_decoded_s1.sign;
        a_exponent_s1n_q <= a_decoded_s1.exponent;
        b_exponent_s1n_q <= b_decoded_s1.exponent;
        special_valid_s1n_q <= special_valid_s1_q;
        special_result_s1n_q <= special_result_s1_q;
        invalid_s1n_q <= invalid_s1_q;
        rounding_s1n_q <= rounding_s1_q;
    end

    assign partial6_comb[0] = a_significand_s1n_q[5:0] * b_significand_s1n_q[5:0];
    assign partial6_comb[1] = a_significand_s1n_q[5:0] * b_significand_s1n_q[11:6];
    assign partial6_comb[2] = a_significand_s1n_q[11:6] * b_significand_s1n_q[5:0];
    assign partial6_comb[3] = a_significand_s1n_q[11:6] * b_significand_s1n_q[11:6];
    assign partial6_comb[4] = a_significand_s1n_q[5:0] * b_significand_s1n_q[17:12];
    assign partial6_comb[5] = a_significand_s1n_q[5:0] * b_significand_s1n_q[23:18];
    assign partial6_comb[6] = a_significand_s1n_q[11:6] * b_significand_s1n_q[17:12];
    assign partial6_comb[7] = a_significand_s1n_q[11:6] * b_significand_s1n_q[23:18];
    assign partial6_comb[8] = a_significand_s1n_q[17:12] * b_significand_s1n_q[5:0];
    assign partial6_comb[9] = a_significand_s1n_q[17:12] * b_significand_s1n_q[11:6];
    assign partial6_comb[10] = a_significand_s1n_q[23:18] * b_significand_s1n_q[5:0];
    assign partial6_comb[11] = a_significand_s1n_q[23:18] * b_significand_s1n_q[11:6];
    assign partial6_comb[12] = a_significand_s1n_q[17:12] * b_significand_s1n_q[17:12];
    assign partial6_comb[13] = a_significand_s1n_q[17:12] * b_significand_s1n_q[23:18];
    assign partial6_comb[14] = a_significand_s1n_q[23:18] * b_significand_s1n_q[17:12];
    assign partial6_comb[15] = a_significand_s1n_q[23:18] * b_significand_s1n_q[23:18];

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s2_q <= 1'b0;
        else valid_s2_q <= valid_s1n_q;
        for (integer partial_index = 0; partial_index < 16; partial_index++) begin
            partial6_s2_q[partial_index] <= partial6_comb[partial_index];
        end
        sign_s2_q <= a_sign_s1n_q ^ b_sign_s1n_q;
        exponent_s2_q <= $signed({a_exponent_s1n_q[9], a_exponent_s1n_q}) +
                         $signed({b_exponent_s1n_q[9], b_exponent_s1n_q});
        special_valid_s2_q <= special_valid_s1n_q;
        special_result_s2_q <= special_result_s1n_q;
        invalid_s2_q <= invalid_s1n_q;
        rounding_s2_q <= rounding_s1n_q;
    end

    assign partial_csa_comb[0] = reduce_partial6_csa(
        partial6_s2_q[0], partial6_s2_q[1], partial6_s2_q[2], partial6_s2_q[3]);
    assign partial_csa_comb[1] = reduce_partial6_csa(
        partial6_s2_q[4], partial6_s2_q[5], partial6_s2_q[6], partial6_s2_q[7]);
    assign partial_csa_comb[2] = reduce_partial6_csa(
        partial6_s2_q[8], partial6_s2_q[9], partial6_s2_q[10], partial6_s2_q[11]);
    assign partial_csa_comb[3] = reduce_partial6_csa(
        partial6_s2_q[12], partial6_s2_q[13], partial6_s2_q[14], partial6_s2_q[15]);

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s2r_q <= 1'b0;
        else valid_s2r_q <= valid_s2_q;
        for (integer group_index = 0; group_index < 4; group_index++) begin
            partial_csa_s2r_q[group_index] <= partial_csa_comb[group_index];
        end
        sign_s2r_q <= sign_s2_q;
        exponent_s2r_q <= exponent_s2_q;
        special_valid_s2r_q <= special_valid_s2_q;
        special_result_s2r_q <= special_result_s2_q;
        invalid_s2r_q <= invalid_s2_q;
        rounding_s2r_q <= rounding_s2_q;
    end

    kogge_stone_adder_48 #(.WIDTH(24)) u_partial_ll_adder (
        .a_i(partial_csa_s2r_q[0][23:0]),
        .b_i(partial_csa_s2r_q[0][47:24]), .cin_i(1'b0), .sum_o(partial_ll_comb));
    kogge_stone_adder_48 #(.WIDTH(24)) u_partial_lh_adder (
        .a_i(partial_csa_s2r_q[1][23:0]),
        .b_i(partial_csa_s2r_q[1][47:24]), .cin_i(1'b0), .sum_o(partial_lh_comb));
    kogge_stone_adder_48 #(.WIDTH(24)) u_partial_hl_adder (
        .a_i(partial_csa_s2r_q[2][23:0]),
        .b_i(partial_csa_s2r_q[2][47:24]), .cin_i(1'b0), .sum_o(partial_hl_comb));
    kogge_stone_adder_48 #(.WIDTH(24)) u_partial_hh_adder (
        .a_i(partial_csa_s2r_q[3][23:0]),
        .b_i(partial_csa_s2r_q[3][47:24]), .cin_i(1'b0), .sum_o(partial_hh_comb));

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s2c_q <= 1'b0;
        else valid_s2c_q <= valid_s2r_q;
        partial_ll_s2_q <= partial_ll_comb;
        partial_lh_s2_q <= partial_lh_comb;
        partial_hl_s2_q <= partial_hl_comb;
        partial_hh_s2_q <= partial_hh_comb;
        sign_s2c_q <= sign_s2r_q;
        exponent_s2c_q <= exponent_s2r_q;
        special_valid_s2c_q <= special_valid_s2r_q;
        special_result_s2c_q <= special_result_s2r_q;
        invalid_s2c_q <= invalid_s2r_q;
        rounding_s2c_q <= rounding_s2r_q;
    end

    assign term0_comb = {24'd0, partial_ll_s2_q};
    assign term1_comb = {12'd0, partial_lh_s2_q, 12'd0};
    assign term2_comb = {12'd0, partial_hl_s2_q, 12'd0};
    assign term3_comb = {partial_hh_s2_q, 24'd0};
    assign csa_sum_l1_comb = term0_comb ^ term1_comb ^ term2_comb;
    assign csa_carry_l1_comb = ((term0_comb & term1_comb) |
                                (term0_comb & term2_comb) |
                                (term1_comb & term2_comb)) << 1;
    assign csa_sum_l2_comb = csa_sum_l1_comb ^ csa_carry_l1_comb ^ term3_comb;
    assign csa_carry_l2_comb = ((csa_sum_l1_comb & csa_carry_l1_comb) |
                                (csa_sum_l1_comb & term3_comb) |
                                (csa_carry_l1_comb & term3_comb)) << 1;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s3_q <= 1'b0;
        else valid_s3_q <= valid_s2c_q;
        csa_sum_s3_q <= csa_sum_l2_comb;
        csa_carry_s3_q <= csa_carry_l2_comb;
        sign_s3_q <= sign_s2c_q;
        exponent_s3_q <= exponent_s2c_q;
        special_valid_s3_q <= special_valid_s2c_q;
        special_result_s3_q <= special_result_s2c_q;
        invalid_s3_q <= invalid_s2c_q;
        rounding_s3_q <= rounding_s2c_q;
    end

    kogge_stone_adder_48 u_product_adder (
        .a_i(csa_sum_s3_q), .b_i(csa_carry_s3_q), .cin_i(1'b0), .sum_o(product_comb));

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s4_q <= 1'b0;
        else valid_s4_q <= valid_s3_q;
        product_s4_q <= product_comb;
        sign_s4_q <= sign_s3_q;
        exponent_s4_q <= exponent_s3_q;
        special_valid_s4_q <= special_valid_s3_q;
        special_result_s4_q <= special_result_s3_q;
        invalid_s4_q <= invalid_s3_q;
        rounding_s4_q <= rounding_s3_q;
    end

    always_comb begin
        normalized_product_comb = product_s4_q;
        normalized_exponent_comb = exponent_s4_q;
        if (!product_s4_q[47]) begin
            normalized_product_comb = product_s4_q << 1;
        end else begin
            normalized_exponent_comb = exponent_s4_q + 11'sd1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s5_q <= 1'b0;
        else valid_s5_q <= valid_s4_q;
        normalized_product_s5_q <= normalized_product_comb;
        normalized_exponent_s5_q <= normalized_exponent_comb;
        sign_s5_q <= sign_s4_q;
        special_valid_s5_q <= special_valid_s4_q;
        special_result_s5_q <= special_result_s4_q;
        invalid_s5_q <= invalid_s4_q;
        rounding_s5_q <= rounding_s4_q;
    end

    always_comb begin
        subnormal_shift_comb = 9'($unsigned(-$signed(normalized_exponent_s5_q) - 11'sd102));
        subnormal_coarse_product_comb = normalized_product_s5_q;
        subnormal_fine_shift_comb = 4'd1;
        subnormal_coarse_sticky_comb = 1'b0;
        subnormal_too_small_comb = 1'b0;
        if (normalized_exponent_s5_q < -11'sd126) begin
            if (subnormal_shift_comb <= 9'd32) begin
                subnormal_coarse_product_comb = normalized_product_s5_q >> 5'd24;
                subnormal_fine_shift_comb = 4'($unsigned(subnormal_shift_comb - 9'd24));
                subnormal_coarse_sticky_comb = |normalized_product_s5_q[23:0];
            end else if (subnormal_shift_comb <= 9'd40) begin
                subnormal_coarse_product_comb = normalized_product_s5_q >> 6'd32;
                subnormal_fine_shift_comb = 4'($unsigned(subnormal_shift_comb - 9'd32));
                subnormal_coarse_sticky_comb = |normalized_product_s5_q[31:0];
            end else if (subnormal_shift_comb <= 9'd48) begin
                subnormal_coarse_product_comb = normalized_product_s5_q >> 6'd40;
                subnormal_fine_shift_comb = 4'($unsigned(subnormal_shift_comb - 9'd40));
                subnormal_coarse_sticky_comb = |normalized_product_s5_q[39:0];
            end else begin
                subnormal_coarse_product_comb = 48'd0;
                subnormal_fine_shift_comb = 4'd1;
                subnormal_coarse_sticky_comb = |normalized_product_s5_q;
                subnormal_too_small_comb = 1'b1;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s6_q <= 1'b0;
        else valid_s6_q <= valid_s5_q;
        normal_main_s6_q <= normalized_product_s5_q[47:24];
        normal_guard_s6_q <= normalized_product_s5_q[23];
        normal_sticky_s6_q <= |normalized_product_s5_q[22:0];
        subnormal_coarse_product_s6_q <= subnormal_coarse_product_comb;
        subnormal_fine_shift_s6_q <= subnormal_fine_shift_comb;
        subnormal_coarse_sticky_s6_q <= subnormal_coarse_sticky_comb;
        subnormal_too_small_s6_q <= subnormal_too_small_comb;
        exponent_s6_q <= normalized_exponent_s5_q;
        sign_s6_q <= sign_s5_q;
        special_valid_s6_q <= special_valid_s5_q;
        special_result_s6_q <= special_result_s5_q;
        invalid_s6_q <= invalid_s5_q;
        rounding_s6_q <= rounding_s5_q;
    end

    always_comb begin
        subnormal_main_comb = 24'(subnormal_coarse_product_s6_q >>
                                     subnormal_fine_shift_s6_q);
        subnormal_guard_comb = 1'b0;
        subnormal_sticky_comb = subnormal_coarse_sticky_s6_q;
        if (!subnormal_too_small_s6_q) begin
            case (subnormal_fine_shift_s6_q)
                4'd1: begin
                    subnormal_guard_comb = subnormal_coarse_product_s6_q[0];
                end
                4'd2: begin
                    subnormal_guard_comb = subnormal_coarse_product_s6_q[1];
                    subnormal_sticky_comb |= |subnormal_coarse_product_s6_q[0:0];
                end
                4'd3: begin
                    subnormal_guard_comb = subnormal_coarse_product_s6_q[2];
                    subnormal_sticky_comb |= |subnormal_coarse_product_s6_q[1:0];
                end
                4'd4: begin
                    subnormal_guard_comb = subnormal_coarse_product_s6_q[3];
                    subnormal_sticky_comb |= |subnormal_coarse_product_s6_q[2:0];
                end
                4'd5: begin
                    subnormal_guard_comb = subnormal_coarse_product_s6_q[4];
                    subnormal_sticky_comb |= |subnormal_coarse_product_s6_q[3:0];
                end
                4'd6: begin
                    subnormal_guard_comb = subnormal_coarse_product_s6_q[5];
                    subnormal_sticky_comb |= |subnormal_coarse_product_s6_q[4:0];
                end
                4'd7: begin
                    subnormal_guard_comb = subnormal_coarse_product_s6_q[6];
                    subnormal_sticky_comb |= |subnormal_coarse_product_s6_q[5:0];
                end
                default: begin
                    subnormal_guard_comb = subnormal_coarse_product_s6_q[7];
                    subnormal_sticky_comb |= |subnormal_coarse_product_s6_q[6:0];
                end
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s7_q <= 1'b0;
        else valid_s7_q <= valid_s6_q;
        normal_main_s7_q <= normal_main_s6_q;
        normal_guard_s7_q <= normal_guard_s6_q;
        normal_sticky_s7_q <= normal_sticky_s6_q;
        subnormal_main_s7_q <= subnormal_main_comb;
        subnormal_guard_s7_q <= subnormal_guard_comb;
        subnormal_sticky_s7_q <= subnormal_sticky_comb;
        exponent_s7_q <= exponent_s6_q;
        sign_s7_q <= sign_s6_q;
        special_valid_s7_q <= special_valid_s6_q;
        special_result_s7_q <= special_result_s6_q;
        invalid_s7_q <= invalid_s6_q;
        rounding_s7_q <= rounding_s6_q;
    end

    fp32_mul_round_prepare u_round_prepare (
        .sign_i(sign_s7_q),
        .normal_main_i(normal_main_s7_q), .normal_guard_i(normal_guard_s7_q),
        .normal_sticky_i(normal_sticky_s7_q), .subnormal_main_i(subnormal_main_s7_q),
        .subnormal_guard_i(subnormal_guard_s7_q), .subnormal_sticky_i(subnormal_sticky_s7_q),
        .rounding_i(rounding_s7_q), .normal_rounded_o(normal_rounded_comb),
        .normal_carry_o(normal_carry_comb),
        .subnormal_rounded_o(subnormal_rounded_comb),
        .overflow_to_inf_o(overflow_to_inf_comb));

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s8_q <= 1'b0;
        else valid_s8_q <= valid_s7_q;
        normal_rounded_s8_q <= normal_rounded_comb;
        normal_carry_s8_q <= normal_carry_comb;
        subnormal_rounded_s8_q <= subnormal_rounded_comb;
        overflow_to_inf_s8_q <= overflow_to_inf_comb;
        exponent_s8_q <= exponent_s7_q;
        sign_s8_q <= sign_s7_q;
        special_valid_s8_q <= special_valid_s7_q;
        special_result_s8_q <= special_result_s7_q;
        invalid_s8_q <= invalid_s7_q;
    end

    // 把舍入进位与指数修正分离，阻断rounding模式到指数寄存器的长组合路径。
    assign normal_round_exponent_comb =
        $signed({exponent_s8_q[10], exponent_s8_q}) +
        $signed({11'd0, normal_carry_s8_q});

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) valid_s9_q <= 1'b0;
        else valid_s9_q <= valid_s8_q;
        normal_rounded_s9_q <= normal_rounded_s8_q;
        normal_round_exponent_s9_q <= normal_round_exponent_comb;
        subnormal_rounded_s9_q <= subnormal_rounded_s8_q;
        overflow_to_inf_s9_q <= overflow_to_inf_s8_q;
        exponent_s9_q <= exponent_s8_q;
        sign_s9_q <= sign_s8_q;
        special_valid_s9_q <= special_valid_s8_q;
        special_result_s9_q <= special_result_s8_q;
        invalid_s9_q <= invalid_s8_q;
    end

    fp32_mul_round_pack #(.FTZ(FTZ)) u_round_pack (
        .sign_i(sign_s9_q), .exponent_i(exponent_s9_q),
        .normal_rounded_i(normal_rounded_s9_q),
        .normal_exponent_i(normal_round_exponent_s9_q),
        .subnormal_rounded_i(subnormal_rounded_s9_q),
        .overflow_to_inf_i(overflow_to_inf_s9_q),
        .special_valid_i(special_valid_s9_q), .special_result_i(special_result_s9_q),
        .result_o(packed_result_comb));

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_o <= 1'b0;
            result_o <= 32'd0;
            invalid_o <= 1'b0;
        end else begin
            valid_o <= valid_s9_q;
            result_o <= packed_result_comb;
            invalid_o <= valid_s9_q && invalid_s9_q;
        end
    end

endmodule

`default_nettype wire
