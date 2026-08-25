`timescale 1ns/1ps
`default_nettype none

(* keep_hierarchy = "yes" *)
module npu_dma_tag_metadata_bank #(
    parameter int unsigned ROW_WIDTH = 4,
    parameter int unsigned ADDRESS_WIDTH = 24,
    parameter int unsigned ROWS = 1 << ROW_WIDTH
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic allocate_valid_i,
    input  logic [ROW_WIDTH-1:0] allocate_row_i,
    input  logic allocate_last_i,
    input  logic [ADDRESS_WIDTH-1:0] allocate_address_i,
    output logic allocate_entry_valid_o,

    input  logic release_row_capture_i,
    input  logic [ROW_WIDTH-1:0] release_row_input_i,
    input  logic release_valid_i,
    output logic release_entry_valid_o,
    output logic release_last_o,
    output logic [ADDRESS_WIDTH-1:0] release_address_o
);

    logic [ROWS-1:0] valid_q;
    logic [ROWS-1:0] last_q;
    logic [ADDRESS_WIDTH-1:0] address_q [0:ROWS-1];
    logic [ROW_WIDTH-1:0] release_row_q;

    assign allocate_entry_valid_o = valid_q[allocate_row_i];
    assign release_entry_valid_o = valid_q[release_row_q];
    assign release_last_o = last_q[release_row_q];
    assign release_address_o = address_q[release_row_q];

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_q <= '0;
            last_q <= '0;
            release_row_q <= '0;
        end else begin
            if (release_row_capture_i) begin
                release_row_q <= release_row_input_i;
            end
            if (allocate_valid_i) begin
                valid_q[allocate_row_i] <= 1'b1;
                last_q[allocate_row_i] <= allocate_last_i;
                address_q[allocate_row_i] <= allocate_address_i;
            end
            if (release_valid_i) begin
                valid_q[release_row_q] <= 1'b0;
                last_q[release_row_q] <= 1'b0;
            end
        end
    end

    initial begin
        if ((ROW_WIDTH != 4) || (ADDRESS_WIDTH != 24) || (ROWS != 16)) begin
            $error("npu_dma_tag_metadata_bank violates DMA v0.1 geometry");
        end
    end

endmodule

`default_nettype wire
