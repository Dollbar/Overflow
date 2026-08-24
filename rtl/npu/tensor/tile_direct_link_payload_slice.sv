`timescale 1ns/1ps
`default_nettype none

// Payload timing island for a direct Tile-to-Tile elastic boundary.  The
// parent distributes each control to a small number of slices, while each
// slice's local enable drives no more than WIDTH payload registers.
(* keep_hierarchy = "yes" *)
module tile_direct_link_payload_slice #(
    parameter integer WIDTH = 1,
    parameter integer SLICE_ID = 0
) (
    input  logic             clk_i,
    input  logic             write_slot0_i,
    input  logic             write_slot1_i,
    input  logic             move_slot1_to_slot0_i,
    input  logic [WIDTH-1:0] input_data_i,
    output logic [WIDTH-1:0] slot0_data_o
);

    logic [WIDTH-1:0] slot1_data_q;
    logic write_slot0_inverted;
    logic write_slot0_buffered;
    logic write_slot1_inverted;
    logic write_slot1_buffered;
    logic move_slot1_inverted;
    logic move_slot1_buffered;

    tile_direct_link_control_inverter u_write_slot0_inverter (
        .data_i (write_slot0_i),
        .data_o (write_slot0_inverted)
    );

    tile_direct_link_control_inverter u_write_slot0_restore (
        .data_i (write_slot0_inverted),
        .data_o (write_slot0_buffered)
    );

    tile_direct_link_control_inverter u_write_slot1_inverter (
        .data_i (write_slot1_i),
        .data_o (write_slot1_inverted)
    );

    tile_direct_link_control_inverter u_write_slot1_restore (
        .data_i (write_slot1_inverted),
        .data_o (write_slot1_buffered)
    );

    tile_direct_link_control_inverter u_move_slot1_inverter (
        .data_i (move_slot1_to_slot0_i),
        .data_o (move_slot1_inverted)
    );

    tile_direct_link_control_inverter u_move_slot1_restore (
        .data_i (move_slot1_inverted),
        .data_o (move_slot1_buffered)
    );

    // SLICE_ID deliberately participates in elaboration so independently
    // placed slices remain distinct module types after synthesis.
    if (SLICE_ID >= 0) begin : gen_payload_registers
        always_ff @(posedge clk_i) begin
            if (write_slot0_buffered) begin
                slot0_data_o <= input_data_i;
            end else if (move_slot1_buffered) begin
                slot0_data_o <= slot1_data_q;
            end
            if (write_slot1_buffered) begin
                slot1_data_q <= input_data_i;
            end
        end
    end

endmodule

`default_nettype wire
