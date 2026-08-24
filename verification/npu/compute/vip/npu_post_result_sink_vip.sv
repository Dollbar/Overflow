`timescale 1ns/1ps
`default_nettype none

// Ready/valid sink for descriptor or result metadata streams. The monitor
// output pulses for one cycle after each accepted transaction.
module npu_post_result_sink_vip #(
    parameter int unsigned PAYLOAD_WIDTH =
        npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic accept_enable_i,

    input  logic source_valid_i,
    output logic source_ready_o,
    input  logic [PAYLOAD_WIDTH-1:0] source_payload_i,

    output logic monitor_valid_o,
    output logic [PAYLOAD_WIDTH-1:0] monitor_payload_o,
    output logic [31:0] transaction_count_o
);

    assign source_ready_o = accept_enable_i && !rst_i && !clear_i;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            monitor_valid_o <= 1'b0;
            monitor_payload_o <= '0;
            transaction_count_o <= 32'd0;
        end else begin
            monitor_valid_o <= source_valid_i && source_ready_o;
            if (source_valid_i && source_ready_o) begin
                monitor_payload_o <= source_payload_i;
                transaction_count_o <= transaction_count_o + 32'd1;
            end
        end
    end

endmodule

`default_nettype wire
