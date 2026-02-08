`timescale 1ns/1ps
`default_nettype none

// One preserved combinational stage used in pairs to form a non-inverting,
// zero-cycle local control buffer after synthesis.
(* keep_hierarchy = "yes" *)
module tile_direct_link_control_inverter (
    input  logic data_i,
    output logic data_o
);

    assign data_o = ~data_i;

endmodule

`default_nettype wire
