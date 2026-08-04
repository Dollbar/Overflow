`timescale 1ns/1ps
`default_nettype none

// Passive ready/valid monitor.  It records completed transfers and packet
// boundaries without driving the observed link.
module npu_noc_flit_monitor_vip #(
    parameter int unsigned FLIT_WIDTH = 32,
    parameter int unsigned SOP_BIT = 1,
    parameter int unsigned EOP_BIT = 0
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic link_valid_i,
    input  logic link_ready_i,
    input  logic [FLIT_WIDTH-1:0] link_flit_i,
    output logic [63:0] observed_flits_o,
    output logic [63:0] observed_packets_o,
    output logic sop_seen_o,
    output logic eop_seen_o,
    output logic [FLIT_WIDTH-1:0] last_flit_o
);

    logic link_fire;

    assign link_fire = link_valid_i && link_ready_i;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            observed_flits_o <= '0;
            observed_packets_o <= '0;
            sop_seen_o <= 1'b0;
            eop_seen_o <= 1'b0;
            last_flit_o <= '0;
        end else if (link_fire) begin
            observed_flits_o <= observed_flits_o + 1'b1;
            last_flit_o <= link_flit_i;
            if (link_flit_i[SOP_BIT]) begin
                sop_seen_o <= 1'b1;
            end
            if (link_flit_i[EOP_BIT]) begin
                eop_seen_o <= 1'b1;
                observed_packets_o <= observed_packets_o + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
