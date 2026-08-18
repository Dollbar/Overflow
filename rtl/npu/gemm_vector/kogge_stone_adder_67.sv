`timescale 1ns/1ps

module kogge_stone_adder_67 (
    input  logic [66:0] a_i,
    input  logic [66:0] b_i,
    input  logic        cin_i,
    output logic [66:0] sum_o
);

    (* keep = "true" *) logic [66:0] propagate_l0;
    (* keep = "true" *) logic [65:0] generate_l0;
    (* keep = "true" *) logic [65:0] propagate_l1;
    (* keep = "true" *) logic [65:0] generate_l1;
    (* keep = "true" *) logic [65:0] propagate_l2;
    (* keep = "true" *) logic [65:0] generate_l2;
    (* keep = "true" *) logic [65:0] propagate_l3;
    (* keep = "true" *) logic [65:0] generate_l3;
    (* keep = "true" *) logic [65:0] propagate_l4;
    (* keep = "true" *) logic [65:0] generate_l4;
    (* keep = "true" *) logic [65:0] propagate_l5;
    (* keep = "true" *) logic [65:0] generate_l5;
    (* keep = "true" *) logic [65:0] propagate_l6;
    (* keep = "true" *) logic [65:0] generate_l6;
    (* keep = "true" *) logic [65:0] propagate_l7;
    (* keep = "true" *) logic [65:0] generate_l7;
    (* keep = "true" *) logic [66:0] carry;

    assign propagate_l0 = a_i ^ b_i;
    assign generate_l0 = a_i[65:0] & b_i[65:0];

    assign propagate_l1[0] = propagate_l0[0];
    assign generate_l1[0] = generate_l0[0];
    assign propagate_l1[65:1] = propagate_l0[65:1] & propagate_l0[64:0];
    assign generate_l1[65:1] = generate_l0[65:1] | (propagate_l0[65:1] & generate_l0[64:0]);

    assign propagate_l2[1:0] = propagate_l1[1:0];
    assign generate_l2[1:0] = generate_l1[1:0];
    assign propagate_l2[65:2] = propagate_l1[65:2] & propagate_l1[63:0];
    assign generate_l2[65:2] = generate_l1[65:2] | (propagate_l1[65:2] & generate_l1[63:0]);

    assign propagate_l3[3:0] = propagate_l2[3:0];
    assign generate_l3[3:0] = generate_l2[3:0];
    assign propagate_l3[65:4] = propagate_l2[65:4] & propagate_l2[61:0];
    assign generate_l3[65:4] = generate_l2[65:4] | (propagate_l2[65:4] & generate_l2[61:0]);

    assign propagate_l4[7:0] = propagate_l3[7:0];
    assign generate_l4[7:0] = generate_l3[7:0];
    assign propagate_l4[65:8] = propagate_l3[65:8] & propagate_l3[57:0];
    assign generate_l4[65:8] = generate_l3[65:8] | (propagate_l3[65:8] & generate_l3[57:0]);

    assign propagate_l5[15:0] = propagate_l4[15:0];
    assign generate_l5[15:0] = generate_l4[15:0];
    assign propagate_l5[65:16] = propagate_l4[65:16] & propagate_l4[49:0];
    assign generate_l5[65:16] = generate_l4[65:16] | (propagate_l4[65:16] & generate_l4[49:0]);

    assign propagate_l6[31:0] = propagate_l5[31:0];
    assign generate_l6[31:0] = generate_l5[31:0];
    assign propagate_l6[65:32] = propagate_l5[65:32] & propagate_l5[33:0];
    assign generate_l6[65:32] = generate_l5[65:32] | (propagate_l5[65:32] & generate_l5[33:0]);

    assign propagate_l7[63:0] = propagate_l6[63:0];
    assign generate_l7[63:0] = generate_l6[63:0];
    assign propagate_l7[65:64] = propagate_l6[65:64] & propagate_l6[1:0];
    assign generate_l7[65:64] = generate_l6[65:64] | (propagate_l6[65:64] & generate_l6[1:0]);

    assign carry[0] = cin_i;
    assign carry[66:1] = generate_l7[65:0] | (propagate_l7[65:0] & {66{cin_i}});
    assign sum_o = propagate_l0 ^ carry;

endmodule
