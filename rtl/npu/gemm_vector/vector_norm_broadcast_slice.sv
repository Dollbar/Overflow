`timescale 1ns/1ps
`default_nettype none

// Lane-local scalar register used to break normalization broadcast fanout.
(* keep_hierarchy = "yes" *)
module vector_norm_broadcast_slice (
    input  logic        clk_i,
    input  logic [31:0] value_i,
    output logic [31:0] value_o
);

    always_ff @(posedge clk_i) begin
        value_o <= value_i;
    end

endmodule

`default_nettype wire
