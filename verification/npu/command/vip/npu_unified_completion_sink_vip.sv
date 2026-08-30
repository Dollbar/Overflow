`timescale 1ns/1ps
`default_nettype none

module npu_unified_completion_sink_vip (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic accept_enable_i,
    input  logic source_valid_i,
    output logic source_ready_o,
    input  logic [npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH-1:0]
                 source_completion_i,
    output logic monitor_valid_o,
    output logic [npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH-1:0]
                 monitor_completion_o,
    output logic [31:0] transaction_count_o,
    output logic protocol_error_o
);

    logic held_valid_q;
    logic [npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH-1:0]
        held_completion_q;

    assign source_ready_o = accept_enable_i && !rst_i && !clear_i;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            monitor_valid_o <= 1'b0;
            monitor_completion_o <= '0;
            transaction_count_o <= 32'd0;
            held_valid_q <= 1'b0;
            held_completion_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            monitor_valid_o <= source_valid_i && source_ready_o;
            if (held_valid_q &&
                (!source_valid_i ||
                 (source_completion_i != held_completion_q))) begin
                protocol_error_o <= 1'b1;
            end
            if (source_valid_i && source_ready_o) begin
                monitor_completion_o <= source_completion_i;
                transaction_count_o <= transaction_count_o + 32'd1;
                held_valid_q <= 1'b0;
            end else if (source_valid_i) begin
                held_valid_q <= 1'b1;
                held_completion_q <= source_completion_i;
            end else begin
                held_valid_q <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
