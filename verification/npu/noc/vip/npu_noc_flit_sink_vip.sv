`timescale 1ns/1ps
`default_nettype none

// Controllable ready/valid sink with payload-stability checking while stalled.
module npu_noc_flit_sink_vip #(
    parameter int unsigned FLIT_WIDTH = 32
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic enable_i,
    input  logic stall_i,

    input  logic link_valid_i,
    output logic link_ready_o,
    input  logic [FLIT_WIDTH-1:0] link_flit_i,

    output logic [63:0] accepted_flits_o,
    output logic [FLIT_WIDTH-1:0] last_flit_o,
    output logic backpressure_seen_o,
    output logic protocol_error_o
);

    logic stalled_q;
    logic [FLIT_WIDTH-1:0] stalled_flit_q;

    assign link_ready_o = enable_i && !stall_i;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            accepted_flits_o <= '0;
            last_flit_o <= '0;
            backpressure_seen_o <= 1'b0;
            protocol_error_o <= 1'b0;
            stalled_q <= 1'b0;
            stalled_flit_q <= '0;
        end else begin
            if (stalled_q &&
                (!link_valid_i || link_flit_i !== stalled_flit_q)) begin
                protocol_error_o <= 1'b1;
            end
            if (link_valid_i && link_ready_o) begin
                accepted_flits_o <= accepted_flits_o + 1'b1;
                last_flit_o <= link_flit_i;
            end
            if (link_valid_i && !link_ready_o) begin
                backpressure_seen_o <= 1'b1;
                if (!stalled_q) begin
                    stalled_flit_q <= link_flit_i;
                end
                stalled_q <= 1'b1;
            end else begin
                stalled_q <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
