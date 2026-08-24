`timescale 1ns/1ps

module fp8_product_prepare (
    input  fp8_pkg::fp8_product_t product_i,
    output logic                  sign_o,
    output logic            [7:0] significand_o,
    output logic            [5:0] left_shift_o,
    output logic                  is_nan_o,
    output logic                  is_pos_inf_o,
    output logic                  is_neg_inf_o,
    output logic                  is_zero_o,
    output logic                  zero_sign_o
);

    localparam logic signed [9:0] PRODUCT_BINARY_POINT_OFFSET = 10'sd26;

    logic signed [9:0] binary_shift;
    logic         [9:0] right_shift;

    always_comb begin
        sign_o = product_i.sign;
        significand_o = 8'd0;
        left_shift_o = 6'd0;
        is_nan_o = product_i.is_nan;
        is_pos_inf_o = product_i.is_inf && !product_i.sign;
        is_neg_inf_o = product_i.is_inf && product_i.sign;
        is_zero_o = product_i.is_zero;
        zero_sign_o = product_i.sign;
        binary_shift = $signed(product_i.exponent) + PRODUCT_BINARY_POINT_OFFSET;
        right_shift = 10'd0;

        if (!(product_i.is_zero || product_i.is_inf || product_i.is_nan)) begin
            if (binary_shift < 10'sd0) begin
                right_shift = $unsigned(-binary_shift);
                if (right_shift <= 10'd7) begin
                    significand_o = product_i.significand >> right_shift[2:0];
                end
            end else if (binary_shift <= 10'sd56) begin
                significand_o = product_i.significand;
                left_shift_o = binary_shift[5:0];
            end
        end
    end

endmodule
