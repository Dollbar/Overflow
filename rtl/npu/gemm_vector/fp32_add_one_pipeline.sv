`timescale 1ns/1ps
`default_nettype none

// Three-cycle RNE pipeline for 1.0 + x, restricted to positive x in [0, 1].
// This is the exact domain produced by fp32_exp_approx and avoids the wider
// align/normalize machinery of a general FP32 adder.
(* keep_hierarchy = "yes" *)
module fp32_add_one_pipeline (
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

    localparam logic [31:0] FP32_ONE = 32'h3f800000;
    localparam logic [31:0] FP32_TWO = 32'h40000000;
    localparam logic [31:0] FP32_CANONICAL_NAN = 32'h7fc00000;

    logic input_special_comb;
    logic [31:0] input_special_result_comb;
    logic input_invalid_comb;
    logic [23:0] input_significand_comb;
    logic [4:0] input_shift_comb;

    logic special_s1_q;
    logic [31:0] special_result_s1_q;
    logic invalid_s1_q;
    logic [23:0] significand_s1_q;
    logic [4:0] shift_s1_q;
    logic valid_s1_q;

    logic [23:0] shifted_main_comb;
    logic [23:0] remainder_mask_comb;
    logic guard_comb;
    logic sticky_comb;
    logic special_s2_q;
    logic [31:0] special_result_s2_q;
    logic invalid_s2_q;
    logic [23:0] shifted_main_s2_q;
    logic guard_s2_q;
    logic sticky_s2_q;
    logic valid_s2_q;

    logic round_increment_comb;
    logic [23:0] rounded_contribution_comb;
    logic [31:0] finite_result_comb;

    always_comb begin
        input_special_comb = 1'b0;
        input_special_result_comb = FP32_ONE;
        input_invalid_comb = invalid_i;
        input_significand_comb = {1'b1, data_i[22:0]};
        input_shift_comb = 5'd0;

        if ((data_i[30:23] == 8'hff) && (data_i[22:0] != 23'd0)) begin
            input_special_comb = 1'b1;
            input_special_result_comb = FP32_CANONICAL_NAN;
            input_invalid_comb = 1'b1;
        end else if (data_i[31]) begin
            input_special_comb = 1'b1;
            input_special_result_comb = FP32_CANONICAL_NAN;
            input_invalid_comb = 1'b1;
        end else if (data_i[30:0] == 31'd0 || data_i[30:23] < 8'd103) begin
            input_special_comb = 1'b1;
            input_special_result_comb = FP32_ONE;
        end else if (data_i >= FP32_ONE) begin
            input_special_comb = 1'b1;
            input_special_result_comb = FP32_TWO;
            if (data_i > FP32_ONE) begin
                input_invalid_comb = 1'b1;
            end
        end else begin
            input_shift_comb = 5'(8'd127 - data_i[30:23]);
        end
    end

    always_comb begin
        shifted_main_comb = significand_s1_q >> shift_s1_q;
        remainder_mask_comb = 24'hffffff >> (5'd24 - shift_s1_q);
        guard_comb = significand_s1_q[shift_s1_q - 1'b1];
        sticky_comb = |(significand_s1_q & (remainder_mask_comb >> 1'b1));
    end

    always_comb begin
        round_increment_comb = guard_s2_q &&
                               (sticky_s2_q || shifted_main_s2_q[0]);
        rounded_contribution_comb = shifted_main_s2_q +
                                    {{23{1'b0}}, round_increment_comb};
        finite_result_comb = {9'h07f, rounded_contribution_comb[22:0]};
        if (rounded_contribution_comb[23]) begin
            finite_result_comb = FP32_TWO;
        end
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

        special_s1_q <= input_special_comb;
        special_result_s1_q <= input_special_result_comb;
        invalid_s1_q <= input_invalid_comb;
        significand_s1_q <= input_significand_comb;
        shift_s1_q <= input_shift_comb;

        special_s2_q <= special_s1_q;
        special_result_s2_q <= special_result_s1_q;
        invalid_s2_q <= invalid_s1_q;
        shifted_main_s2_q <= shifted_main_comb;
        guard_s2_q <= guard_comb;
        sticky_s2_q <= sticky_comb;

        result_o <= special_s2_q ? special_result_s2_q : finite_result_comb;
        invalid_o <= invalid_s2_q;
    end

endmodule

`default_nettype wire
