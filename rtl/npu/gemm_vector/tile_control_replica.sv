`timescale 1ns/1ps

(* keep_hierarchy = "yes" *)
module tile_control_replica #(
    parameter integer REPLICA_ID = 0
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    output logic rst_o,
    output logic clear_o
);

    generate
        if (REPLICA_ID >= 0) begin : gen_valid_replica
            always_ff @(posedge clk_i) begin
                rst_o <= rst_i;
                clear_o <= clear_i;
            end
        end
    endgenerate

endmodule
