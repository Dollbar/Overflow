`timescale 1ns/1ps

module fp8_product_align_fine (
    input  logic  [7:0] significand_i,
    input  logic  [5:0] left_shift_i,
    output logic [14:0] fine_aligned_o,
    output logic  [2:0] coarse_shift_o
);

    always_comb begin
        fine_aligned_o = {7'd0, significand_i} << left_shift_i[2:0];
        coarse_shift_o = left_shift_i[5:3];
    end

endmodule
