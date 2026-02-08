`timescale 1ns/1ps
`default_nettype none

// Softmax负域专用FP32指数近似器。有效精度区间为[-16, 0]，固定十六级流水。
// 算法把exp(x)变换为2^(-|x|*log2(e))，再用16段线性插值近似2^-fraction。
(* keep_hierarchy = "yes" *)
module fp32_exp_approx (
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
    localparam logic [31:0] FP32_ONE = 32'h3f800000;
    localparam logic [31:0] FP32_NEGATIVE_SIXTEEN = 32'hc1800000;

    logic input_nan_comb;
    logic input_inf_comb;
    logic input_zero_comb;
    logic input_positive_nonzero_comb;
    logic input_below_range_comb;
    logic input_special_comb;
    logic [31:0] input_special_result_comb;
    logic input_invalid_comb;
    logic [23:0] input_significand_comb;
    logic [7:0] magnitude_shift_comb;
    logic [20:0] magnitude_q16_comb;
    logic [20:0] magnitude_q16_s1_q;

    logic [23:0] range_partial0_comb;
    logic [23:0] range_partial1_comb;
    logic [23:0] range_partial2_comb;
    logic [23:0] range_partial0_s2_q;
    logic [23:0] range_partial1_s2_q;
    logic [23:0] range_partial2_s2_q;

    logic [30:0] range_low_comb;
    logic [30:0] range_low_s3_q;
    logic [23:0] range_partial2_s3_q;

    logic [37:0] range_product_comb;
    logic [37:0] range_product_s4_q;
    logic range_round_increment_comb;
    logic [23:0] range_q16_truncated_comb;
    logic [23:0] range_round_vector_comb;
    logic [23:0] range_q16_comb;
    logic [23:0] range_q16_s5_q;

    logic [3:0] segment_index_comb;
    logic [11:0] segment_remainder_comb;
    logic [23:0] segment_high_comb;
    logic [23:0] segment_low_comb;
    logic [23:0] segment_delta_comb;
    logic [7:0] integer_part_s6_q;
    logic fraction_zero_s6_q;
    logic [22:0] segment_high_s6_q;
    logic [18:0] segment_delta_s6_q;
    logic [11:0] segment_remainder_s6_q;

    logic [22:0] interpolation_local0_s9_q;
    logic [22:0] interpolation_local1_s9_q;
    logic [22:0] interpolation_local2_s9_q;
    logic [7:0] integer_part_s7_q;
    logic fraction_zero_s7_q;
    logic [22:0] segment_high_s7_q;
    logic [7:0] integer_part_s8_q;
    logic fraction_zero_s8_q;
    logic [22:0] segment_high_s8_q;
    logic [7:0] integer_part_s9_q;
    logic fraction_zero_s9_q;
    logic [22:0] segment_high_s9_q;

    logic [30:0] interpolation_operand0_comb;
    logic [30:0] interpolation_operand1_comb;
    logic [30:0] interpolation_operand2_comb;
    logic [29:0] interpolation_csa_majority_comb;
    logic [30:0] interpolation_csa_sum_comb;
    logic [30:0] interpolation_csa_carry_comb;
    logic [30:0] interpolation_csa_sum_s10_q;
    logic [30:0] interpolation_csa_carry_s10_q;
    logic [7:0] integer_part_s10_q;
    logic fraction_zero_s10_q;
    logic [22:0] segment_high_s10_q;

    logic [12:0] interpolation_low_sum_comb;
    logic [11:0] interpolation_low_product_s11_q;
    logic [18:0] interpolation_csa_sum_upper_s11_q;
    logic [18:0] interpolation_csa_carry_upper_s11_q;
    logic interpolation_low_carry_s11_q;
    logic [7:0] integer_part_s11_q;
    logic fraction_zero_s11_q;
    logic [22:0] segment_high_s11_q;

    logic [10:0] interpolation_middle_sum_comb;
    logic [11:0] interpolation_low_product_s12_q;
    logic [9:0] interpolation_middle_product_s12_q;
    logic [8:0] interpolation_csa_sum_high_s12_q;
    logic [8:0] interpolation_csa_carry_high_s12_q;
    logic interpolation_middle_carry_s12_q;
    logic [7:0] integer_part_s12_q;
    logic fraction_zero_s12_q;
    logic [22:0] segment_high_s12_q;

    logic [9:0] interpolation_high_sum_comb;
    logic [30:0] interpolation_product_comb;
    logic [30:0] interpolation_product_s13_q;
    logic [7:0] integer_part_s13_q;
    logic fraction_zero_s13_q;
    logic [22:0] segment_high_s13_q;
    logic interpolation_round_increment_comb;
    logic [22:0] interpolation_truncated_comb;
    logic [22:0] interpolation_round_vector_comb;
    logic [22:0] interpolation_correction_comb;
    logic [22:0] interpolation_correction_s14_q;
    logic [7:0] integer_part_s14_q;
    logic fraction_zero_s14_q;
    logic [22:0] segment_high_s14_q;

    logic [22:0] interpolated_fraction_comb;
    logic [22:0] normalized_fraction_comb;
    logic [7:0] biased_exponent_base_comb;
    logic [7:0] biased_exponent_comb;
    logic [22:0] normalized_fraction_s15_q;
    logic [7:0] biased_exponent_s15_q;

    logic [14:0] valid_pipe_q;
    logic [14:0] special_pipe_q;
    logic [14:0] invalid_pipe_q;
    logic [31:0] special_result_pipe_q [0:14];

    // 输入分类和FP32绝对值到Q5.16的转换在入口级完成。
    always_comb begin
        input_nan_comb = (data_i[30:23] == 8'hff) && (data_i[22:0] != 23'd0);
        input_inf_comb = (data_i[30:23] == 8'hff) && (data_i[22:0] == 23'd0);
        input_zero_comb = (data_i[30:0] == 31'd0);
        input_positive_nonzero_comb = !data_i[31] && !input_zero_comb;
        input_below_range_comb = data_i[31] &&
                                 (data_i[30:0] > FP32_NEGATIVE_SIXTEEN[30:0]);
        input_special_comb = input_nan_comb || input_inf_comb || input_zero_comb ||
                             input_positive_nonzero_comb || input_below_range_comb;
        input_special_result_comb = 32'd0;
        input_invalid_comb = invalid_i;
        if (input_nan_comb) begin
            input_special_result_comb = FP32_CANONICAL_NAN;
            input_invalid_comb = 1'b1;
        end else if (input_inf_comb) begin
            if (data_i[31]) begin
                input_special_result_comb = 32'd0;
            end else begin
                input_special_result_comb = FP32_ONE;
                input_invalid_comb = 1'b1;
            end
        end else if (input_zero_comb) begin
            input_special_result_comb = FP32_ONE;
        end else if (input_positive_nonzero_comb) begin
            input_special_result_comb = FP32_ONE;
            input_invalid_comb = 1'b1;
        end else if (input_below_range_comb) begin
            input_special_result_comb = 32'd0;
        end

        input_significand_comb = {1'b1, data_i[22:0]};
        magnitude_shift_comb = 8'd0;
        magnitude_q16_comb = 21'd0;
        if (data_i[30:23] >= 8'd111 && data_i[30:23] <= 8'd131) begin
            magnitude_shift_comb = 8'd134 - data_i[30:23];
            magnitude_q16_comb = 21'(
                input_significand_comb >> magnitude_shift_comb);
        end
    end

    always_ff @(posedge clk_i) begin
        magnitude_q16_s1_q <= magnitude_q16_comb;
    end

    // 将21x17常数乘法分为三个7x17局部乘法，限制单级组合深度。
    always_comb begin
        range_partial0_comb = 24'(magnitude_q16_s1_q[6:0] * 17'd94548);
        range_partial1_comb = 24'(magnitude_q16_s1_q[13:7] * 17'd94548);
        range_partial2_comb = 24'(magnitude_q16_s1_q[20:14] * 17'd94548);
    end

    always_ff @(posedge clk_i) begin
        range_partial0_s2_q <= range_partial0_comb;
        range_partial1_s2_q <= range_partial1_comb;
        range_partial2_s2_q <= range_partial2_comb;
    end

    // 先合并低14位输入分块的贡献。
    kogge_stone_adder_48 #(.WIDTH(31)) u_range_low_adder (
        .a_i({7'd0, range_partial0_s2_q}),
        .b_i({range_partial1_s2_q, 7'd0}),
        .cin_i(1'b0),
        .sum_o(range_low_comb)
    );

    always_ff @(posedge clk_i) begin
        range_low_s3_q <= range_low_comb;
        range_partial2_s3_q <= range_partial2_s2_q;
    end

    // 合并最高7位输入分块的贡献，形成精确常数乘积。
    kogge_stone_adder_48 #(.WIDTH(38)) u_range_product_adder (
        .a_i({7'd0, range_low_s3_q}),
        .b_i({range_partial2_s3_q, 14'd0}),
        .cin_i(1'b0),
        .sum_o(range_product_comb)
    );

    always_ff @(posedge clk_i) begin
        range_product_s4_q <= range_product_comb;
    end

    // 单独一级完成最近偶数舍入，避免乘积合并与舍入加法串联。
    always_comb begin
        range_round_increment_comb = range_product_s4_q[15] &&
                                     ((|range_product_s4_q[14:0]) ||
                                      range_product_s4_q[16]);
        range_q16_truncated_comb = {2'b00, range_product_s4_q[37:16]};
        range_round_vector_comb = {{23{1'b0}}, range_round_increment_comb};
    end

    kogge_stone_adder_48 #(.WIDTH(24)) u_range_round_adder (
        .a_i(range_q16_truncated_comb),
        .b_i(range_round_vector_comb),
        .cin_i(1'b0),
        .sum_o(range_q16_comb)
    );

    always_ff @(posedge clk_i) begin
        range_q16_s5_q <= range_q16_comb;
    end

    // LUT保存2^(-k/16)的Q1.23锚点，相邻锚点用于线性插值。
    always_comb begin
        segment_index_comb = range_q16_s5_q[15:12];
        segment_remainder_comb = range_q16_s5_q[11:0];
        segment_high_comb = 24'h800000;
        segment_low_comb = 24'h7a92bf;
        case (segment_index_comb)
            4'd0:  begin segment_high_comb = 24'h800000; segment_low_comb = 24'h7a92bf; end
            4'd1:  begin segment_high_comb = 24'h7a92bf; segment_low_comb = 24'h756063; end
            4'd2:  begin segment_high_comb = 24'h756063; segment_low_comb = 24'h70666f; end
            4'd3:  begin segment_high_comb = 24'h70666f; segment_low_comb = 24'h6ba27e; end
            4'd4:  begin segment_high_comb = 24'h6ba27e; segment_low_comb = 24'h671246; end
            4'd5:  begin segment_high_comb = 24'h671246; segment_low_comb = 24'h62b395; end
            4'd6:  begin segment_high_comb = 24'h62b395; segment_low_comb = 24'h5e8452; end
            4'd7:  begin segment_high_comb = 24'h5e8452; segment_low_comb = 24'h5a827a; end
            4'd8:  begin segment_high_comb = 24'h5a827a; segment_low_comb = 24'h56ac1f; end
            4'd9:  begin segment_high_comb = 24'h56ac1f; segment_low_comb = 24'h52ff6b; end
            4'd10: begin segment_high_comb = 24'h52ff6b; segment_low_comb = 24'h4f7a99; end
            4'd11: begin segment_high_comb = 24'h4f7a99; segment_low_comb = 24'h4c1bf8; end
            4'd12: begin segment_high_comb = 24'h4c1bf8; segment_low_comb = 24'h48e1ea; end
            4'd13: begin segment_high_comb = 24'h48e1ea; segment_low_comb = 24'h45cae1; end
            4'd14: begin segment_high_comb = 24'h45cae1; segment_low_comb = 24'h42d562; end
            4'd15: begin segment_high_comb = 24'h42d562; segment_low_comb = 24'h400000; end
            default: begin segment_high_comb = 24'h800000; segment_low_comb = 24'h7a92bf; end
        endcase
    end


    kogge_stone_adder_48 #(.WIDTH(24)) u_segment_delta_adder (
        .a_i(segment_high_comb),
        .b_i(~segment_low_comb),
        .cin_i(1'b1),
        .sum_o(segment_delta_comb)
    );

    always_ff @(posedge clk_i) begin
        integer_part_s6_q <= range_q16_s5_q[23:16];
        fraction_zero_s6_q <= (range_q16_s5_q[15:0] == 16'd0);
        segment_high_s6_q <= segment_high_comb[22:0];
        segment_delta_s6_q <= segment_delta_comb[18:0];
        segment_remainder_s6_q <= segment_remainder_comb;
    end

    // delta最大为19'h56d41。三个精确19x4乘法器分别处理remainder的三个半字节。
    fp32_exp_mul_u19_u4 u_interpolation_local0 (
        .clk_i(clk_i),
        .multiplicand_i(segment_delta_s6_q),
        .multiplier_i(segment_remainder_s6_q[3:0]),
        .product_o(interpolation_local0_s9_q)
    );

    fp32_exp_mul_u19_u4 u_interpolation_local1 (
        .clk_i(clk_i),
        .multiplicand_i(segment_delta_s6_q),
        .multiplier_i(segment_remainder_s6_q[7:4]),
        .product_o(interpolation_local1_s9_q)
    );

    fp32_exp_mul_u19_u4 u_interpolation_local2 (
        .clk_i(clk_i),
        .multiplicand_i(segment_delta_s6_q),
        .multiplier_i(segment_remainder_s6_q[11:8]),
        .product_o(interpolation_local2_s9_q)
    );

    always_ff @(posedge clk_i) begin
        integer_part_s7_q <= integer_part_s6_q;
        fraction_zero_s7_q <= fraction_zero_s6_q;
        segment_high_s7_q <= segment_high_s6_q;
        integer_part_s8_q <= integer_part_s7_q;
        fraction_zero_s8_q <= fraction_zero_s7_q;
        segment_high_s8_q <= segment_high_s7_q;
        integer_part_s9_q <= integer_part_s8_q;
        fraction_zero_s9_q <= fraction_zero_s8_q;
        segment_high_s9_q <= segment_high_s8_q;
    end

    // 三行局部乘积先经无进位保存压缩，避免本级出现宽进位链。
    always_comb begin
        interpolation_operand0_comb = {8'd0, interpolation_local0_s9_q};
        interpolation_operand1_comb = {4'd0, interpolation_local1_s9_q, 4'd0};
        interpolation_operand2_comb = {interpolation_local2_s9_q, 8'd0};
        interpolation_csa_majority_comb =
            (interpolation_operand0_comb[29:0] & interpolation_operand1_comb[29:0]) |
            (interpolation_operand0_comb[29:0] & interpolation_operand2_comb[29:0]) |
            (interpolation_operand1_comb[29:0] & interpolation_operand2_comb[29:0]);
        interpolation_csa_sum_comb = interpolation_operand0_comb ^
                                     interpolation_operand1_comb ^
                                     interpolation_operand2_comb;
        interpolation_csa_carry_comb =
            {interpolation_csa_majority_comb, 1'b0};
    end

    always_ff @(posedge clk_i) begin
        interpolation_csa_sum_s10_q <= interpolation_csa_sum_comb;
        interpolation_csa_carry_s10_q <= interpolation_csa_carry_comb;
        integer_part_s10_q <= integer_part_s9_q;
        fraction_zero_s10_q <= fraction_zero_s9_q;
        segment_high_s10_q <= segment_high_s9_q;
    end

    // 最终进位传播按12/10/9位分三级完成，每一级只跨越很窄的位段。
    kogge_stone_adder_48 #(.WIDTH(13)) u_interpolation_low_block_adder (
        .a_i({1'b0, interpolation_csa_sum_s10_q[11:0]}),
        .b_i({1'b0, interpolation_csa_carry_s10_q[11:0]}),
        .cin_i(1'b0),
        .sum_o(interpolation_low_sum_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_low_product_s11_q <= interpolation_low_sum_comb[11:0];
        interpolation_low_carry_s11_q <= interpolation_low_sum_comb[12];
        interpolation_csa_sum_upper_s11_q <= interpolation_csa_sum_s10_q[30:12];
        interpolation_csa_carry_upper_s11_q <= interpolation_csa_carry_s10_q[30:12];
        integer_part_s11_q <= integer_part_s10_q;
        fraction_zero_s11_q <= fraction_zero_s10_q;
        segment_high_s11_q <= segment_high_s10_q;
    end

    kogge_stone_adder_48 #(.WIDTH(11)) u_interpolation_middle_block_adder (
        .a_i({1'b0, interpolation_csa_sum_upper_s11_q[9:0]}),
        .b_i({1'b0, interpolation_csa_carry_upper_s11_q[9:0]}),
        .cin_i(interpolation_low_carry_s11_q),
        .sum_o(interpolation_middle_sum_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_low_product_s12_q <= interpolation_low_product_s11_q;
        interpolation_middle_product_s12_q <= interpolation_middle_sum_comb[9:0];
        interpolation_middle_carry_s12_q <= interpolation_middle_sum_comb[10];
        interpolation_csa_sum_high_s12_q <= interpolation_csa_sum_upper_s11_q[18:10];
        interpolation_csa_carry_high_s12_q <= interpolation_csa_carry_upper_s11_q[18:10];
        integer_part_s12_q <= integer_part_s11_q;
        fraction_zero_s12_q <= fraction_zero_s11_q;
        segment_high_s12_q <= segment_high_s11_q;
    end

    kogge_stone_adder_48 #(.WIDTH(10)) u_interpolation_high_block_adder (
        .a_i({1'b0, interpolation_csa_sum_high_s12_q}),
        .b_i({1'b0, interpolation_csa_carry_high_s12_q}),
        .cin_i(interpolation_middle_carry_s12_q),
        .sum_o(interpolation_high_sum_comb)
    );

    always_comb begin
        interpolation_product_comb = {interpolation_high_sum_comb[8:0],
                                      interpolation_middle_product_s12_q,
                                      interpolation_low_product_s12_q};
    end

    // 由19位delta和12位remainder的数值上界保证最高进位恒为零。
    wire _unused_interpolation_bounds = &{1'b0,
                                          segment_delta_comb[23:19],
                                          interpolation_high_sum_comb[9]};

    always_ff @(posedge clk_i) begin
        interpolation_product_s13_q <= interpolation_product_comb;
        integer_part_s13_q <= integer_part_s12_q;
        fraction_zero_s13_q <= fraction_zero_s12_q;
        segment_high_s13_q <= segment_high_s12_q;
    end

    // 以最近偶数方式除以4096；高4位补零恢复原23位校正量接口。
    always_comb begin
        interpolation_round_increment_comb = interpolation_product_s13_q[11] &&
                                              ((|interpolation_product_s13_q[10:0]) ||
                                               interpolation_product_s13_q[12]);
        interpolation_truncated_comb = {4'd0, interpolation_product_s13_q[30:12]};
        interpolation_round_vector_comb = {{22{1'b0}},
                                             interpolation_round_increment_comb};
    end

    kogge_stone_adder_48 #(.WIDTH(23)) u_interpolation_round_adder (
        .a_i(interpolation_truncated_comb),
        .b_i(interpolation_round_vector_comb),
        .cin_i(1'b0),
        .sum_o(interpolation_correction_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_correction_s14_q <= interpolation_correction_comb;
        integer_part_s14_q <= integer_part_s13_q;
        fraction_zero_s14_q <= fraction_zero_s13_q;
        segment_high_s14_q <= segment_high_s13_q;
    end

    // 低23位减法足以形成FP32 fraction；隐含最高位由指数分支确定。
    kogge_stone_adder_48 #(.WIDTH(23)) u_interpolated_fraction_adder (
        .a_i(segment_high_s14_q),
        .b_i(~interpolation_correction_s14_q),
        .cin_i(1'b1),
        .sum_o(interpolated_fraction_comb)
    );

    always_comb begin
        normalized_fraction_comb = interpolated_fraction_comb;
        biased_exponent_base_comb = 8'd127;
        if (!fraction_zero_s14_q) begin
            normalized_fraction_comb = {interpolated_fraction_comb[21:0], 1'b0};
            biased_exponent_base_comb = 8'd126;
        end
    end


    kogge_stone_adder_48 #(.WIDTH(8)) u_biased_exponent_adder (
        .a_i(biased_exponent_base_comb),
        .b_i(~integer_part_s14_q),
        .cin_i(1'b1),
        .sum_o(biased_exponent_comb)
    );

    always_ff @(posedge clk_i) begin
        normalized_fraction_s15_q <= normalized_fraction_comb;
        biased_exponent_s15_q <= biased_exponent_comb;
    end

    // 特殊值、Invalid和Valid与十五个内部数据寄存级保持严格对齐。
    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_pipe_q <= 15'd0;
        end else begin
            valid_pipe_q[0] <= valid_i;
            for (integer pipe_index = 1; pipe_index < 15; pipe_index++) begin
                valid_pipe_q[pipe_index] <= valid_pipe_q[pipe_index-1];
            end
        end
        special_pipe_q[0] <= input_special_comb;
        invalid_pipe_q[0] <= input_invalid_comb;
        special_result_pipe_q[0] <= input_special_result_comb;
        for (integer pipe_index = 1; pipe_index < 15; pipe_index++) begin
            special_pipe_q[pipe_index] <= special_pipe_q[pipe_index-1];
            invalid_pipe_q[pipe_index] <= invalid_pipe_q[pipe_index-1];
            special_result_pipe_q[pipe_index] <= special_result_pipe_q[pipe_index-1];
        end
    end

    // 输出级隔离后续16路复制时的负载；Reset和Clear只清除有效状态。
    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_o <= 1'b0;
        end else begin
            valid_o <= valid_pipe_q[14];
        end
        if (special_pipe_q[14]) begin
            result_o <= special_result_pipe_q[14];
        end else begin
            result_o <= {1'b0, biased_exponent_s15_q, normalized_fraction_s15_q};
        end
        invalid_o <= invalid_pipe_q[14];
    end

endmodule

`default_nettype wire
