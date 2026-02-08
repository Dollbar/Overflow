`timescale 1ns/1ps
`default_nettype none

module mxfp_unpack #(
    parameter bit DAZ = 1'b0
) (
    input  logic [7:0]                 data_i,
    input  mxfp_pkg::mxfp_format_e    format_i,
    input  mxfp_pkg::mxfp_scale_t     scale_i,
    output mxfp_pkg::mxfp_decoded_t   decoded_o
);

    logic [4:0] exponent_field;
    logic [2:0] fraction_aligned;
    logic signed [7:0] bias_value;
    logic exponent_is_zero;
    logic fraction_is_zero;
    logic element_is_inf;
    logic element_is_nan;
    logic element_is_zero;
    logic element_is_subnormal;
    logic element_is_normal;
    logic [1:0] leading_zero_count;
    logic [3:0] subnormal_source;
    logic [3:0] subnormal_normalized;
    logic scale_is_nan;
    logic signed [8:0] scale_exponent;

    always_comb begin
        exponent_field = 5'd0;
        fraction_aligned = 3'd0;
        bias_value = 8'sd0;
        exponent_is_zero = 1'b1;
        fraction_is_zero = 1'b1;
        element_is_inf = 1'b0;
        element_is_nan = 1'b0;

        unique case (format_i)
            mxfp_pkg::MXFP4_E2M1: begin
                exponent_field = {3'd0, data_i[2:1]};
                fraction_aligned = {data_i[0], 2'b00};
                bias_value = 8'sd1;
                exponent_is_zero = ~|data_i[2:1];
                fraction_is_zero = ~data_i[0];
            end
            mxfp_pkg::MXFP8_E4M3: begin
                exponent_field = {1'b0, data_i[6:3]};
                fraction_aligned = data_i[2:0];
                bias_value = 8'sd7;
                exponent_is_zero = ~|data_i[6:3];
                fraction_is_zero = ~|data_i[2:0];
                element_is_nan = &data_i[6:0];
            end
            default: begin
                element_is_nan = 1'b1;
            end
        endcase

        scale_is_nan = scale_i == mxfp_pkg::MX_E8M0_NAN;
        scale_exponent = $signed({1'b0, scale_i}) -
                         mxfp_pkg::MX_E8M0_BIAS;
        element_is_zero = exponent_is_zero &&
                          (fraction_is_zero || DAZ);
        element_is_subnormal = exponent_is_zero && !fraction_is_zero &&
                               !DAZ;
        element_is_normal = !exponent_is_zero && !element_is_inf &&
                            !element_is_nan;
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
        subnormal_source = {1'b0, fraction_aligned};
        subnormal_normalized =
            subnormal_source << (leading_zero_count + 2'd1);
    end

    always_comb begin
        decoded_o = '0;
        decoded_o.sign = (format_i == mxfp_pkg::MXFP4_E2M1) ?
                         data_i[3] : data_i[7];
        decoded_o.scale_exponent = scale_exponent;
        decoded_o.is_zero = element_is_zero && !scale_is_nan;
        decoded_o.is_subnormal = element_is_subnormal && !scale_is_nan;
        decoded_o.is_normal = element_is_normal && !scale_is_nan;
        decoded_o.is_inf = element_is_inf && !scale_is_nan;
        decoded_o.is_nan = element_is_nan || scale_is_nan;
        if (element_is_subnormal && !scale_is_nan) begin
            decoded_o.element_exponent = 8'sd0 - bias_value -
                $signed({6'b000000, leading_zero_count});
            decoded_o.significand = subnormal_normalized;
        end else if (element_is_normal && !scale_is_nan) begin
            decoded_o.element_exponent =
                $signed({3'b000, exponent_field}) - bias_value;
            decoded_o.significand = {1'b1, fraction_aligned};
        end
    end

endmodule

`default_nettype wire
