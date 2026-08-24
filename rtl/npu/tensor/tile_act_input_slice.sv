`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module tile_act_input_slice #(
    parameter integer REPLICA_ID = 0
) (
    input  logic       clk_i,
    input  logic       rst_i,
    input  logic       clear_i,
    input  logic       hold_i,
    input  logic       valid_i,
    input  logic [7:0] data_i,
    input  logic [1:0] format_i,
    input  logic [7:0] scale_i,
    output logic       valid_o,
    output logic [7:0] data_o,
    output logic [1:0] format_o,
    output logic [7:0] scale_o
);

    generate
        if (REPLICA_ID >= 0) begin : gen_valid_replica
            always_ff @(posedge clk_i) begin
                if (rst_i || clear_i || hold_i) begin
                    valid_o <= 1'b0;
                end else begin
                    valid_o <= valid_i;
                end
                data_o <= data_i;
                format_o <= format_i;
                scale_o <= scale_i;
            end
        end
    endgenerate

endmodule
