`timescale 1ns/1ps
`default_nettype none

// REGISTER_ID is deliberately part of elaboration.  It gives every physical
// tree point a distinct module type so logic optimizers cannot merge equal
// registers back into a single high-fanout driver.
(* keep_hierarchy = "yes" *)
module gemm_control_tree_register #(
    parameter integer REGISTER_ID = 0
) (
    input  logic clk_i,
    input  logic data_i,
    output logic data_o
);

    generate
        if (REGISTER_ID >= 0) begin : gen_valid_register
            always_ff @(posedge clk_i) begin
                data_o <= data_i;
            end
        end
    endgenerate

endmodule

`default_nettype wire
