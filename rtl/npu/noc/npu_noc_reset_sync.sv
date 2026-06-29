`timescale 1ns/1ps
`default_nettype none

// Active-high asynchronous assertion with two-stage synchronous release.
module npu_noc_reset_sync (
    input  logic clk_i,
    input  logic async_rst_i,
    output logic sync_rst_o
);

    // The first stage is intentionally asynchronously asserted and then used
    // as the synchronous release shift source.
    /* verilator lint_off SYNCASYNCNET */
    (* async_reg = "true" *) logic [1:0] release_q;

    always_ff @(posedge clk_i or posedge async_rst_i) begin
        if (async_rst_i) begin
            release_q <= 2'b11;
        end else begin
            release_q <= {release_q[0], 1'b0};
        end
    end

    assign sync_rst_o = release_q[1];
    /* verilator lint_on SYNCASYNCNET */

endmodule

`default_nettype wire
