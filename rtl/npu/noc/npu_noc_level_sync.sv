`timescale 1ns/1ps
`default_nettype none

// Two-stage synchronization for a slow-changing control level. Payload and
// ready/valid data paths must use npu_noc_async_fifo instead.
module npu_noc_level_sync #(
    parameter logic RESET_VALUE = 1'b0
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic async_level_i,
    output logic sync_level_o
);

    (* async_reg = "true" *) logic [1:0] level_q;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            level_q <= {2{RESET_VALUE}};
        end else begin
            level_q <= {level_q[0], async_level_i};
        end
    end

    assign sync_level_o = level_q[1];

endmodule

`default_nettype wire
