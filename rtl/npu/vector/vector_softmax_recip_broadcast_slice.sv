`timescale 1ns/1ps
`default_nettype none

// Lane-local reciprocal copy used to isolate each normalization multiplier
// from the global reciprocal-result fanout.
(* keep_hierarchy = "yes" *)
module vector_softmax_recip_broadcast_slice (
    input  logic        clk_i,
    input  logic [31:0] reciprocal_i,
    output logic [31:0] reciprocal_o
);
    always_ff @(posedge clk_i) begin
        reciprocal_o <= reciprocal_i;
    end
endmodule

`default_nettype wire
