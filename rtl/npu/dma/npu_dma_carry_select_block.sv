`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "yes" *)
module npu_dma_carry_select_block #(
    parameter int unsigned WIDTH = 5
) (
    input  logic [WIDTH-1:0] a_i,
    input  logic [WIDTH-1:0] b_i,
    output logic [WIDTH-1:0] sum_without_carry_o,
    output logic [WIDTH-1:0] sum_with_carry_o,
    output logic carry_without_carry_o,
    output logic carry_with_carry_o
);

    logic [WIDTH:0] candidate_without_carry;
    logic [WIDTH:0] candidate_with_carry;

    assign candidate_without_carry = {1'b0, a_i} + {1'b0, b_i};
    assign candidate_with_carry = {1'b0, a_i} + {1'b0, b_i} +
                                  (WIDTH + 1)'(1);
    assign {carry_without_carry_o, sum_without_carry_o} =
        candidate_without_carry;
    assign {carry_with_carry_o, sum_with_carry_o} = candidate_with_carry;

endmodule

`default_nettype wire
