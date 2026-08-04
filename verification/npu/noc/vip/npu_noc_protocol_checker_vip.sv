`timescale 1ns/1ps
`default_nettype none

// Passive packet and ready/valid protocol checker for a packed NoC flit.
// Metadata must remain constant from SOP through EOP and valid data must stay
// stable while the receiver applies backpressure.
module npu_noc_protocol_checker_vip #(
    parameter int unsigned FLIT_WIDTH = 32,
    parameter int unsigned SOP_BIT = 1,
    parameter int unsigned EOP_BIT = 0,
    parameter int unsigned SOURCE_LSB = 2,
    parameter int unsigned DESTINATION_LSB = 5,
    parameter int unsigned TRAFFIC_CLASS_LSB = 8,
    parameter int unsigned MAX_PACKET_FLITS = 32
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic link_valid_i,
    input  logic link_ready_i,
    input  logic [FLIT_WIDTH-1:0] link_flit_i,
    output logic protocol_error_o,
    output logic framing_error_o,
    output logic stability_error_o,
    output logic metadata_error_o,
    output logic length_error_o
);

    localparam int unsigned LENGTH_WIDTH =
        (MAX_PACKET_FLITS < 2) ? 1 : $clog2(MAX_PACKET_FLITS + 1);

    logic packet_open_q;
    logic stalled_q;
    logic [LENGTH_WIDTH-1:0] packet_length_q;
    logic [7:0] packet_metadata_q;
    logic [FLIT_WIDTH-1:0] stalled_flit_q;
    logic link_fire;
    logic [7:0] observed_metadata;

    assign link_fire = link_valid_i && link_ready_i;
    assign observed_metadata = {
        link_flit_i[SOURCE_LSB +: 3],
        link_flit_i[DESTINATION_LSB +: 3],
        link_flit_i[TRAFFIC_CLASS_LSB +: 2]
    };
    assign protocol_error_o = framing_error_o || stability_error_o ||
        metadata_error_o || length_error_o;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            packet_open_q <= 1'b0;
            stalled_q <= 1'b0;
            packet_length_q <= '0;
            packet_metadata_q <= '0;
            stalled_flit_q <= '0;
            framing_error_o <= 1'b0;
            stability_error_o <= 1'b0;
            metadata_error_o <= 1'b0;
            length_error_o <= 1'b0;
        end else begin
            // A transfer that was stalled in the previous cycle must retain
            // both valid and the complete flit until it is accepted.
            if (stalled_q &&
                (!link_valid_i || link_flit_i !== stalled_flit_q)) begin
                stability_error_o <= 1'b1;
            end
            if (link_valid_i && !link_ready_i) begin
                if (!stalled_q) begin
                    stalled_flit_q <= link_flit_i;
                end
                stalled_q <= 1'b1;
            end else begin
                stalled_q <= 1'b0;
            end

            if (link_fire) begin
                if (!packet_open_q) begin
                    if (!link_flit_i[SOP_BIT]) begin
                        framing_error_o <= 1'b1;
                    end
                    packet_metadata_q <= observed_metadata;
                    packet_length_q <= LENGTH_WIDTH'(1);
                end else begin
                    if (link_flit_i[SOP_BIT]) begin
                        framing_error_o <= 1'b1;
                    end
                    if (observed_metadata != packet_metadata_q) begin
                        metadata_error_o <= 1'b1;
                    end
                    if (packet_length_q >= LENGTH_WIDTH'(MAX_PACKET_FLITS)) begin
                        length_error_o <= 1'b1;
                    end else begin
                        packet_length_q <= packet_length_q + 1'b1;
                    end
                end

                if (link_flit_i[EOP_BIT]) begin
                    packet_open_q <= 1'b0;
                    packet_length_q <= '0;
                end else begin
                    packet_open_q <= 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire
