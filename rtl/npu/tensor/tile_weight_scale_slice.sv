`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "yes" *)
module tile_weight_scale_slice (
    input  logic       select_i,
    input  logic [7:0] global_scale_i,
    input  logic [7:0] saved_scale_i,
    output logic [7:0] scale_o
);

    assign scale_o = select_i ? global_scale_i : saved_scale_i;

endmodule

`default_nettype wire
