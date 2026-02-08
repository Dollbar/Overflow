`timescale 1ns/1ps
`default_nettype none

// Preserved lane-local control buffer used to split high-fanout timing paths.
(* keep_hierarchy = "yes" *)
module tile_control_inverter (
    input  logic data_i,
    output logic data_o
);

    assign data_o = ~data_i;

endmodule

`default_nettype wire
