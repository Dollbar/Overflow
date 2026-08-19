`timescale 1ns/1ps
`default_nettype none

// Adapter from one verification command stream to the descriptor buffer's
// separate write and submit channels. The command must remain stable while
// command_valid_i is asserted and command_ready_o is low.
module npu_descriptor_source_vip #(
    parameter int unsigned INDEX_WIDTH = 4
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic command_valid_i,
    output logic command_ready_o,
    input  logic command_submit_i,
    input  logic [INDEX_WIDTH-1:0] command_index_i,
    input  logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0]
                 command_descriptor_i,

    output logic write_valid_o,
    input  logic write_ready_i,
    output logic [INDEX_WIDTH-1:0] write_index_o,
    output logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0]
                 write_descriptor_o,
    output logic submit_valid_o,
    input  logic submit_ready_i,
    output logic [INDEX_WIDTH-1:0] submit_index_o,
    output logic [31:0] transaction_count_o
);

    assign command_ready_o = command_submit_i ? submit_ready_i : write_ready_i;
    assign write_valid_o = command_valid_i && !command_submit_i;
    assign write_index_o = command_index_i;
    assign write_descriptor_o = command_descriptor_i;
    assign submit_valid_o = command_valid_i && command_submit_i;
    assign submit_index_o = command_index_i;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            transaction_count_o <= 32'd0;
        end else if (command_valid_i && command_ready_o) begin
            transaction_count_o <= transaction_count_o + 32'd1;
        end
    end

endmodule

`default_nettype wire
