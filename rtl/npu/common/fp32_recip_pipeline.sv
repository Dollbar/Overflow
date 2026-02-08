`timescale 1ns/1ps
`default_nettype none

// Softmax16正分母专用FP32倒数近似器。有效域为[1,16]，固定十一级流水。
// 尾数倒数使用16段Q1.23线性插值，分段乘法保持逐位精确。
(* keep_hierarchy = "yes" *)
module fp32_recip_pipeline (
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
    localparam logic [31:0] FP32_ONE = 32'h3f800000;
    localparam logic [31:0] FP32_SIXTEEN = 32'h41800000;

    logic input_nan_comb;
    logic input_inf_comb;
    logic input_zero_comb;
    logic input_below_range_comb;
    logic input_above_range_comb;
    logic input_special_comb;
    logic [31:0] input_special_result_comb;
    logic input_invalid_comb;
    logic [7:0] input_integer_part_comb;

    logic [3:0] segment_index_comb;
    logic [11:0] segment_remainder_comb;
    logic [23:0] segment_high_comb;
    logic [23:0] segment_low_comb;
    logic [23:0] segment_delta_comb;
    logic [7:0] integer_part_s1_q;
    logic [23:0] segment_high_s1_q;
    logic [18:0] segment_delta_s1_q;
    logic [11:0] segment_remainder_s1_q;

    logic [22:0] interpolation_local0_s4_q;
    logic [22:0] interpolation_local1_s4_q;
    logic [22:0] interpolation_local2_s4_q;
    logic [7:0] integer_part_s2_q;
    logic [23:0] segment_high_s2_q;
    logic [7:0] integer_part_s3_q;
    logic [23:0] segment_high_s3_q;
    logic [7:0] integer_part_s4_q;
    logic [23:0] segment_high_s4_q;

    logic [30:0] interpolation_operand0_comb;
    logic [30:0] interpolation_operand1_comb;
    logic [30:0] interpolation_operand2_comb;
    logic [29:0] interpolation_csa_majority_comb;
    logic [30:0] interpolation_csa_sum_comb;
    logic [30:0] interpolation_csa_carry_comb;
    logic [30:0] interpolation_csa_sum_s5_q;
    logic [30:0] interpolation_csa_carry_s5_q;
    logic [7:0] integer_part_s5_q;
    logic [23:0] segment_high_s5_q;

    logic [12:0] interpolation_low_sum_comb;
    logic [11:0] interpolation_low_product_s6_q;
    logic [18:0] interpolation_csa_sum_upper_s6_q;
    logic [18:0] interpolation_csa_carry_upper_s6_q;
    logic interpolation_low_carry_s6_q;
    logic [7:0] integer_part_s6_q;
    logic [23:0] segment_high_s6_q;

    logic [10:0] interpolation_middle_sum_comb;
    logic [11:0] interpolation_low_product_s7_q;
    logic [9:0] interpolation_middle_product_s7_q;
    logic [8:0] interpolation_csa_sum_high_s7_q;
    logic [8:0] interpolation_csa_carry_high_s7_q;
    logic interpolation_middle_carry_s7_q;
    logic [7:0] integer_part_s7_q;
    logic [23:0] segment_high_s7_q;

    logic [9:0] interpolation_high_sum_comb;
    logic [30:0] interpolation_product_comb;
    logic [30:0] interpolation_product_s8_q;
    logic [7:0] integer_part_s8_q;
    logic [23:0] segment_high_s8_q;

    logic interpolation_round_increment_comb;
    logic [23:0] interpolation_truncated_comb;
    logic [23:0] interpolation_round_vector_comb;
    logic [23:0] interpolation_correction_comb;
    logic [23:0] interpolation_correction_s9_q;
    logic [7:0] integer_part_s9_q;
    logic [23:0] segment_high_s9_q;

    logic [23:0] interpolated_fraction_comb;
    logic [22:0] normalized_fraction_comb;
    logic [7:0] biased_exponent_base_comb;
    logic [7:0] biased_exponent_comb;
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
        input_below_range_comb = !data_i[31] && !input_zero_comb &&
                                 (data_i < FP32_ONE);
        input_above_range_comb = !data_i[31] && !input_inf_comb &&
                                 (data_i > FP32_SIXTEEN);
        input_special_comb = input_nan_comb || data_i[31] || input_inf_comb ||
                             input_zero_comb || input_below_range_comb ||
                             input_above_range_comb;
        input_special_result_comb = 32'd0;
        input_invalid_comb = invalid_i;
        if (input_nan_comb || data_i[31]) begin
            input_special_result_comb = FP32_CANONICAL_NAN;
            input_invalid_comb = 1'b1;
        end else if (input_inf_comb) begin
            input_special_result_comb = 32'd0;
        end else if (input_zero_comb) begin
            input_special_result_comb = FP32_POSITIVE_INFINITY;
            input_invalid_comb = 1'b1;
        end else if (input_below_range_comb) begin
            input_special_result_comb = FP32_ONE;
            input_invalid_comb = 1'b1;
        end else if (input_above_range_comb) begin
            input_special_result_comb = 32'd0;
            input_invalid_comb = 1'b1;
        end
        input_integer_part_comb = data_i[30:23] - 8'd127;
    end

    // LUT保存1/(1+k/16)的Q1.23锚点。
    always_comb begin
        segment_index_comb = data_i[22:19];
        segment_remainder_comb = data_i[18:7];
        segment_high_comb = 24'h800000;
        segment_low_comb = 24'h787878;
        case (segment_index_comb)
            4'd0:  begin segment_high_comb = 24'h800000; segment_low_comb = 24'h787878; end
            4'd1:  begin segment_high_comb = 24'h787878; segment_low_comb = 24'h71c71c; end
            4'd2:  begin segment_high_comb = 24'h71c71c; segment_low_comb = 24'h6bca1b; end
            4'd3:  begin segment_high_comb = 24'h6bca1b; segment_low_comb = 24'h666666; end
            4'd4:  begin segment_high_comb = 24'h666666; segment_low_comb = 24'h618618; end
            4'd5:  begin segment_high_comb = 24'h618618; segment_low_comb = 24'h5d1746; end
            4'd6:  begin segment_high_comb = 24'h5d1746; segment_low_comb = 24'h590b21; end
            4'd7:  begin segment_high_comb = 24'h590b21; segment_low_comb = 24'h555555; end
            4'd8:  begin segment_high_comb = 24'h555555; segment_low_comb = 24'h51eb85; end
            4'd9:  begin segment_high_comb = 24'h51eb85; segment_low_comb = 24'h4ec4ec; end
            4'd10: begin segment_high_comb = 24'h4ec4ec; segment_low_comb = 24'h4bda13; end
            4'd11: begin segment_high_comb = 24'h4bda13; segment_low_comb = 24'h492492; end
            4'd12: begin segment_high_comb = 24'h492492; segment_low_comb = 24'h469ee6; end
            4'd13: begin segment_high_comb = 24'h469ee6; segment_low_comb = 24'h444444; end
            4'd14: begin segment_high_comb = 24'h444444; segment_low_comb = 24'h421084; end
            4'd15: begin segment_high_comb = 24'h421084; segment_low_comb = 24'h400000; end
            default: begin segment_high_comb = 24'h800000; segment_low_comb = 24'h787878; end
        endcase
    end

    kogge_stone_adder_48 #(.WIDTH(24)) u_segment_delta_adder (
        .a_i(segment_high_comb),
        .b_i(~segment_low_comb),
        .cin_i(1'b1),
        .sum_o(segment_delta_comb)
    );

    always_ff @(posedge clk_i) begin
        integer_part_s1_q <= input_integer_part_comb;
        segment_high_s1_q <= segment_high_comb;
        segment_delta_s1_q <= segment_delta_comb[18:0];
        segment_remainder_s1_q <= segment_remainder_comb;
    end

    fp32_exp_mul_u19_u4 u_interpolation_local0 (
        .clk_i(clk_i),
        .multiplicand_i(segment_delta_s1_q),
        .multiplier_i(segment_remainder_s1_q[3:0]),
        .product_o(interpolation_local0_s4_q)
    );

    fp32_exp_mul_u19_u4 u_interpolation_local1 (
        .clk_i(clk_i),
        .multiplicand_i(segment_delta_s1_q),
        .multiplier_i(segment_remainder_s1_q[7:4]),
        .product_o(interpolation_local1_s4_q)
    );

    fp32_exp_mul_u19_u4 u_interpolation_local2 (
        .clk_i(clk_i),
        .multiplicand_i(segment_delta_s1_q),
        .multiplier_i(segment_remainder_s1_q[11:8]),
        .product_o(interpolation_local2_s4_q)
    );

    always_ff @(posedge clk_i) begin
        integer_part_s2_q <= integer_part_s1_q;
        segment_high_s2_q <= segment_high_s1_q;
        integer_part_s3_q <= integer_part_s2_q;
        segment_high_s3_q <= segment_high_s2_q;
        integer_part_s4_q <= integer_part_s3_q;
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
        integer_part_s5_q <= integer_part_s4_q;
        segment_high_s5_q <= segment_high_s4_q;
    end

    kogge_stone_adder_48 #(.WIDTH(13)) u_interpolation_low_block_adder (
        .a_i({1'b0, interpolation_csa_sum_s5_q[11:0]}),
        .b_i({1'b0, interpolation_csa_carry_s5_q[11:0]}),
        .cin_i(1'b0),
        .sum_o(interpolation_low_sum_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_low_product_s6_q <= interpolation_low_sum_comb[11:0];
        interpolation_low_carry_s6_q <= interpolation_low_sum_comb[12];
        interpolation_csa_sum_upper_s6_q <= interpolation_csa_sum_s5_q[30:12];
        interpolation_csa_carry_upper_s6_q <= interpolation_csa_carry_s5_q[30:12];
        integer_part_s6_q <= integer_part_s5_q;
        segment_high_s6_q <= segment_high_s5_q;
    end

    kogge_stone_adder_48 #(.WIDTH(11)) u_interpolation_middle_block_adder (
        .a_i({1'b0, interpolation_csa_sum_upper_s6_q[9:0]}),
        .b_i({1'b0, interpolation_csa_carry_upper_s6_q[9:0]}),
        .cin_i(interpolation_low_carry_s6_q),
        .sum_o(interpolation_middle_sum_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_low_product_s7_q <= interpolation_low_product_s6_q;
        interpolation_middle_product_s7_q <= interpolation_middle_sum_comb[9:0];
        interpolation_middle_carry_s7_q <= interpolation_middle_sum_comb[10];
        interpolation_csa_sum_high_s7_q <= interpolation_csa_sum_upper_s6_q[18:10];
        interpolation_csa_carry_high_s7_q <= interpolation_csa_carry_upper_s6_q[18:10];
        integer_part_s7_q <= integer_part_s6_q;
        segment_high_s7_q <= segment_high_s6_q;
    end

    kogge_stone_adder_48 #(.WIDTH(10)) u_interpolation_high_block_adder (
        .a_i({1'b0, interpolation_csa_sum_high_s7_q}),
        .b_i({1'b0, interpolation_csa_carry_high_s7_q}),
        .cin_i(interpolation_middle_carry_s7_q),
        .sum_o(interpolation_high_sum_comb)
    );

    always_comb begin
        interpolation_product_comb = {interpolation_high_sum_comb[8:0],
                                      interpolation_middle_product_s7_q,
                                      interpolation_low_product_s7_q};
    end

    always_ff @(posedge clk_i) begin
        interpolation_product_s8_q <= interpolation_product_comb;
        integer_part_s8_q <= integer_part_s7_q;
        segment_high_s8_q <= segment_high_s7_q;
    end

    always_comb begin
        interpolation_round_increment_comb = interpolation_product_s8_q[11] &&
                                              ((|interpolation_product_s8_q[10:0]) ||
                                               interpolation_product_s8_q[12]);
        interpolation_truncated_comb = {5'd0, interpolation_product_s8_q[30:12]};
        interpolation_round_vector_comb = {{23{1'b0}},
                                             interpolation_round_increment_comb};
    end

    kogge_stone_adder_48 #(.WIDTH(24)) u_interpolation_round_adder (
        .a_i(interpolation_truncated_comb),
        .b_i(interpolation_round_vector_comb),
        .cin_i(1'b0),
        .sum_o(interpolation_correction_comb)
    );

    always_ff @(posedge clk_i) begin
        interpolation_correction_s9_q <= interpolation_correction_comb;
        integer_part_s9_q <= integer_part_s8_q;
        segment_high_s9_q <= segment_high_s8_q;
    end

    kogge_stone_adder_48 #(.WIDTH(24)) u_interpolated_fraction_adder (
        .a_i(segment_high_s9_q),
        .b_i(~interpolation_correction_s9_q),
        .cin_i(1'b1),
        .sum_o(interpolated_fraction_comb)
    );

    always_comb begin
        normalized_fraction_comb = interpolated_fraction_comb[22:0];
        biased_exponent_base_comb = 8'd127;
        if (interpolated_fraction_comb != 24'h800000) begin
            normalized_fraction_comb = {interpolated_fraction_comb[21:0], 1'b0};
            biased_exponent_base_comb = 8'd126;
        end
    end

    kogge_stone_adder_48 #(.WIDTH(8)) u_biased_exponent_adder (
        .a_i(biased_exponent_base_comb),
        .b_i(~integer_part_s9_q),
        .cin_i(1'b1),
        .sum_o(biased_exponent_comb)
    );

    always_ff @(posedge clk_i) begin
        normalized_fraction_s10_q <= normalized_fraction_comb;
        biased_exponent_s10_q <= biased_exponent_comb;
    end

    // Valid与十个内部数据寄存级保持对齐，Reset/Clear只清除有效状态。
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
                                          interpolated_fraction_comb[23]};

endmodule

`default_nettype wire
