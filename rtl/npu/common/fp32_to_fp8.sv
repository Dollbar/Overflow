`timescale 1ns/1ps
`default_nettype none

module fp32_to_fp8 (
    input  logic [31:0] data_i,
    output logic [7:0]  data_o,
    output logic        overflow_o,
    output logic        inexact_o
);

    logic        sign_comb;
    logic [7:0]  exponent_field_comb;
    logic [22:0] fraction_field_comb;
    logic        input_zero_comb;
    logic        input_inf_comb;
    logic        input_nan_comb;
    logic [23:0] significand_comb;

    logic [3:0] normal_main_e4_comb;
    logic       normal_guard_e4_comb;
    logic       normal_sticky_e4_comb;
    logic       normal_increment_e4_comb;
    /* The retained hidden bits [3]/[2] are intentionally not encoded. */
    /* verilator lint_off UNUSEDSIGNAL */
    logic [4:0] normal_rounded_e4_comb;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [8:0] target_exponent_e4_comb;

    logic [2:0] subnormal_main_e4_comb;
    logic       subnormal_guard_e4_comb;
    logic       subnormal_sticky_e4_comb;
    logic       subnormal_increment_e4_comb;
    logic [3:0] subnormal_rounded_e4_comb;

    logic [7:0] finite_result_e4_comb;
    logic       finite_overflow_e4_comb;
    logic       finite_inexact_e4_comb;

    always_comb begin
        sign_comb = data_i[31];
        exponent_field_comb = data_i[30:23];
        fraction_field_comb = data_i[22:0];
        input_zero_comb = (exponent_field_comb == 8'h00) &&
                          (fraction_field_comb == 23'd0);
        input_inf_comb = (exponent_field_comb == 8'hff) &&
                         (fraction_field_comb == 23'd0);
        input_nan_comb = (exponent_field_comb == 8'hff) &&
                         (fraction_field_comb != 23'd0);
        significand_comb = {1'b1, fraction_field_comb};
    end

    // MXFP8 v0.2 has one element format and one rounding policy: E4M3FN/RNE.
    always_comb begin
        normal_main_e4_comb = significand_comb[23:20];
        normal_guard_e4_comb = significand_comb[19];
        normal_sticky_e4_comb = |significand_comb[18:0];
        normal_increment_e4_comb = normal_guard_e4_comb &&
            (normal_sticky_e4_comb || normal_main_e4_comb[0]);
        normal_rounded_e4_comb = {1'b0, normal_main_e4_comb} +
                                 normal_increment_e4_comb;
        target_exponent_e4_comb = {1'b0, exponent_field_comb} - 9'd120 +
                                  normal_rounded_e4_comb[4];
    end

    /*
     * Only four FP32 exponent bins can round into an E4M3 subnormal. Explicit
     * bins avoid a variable 24-bit barrel shifter on the conversion path.
     */
    always_comb begin
        subnormal_main_e4_comb = 3'd0;
        subnormal_guard_e4_comb = 1'b0;
        subnormal_sticky_e4_comb = |data_i[30:0];
        case (exponent_field_comb)
            8'd120: begin
                subnormal_main_e4_comb = significand_comb[23:21];
                subnormal_guard_e4_comb = significand_comb[20];
                subnormal_sticky_e4_comb = |significand_comb[19:0];
            end
            8'd119: begin
                subnormal_main_e4_comb = {1'b0, significand_comb[23:22]};
                subnormal_guard_e4_comb = significand_comb[21];
                subnormal_sticky_e4_comb = |significand_comb[20:0];
            end
            8'd118: begin
                subnormal_main_e4_comb = {2'b00, significand_comb[23]};
                subnormal_guard_e4_comb = significand_comb[22];
                subnormal_sticky_e4_comb = |significand_comb[21:0];
            end
            8'd117: begin
                subnormal_main_e4_comb = 3'd0;
                subnormal_guard_e4_comb = significand_comb[23];
                subnormal_sticky_e4_comb = |significand_comb[22:0];
            end
            default: begin
                subnormal_main_e4_comb = 3'd0;
                subnormal_guard_e4_comb = 1'b0;
                subnormal_sticky_e4_comb = |data_i[30:0];
            end
        endcase
        subnormal_increment_e4_comb = subnormal_guard_e4_comb &&
            (subnormal_sticky_e4_comb || subnormal_main_e4_comb[0]);
        subnormal_rounded_e4_comb = {1'b0, subnormal_main_e4_comb} +
                                    subnormal_increment_e4_comb;
    end

    always_comb begin
        finite_result_e4_comb = {sign_comb, 7'd0};
        finite_overflow_e4_comb = 1'b0;
        finite_inexact_e4_comb = 1'b0;
        if (exponent_field_comb >= 8'd121) begin
            finite_inexact_e4_comb = normal_guard_e4_comb |
                                     normal_sticky_e4_comb;
            if ((target_exponent_e4_comb > 9'd15) ||
                ((target_exponent_e4_comb == 9'd15) &&
                 (normal_rounded_e4_comb[2:0] == 3'b111))) begin
                finite_result_e4_comb = {sign_comb, 4'hf, 3'b110};
                finite_overflow_e4_comb = 1'b1;
            end else begin
                finite_result_e4_comb = {
                    sign_comb, target_exponent_e4_comb[3:0],
                    normal_rounded_e4_comb[2:0]
                };
            end
        end else begin
            finite_inexact_e4_comb = subnormal_guard_e4_comb |
                                     subnormal_sticky_e4_comb;
            if (subnormal_rounded_e4_comb[3]) begin
                finite_result_e4_comb = {sign_comb, 4'h1, 3'b000};
            end else begin
                finite_result_e4_comb = {
                    sign_comb, 4'h0, subnormal_rounded_e4_comb[2:0]
                };
            end
        end
    end

    always_comb begin
        data_o = finite_result_e4_comb;
        overflow_o = finite_overflow_e4_comb;
        inexact_o = finite_inexact_e4_comb;

        if (input_zero_comb) begin
            data_o = {sign_comb, 7'd0};
            overflow_o = 1'b0;
            inexact_o = 1'b0;
        end else if (input_nan_comb) begin
            data_o = 8'h7f;
            overflow_o = 1'b0;
            inexact_o = 1'b0;
        end else if (input_inf_comb) begin
            data_o = {sign_comb, 4'hf, 3'b110};
            overflow_o = 1'b1;
            inexact_o = 1'b0;
        end
    end

endmodule

`default_nettype wire
