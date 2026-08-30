`timescale 1ns/1ps
`default_nettype none

module npu_decoded_command_source_vip (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic command_valid_i,
    output logic command_ready_o,
    input  logic [npu_command_pkg::NPU_DECODED_COMMAND_WIDTH-1:0]
                 command_i,
    output logic source_valid_o,
    input  logic source_ready_i,
    output logic [npu_command_pkg::NPU_DECODED_COMMAND_WIDTH-1:0]
                 source_command_o,
    output logic [31:0] transaction_count_o,
    output logic protocol_error_o
);

    logic held_valid_q;
    logic [npu_command_pkg::NPU_DECODED_COMMAND_WIDTH-1:0] held_command_q;

    assign command_ready_o = source_ready_i;
    assign source_valid_o = command_valid_i;
    assign source_command_o = command_i;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            transaction_count_o <= 32'd0;
            held_valid_q <= 1'b0;
            held_command_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            if (held_valid_q &&
                (!command_valid_i || (command_i != held_command_q))) begin
                protocol_error_o <= 1'b1;
            end
            if (command_valid_i && command_ready_o) begin
                transaction_count_o <= transaction_count_o + 32'd1;
                held_valid_q <= 1'b0;
            end else if (command_valid_i) begin
                held_valid_q <= 1'b1;
                held_command_q <= command_i;
            end else begin
                held_valid_q <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
