`timescale 1ns/1ps
`default_nettype none

module npu_dma_hbm_rank_count16 (
    input  logic [15:0] bits_i,
    output logic [4:0] count_o
);
    logic [8*2-1:0] pair_count;
    logic [4*3-1:0] quad_count;
    logic [2*4-1:0] oct_count;

    generate
        for (genvar pair_index = 0; pair_index < 8;
             pair_index = pair_index + 1) begin : g_pair
            assign pair_count[pair_index*2 +: 2] =
                {1'b0, bits_i[pair_index*2]} +
                {1'b0, bits_i[pair_index*2+1]};
        end
        for (genvar quad_index = 0; quad_index < 4;
             quad_index = quad_index + 1) begin : g_quad
            assign quad_count[quad_index*3 +: 3] =
                {1'b0, pair_count[quad_index*4 +: 2]} +
                {1'b0, pair_count[quad_index*4+2 +: 2]};
        end
        for (genvar oct_index = 0; oct_index < 2;
             oct_index = oct_index + 1) begin : g_oct
            assign oct_count[oct_index*4 +: 4] =
                {1'b0, quad_count[oct_index*6 +: 3]} +
                {1'b0, quad_count[oct_index*6+3 +: 3]};
        end
    endgenerate

    assign count_o = {1'b0, oct_count[0 +: 4]} +
                     {1'b0, oct_count[4 +: 4]};
endmodule

`default_nettype wire
