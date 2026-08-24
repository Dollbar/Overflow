`timescale 1ns/1ps
`default_nettype none

module fp32_compare (
    input  logic [31:0] a_i,
    input  logic [31:0] b_i,
    output logic        equal_o,
    output logic        less_o,
    output logic        less_equal_o,
    output logic        greater_o,
    output logic        greater_equal_o,
    output logic        unordered_o,
    output logic [31:0] minimum_o,
    output logic [31:0] maximum_o
);

    localparam logic [31:0] FP32_CANONICAL_NAN = 32'h7fc00000;
    logic a_nan_comb;
    logic b_nan_comb;
    logic a_zero_comb;
    logic b_zero_comb;
    logic ordered_equal_comb;
    logic ordered_less_comb;

    always_comb begin
        a_nan_comb = (a_i[30:23] == 8'hff) && (a_i[22:0] != 23'd0);
        b_nan_comb = (b_i[30:23] == 8'hff) && (b_i[22:0] != 23'd0);
        a_zero_comb = (a_i[30:0] == 31'd0);
        b_zero_comb = (b_i[30:0] == 31'd0);
        unordered_o = a_nan_comb || b_nan_comb;

        ordered_equal_comb = (a_i == b_i) || (a_zero_comb && b_zero_comb);
        ordered_less_comb = 1'b0;
        if (!ordered_equal_comb) begin
            if (a_i[31] != b_i[31]) begin
                ordered_less_comb = a_i[31];
            end else if (!a_i[31]) begin
                ordered_less_comb = a_i[30:0] < b_i[30:0];
            end else begin
                ordered_less_comb = a_i[30:0] > b_i[30:0];
            end
        end

        equal_o = !unordered_o && ordered_equal_comb;
        less_o = !unordered_o && ordered_less_comb;
        less_equal_o = equal_o || less_o;
        greater_o = !unordered_o && !ordered_equal_comb && !ordered_less_comb;
        greater_equal_o = equal_o || greater_o;

        if (a_nan_comb && b_nan_comb) begin
            minimum_o = FP32_CANONICAL_NAN;
            maximum_o = FP32_CANONICAL_NAN;
        end else if (a_nan_comb) begin
            minimum_o = b_i;
            maximum_o = b_i;
        end else if (b_nan_comb) begin
            minimum_o = a_i;
            maximum_o = a_i;
        end else if (a_zero_comb && b_zero_comb) begin
            minimum_o = {a_i[31] | b_i[31], 31'd0};
            maximum_o = {a_i[31] & b_i[31], 31'd0};
        end else if (ordered_less_comb) begin
            minimum_o = a_i;
            maximum_o = b_i;
        end else begin
            minimum_o = b_i;
            maximum_o = a_i;
        end
    end

endmodule

`default_nettype wire
