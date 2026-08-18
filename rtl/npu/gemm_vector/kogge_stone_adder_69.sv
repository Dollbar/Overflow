`timescale 1ns/1ps

module kogge_stone_adder_69 (
    input  logic [68:0] a_i,
    input  logic [68:0] b_i,
    input  logic        cin_i,
    output logic [68:0] sum_o
);

    (* keep = "true" *) logic [68:0] propagate_l0;
    (* keep = "true" *) logic [67:0] generate_l0;
    (* keep = "true" *) logic [67:0] propagate_l1;
    (* keep = "true" *) logic [67:0] generate_l1;
    (* keep = "true" *) logic [67:0] propagate_l2;
    (* keep = "true" *) logic [67:0] generate_l2;
    (* keep = "true" *) logic [67:0] propagate_l3;
    (* keep = "true" *) logic [67:0] generate_l3;
    (* keep = "true" *) logic [67:0] propagate_l4;
    (* keep = "true" *) logic [67:0] generate_l4;
    (* keep = "true" *) logic [67:0] propagate_l5;
    (* keep = "true" *) logic [67:0] generate_l5;
    (* keep = "true" *) logic [67:0] propagate_l6;
    (* keep = "true" *) logic [67:0] generate_l6;
    (* keep = "true" *) logic [67:0] propagate_l7;
    (* keep = "true" *) logic [67:0] generate_l7;
    (* keep = "true" *) logic [68:0] carry;

    assign propagate_l0 = a_i ^ b_i;
    assign generate_l0 = a_i[67:0] & b_i[67:0];

    assign propagate_l1[0] = propagate_l0[0];
    assign generate_l1[0] = generate_l0[0];
    assign propagate_l1[67:1] = propagate_l0[67:1] & propagate_l0[66:0];
    assign generate_l1[67:1] = generate_l0[67:1] |
                                (propagate_l0[67:1] & generate_l0[66:0]);

    assign propagate_l2[1:0] = propagate_l1[1:0];
    assign generate_l2[1:0] = generate_l1[1:0];
    assign propagate_l2[67:2] = propagate_l1[67:2] & propagate_l1[65:0];
    assign generate_l2[67:2] = generate_l1[67:2] |
                                (propagate_l1[67:2] & generate_l1[65:0]);

    assign propagate_l3[3:0] = propagate_l2[3:0];
    assign generate_l3[3:0] = generate_l2[3:0];
    assign propagate_l3[67:4] = propagate_l2[67:4] & propagate_l2[63:0];
    assign generate_l3[67:4] = generate_l2[67:4] |
                                (propagate_l2[67:4] & generate_l2[63:0]);

    assign propagate_l4[7:0] = propagate_l3[7:0];
    assign generate_l4[7:0] = generate_l3[7:0];
    assign propagate_l4[67:8] = propagate_l3[67:8] & propagate_l3[59:0];
    assign generate_l4[67:8] = generate_l3[67:8] |
                                (propagate_l3[67:8] & generate_l3[59:0]);

    assign propagate_l5[15:0] = propagate_l4[15:0];
    assign generate_l5[15:0] = generate_l4[15:0];
    assign propagate_l5[67:16] = propagate_l4[67:16] & propagate_l4[51:0];
    assign generate_l5[67:16] = generate_l4[67:16] |
                                 (propagate_l4[67:16] & generate_l4[51:0]);

    assign propagate_l6[31:0] = propagate_l5[31:0];
    assign generate_l6[31:0] = generate_l5[31:0];
    assign propagate_l6[67:32] = propagate_l5[67:32] & propagate_l5[35:0];
    assign generate_l6[67:32] = generate_l5[67:32] |
                                 (propagate_l5[67:32] & generate_l5[35:0]);

    assign propagate_l7[63:0] = propagate_l6[63:0];
    assign generate_l7[63:0] = generate_l6[63:0];
    assign propagate_l7[67:64] = propagate_l6[67:64] & propagate_l6[3:0];
    assign generate_l7[67:64] = generate_l6[67:64] |
                                 (propagate_l6[67:64] & generate_l6[3:0]);

    assign carry[0] = cin_i;
    assign carry[68:1] = generate_l7 | (propagate_l7 & {68{cin_i}});
    assign sum_o = propagate_l0 ^ carry;

endmodule
