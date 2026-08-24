`timescale 1ns/1ps
`default_nettype none

// A hierarchy-preserved lane-local copy prevents synthesis from merging the
// 16 MAX broadcast registers back into one high-fanout source.
(* keep_hierarchy = "yes" *)
module vector_softmax_max_broadcast_slice (
    input  logic        clk_i,
    input  logic [31:0] maximum_i,
    output logic [31:0] maximum_o
);
    always_ff @(posedge clk_i) begin
        maximum_o <= maximum_i;
    end
endmodule

`default_nettype wire
