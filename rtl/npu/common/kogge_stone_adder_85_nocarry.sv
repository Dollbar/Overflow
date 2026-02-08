`timescale 1ns/1ps
`default_nettype none

// Constant-carry-zero prefix adder used only to collapse carry-save state.
module kogge_stone_adder_85_nocarry (
    input  logic [84:0] a_i,
    input  logic [84:0] b_i,
    output logic [84:0] sum_o
);

    logic [84:0] propagate_l0;
    logic [83:0] generate_l0;
    logic [83:2] propagate_l1;
    logic [83:0] generate_l1;
    logic [83:4] propagate_l2;
    logic [83:0] generate_l2;
    logic [83:8] propagate_l3;
    logic [83:0] generate_l3;
    logic [83:16] propagate_l4;
    logic [83:0] generate_l4;
    logic [83:32] propagate_l5;
    logic [83:0] generate_l5;
    logic [83:64] propagate_l6;
    logic [83:0] generate_l6;
    logic [83:0] generate_l7;
    logic [84:0] carry;

    assign propagate_l0 = a_i ^ b_i;
    assign generate_l0 = a_i[83:0] & b_i[83:0];

    assign generate_l1[0] = generate_l0[0];
    assign propagate_l1[83:2] = propagate_l0[83:2] & propagate_l0[82:1];
    assign generate_l1[83:1] = generate_l0[83:1] |
                                (propagate_l0[83:1] & generate_l0[82:0]);

    assign generate_l2[1:0] = generate_l1[1:0];
    assign propagate_l2[83:4] = propagate_l1[83:4] & propagate_l1[81:2];
    assign generate_l2[83:2] = generate_l1[83:2] |
                                (propagate_l1[83:2] & generate_l1[81:0]);

    assign generate_l3[3:0] = generate_l2[3:0];
    assign propagate_l3[83:8] = propagate_l2[83:8] & propagate_l2[79:4];
    assign generate_l3[83:4] = generate_l2[83:4] |
                                (propagate_l2[83:4] & generate_l2[79:0]);

    assign generate_l4[7:0] = generate_l3[7:0];
    assign propagate_l4[83:16] = propagate_l3[83:16] & propagate_l3[75:8];
    assign generate_l4[83:8] = generate_l3[83:8] |
                                (propagate_l3[83:8] & generate_l3[75:0]);

    assign generate_l5[15:0] = generate_l4[15:0];
    assign propagate_l5[83:32] = propagate_l4[83:32] & propagate_l4[67:16];
    assign generate_l5[83:16] = generate_l4[83:16] |
                                 (propagate_l4[83:16] & generate_l4[67:0]);

    assign generate_l6[31:0] = generate_l5[31:0];
    assign propagate_l6[83:64] = propagate_l5[83:64] & propagate_l5[51:32];
    assign generate_l6[83:32] = generate_l5[83:32] |
                                 (propagate_l5[83:32] & generate_l5[51:0]);

    assign generate_l7[63:0] = generate_l6[63:0];
    assign generate_l7[83:64] = generate_l6[83:64] |
                                 (propagate_l6[83:64] & generate_l6[19:0]);

    assign carry[0] = 1'b0;
    assign carry[84:1] = generate_l7;
    assign sum_o = propagate_l0 ^ carry;

endmodule

`default_nettype wire
