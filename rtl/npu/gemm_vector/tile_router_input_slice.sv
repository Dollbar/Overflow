`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "yes" *)
module tile_router_input_slice #(
    parameter integer WIDTH = 16
) (
    input  logic             clk_i,
    input  logic             enqueue_i,
    input  logic             write_select_i,
    input  logic             read_select_i,
    input  logic [WIDTH-1:0] enqueue_data_i,
    output logic [WIDTH-1:0] head_data_o
);

    logic [WIDTH-1:0] bank_zero_q;
    logic [WIDTH-1:0] bank_one_q;

    always_ff @(posedge clk_i) begin
        if (enqueue_i) begin
            if (write_select_i) begin
                bank_one_q <= enqueue_data_i;
            end else begin
                bank_zero_q <= enqueue_data_i;
            end
        end
    end

    always_comb begin
        if (read_select_i) begin
            head_data_o = bank_one_q;
        end else begin
            head_data_o = bank_zero_q;
        end
    end

endmodule

`default_nettype wire
