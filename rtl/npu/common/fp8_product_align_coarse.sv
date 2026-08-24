`timescale 1ns/1ps

module fp8_product_align_coarse (
    input  logic [14:0] fine_aligned_i,
    input  logic  [2:0] coarse_shift_i,
    output logic [66:0] magnitude_o
);

    always_comb begin
        magnitude_o = 67'd0;
        case (coarse_shift_i)
            3'd0: magnitude_o = {52'd0, fine_aligned_i};
            3'd1: magnitude_o = {44'd0, fine_aligned_i, 8'd0};
            3'd2: magnitude_o = {36'd0, fine_aligned_i, 16'd0};
            3'd3: magnitude_o = {28'd0, fine_aligned_i, 24'd0};
            3'd4: magnitude_o = {20'd0, fine_aligned_i, 32'd0};
            3'd5: magnitude_o = {12'd0, fine_aligned_i, 40'd0};
            3'd6: magnitude_o = {4'd0, fine_aligned_i, 48'd0};
            3'd7: magnitude_o = {fine_aligned_i[10:0], 56'd0};
            default: magnitude_o = 67'd0;
        endcase
    end

endmodule
