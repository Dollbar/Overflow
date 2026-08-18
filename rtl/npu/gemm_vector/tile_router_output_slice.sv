`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "yes" *)
module tile_router_output_slice #(
    parameter integer WIDTH = 16
) (
    input  logic             clk_i,
    input  logic             load_i,
    input  logic [WIDTH-1:0] data_i,
    output logic [WIDTH-1:0] data_o
);

    logic load_inverted;
    logic load_buffered;

    tile_router_control_inverter u_load_inverter (
        .data_i (load_i),
        .data_o (load_inverted)
    );

    tile_router_control_inverter u_load_restore (
        .data_i (load_inverted),
        .data_o (load_buffered)
    );

    always_ff @(posedge clk_i) begin
        if (load_buffered) begin
            data_o <= data_i;
        end
    end

endmodule

`default_nettype wire
