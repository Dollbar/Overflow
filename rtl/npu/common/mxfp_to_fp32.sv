`timescale 1ns/1ps
`default_nettype none

module mxfp_to_fp32 #(
    parameter bit DAZ = 1'b0
) (
    input  logic [7:0]               data_i,
    input  mxfp_pkg::mxfp_format_e  format_i,
    input  mxfp_pkg::mxfp_scale_t   scale_i,
    output logic [31:0]              data_o,
    output logic                     invalid_o
);

    /* verilator lint_off UNUSEDSIGNAL */
    mxfp_pkg::mxfp_decoded_t decoded;
    /* verilator lint_on UNUSEDSIGNAL */
    logic signed [10:0] combined_exponent;
    logic [7:0] biased_exponent;
    logic [23:0] exact_significand;
    logic [7:0] exponent_field;
    logic [22:0] fraction_field;
    logic [7:0] subnormal_shift;

    mxfp_unpack #(.DAZ(DAZ)) u_unpack (
        .data_i    (data_i),
        .format_i  (format_i),
        .scale_i   (scale_i),
        .decoded_o (decoded)
    );

    always_comb begin
        combined_exponent =
            $signed({{3{decoded.element_exponent[7]}},
                     decoded.element_exponent}) +
            $signed({{2{decoded.scale_exponent[8]}},
                     decoded.scale_exponent});
        biased_exponent = 8'(combined_exponent + 11'sd127);
        exact_significand = {decoded.significand, 20'd0};
        exponent_field = 8'd0;
        fraction_field = 23'd0;
        subnormal_shift = 8'd0;
        invalid_o = decoded.is_nan;

        if (decoded.is_nan) begin
            data_o = 32'h7fc00000;
        end else if (decoded.is_inf || (combined_exponent > 11'sd127)) begin
            data_o = {decoded.sign, 8'hff, 23'd0};
        end else if (decoded.is_zero ||
                     (combined_exponent < -11'sd149)) begin
            data_o = {decoded.sign, 31'd0};
        end else if (combined_exponent >= -11'sd126) begin
            exponent_field = biased_exponent;
            fraction_field = exact_significand[22:0];
            data_o = {decoded.sign, exponent_field, fraction_field};
        end else begin
            subnormal_shift = 8'(-11'sd126 - combined_exponent);
            fraction_field = 23'(exact_significand >> subnormal_shift);
            data_o = {decoded.sign, 8'd0, fraction_field};
        end
    end

endmodule

`default_nettype wire
