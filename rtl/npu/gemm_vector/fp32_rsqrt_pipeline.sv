`timescale 1ns/1ps
`default_nettype none

// LayerNorm/RMSNorm正Normal输入专用FP32倒平方根近似器，固定十一级流水。
// 指数奇偶各使用16段Q1.23线性插值，避免通用乘法器和迭代反馈路径。
(* keep_hierarchy = "yes" *)
module fp32_rsqrt_pipeline (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        clear_i,
    input  logic        valid_i,
    input  logic [31:0] data_i,
    input  logic        invalid_i,
    output logic        valid_o,
    output logic [31:0] result_o,
    output logic        invalid_o
);

    localparam logic [31:0] FP32_CANONICAL_NAN = 32'h7fc00000;
    localparam logic [31:0] FP32_POSITIVE_INFINITY = 32'h7f800000;

    logic input_nan_comb;
    logic input_inf_comb;
    logic input_zero_comb;
    logic input_subnormal_comb;
    logic input_negative_comb;
    logic input_special_comb;
    logic [31:0] input_special_result_comb;
    logic input_invalid_comb;
    logic signed [8:0] unbiased_exponent_comb;
    logic signed [8:0] exponent_half_comb;
    logic exponent_odd_comb;

    logic [3:0] segment_index_comb;
    logic [11:0] segment_remainder_comb;
    logic [23:0] segment_high_comb;
    logic [23:0] segment_low_comb;
    logic [23:0] segment_delta_comb;
    logic signed [8:0] exponent_half_s1_q;
    logic [23:0] segment_high_s1_q;
    logic [18:0] segment_delta_s1_q;
    logic [11:0] segment_remainder_s1_q;

    logic [22:0] interpolation_local0_s4_q;
    logic [22:0] interpolation_local1_s4_q;
    logic [22:0] interpolation_local2_s4_q;
    logic signed [8:0] exponent_half_s2_q;
    logic signed [8:0] exponent_half_s3_q;
    logic signed [8:0] exponent_half_s4_q;
    logic [23:0] segment_high_s2_q;
    logic [23:0] segment_high_s3_q;
    logic [23:0] segment_high_s4_q;

    logic [30:0] interpolation_operand0_comb;
    logic [30:0] interpolation_operand1_comb;
    logic [30:0] interpolation_operand2_comb;
    logic [29:0] interpolation_csa_majority_comb;
    logic [30:0] interpolation_csa_sum_comb;
    logic [30:0] interpolation_csa_carry_comb;
    logic [30:0] interpolation_csa_sum_s5_q;
    logic [30:0] interpolation_csa_carry_s5_q;
    logic signed [8:0] exponent_half_s5_q;
    logic [23:0] segment_high_s5_q;

    logic [12:0] interpolation_low_sum_comb;
    logic [11:0] interpolation_low_product_s6_q;
    logic [18:0] interpolation_csa_sum_upper_s6_q;
    logic [18:0] interpolation_csa_carry_upper_s6_q;
    logic interpolation_low_carry_s6_q;
    logic signed [8:0] exponent_half_s6_q;
    logic [23:0] segment_high_s6_q;

    logic [10:0] interpolation_middle_sum_comb;
    logic [11:0] interpolation_low_product_s7_q;
    logic [9:0] interpolation_middle_product_s7_q;
    logic [8:0] interpolation_csa_sum_high_s7_q;
    logic [8:0] interpolation_csa_carry_high_s7_q;
    logic interpolation_middle_carry_s7_q;
    logic signed [8:0] exponent_half_s7_q;
    logic [23:0] segment_high_s7_q;

    logic [9:0] interpolation_high_sum_comb;
    logic [30:0] interpolation_product_comb;
    logic [30:0] interpolation_product_s8_q;
    logic signed [8:0] exponent_half_s8_q;
    logic [23:0] segment_high_s8_q;

    logic interpolation_round_increment_comb;
    logic [23:0] interpolation_truncated_comb;
    logic [23:0] interpolation_round_vector_comb;
    logic [23:0] interpolation_correction_comb;
    logic [23:0] interpolation_correction_s9_q;
    logic signed [8:0] exponent_half_s9_q;
    logic [23:0] segment_high_s9_q;

    logic [23:0] interpolated_rsqrt_comb;
    logic [22:0] normalized_fraction_comb;
    logic [8:0] biased_exponent_base_comb;
    logic [8:0] biased_exponent_comb;
    logic [22:0] normalized_fraction_s10_q;
    logic [7:0] biased_exponent_s10_q;

    logic [9:0] valid_pipe_q;
    logic [9:0] special_pipe_q;
    logic [9:0] invalid_pipe_q;
    logic [31:0] special_result_pipe_q [0:9];

    always_comb begin
        input_nan_comb = (data_i[30:23] == 8'hff) && (data_i[22:0] != 23'd0);
        input_inf_comb = (data_i[30:23] == 8'hff) && (data_i[22:0] == 23'd0);
        input_zero_comb = (data_i[30:0] == 31'd0);
        input_subnormal_comb = (data_i[30:23] == 8'd0) && !input_zero_comb;
        input_negative_comb = data_i[31] && !input_zero_comb;
        input_special_comb = input_nan_comb || input_inf_comb || input_zero_comb ||
                             input_subnormal_comb || input_negative_comb;
        input_special_result_comb = 32'd0;
        input_invalid_comb = invalid_i;
        if (input_nan_comb || input_negative_comb) begin
            input_special_result_comb = FP32_CANONICAL_NAN;
            input_invalid_comb = 1'b1;
        end else if (input_zero_comb || input_subnormal_comb) begin
            input_special_result_comb = FP32_POSITIVE_INFINITY;
            input_invalid_comb = 1'b1;
        end else if (input_inf_comb) begin
            input_special_result_comb = 32'd0;
        end
        unbiased_exponent_comb = $signed({1'b0, data_i[30:23]}) - 9'sd127;
        exponent_half_comb = unbiased_exponent_comb >>> 1;
        exponent_odd_comb = unbiased_exponent_comb[0];
    end

    // LUT保存1/sqrt(m)与1/sqrt(2m)的Q1.23锚点，后者吸收奇指数因子。
    always_comb begin
        segment_index_comb = data_i[22:19];
        segment_remainder_comb = data_i[18:7];
        segment_high_comb = 24'h800000;
        segment_low_comb = 24'h7c2da1;
        case ({exponent_odd_comb, segment_index_comb})
            5'h00: begin segment_high_comb = 24'h800000; segment_low_comb = 24'h7c2da1; end
            5'h01: begin segment_high_comb = 24'h7c2da1; segment_low_comb = 24'h78adf7; end
            5'h02: begin segment_high_comb = 24'h78adf7; segment_low_comb = 24'h7575fb; end
            5'h03: begin segment_high_comb = 24'h7575fb; segment_low_comb = 24'h727c97; end
            5'h04: begin segment_high_comb = 24'h727c97; segment_low_comb = 24'h6fba41; end
            5'h05: begin segment_high_comb = 24'h6fba41; segment_low_comb = 24'h6d28a5; end
            5'h06: begin segment_high_comb = 24'h6d28a5; segment_low_comb = 24'h6ac267; end
            5'h07: begin segment_high_comb = 24'h6ac267; segment_low_comb = 24'h6882f6; end
            5'h08: begin segment_high_comb = 24'h6882f6; segment_low_comb = 24'h666666; end
            5'h09: begin segment_high_comb = 24'h666666; segment_low_comb = 24'h646956; end
            5'h0a: begin segment_high_comb = 24'h646956; segment_low_comb = 24'h6288d1; end
            5'h0b: begin segment_high_comb = 24'h6288d1; segment_low_comb = 24'h60c248; end
            5'h0c: begin segment_high_comb = 24'h60c248; segment_low_comb = 24'h5f1376; end
            5'h0d: begin segment_high_comb = 24'h5f1376; segment_low_comb = 24'h5d7a5d; end
            5'h0e: begin segment_high_comb = 24'h5d7a5d; segment_low_comb = 24'h5bf53a; end
            5'h0f: begin segment_high_comb = 24'h5bf53a; segment_low_comb = 24'h5a827a; end
            5'h10: begin segment_high_comb = 24'h5a827a; segment_low_comb = 24'h57ceaa; end
            5'h11: begin segment_high_comb = 24'h57ceaa; segment_low_comb = 24'h555555; end
            5'h12: begin segment_high_comb = 24'h555555; segment_low_comb = 24'h530eb0; end
            5'h13: begin segment_high_comb = 24'h530eb0; segment_low_comb = 24'h50f44e; end
            5'h14: begin segment_high_comb = 24'h50f44e; segment_low_comb = 24'h4f00d9; end
            5'h15: begin segment_high_comb = 24'h4f00d9; segment_low_comb = 24'h4d2fd9; end
            5'h16: begin segment_high_comb = 24'h4d2fd9; segment_low_comb = 24'h4b7d83; end
            5'h17: begin segment_high_comb = 24'h4b7d83; segment_low_comb = 24'h49e69d; end
            5'h18: begin segment_high_comb = 24'h49e69d; segment_low_comb = 24'h486861; end
            5'h19: begin segment_high_comb = 24'h486861; segment_low_comb = 24'h47006b; end
            5'h1a: begin segment_high_comb = 24'h47006b; segment_low_comb = 24'h45aca4; end
            5'h1b: begin segment_high_comb = 24'h45aca4; segment_low_comb = 24'h446b3c; end
            5'h1c: begin segment_high_comb = 24'h446b3c; segment_low_comb = 24'h433a99; end
            5'h1d: begin segment_high_comb = 24'h433a99; segment_low_comb = 24'h421953; end
            5'h1e: begin segment_high_comb = 24'h421953; segment_low_comb = 24'h410629; end
            5'h1f: begin segment_high_comb = 24'h410629; segment_low_comb = 24'h400000; end
            default: begin segment_high_comb = 24'h800000; segment_low_comb = 24'h7c2da1; end
        endcase
    end

    kogge_stone_adder_48 #(.WIDTH(24)) u_segment_delta_adder (
        .a_i(segment_high_comb), .b_i(~segment_low_comb), .cin_i(1'b1),
        .sum_o(segment_delta_comb)
    );

    always_ff @(posedge clk_i) begin
        exponent_half_s1_q <= exponent_half_comb;
        segment_high_s1_q <= segment_high_comb;
        segment_delta_s1_q <= segment_delta_comb[18:0];
        segment_remainder_s1_q <= segment_remainder_comb;
    end

    fp32_exp_mul_u19_u4 u_interpolation_local0 (
        .clk_i(clk_i), .multiplicand_i(segment_delta_s1_q),
        .multiplier_i(segment_remainder_s1_q[3:0]), .product_o(interpolation_local0_s4_q)
    );
    fp32_exp_mul_u19_u4 u_interpolation_local1 (
        .clk_i(clk_i), .multiplicand_i(segment_delta_s1_q),
        .multiplier_i(segment_remainder_s1_q[7:4]), .product_o(interpolation_local1_s4_q)
    );
    fp32_exp_mul_u19_u4 u_interpolation_local2 (
        .clk_i(clk_i), .multiplicand_i(segment_delta_s1_q),
        .multiplier_i(segment_remainder_s1_q[11:8]), .product_o(interpolation_local2_s4_q)
    );

    always_ff @(posedge clk_i) begin
        exponent_half_s2_q <= exponent_half_s1_q;
        segment_high_s2_q <= segment_high_s1_q;
        exponent_half_s3_q <= exponent_half_s2_q;
        segment_high_s3_q <= segment_high_s2_q;
        exponent_half_s4_q <= exponent_half_s3_q;
        segment_high_s4_q <= segment_high_s3_q;
    end

    always_comb begin
        interpolation_operand0_comb = {8'd0, interpolation_local0_s4_q};
        interpolation_operand1_comb = {4'd0, interpolation_local1_s4_q, 4'd0};
        interpolation_operand2_comb = {interpolation_local2_s4_q, 8'd0};
        interpolation_csa_majority_comb =
            (interpolation_operand0_comb[29:0] & interpolation_operand1_comb[29:0]) |
            (interpolation_operand0_comb[29:0] & interpolation_operand2_comb[29:0]) |
            (interpolation_operand1_comb[29:0] & interpolation_operand2_comb[29:0]);
        interpolation_csa_sum_comb = interpolation_operand0_comb ^
                                     interpolation_operand1_comb ^
                                     interpolation_operand2_comb;
        interpolation_csa_carry_comb = {interpolation_csa_majority_comb, 1'b0};
    end

    always_ff @(posedge clk_i) begin
        interpolation_csa_sum_s5_q <= interpolation_csa_sum_comb;
        interpolation_csa_carry_s5_q <= interpolation_csa_carry_comb;
        exponent_half_s5_q <= exponent_half_s4_q;
        segment_high_s5_q <= segment_high_s4_q;
    end

    kogge_stone_adder_48 #(.WIDTH(13)) u_interpolation_low_block_adder (
        .a_i({1'b0, interpolation_csa_sum_s5_q[11:0]}),
        .b_i({1'b0, interpolation_csa_carry_s5_q[11:0]}),
        .cin_i(1'b0), .sum_o(interpolation_low_sum_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_low_product_s6_q <= interpolation_low_sum_comb[11:0];
        interpolation_low_carry_s6_q <= interpolation_low_sum_comb[12];
        interpolation_csa_sum_upper_s6_q <= interpolation_csa_sum_s5_q[30:12];
        interpolation_csa_carry_upper_s6_q <= interpolation_csa_carry_s5_q[30:12];
        exponent_half_s6_q <= exponent_half_s5_q;
        segment_high_s6_q <= segment_high_s5_q;
    end

    kogge_stone_adder_48 #(.WIDTH(11)) u_interpolation_middle_block_adder (
        .a_i({1'b0, interpolation_csa_sum_upper_s6_q[9:0]}),
        .b_i({1'b0, interpolation_csa_carry_upper_s6_q[9:0]}),
        .cin_i(interpolation_low_carry_s6_q), .sum_o(interpolation_middle_sum_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_low_product_s7_q <= interpolation_low_product_s6_q;
        interpolation_middle_product_s7_q <= interpolation_middle_sum_comb[9:0];
        interpolation_middle_carry_s7_q <= interpolation_middle_sum_comb[10];
        interpolation_csa_sum_high_s7_q <= interpolation_csa_sum_upper_s6_q[18:10];
        interpolation_csa_carry_high_s7_q <= interpolation_csa_carry_upper_s6_q[18:10];
        exponent_half_s7_q <= exponent_half_s6_q;
        segment_high_s7_q <= segment_high_s6_q;
    end

    kogge_stone_adder_48 #(.WIDTH(10)) u_interpolation_high_block_adder (
        .a_i({1'b0, interpolation_csa_sum_high_s7_q}),
        .b_i({1'b0, interpolation_csa_carry_high_s7_q}),
        .cin_i(interpolation_middle_carry_s7_q), .sum_o(interpolation_high_sum_comb)
    );

    always_comb begin
        interpolation_product_comb = {interpolation_high_sum_comb[8:0],
                                      interpolation_middle_product_s7_q,
                                      interpolation_low_product_s7_q};
    end

    always_ff @(posedge clk_i) begin
        interpolation_product_s8_q <= interpolation_product_comb;
        exponent_half_s8_q <= exponent_half_s7_q;
        segment_high_s8_q <= segment_high_s7_q;
    end

    always_comb begin
        interpolation_round_increment_comb = interpolation_product_s8_q[11] &&
                                              ((|interpolation_product_s8_q[10:0]) ||
                                               interpolation_product_s8_q[12]);
        interpolation_truncated_comb = {5'd0, interpolation_product_s8_q[30:12]};
        interpolation_round_vector_comb = {{23{1'b0}}, interpolation_round_increment_comb};
    end

    kogge_stone_adder_48 #(.WIDTH(24)) u_interpolation_round_adder (
        .a_i(interpolation_truncated_comb), .b_i(interpolation_round_vector_comb),
        .cin_i(1'b0), .sum_o(interpolation_correction_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_correction_s9_q <= interpolation_correction_comb;
        exponent_half_s9_q <= exponent_half_s8_q;
        segment_high_s9_q <= segment_high_s8_q;
    end

    kogge_stone_adder_48 #(.WIDTH(24)) u_interpolated_rsqrt_adder (
        .a_i(segment_high_s9_q), .b_i(~interpolation_correction_s9_q),
        .cin_i(1'b1), .sum_o(interpolated_rsqrt_comb)
    );

    always_comb begin
        normalized_fraction_comb = {interpolated_rsqrt_comb[21:0], 1'b0};
        biased_exponent_base_comb = 9'd126;
        if (interpolated_rsqrt_comb == 24'h800000) begin
            normalized_fraction_comb = 23'd0;
            biased_exponent_base_comb = 9'd127;
        end
    end

    kogge_stone_adder_48 #(.WIDTH(9)) u_biased_exponent_adder (
        .a_i(biased_exponent_base_comb), .b_i(~exponent_half_s9_q),
        .cin_i(1'b1), .sum_o(biased_exponent_comb)
    );

    always_ff @(posedge clk_i) begin
        normalized_fraction_s10_q <= normalized_fraction_comb;
        biased_exponent_s10_q <= biased_exponent_comb[7:0];
    end

    // Reset/Clear仅清除有效状态，数据寄存器由valid流水限定可观察性。
    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_pipe_q <= 10'd0;
        end else begin
            valid_pipe_q[0] <= valid_i;
            for (integer pipe_index = 1; pipe_index < 10; pipe_index++) begin
                valid_pipe_q[pipe_index] <= valid_pipe_q[pipe_index-1];
            end
        end
        special_pipe_q[0] <= input_special_comb;
        invalid_pipe_q[0] <= input_invalid_comb;
        special_result_pipe_q[0] <= input_special_result_comb;
        for (integer pipe_index = 1; pipe_index < 10; pipe_index++) begin
            special_pipe_q[pipe_index] <= special_pipe_q[pipe_index-1];
            invalid_pipe_q[pipe_index] <= invalid_pipe_q[pipe_index-1];
            special_result_pipe_q[pipe_index] <= special_result_pipe_q[pipe_index-1];
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_o <= 1'b0;
        end else begin
            valid_o <= valid_pipe_q[9];
        end
        if (special_pipe_q[9]) begin
            result_o <= special_result_pipe_q[9];
        end else begin
            result_o <= {1'b0, biased_exponent_s10_q, normalized_fraction_s10_q};
        end
        invalid_o <= invalid_pipe_q[9];
    end

    wire _unused_interpolation_bounds = &{1'b0,
                                          segment_delta_comb[23:19],
                                          interpolation_high_sum_comb[9],
                                          biased_exponent_comb[8]};

endmodule

`default_nettype wire
