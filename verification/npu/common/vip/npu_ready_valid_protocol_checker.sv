`timescale 1ns/1ps
`default_nettype none

module npu_ready_valid_protocol_checker #(
    parameter int unsigned WIDTH = 1,
    parameter int unsigned CHANNEL_ID = 0
) (
    input logic clk_i,
    input logic rst_i,
    input logic clear_i,
    input logic valid_i,
    input logic ready_i,
    input logic [WIDTH-1:0] payload_i
);

    property p_payload_stable_while_stalled;
        @(posedge clk_i) disable iff (rst_i || clear_i)
            valid_i && !ready_i |=> valid_i && $stable(payload_i);
    endproperty

    assert property (p_payload_stable_while_stalled)
        else $fatal(1,
            "ready-valid channel %0d changed or withdrew payload while stalled",
            CHANNEL_ID);

    cover property (@(posedge clk_i) disable iff (rst_i || clear_i)
        valid_i && !ready_i ##1 valid_i && ready_i);

    cover property (@(posedge clk_i) disable iff (rst_i || clear_i)
        valid_i && ready_i ##1 valid_i && ready_i);

endmodule

`default_nettype wire
