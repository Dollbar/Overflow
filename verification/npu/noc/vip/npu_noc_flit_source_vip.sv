`timescale 1ns/1ps
`default_nettype none

// One-entry ready/valid source. A testbench can submit the next flit in the
// same cycle that the current flit leaves without introducing a bubble.
module npu_noc_flit_source_vip #(
    parameter int unsigned FLIT_WIDTH = 32
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic submit_valid_i,
    output logic submit_ready_o,
    input  logic [FLIT_WIDTH-1:0] submit_flit_i,

    output logic link_valid_o,
    input  logic link_ready_i,
    output logic [FLIT_WIDTH-1:0] link_flit_o,

    output logic [63:0] submitted_flits_o,
    output logic [63:0] transmitted_flits_o
);

    logic full_q;
    logic [FLIT_WIDTH-1:0] flit_q;
    logic link_fire;
    logic submit_fire;

    assign link_valid_o = full_q;
    assign link_flit_o = flit_q;
    assign link_fire = link_valid_o && link_ready_i;
    assign submit_ready_o = !full_q || link_fire;
    assign submit_fire = submit_valid_i && submit_ready_o;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            full_q <= 1'b0;
            flit_q <= '0;
            submitted_flits_o <= '0;
            transmitted_flits_o <= '0;
        end else begin
            case ({submit_fire, link_fire})
                2'b10: full_q <= 1'b1;
                2'b01: full_q <= 1'b0;
                default: full_q <= full_q;
            endcase
            if (submit_fire) begin
                flit_q <= submit_flit_i;
                submitted_flits_o <= submitted_flits_o + 1'b1;
            end
            if (link_fire) begin
                transmitted_flits_o <= transmitted_flits_o + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
