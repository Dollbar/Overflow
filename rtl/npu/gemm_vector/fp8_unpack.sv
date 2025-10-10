`timescale 1ns/1ps

module fp8_unpack #(
    parameter bit DAZ = 1'b0,
    parameter bit STATIC_FORMAT = 1'b0,
    parameter bit STATIC_FORMAT_E5M2 = 1'b0
) (
    input  logic [7:0]              data_i,
    input  fp8_pkg::fp8_format_e    format_i,
    output fp8_pkg::fp8_decoded_t   decoded_o
);

    logic sign_raw;
    logic [fp8_pkg::E5M2_EXP_WIDTH-1:0] exponent_field;
    logic [fp8_pkg::E4M3_FRAC_WIDTH-1:0] fraction_aligned;
    logic signed [7:0] bias_value;
    logic exponent_is_zero;
    logic fraction_is_zero;
    logic use_e5m2;
    logic e4m3_exponent_is_zero;
    logic e5m2_exponent_is_zero;
    logic e4m3_fraction_is_zero;
    logic e5m2_fraction_is_zero;
    logic e4m3_is_nan;
    logic e5m2_is_inf;
    logic e5m2_is_nan;
    logic input_is_zero;
    logic input_is_subnormal;
    logic input_is_normal;
    logic input_is_inf;
    logic input_is_nan;
    logic [1:0] leading_zero_count;
    logic [3:0] subnormal_source;
    logic [3:0] subnormal_normalized;

    // Build the two format classifiers directly from the raw encoding.  This
    // keeps the dynamic format select out of the exponent/fraction reduction
    // trees and leaves only a shallow final selection between format results.
    always_comb begin
        sign_raw = data_i[7];
        use_e5m2 = STATIC_FORMAT ? STATIC_FORMAT_E5M2
                                  : (format_i == fp8_pkg::FP8_E5M2);

        e4m3_exponent_is_zero = ~|data_i[6:3];
        e5m2_exponent_is_zero = ~|data_i[6:2];
        e4m3_fraction_is_zero = ~|data_i[2:0];
        e5m2_fraction_is_zero = ~|data_i[1:0];
        e4m3_is_nan = &data_i[6:0];
        e5m2_is_inf = (&data_i[6:2]) && e5m2_fraction_is_zero;
        e5m2_is_nan = (&data_i[6:2]) && !e5m2_fraction_is_zero;

        if (use_e5m2) begin
            exponent_field = data_i[6:2];
            fraction_aligned = {data_i[1:0], 1'b0};
            bias_value = fp8_pkg::E5M2_BIAS;
            exponent_is_zero = e5m2_exponent_is_zero;
            fraction_is_zero = e5m2_fraction_is_zero;
            input_is_inf = e5m2_is_inf;
            input_is_nan = e5m2_is_nan;
        end else begin
            exponent_field = {1'b0, data_i[6:3]};
            fraction_aligned = data_i[2:0];
            bias_value = fp8_pkg::E4M3_BIAS;
            exponent_is_zero = e4m3_exponent_is_zero;
            fraction_is_zero = e4m3_fraction_is_zero;
            input_is_inf = 1'b0;
            input_is_nan = e4m3_is_nan;
        end

        input_is_zero = exponent_is_zero && (fraction_is_zero || DAZ);
        input_is_subnormal = exponent_is_zero && !fraction_is_zero && !DAZ;
        input_is_normal = !exponent_is_zero && !input_is_inf && !input_is_nan;
    end

    always_comb begin
        subnormal_source = {1'b0, fraction_aligned};
        subnormal_normalized = subnormal_source << (leading_zero_count + 2'd1);
    end

    always_comb begin
        leading_zero_count = 2'd0;
        if (fraction_aligned[2]) begin
            leading_zero_count = 2'd0;
        end else if (fraction_aligned[1]) begin
            leading_zero_count = 2'd1;
        end else if (fraction_aligned[0]) begin
            leading_zero_count = 2'd2;
        end
    end

    always_comb begin
        decoded_o = '0;
        decoded_o.sign = sign_raw;
        decoded_o.is_zero = input_is_zero;
        decoded_o.is_subnormal = input_is_subnormal;
        decoded_o.is_normal = input_is_normal;
        decoded_o.is_inf = input_is_inf;
        decoded_o.is_nan = input_is_nan;
        if (input_is_subnormal) begin
            decoded_o.exponent = 8'sd0 - bias_value
                               - $signed({6'b000000, leading_zero_count});
            decoded_o.significand = subnormal_normalized;
        end else if (input_is_normal) begin
            decoded_o.exponent = $signed({3'b000, exponent_field}) - bias_value;
            decoded_o.significand = {1'b1, fraction_aligned};
        end
    end

endmodule
