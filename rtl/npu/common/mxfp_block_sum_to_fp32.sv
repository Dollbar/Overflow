`timescale 1ns/1ps
`default_nettype none

// Converts an exact signed Q32 MX dot-product sum to IEEE FP32. The default
// width preserves the 32-element block ABI; a PE selects 85 bits so the whole
// matrix dot product is rounded only once.
module mxfp_block_sum_to_fp32 #(
    parameter bit FTZ = 1'b0,
    parameter int unsigned EXACT_WIDTH = 70
) (
    input  logic                           clk_i,
    input  logic                           rst_i,
    input  logic                           clear_i,
    input  logic                           valid_i,
    input  logic signed  [EXACT_WIDTH-1:0] exact_i,
    input  logic signed              [9:0] scale_exponent_i,
    input  fp8_pkg::fp8_reduce_special_e   special_i,
    input  fp8_pkg::fp8_reduce_zero_sign_e zero_sign_i,
    input  logic                           invalid_i,
    output logic                           valid_o,
    output logic                    [31:0] result_o,
    output logic                           invalid_o
);

    localparam logic [31:0] FP32_QNAN = 32'h7fc00000;
    localparam logic [31:0] FP32_POS_INF = 32'h7f800000;
    localparam logic [31:0] FP32_NEG_INF = 32'hff800000;

    logic [EXACT_WIDTH-1:0] magnitude;
    logic sign;
    logic nonzero;
    logic [6:0] msb_index;
    logic signed [11:0] unbiased_exponent;
    logic signed [12:0] shift_count;
    logic [23:0] normal_main;
    logic [24:0] rounded_normal;
    logic [22:0] subnormal_main;
    logic [23:0] rounded_subnormal;
    logic guard_bit;
    logic sticky_bit;
    logic round_increment;
    logic [31:0] finite_result;
    logic [31:0] result_comb;
    logic invalid_comb;
    logic [31:0] result_q;
    logic invalid_q;
    logic valid_q;

    always_comb begin
        sign = exact_i[EXACT_WIDTH-1];
        magnitude = sign ?
                           (~$unsigned(exact_i) + EXACT_WIDTH'(1)) :
                           $unsigned(exact_i);
        nonzero = |magnitude;
        msb_index = 7'd0;
        for (integer bit_index = 0; bit_index < EXACT_WIDTH; bit_index++) begin
            if (magnitude[bit_index]) begin
                msb_index = 7'(bit_index);
            end
        end

        unbiased_exponent = $signed({5'd0, msb_index}) - 12'sd32 +
            $signed({{2{scale_exponent_i[9]}}, scale_exponent_i});
        shift_count = 13'sd0;
        normal_main = 24'd0;
        rounded_normal = 25'd0;
        subnormal_main = 23'd0;
        rounded_subnormal = 24'd0;
        guard_bit = 1'b0;
        sticky_bit = 1'b0;
        round_increment = 1'b0;
        finite_result = {sign, 31'd0};

        if (nonzero && (unbiased_exponent >= -12'sd126)) begin
            shift_count = $signed({6'd0, msb_index}) - 13'sd23;
            if (shift_count > 0) begin
                normal_main = 24'(magnitude >> shift_count);
                guard_bit = magnitude[shift_count-1];
                for (integer sticky_index = 0; sticky_index < EXACT_WIDTH;
                     sticky_index++) begin
                    if (sticky_index < (integer'(shift_count) - 1)) begin
                        sticky_bit |= magnitude[sticky_index];
                    end
                end
            end else begin
                normal_main = 24'(magnitude << (-shift_count));
            end
            round_increment = guard_bit && (sticky_bit || normal_main[0]);
            rounded_normal = {1'b0, normal_main} + round_increment;
            if (rounded_normal[24]) begin
                unbiased_exponent = unbiased_exponent + 12'sd1;
                normal_main = rounded_normal[24:1];
            end else begin
                normal_main = rounded_normal[23:0];
            end
            if (unbiased_exponent > 12'sd127) begin
                finite_result = sign ? FP32_NEG_INF : FP32_POS_INF;
            end else begin
                finite_result = {sign,
                    8'(unbiased_exponent + 12'sd127), normal_main[22:0]};
            end
        end else if (nonzero && !FTZ) begin
            // fraction = round(exact * 2^(scale-32+149)).
            shift_count = -($signed({{2{scale_exponent_i[9]}},
                                      scale_exponent_i}) + 12'sd117);
            if (shift_count > 0) begin
                subnormal_main = 23'(magnitude >> shift_count);
                if (shift_count <= 13'(EXACT_WIDTH)) begin
                    guard_bit = magnitude[shift_count-1];
                end
                for (integer sticky_index = 0; sticky_index < EXACT_WIDTH;
                     sticky_index++) begin
                    if (sticky_index < (integer'(shift_count) - 1)) begin
                        sticky_bit |= magnitude[sticky_index];
                    end
                end
            end else begin
                subnormal_main = 23'(magnitude << (-shift_count));
            end
            round_increment = guard_bit && (sticky_bit || subnormal_main[0]);
            rounded_subnormal = {1'b0, subnormal_main} + round_increment;
            if (rounded_subnormal[23]) begin
                finite_result = {sign, 8'd1, 23'd0};
            end else begin
                finite_result = {sign, 8'd0, rounded_subnormal[22:0]};
            end
        end

        result_comb = finite_result;
        invalid_comb = invalid_i;
        unique case (special_i)
            fp8_pkg::FP8_REDUCE_NAN: begin
                result_comb = FP32_QNAN;
                invalid_comb = invalid_i;
            end
            fp8_pkg::FP8_REDUCE_POS_INF: result_comb = FP32_POS_INF;
            fp8_pkg::FP8_REDUCE_NEG_INF: result_comb = FP32_NEG_INF;
            default: begin
                if (!nonzero) begin
                    unique case (zero_sign_i)
                        fp8_pkg::FP8_ZERO_SIGN_NEGATIVE:
                            result_comb = 32'h80000000;
                        fp8_pkg::FP8_ZERO_SIGN_POSITIVE:
                            result_comb = 32'h00000000;
                        default: result_comb = 32'h00000000;
                    endcase
                end
            end
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_q <= 1'b0;
            valid_o <= 1'b0;
            result_o <= 32'd0;
            invalid_o <= 1'b0;
        end else begin
            valid_q <= valid_i;
            result_q <= result_comb;
            invalid_q <= invalid_comb;
            valid_o <= valid_q;
            result_o <= result_q;
            invalid_o <= valid_q && invalid_q;
        end
    end

`ifndef YOSYS
    initial begin
        assert ((EXACT_WIDTH >= 24) && (EXACT_WIDTH <= 127))
            else $error("mxfp_block_sum_to_fp32 EXACT_WIDTH out of range");
    end
`endif

endmodule

`default_nettype wire
