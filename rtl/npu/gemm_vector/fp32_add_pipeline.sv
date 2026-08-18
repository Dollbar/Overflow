`timescale 1ns/1ps
`default_nettype none

// 六级流水的IEEE FP32加法器。该模块用于把各K=16块产生的FP32部分和逐块累加。
(* keep_hierarchy = "yes" *)
module fp32_add_pipeline #(
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
    localparam logic [31:0] FP32_POSITIVE_INF = 32'h7f800000;
    localparam logic [31:0] FP32_NEGATIVE_INF = 32'hff800000;

    fp8_pkg::fp32_unpacked_t a_unpacked_comb;
    fp8_pkg::fp32_unpacked_t b_unpacked_comb;
    /* verilator lint_off UNUSEDSIGNAL */
    fp8_pkg::fp32_decoded_t a_decoded_s1;
    fp8_pkg::fp32_decoded_t b_decoded_s1;
    /* verilator lint_on UNUSEDSIGNAL */

    logic special_valid_comb;
    logic [31:0] special_result_comb;
    logic special_invalid_comb;
    logic special_valid_s1_q;
    logic [31:0] special_result_s1_q;
    logic special_invalid_s1_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s1_q;
    logic valid_s1_q;

    logic [26:0] a_extended_comb;
    logic [26:0] b_extended_comb;
    logic [26:0] a_aligned_comb;
    logic [26:0] b_aligned_comb;
    logic signed [10:0] common_exponent_comb;
    logic [8:0] exponent_distance_comb;
    logic [4:0] shift_amount_comb;
    logic sticky_comb;

    logic [26:0] a_aligned_s2_q;
    logic [26:0] b_aligned_s2_q;
    logic a_sign_s2_q;
    logic b_sign_s2_q;
    logic signed [10:0] common_exponent_s2_q;
    logic special_valid_s2_q;
    logic [31:0] special_result_s2_q;
    logic special_invalid_s2_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s2_q;
    logic valid_s2_q;

    logic [27:0] arithmetic_a_comb;
    logic [27:0] arithmetic_b_comb;
    logic carry_input_comb;
    logic finite_sign_prepare_comb;
    logic product_not_smaller_comb;
    logic equal_magnitude_comb;
    logic [27:0] arithmetic_a_s2a_q;
    logic [27:0] arithmetic_b_s2a_q;
    logic carry_input_s2a_q;
    logic finite_sign_s2a_q;
    logic signed [10:0] common_exponent_s2a_q;
    logic special_valid_s2a_q;
    logic [31:0] special_result_s2a_q;
    logic special_invalid_s2a_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s2a_q;
    logic valid_s2a_q;

    logic [27:0] magnitude_comb;
    logic finite_sign_comb;
    logic [27:0] magnitude_s3_q;
    logic finite_sign_s3_q;
    logic signed [10:0] common_exponent_s3_q;
    logic special_valid_s3_q;
    logic [31:0] special_result_s3_q;
    logic special_invalid_s3_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s3_q;
    logic valid_s3_q;

    logic [26:0] normalized_significand_comb;
    logic signed [10:0] normalized_exponent_comb;
    logic normalized_zero_comb;
    logic [26:0] normalized_significand_s4_q;
    logic signed [10:0] normalized_exponent_s4_q;
    logic normalized_zero_s4_q;
    logic finite_sign_s4_q;
    logic special_valid_s4_q;
    logic [31:0] special_result_s4_q;
    logic special_invalid_s4_q;
    (* keep *) fp8_pkg::fp8_rounding_e rounding_s4_q;
    logic valid_s4_q;
    logic [31:0] packed_result_comb;

    fp32_unpack u_unpack_a (
        .data_i     (a_i),
        .unpacked_o (a_unpacked_comb)
    );

    fp32_unpack u_unpack_b (
        .data_i     (b_i),
        .unpacked_o (b_unpacked_comb)
    );

    fp32_subnormal_normalize u_normalize_subnormal_a (
        .clk_i      (clk_i),
        .rst_i      (rst_i || clear_i),
        .unpacked_i (a_unpacked_comb),
        .decoded_o  (a_decoded_s1)
    );

    fp32_subnormal_normalize u_normalize_subnormal_b (
        .clk_i      (clk_i),
        .rst_i      (rst_i || clear_i),
        .unpacked_i (b_unpacked_comb),
        .decoded_o  (b_decoded_s1)
    );

    // 特殊值在输入级决定，普通有限数则进入对阶、加减、规格化和舍入流水。
    always_comb begin
        special_valid_comb = 1'b1;
        special_result_comb = FP32_CANONICAL_NAN;
        special_invalid_comb = |invalid_i;
        if (a_unpacked_comb.is_nan || b_unpacked_comb.is_nan) begin
            special_result_comb = FP32_CANONICAL_NAN;
        end else if (a_unpacked_comb.is_inf && b_unpacked_comb.is_inf &&
                     (a_unpacked_comb.sign != b_unpacked_comb.sign)) begin
            special_result_comb = FP32_CANONICAL_NAN;
            special_invalid_comb = 1'b1;
        end else if (a_unpacked_comb.is_inf) begin
            special_result_comb = a_unpacked_comb.sign ?
                                     FP32_NEGATIVE_INF : FP32_POSITIVE_INF;
        end else if (b_unpacked_comb.is_inf) begin
            special_result_comb = b_unpacked_comb.sign ?
                                     FP32_NEGATIVE_INF : FP32_POSITIVE_INF;
        end else if (a_unpacked_comb.is_zero && b_unpacked_comb.is_zero) begin
            special_result_comb = {(a_unpacked_comb.sign == b_unpacked_comb.sign) ?
                                      a_unpacked_comb.sign :
                                      (rounding_i == fp8_pkg::RDN), 31'd0};
        end else if (a_unpacked_comb.is_zero) begin
            special_result_comb = b_i;
        end else if (b_unpacked_comb.is_zero) begin
            special_result_comb = a_i;
        end else begin
            special_valid_comb = 1'b0;
            special_result_comb = 32'd0;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_s1_q <= 1'b0;
        end else begin
            valid_s1_q <= valid_i;
        end
        special_valid_s1_q <= special_valid_comb;
        special_result_s1_q <= special_result_comb;
        special_invalid_s1_q <= special_invalid_comb;
        rounding_s1_q <= rounding_i;
    end

    // 以27位“隐藏位+小数+GRS”格式对阶，并把所有被移出的低位归并到Sticky位。
    always_comb begin
        a_extended_comb = {a_decoded_s1.significand, 3'b000};
        b_extended_comb = {b_decoded_s1.significand, 3'b000};
        a_aligned_comb = a_extended_comb;
        b_aligned_comb = b_extended_comb;
        common_exponent_comb = $signed(
            {a_decoded_s1.exponent[9], a_decoded_s1.exponent});
        exponent_distance_comb = 9'd0;
        shift_amount_comb = 5'd0;
        sticky_comb = 1'b0;
        if ($signed(a_decoded_s1.exponent) >=
            $signed(b_decoded_s1.exponent)) begin
            exponent_distance_comb = 9'($unsigned(
                $signed(a_decoded_s1.exponent) -
                $signed(b_decoded_s1.exponent)));
            if (exponent_distance_comb >= 9'd27) begin
                b_aligned_comb = {26'd0, |b_extended_comb};
            end else begin
                shift_amount_comb = exponent_distance_comb[4:0];
                b_aligned_comb = b_extended_comb >> shift_amount_comb;
                sticky_comb = |(b_extended_comb <<
                                  (5'd27 - shift_amount_comb));
                b_aligned_comb[0] = b_aligned_comb[0] | sticky_comb;
            end
        end else begin
            common_exponent_comb = $signed(
                {b_decoded_s1.exponent[9], b_decoded_s1.exponent});
            exponent_distance_comb = 9'($unsigned(
                $signed(b_decoded_s1.exponent) -
                $signed(a_decoded_s1.exponent)));
            if (exponent_distance_comb >= 9'd27) begin
                a_aligned_comb = {26'd0, |a_extended_comb};
            end else begin
                shift_amount_comb = exponent_distance_comb[4:0];
                a_aligned_comb = a_extended_comb >> shift_amount_comb;
                sticky_comb = |(a_extended_comb <<
                                  (5'd27 - shift_amount_comb));
                a_aligned_comb[0] = a_aligned_comb[0] | sticky_comb;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_s2_q <= 1'b0;
        end else begin
            valid_s2_q <= valid_s1_q;
        end
        a_aligned_s2_q <= a_aligned_comb;
        b_aligned_s2_q <= b_aligned_comb;
        a_sign_s2_q <= a_decoded_s1.sign;
        b_sign_s2_q <= b_decoded_s1.sign;
        common_exponent_s2_q <= common_exponent_comb;
        special_valid_s2_q <= special_valid_s1_q;
        special_result_s2_q <= special_result_s1_q;
        special_invalid_s2_q <= special_invalid_s1_q;
        rounding_s2_q <= rounding_s1_q;
    end

    // 把幅值比较和操作数选择放在独立流水级，隔离后续28位加法进位链。
    always_comb begin
        product_not_smaller_comb = (a_aligned_s2_q >= b_aligned_s2_q);
        equal_magnitude_comb = (a_aligned_s2_q == b_aligned_s2_q);
        arithmetic_a_comb = {1'b0, a_aligned_s2_q};
        arithmetic_b_comb = {1'b0, b_aligned_s2_q};
        carry_input_comb = 1'b0;
        finite_sign_prepare_comb = a_sign_s2_q;

        if (a_sign_s2_q != b_sign_s2_q) begin
            carry_input_comb = 1'b1;
            if (product_not_smaller_comb) begin
                arithmetic_a_comb = {1'b0, a_aligned_s2_q};
                arithmetic_b_comb = ~{1'b0, b_aligned_s2_q};
                finite_sign_prepare_comb = a_sign_s2_q;
            end else begin
                arithmetic_a_comb = {1'b0, b_aligned_s2_q};
                arithmetic_b_comb = ~{1'b0, a_aligned_s2_q};
                finite_sign_prepare_comb = b_sign_s2_q;
            end
            if (equal_magnitude_comb) begin
                finite_sign_prepare_comb = (rounding_s2_q == fp8_pkg::RDN);
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_s2a_q <= 1'b0;
        end else begin
            valid_s2a_q <= valid_s2_q;
        end
        arithmetic_a_s2a_q <= arithmetic_a_comb;
        arithmetic_b_s2a_q <= arithmetic_b_comb;
        carry_input_s2a_q <= carry_input_comb;
        finite_sign_s2a_q <= finite_sign_prepare_comb;
        common_exponent_s2a_q <= common_exponent_s2_q;
        special_valid_s2a_q <= special_valid_s2_q;
        special_result_s2a_q <= special_result_s2_q;
        special_invalid_s2a_q <= special_invalid_s2_q;
        rounding_s2a_q <= rounding_s2_q;
    end

    fp32_significand_add u_significand_add (
        .arithmetic_a_i (arithmetic_a_s2a_q),
        .arithmetic_b_i (arithmetic_b_s2a_q),
        .carry_i        (carry_input_s2a_q),
        .sign_i         (finite_sign_s2a_q),
        .magnitude_o    (magnitude_comb),
        .sign_o         (finite_sign_comb)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_s3_q <= 1'b0;
        end else begin
            valid_s3_q <= valid_s2a_q;
        end
        magnitude_s3_q <= magnitude_comb;
        finite_sign_s3_q <= finite_sign_comb;
        common_exponent_s3_q <= common_exponent_s2a_q;
        special_valid_s3_q <= special_valid_s2a_q;
        special_result_s3_q <= special_result_s2a_q;
        special_invalid_s3_q <= special_invalid_s2a_q;
        rounding_s3_q <= rounding_s2a_q;
    end

    fp32_normalize u_normalize (
        .magnitude_i    (magnitude_s3_q),
        .exponent_i     (common_exponent_s3_q),
        .significand_o  (normalized_significand_comb),
        .exponent_o     (normalized_exponent_comb),
        .zero_o         (normalized_zero_comb)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_s4_q <= 1'b0;
        end else begin
            valid_s4_q <= valid_s3_q;
        end
        normalized_significand_s4_q <= normalized_significand_comb;
        normalized_exponent_s4_q <= normalized_exponent_comb;
        normalized_zero_s4_q <= normalized_zero_comb;
        finite_sign_s4_q <= finite_sign_s3_q;
        special_valid_s4_q <= special_valid_s3_q;
        special_result_s4_q <= special_result_s3_q;
        special_invalid_s4_q <= special_invalid_s3_q;
        rounding_s4_q <= rounding_s3_q;
    end

    fp32_round_pack #(
        .FTZ (FTZ)
    ) u_round_pack (
        .significand_i    (normalized_significand_s4_q),
        .exponent_i       (normalized_exponent_s4_q),
        .sign_i           (finite_sign_s4_q),
        .zero_i           (normalized_zero_s4_q),
        .rounding_i       (rounding_s4_q),
        .special_valid_i  (special_valid_s4_q),
        .special_result_i (special_result_s4_q),
        .result_o         (packed_result_comb)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_o <= 1'b0;
            result_o <= 32'd0;
            invalid_o <= 1'b0;
        end else begin
            valid_o <= valid_s4_q;
            result_o <= packed_result_comb;
            invalid_o <= valid_s4_q && special_invalid_s4_q;
        end
    end

endmodule

`default_nettype wire
