`timescale 1ns/1ps
`default_nettype none

// 19x4无符号乘法器：先做四个最多5x4的小乘积，再用14/13位加法器合并。
// 三个寄存级均无控制状态，由上层valid流水统一限定结果有效性。
module fp32_exp_mul_u19_u4 (
    input  logic        clk_i,
    input  logic [18:0] multiplicand_i,
    input  logic [3:0]  multiplier_i,
    output logic [22:0] product_o
);

    logic [8:0] partial0_comb;
    logic [8:0] partial1_comb;
    logic [8:0] partial2_comb;
    logic [7:0] partial3_comb;
    logic [8:0] partial0_s1_q;
    logic [8:0] partial1_s1_q;
    logic [8:0] partial2_s1_q;
    logic [7:0] partial3_s1_q;
    logic [13:0] low_pair_comb;
    logic [12:0] high_pair_comb;
    logic [13:0] low_pair_s2_q;
    logic [12:0] high_pair_s2_q;
    logic [12:0] upper_product_comb;

    always_comb begin
        partial0_comb = 9'(multiplicand_i[4:0] * multiplier_i);
        partial1_comb = 9'(multiplicand_i[9:5] * multiplier_i);
        partial2_comb = 9'(multiplicand_i[14:10] * multiplier_i);
        partial3_comb = 8'(multiplicand_i[18:15] * multiplier_i);
    end

    always_ff @(posedge clk_i) begin
        partial0_s1_q <= partial0_comb;
        partial1_s1_q <= partial1_comb;
        partial2_s1_q <= partial2_comb;
        partial3_s1_q <= partial3_comb;
    end

    kogge_stone_adder_48 #(.WIDTH(14)) u_low_pair_adder (
        .a_i({5'd0, partial0_s1_q}),
        .b_i({partial1_s1_q, 5'd0}),
        .cin_i(1'b0),
        .sum_o(low_pair_comb)
    );

    kogge_stone_adder_48 #(.WIDTH(13)) u_high_pair_adder (
        .a_i({4'd0, partial2_s1_q}),
        .b_i({partial3_s1_q, 5'd0}),
        .cin_i(1'b0),
        .sum_o(high_pair_comb)
    );

    always_ff @(posedge clk_i) begin
        low_pair_s2_q <= low_pair_comb;
        high_pair_s2_q <= high_pair_comb;
    end

    // 高分块从bit10开始，故这里只需要13位加法，低10位可直接拼接。
    kogge_stone_adder_48 #(.WIDTH(13)) u_upper_product_adder (
        .a_i(high_pair_s2_q),
        .b_i({9'd0, low_pair_s2_q[13:10]}),
        .cin_i(1'b0),
        .sum_o(upper_product_comb)
    );

    always_ff @(posedge clk_i) begin
        product_o <= {upper_product_comb, low_pair_s2_q[9:0]};
    end

endmodule

`default_nettype wire
