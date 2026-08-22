`include "kdlink_defs.vh"
module kdlink_reverse_ctrl (
    input wire clk_i,
    input wire rst_n_i,
    input wire [4:0] local_node_i,
    input wire [7:0] link_epoch_i,
    input wire tx_event_valid_i,
    output wire tx_event_ready_o,
    input wire [3:0] tx_message_type_i,
    input wire [2:0] tx_vc_i,
    input wire [2:0] tx_plane_id_i,
    input wire tx_slice_id_i,
    input wire tx_phase_i,
    input wire [4:0] tx_dst_node_i,
    input wire [11:0] tx_collective_id_i,
    input wire [11:0] tx_packet_seq_i,
    input wire [7:0] tx_credit_delta_i,
    input wire [15:0] tx_credit_total_i,
    input wire [15:0] tx_ack_bitmap_i,
    input wire [7:0] tx_status_i,
    output wire tx_word_valid_o,
    output wire [127:0] tx_word_o,
    input wire rx_word_valid_i,
    output wire rx_word_ready_o,
    input wire [127:0] rx_word_i,
    output reg rx_message_valid_o,
    output reg [3:0] rx_message_type_o,
    output reg [2:0] rx_vc_o,
    output reg [2:0] rx_plane_id_o,
    output reg rx_slice_id_o,
    output reg rx_phase_o,
    output reg [4:0] rx_src_node_o,
    output reg [11:0] rx_collective_id_o,
    output reg [11:0] rx_packet_seq_o,
    output reg [15:0] rx_ack_bitmap_o,
    output reg [7:0] rx_status_o,
    output reg credit_update_valid_o,
    output reg ack_valid_o,
    output reg nack_valid_o,
    output reg link_reset_valid_o,
    output reg init_ack_valid_o,
    output reg keepalive_ack_valid_o,
    output reg lane_status_valid_o,
    output wire [127:0] credit_totals_o,
    output reg link_up_o,
    output reg crc_error_o,
    output reg epoch_error_o,
    output reg identity_error_o,
    output reg protocol_error_o
);
    wire codec_rx_valid;
    wire codec_rx_crc_good;
    wire [111:0] codec_rx_body;
    wire [3:0] body_version;
    wire [3:0] body_message_type;
    wire [2:0] body_vc;
    wire [2:0] body_plane_id;
    wire body_slice_id;
    wire body_phase;
    wire [7:0] body_link_epoch;
    wire [4:0] body_src_node;
    wire [4:0] body_dst_node;
    wire [11:0] body_collective_id;
    wire [11:0] body_packet_seq;
    wire [15:0] body_credit_total;
    wire [15:0] body_ack_bitmap;
    wire [7:0] body_status;
    wire [5:0] body_reserved;
    wire body_version_good;
    wire body_epoch_good;
    wire body_identity_good;
    wire body_type_good;
    wire body_reserved_good;
    wire body_accept;
    reg [15:0] credit_total_q [0:7];
    integer vc_index;

    assign tx_event_ready_o = 1'b1;
    assign rx_word_ready_o = 1'b1;
    kdlink_reverse_codec u_codec (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .tx_valid_i(tx_event_valid_i), .message_type_i(tx_message_type_i), .vc_i(tx_vc_i),
        .plane_id_i(tx_plane_id_i), .slice_id_i(tx_slice_id_i), .phase_i(tx_phase_i),
        .link_epoch_i(link_epoch_i), .src_node_i(local_node_i), .dst_node_i(tx_dst_node_i),
        .collective_id_i(tx_collective_id_i), .packet_seq_i(tx_packet_seq_i),
        .credit_delta_i(tx_credit_delta_i), .credit_total_i(tx_credit_total_i),
        .ack_bitmap_i(tx_ack_bitmap_i), .status_i(tx_status_i),
        .tx_valid_o(tx_word_valid_o), .tx_word_o(tx_word_o),
        .rx_valid_i(rx_word_valid_i), .rx_word_i(rx_word_i),
        .rx_valid_o(codec_rx_valid), .rx_crc_good_o(codec_rx_crc_good), .rx_body_o(codec_rx_body)
    );

    assign body_version = codec_rx_body[3:0];
    assign body_message_type = codec_rx_body[7:4];
    assign body_vc = codec_rx_body[10:8];
    assign body_plane_id = codec_rx_body[13:11];
    assign body_slice_id = codec_rx_body[14];
    assign body_phase = codec_rx_body[15];
    assign body_link_epoch = codec_rx_body[23:16];
    assign body_src_node = codec_rx_body[28:24];
    assign body_dst_node = codec_rx_body[33:29];
    assign body_collective_id = codec_rx_body[45:34];
    assign body_packet_seq = codec_rx_body[57:46];
    assign body_credit_total = codec_rx_body[81:66];
    assign body_ack_bitmap = codec_rx_body[97:82];
    assign body_status = codec_rx_body[105:98];
    assign body_reserved = codec_rx_body[111:106];
    assign body_version_good = body_version == `KDL_SCHEMA_VERSION;
    assign body_epoch_good = body_link_epoch == link_epoch_i;
    assign body_identity_good = body_dst_node == local_node_i;
    assign body_type_good = body_message_type <= `KDL_REVERSE_TYPE_LANE_STATUS;
    assign body_reserved_good = body_reserved == 6'd0;
    assign body_accept = codec_rx_valid && codec_rx_crc_good && body_version_good && body_epoch_good && body_identity_good && body_type_good && body_reserved_good;

    genvar packed_vc;
    generate
        for (packed_vc = 0; packed_vc < 8; packed_vc = packed_vc + 1) begin : g_credit_output
            assign credit_totals_o[packed_vc*16 +: 16] = credit_total_q[packed_vc];
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rx_message_valid_o <= 1'b0;
            rx_message_type_o <= 4'd0;
            rx_vc_o <= 3'd0;
            rx_plane_id_o <= 3'd0;
            rx_slice_id_o <= 1'b0;
            rx_phase_o <= 1'b0;
            rx_src_node_o <= 5'd0;
            rx_collective_id_o <= 12'd0;
            rx_packet_seq_o <= 12'd0;
            rx_ack_bitmap_o <= 16'd0;
            rx_status_o <= 8'd0;
            credit_update_valid_o <= 1'b0;
            ack_valid_o <= 1'b0;
            nack_valid_o <= 1'b0;
            link_reset_valid_o <= 1'b0;
            init_ack_valid_o <= 1'b0;
            keepalive_ack_valid_o <= 1'b0;
            lane_status_valid_o <= 1'b0;
            link_up_o <= 1'b0;
            crc_error_o <= 1'b0;
            epoch_error_o <= 1'b0;
            identity_error_o <= 1'b0;
            protocol_error_o <= 1'b0;
            for (vc_index = 0; vc_index < 8; vc_index = vc_index + 1) credit_total_q[vc_index] <= 16'd0;
        end else begin
            rx_message_valid_o <= 1'b0;
            credit_update_valid_o <= 1'b0;
            ack_valid_o <= 1'b0;
            nack_valid_o <= 1'b0;
            link_reset_valid_o <= 1'b0;
            init_ack_valid_o <= 1'b0;
            keepalive_ack_valid_o <= 1'b0;
            lane_status_valid_o <= 1'b0;
            crc_error_o <= 1'b0;
            epoch_error_o <= 1'b0;
            identity_error_o <= 1'b0;
            if (codec_rx_valid && !codec_rx_crc_good) begin
                crc_error_o <= 1'b1;
                protocol_error_o <= 1'b1;
            end
            if (codec_rx_valid && codec_rx_crc_good && !body_epoch_good) begin
                epoch_error_o <= 1'b1;
                protocol_error_o <= 1'b1;
            end
            if (codec_rx_valid && codec_rx_crc_good && body_epoch_good && !body_identity_good) begin
                identity_error_o <= 1'b1;
                protocol_error_o <= 1'b1;
            end
            if (codec_rx_valid && codec_rx_crc_good && (!body_version_good || !body_type_good || !body_reserved_good)) protocol_error_o <= 1'b1;
            if (body_accept) begin
                rx_message_valid_o <= 1'b1;
                rx_message_type_o <= body_message_type;
                rx_vc_o <= body_vc;
                rx_plane_id_o <= body_plane_id;
                rx_slice_id_o <= body_slice_id;
                rx_phase_o <= body_phase;
                rx_src_node_o <= body_src_node;
                rx_collective_id_o <= body_collective_id;
                rx_packet_seq_o <= body_packet_seq;
                rx_ack_bitmap_o <= body_ack_bitmap;
                rx_status_o <= body_status;
                if (body_message_type <= `KDL_REVERSE_TYPE_NACK) begin
                    credit_total_q[body_vc] <= body_credit_total;
                    credit_update_valid_o <= 1'b1;
                end
                if (body_message_type == `KDL_REVERSE_TYPE_ACK) ack_valid_o <= 1'b1;
                if (body_message_type == `KDL_REVERSE_TYPE_NACK) nack_valid_o <= 1'b1;
                if (body_message_type == `KDL_REVERSE_TYPE_LINK_RESET) begin
                    link_reset_valid_o <= 1'b1;
                    link_up_o <= 1'b0;
                    for (vc_index = 0; vc_index < 8; vc_index = vc_index + 1) credit_total_q[vc_index] <= 16'd0;
                end
                if (body_message_type == `KDL_REVERSE_TYPE_INIT_ACK) begin
                    init_ack_valid_o <= 1'b1;
                    link_up_o <= 1'b1;
                end
                if (body_message_type == `KDL_REVERSE_TYPE_KEEPALIVE_ACK) keepalive_ack_valid_o <= 1'b1;
                if (body_message_type == `KDL_REVERSE_TYPE_LANE_STATUS) lane_status_valid_o <= 1'b1;
            end
        end
    end
endmodule
