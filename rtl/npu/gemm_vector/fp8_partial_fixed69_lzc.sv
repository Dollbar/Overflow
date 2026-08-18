`timescale 1ns/1ps

module fp8_partial_fixed69_lzc (
    input  logic [68:0] magnitude_i,
    output logic        nonzero_o,
    output logic [6:0]  msb_index_o
);

    logic [17:0] group_valid;
    logic  [6:0] group_index [0:17];
    logic  [8:0] select_valid_l1;
    logic  [6:0] select_index_l1 [0:8];
    logic  [4:0] select_valid_l2;
    logic  [6:0] select_index_l2 [0:4];
    logic  [2:0] select_valid_l3;
    logic  [6:0] select_index_l3 [0:2];
    logic  [1:0] select_valid_l4;
    logic  [6:0] select_index_l4 [0:1];

    generate
        for (genvar group = 0; group < 17; group = group + 1) begin : gen_group_decode
            localparam integer BASE = group * 4;
            localparam logic [6:0] BASE_INDEX = 7'(BASE);
            assign group_valid[group] = |magnitude_i[BASE +: 4];
            assign group_index[group] = magnitude_i[BASE + 3] ? (BASE_INDEX + 7'd3) :
                                        magnitude_i[BASE + 2] ? (BASE_INDEX + 7'd2) :
                                        magnitude_i[BASE + 1] ? (BASE_INDEX + 7'd1) : BASE_INDEX;
        end

        for (genvar pair_l1 = 0; pair_l1 < 9; pair_l1 = pair_l1 + 1) begin : gen_select_l1
            assign select_valid_l1[pair_l1] = group_valid[(2 * pair_l1) + 1] |
                                               group_valid[2 * pair_l1];
            assign select_index_l1[pair_l1] = group_valid[(2 * pair_l1) + 1] ?
                                               group_index[(2 * pair_l1) + 1] :
                                               group_index[2 * pair_l1];
        end

        for (genvar pair_l2 = 0; pair_l2 < 4; pair_l2 = pair_l2 + 1) begin : gen_select_l2
            assign select_valid_l2[pair_l2] = select_valid_l1[(2 * pair_l2) + 1] |
                                               select_valid_l1[2 * pair_l2];
            assign select_index_l2[pair_l2] = select_valid_l1[(2 * pair_l2) + 1] ?
                                               select_index_l1[(2 * pair_l2) + 1] :
                                               select_index_l1[2 * pair_l2];
        end

        for (genvar pair_l3 = 0; pair_l3 < 2; pair_l3 = pair_l3 + 1) begin : gen_select_l3
            assign select_valid_l3[pair_l3] = select_valid_l2[(2 * pair_l3) + 1] |
                                               select_valid_l2[2 * pair_l3];
            assign select_index_l3[pair_l3] = select_valid_l2[(2 * pair_l3) + 1] ?
                                               select_index_l2[(2 * pair_l3) + 1] :
                                               select_index_l2[2 * pair_l3];
        end
    endgenerate

    assign group_valid[17] = magnitude_i[68];
    assign group_index[17] = 7'd68;

    assign select_valid_l2[4] = select_valid_l1[8];
    assign select_index_l2[4] = select_index_l1[8];
    assign select_valid_l3[2] = select_valid_l2[4];
    assign select_index_l3[2] = select_index_l2[4];

    assign select_valid_l4[0] = select_valid_l3[1] | select_valid_l3[0];
    assign select_index_l4[0] = select_valid_l3[1] ? select_index_l3[1] :
                                                        select_index_l3[0];
    assign select_valid_l4[1] = select_valid_l3[2];
    assign select_index_l4[1] = select_index_l3[2];

    assign nonzero_o = select_valid_l4[1] | select_valid_l4[0];
    assign msb_index_o = select_valid_l4[1] ? select_index_l4[1] :
                                                   select_index_l4[0];

endmodule
