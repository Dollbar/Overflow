`timescale 1ns/1ps
`default_nettype none

// One packet-aware elastic register at the synchronous Pod/router boundary.
// The slice validates endpoint metadata but does not route or allocate credits.
module npu_pod_noc_link_slice #(
    parameter int unsigned PAYLOAD_BYTES = 128,
    parameter int unsigned POD_ID_WIDTH = 3,
    parameter int unsigned TRAFFIC_CLASS_WIDTH = 2,
    parameter int unsigned VERSION_WIDTH = 4,
    parameter logic [VERSION_WIDTH-1:0] PROTOCOL_VERSION = VERSION_WIDTH'(1),
    parameter logic [POD_ID_WIDTH-1:0] LOCAL_POD_ID = '0,
    parameter bit CHECK_LOCAL_SOURCE = 1'b1,
    parameter int unsigned FLIT_WIDTH =
        PAYLOAD_BYTES * 8 + PAYLOAD_BYTES + VERSION_WIDTH + 2 +
        2 * POD_ID_WIDTH + TRAFFIC_CLASS_WIDTH
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic source_valid_i,
    output logic source_ready_o,
    input  logic [FLIT_WIDTH-1:0] source_flit_i,

    output logic sink_valid_o,
    input  logic sink_ready_i,
    output logic [FLIT_WIDTH-1:0] sink_flit_o,

    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o
);

    localparam int unsigned PAYLOAD_WIDTH = PAYLOAD_BYTES * 8;
    localparam int unsigned KEEP_LSB = PAYLOAD_WIDTH;
    localparam int unsigned TRAFFIC_CLASS_LSB = KEEP_LSB + PAYLOAD_BYTES;
    localparam int unsigned DESTINATION_LSB =
        TRAFFIC_CLASS_LSB + TRAFFIC_CLASS_WIDTH;
    localparam int unsigned SOURCE_LSB = DESTINATION_LSB + POD_ID_WIDTH;
    localparam int unsigned EOP_BIT = SOURCE_LSB + POD_ID_WIDTH;
    localparam int unsigned SOP_BIT = EOP_BIT + 1;
    localparam int unsigned VERSION_LSB = SOP_BIT + 1;

    logic buffer_valid_q;
    logic [FLIT_WIDTH-1:0] buffer_flit_q;
    logic packet_active_q;
    logic [VERSION_WIDTH-1:0] packet_version_q;
    logic [POD_ID_WIDTH-1:0] packet_source_q;
    logic [POD_ID_WIDTH-1:0] packet_destination_q;
    logic [TRAFFIC_CLASS_WIDTH-1:0] packet_traffic_class_q;
    logic protocol_error_q;

    logic source_fire;
    logic sink_fire;
    logic source_sop;
    logic source_eop;
    logic [VERSION_WIDTH-1:0] source_version;
    logic [POD_ID_WIDTH-1:0] source_pod;
    logic [POD_ID_WIDTH-1:0] source_destination;
    logic [TRAFFIC_CLASS_WIDTH-1:0] source_traffic_class;
    logic [PAYLOAD_BYTES-1:0] source_keep;
    logic endpoint_mismatch;
    logic metadata_mismatch;
    logic framing_error;
    logic payload_error;

    assign source_version = source_flit_i[VERSION_LSB +: VERSION_WIDTH];
    assign source_sop = source_flit_i[SOP_BIT];
    assign source_eop = source_flit_i[EOP_BIT];
    assign source_pod = source_flit_i[SOURCE_LSB +: POD_ID_WIDTH];
    assign source_destination =
        source_flit_i[DESTINATION_LSB +: POD_ID_WIDTH];
    assign source_traffic_class =
        source_flit_i[TRAFFIC_CLASS_LSB +: TRAFFIC_CLASS_WIDTH];
    assign source_keep = source_flit_i[KEEP_LSB +: PAYLOAD_BYTES];

    assign source_ready_o = (!buffer_valid_q || sink_ready_i) &&
                            (!quiesce_i || packet_active_q);
    assign source_fire = source_valid_i && source_ready_o;
    assign sink_fire = sink_valid_o && sink_ready_i;
    assign sink_valid_o = buffer_valid_q;
    assign sink_flit_o = buffer_flit_q;

    assign endpoint_mismatch = CHECK_LOCAL_SOURCE ?
        (source_pod != LOCAL_POD_ID) :
        (source_destination != LOCAL_POD_ID);
    assign metadata_mismatch = packet_active_q &&
        ((source_version != packet_version_q) ||
         (source_pod != packet_source_q) ||
         (source_destination != packet_destination_q) ||
         (source_traffic_class != packet_traffic_class_q));
    assign framing_error = packet_active_q ? source_sop : !source_sop;
    assign payload_error = (source_keep == '0) ||
                           (!source_eop && (source_keep != '1));

    assign busy_o = buffer_valid_q || packet_active_q;
    assign quiesced_o = !buffer_valid_q && !packet_active_q;
    assign protocol_error_o = protocol_error_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            buffer_valid_q <= 1'b0;
            buffer_flit_q <= '0;
        end else begin
            case ({source_fire, sink_fire})
                2'b10: begin
                    buffer_valid_q <= 1'b1;
                    buffer_flit_q <= source_flit_i;
                end
                2'b01: begin
                    buffer_valid_q <= 1'b0;
                end
                2'b11: begin
                    buffer_valid_q <= 1'b1;
                    buffer_flit_q <= source_flit_i;
                end
                default: begin
                    buffer_valid_q <= buffer_valid_q;
                    buffer_flit_q <= buffer_flit_q;
                end
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            packet_active_q <= 1'b0;
            packet_version_q <= '0;
            packet_source_q <= '0;
            packet_destination_q <= '0;
            packet_traffic_class_q <= '0;
        end else if (source_fire) begin
            if (!packet_active_q) begin
                packet_active_q <= !source_eop;
                packet_version_q <= source_version;
                packet_source_q <= source_pod;
                packet_destination_q <= source_destination;
                packet_traffic_class_q <= source_traffic_class;
            end else if (source_eop) begin
                packet_active_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            protocol_error_q <= 1'b0;
        end else if (source_fire &&
                     ((source_version != PROTOCOL_VERSION) ||
                      endpoint_mismatch || metadata_mismatch ||
                      framing_error || payload_error)) begin
            protocol_error_q <= 1'b1;
        end
    end

endmodule

`default_nettype wire
