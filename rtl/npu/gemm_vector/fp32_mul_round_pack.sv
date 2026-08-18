`timescale 1ns/1ps
`default_nettype none

module fp32_mul_round_pack #(
    parameter bit FTZ = 1'b0
) (
    input  logic               sign_i,
    input  logic signed [10:0] exponent_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic        [24:0] normal_rounded_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic signed [11:0] normal_exponent_i,
    input  logic        [23:0] subnormal_rounded_i,
    input  logic               overflow_to_inf_i,
    input  logic               special_valid_i,
    input  logic        [31:0] special_result_i,
    output logic        [31:0] result_o
);

    logic [31:0] finite_result_comb;
    logic [31:0] ftz_result_comb;

    always_comb begin
        finite_result_comb = {sign_i, 8'd0, subnormal_rounded_i[22:0]};
        if (exponent_i >= -11'sd126) begin
            if (normal_exponent_i > 12'sd127) begin
                finite_result_comb = overflow_to_inf_i ?
                    {sign_i, 8'hff, 23'd0} : {sign_i, 8'hfe, 23'h7fffff};
            end else if (normal_rounded_i[24]) begin
                finite_result_comb = {sign_i,
                    8'($unsigned(normal_exponent_i + 12'sd127)), 23'd0};
            end else begin
                finite_result_comb = {sign_i,
                    8'($unsigned(normal_exponent_i + 12'sd127)), normal_rounded_i[22:0]};
            end
        end else if (subnormal_rounded_i[23]) begin
            finite_result_comb = {sign_i, 8'h01, 23'd0};
        end

        ftz_result_comb = finite_result_comb;
        if (FTZ && (finite_result_comb[30:23] == 8'h00) &&
            (finite_result_comb[22:0] != 23'd0)) begin
            ftz_result_comb = {sign_i, 31'd0};
        end
        result_o = special_valid_i ? special_result_i : ftz_result_comb;
    end

endmodule

`default_nettype wire
