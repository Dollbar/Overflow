`timescale 1ns/1ps
`default_nettype none

module mxfp_mul_exact (
    input  logic                       clk_i,
    input  logic                       rst_i,
    input  logic                       clear_i,
    input  logic                       valid_i,
    input  mxfp_pkg::mxfp_decoded_t    a_i,
    input  mxfp_pkg::mxfp_decoded_t    b_i,
    output logic                       valid_o,
    output mxfp_pkg::mxfp_product_t    product_o,
    output logic                       invalid_o
);

    logic [7:0] significand_product;
    logic finite_a;
    logic finite_b;
    logic multiply_invalid;
    mxfp_pkg::mxfp_product_t product_comb;
    logic invalid_comb;

    booth_radix4_u4 u_significand_multiplier (
        .a_i       (a_i.significand),
        .b_i       (b_i.significand),
        .product_o (significand_product)
    );

    always_comb begin
        finite_a = a_i.is_normal || a_i.is_subnormal;
        finite_b = b_i.is_normal || b_i.is_subnormal;
        multiply_invalid = (a_i.is_inf && b_i.is_zero) ||
                           (a_i.is_zero && b_i.is_inf);
        invalid_comb = multiply_invalid;
        product_comb = '0;
        product_comb.sign = a_i.sign ^ b_i.sign;
        product_comb.scale_exponent =
            $signed({a_i.scale_exponent[8], a_i.scale_exponent}) +
            $signed({b_i.scale_exponent[8], b_i.scale_exponent});
        if (a_i.is_nan || b_i.is_nan || multiply_invalid) begin
            product_comb.is_nan = 1'b1;
        end else if (a_i.is_inf || b_i.is_inf) begin
            product_comb.is_inf = 1'b1;
        end else if (a_i.is_zero || b_i.is_zero) begin
            product_comb.is_zero = 1'b1;
        end else if (finite_a && finite_b) begin
            product_comb.element_exponent =
                $signed({a_i.element_exponent[7], a_i.element_exponent}) +
                $signed({b_i.element_exponent[7], b_i.element_exponent});
            product_comb.significand = significand_product;
        end else begin
            product_comb.is_nan = 1'b1;
            invalid_comb = 1'b1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            valid_o <= 1'b0;
            product_o <= '0;
            invalid_o <= 1'b0;
        end else if (clear_i) begin
            valid_o <= 1'b0;
            invalid_o <= 1'b0;
        end else begin
            valid_o <= valid_i;
            product_o <= product_comb;
            invalid_o <= valid_i && invalid_comb;
        end
    end

endmodule

`default_nettype wire
