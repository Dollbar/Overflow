`timescale 1ns/1ps
`default_nettype none

// Two-entry elastic boundary for direct Tile-to-Tile streams.  input_ready_o
// depends only on local registered occupancy, cutting the downstream ready
// combinational path.  A full buffer conservatively accepts no replacement on
// the same cycle as a pop; sustained one-word-per-cycle traffic remains bubble
// free because it normally occupies only slot zero.
module tile_direct_link_buffer #(
    parameter integer WIDTH = 1
) (
    input  logic             clk_i,
    input  logic             rst_i,
    input  logic             clear_i,
    input  logic             input_valid_i,
    output logic             input_ready_o,
    input  logic [WIDTH-1:0] input_data_i,
    output logic             output_valid_o,
    input  logic             output_ready_i,
    output logic [WIDTH-1:0] output_data_o
);

    logic slot0_valid_q;
    logic slot1_valid_q;
    logic [WIDTH-1:0] slot0_data_q;
    logic input_fire;
    logic output_fire;
    logic write_slot0;
    logic write_slot1;
    logic move_slot1_to_slot0;

    assign input_ready_o = !slot1_valid_q;
    assign output_valid_o = slot0_valid_q;
    assign output_data_o = slot0_data_q;
    assign input_fire = input_valid_i && input_ready_o;
    assign output_fire = output_valid_o && output_ready_i;
    assign write_slot0 = (input_fire && output_fire) ||
                         (input_fire && !output_fire && !slot0_valid_q);
    assign write_slot1 = input_fire && !output_fire && slot0_valid_q;
    assign move_slot1_to_slot0 = !input_fire && output_fire && slot1_valid_q;

    for (genvar slice_index = 0;
         slice_index < ((WIDTH + 15) / 16);
         slice_index = slice_index + 1) begin : gen_payload_slice
        localparam integer OFFSET = slice_index * 16;
        localparam integer SLICE_WIDTH =
            ((WIDTH - OFFSET) < 16) ? (WIDTH - OFFSET) : 16;
        tile_direct_link_payload_slice #(
            .WIDTH    (SLICE_WIDTH),
            .SLICE_ID (slice_index)
        ) u_payload_slice (
            .clk_i                 (clk_i),
            .write_slot0_i         (write_slot0),
            .write_slot1_i         (write_slot1),
            .move_slot1_to_slot0_i (move_slot1_to_slot0),
            .input_data_i          (input_data_i[OFFSET +: SLICE_WIDTH]),
            .slot0_data_o          (slot0_data_q[OFFSET +: SLICE_WIDTH])
        );
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            slot0_valid_q <= 1'b0;
            slot1_valid_q <= 1'b0;
        end else begin
            unique case ({input_fire, output_fire})
                2'b10: begin
                    if (!slot0_valid_q) begin
                        slot0_valid_q <= 1'b1;
                    end else begin
                        slot1_valid_q <= 1'b1;
                    end
                end
                2'b01: begin
                    if (slot1_valid_q) begin
                        slot0_valid_q <= 1'b1;
                        slot1_valid_q <= 1'b0;
                    end else begin
                        slot0_valid_q <= 1'b0;
                    end
                end
                2'b11: begin
                    // input_ready_o guarantees slot one is empty here.
                    slot0_valid_q <= 1'b1;
                    slot1_valid_q <= 1'b0;
                end
                default: begin
                    slot0_valid_q <= slot0_valid_q;
                    slot1_valid_q <= slot1_valid_q;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
