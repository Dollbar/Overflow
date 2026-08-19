`include "kdlink_v2_defs.vh"
module kdlink_v2_reliable_endpoint #(
    parameter [15:0] INITIAL_CREDITS = 16'd64,
    parameter integer TX_FIFO_ADDR_BITS = 7,
    parameter integer RX_FIFO_ADDR_BITS = 7,
    parameter integer RESPONSE_FIFO_ADDR_BITS = 7,
    parameter integer REPLAY_SLOT_BITS = 9
) (
    input wire core_clk_i,
    input wire core_rst_n_i,
    input wire phy_clk_i,
    input wire phy_rst_n_i,
    input wire [4:0] local_node_i,
    input wire [7:0] link_epoch_i,
    input wire tx_valid_i,
    output wire tx_ready_o,
    input wire [95:0] tx_header_i,
    input wire [511:0] tx_payload_i,
    input wire [6:0] tx_payload_bytes_i,
    output wire rx_commit_valid_o,
    input wire rx_commit_ready_i,
    output wire [95:0] rx_commit_header_o,
    output wire [511:0] rx_commit_payload_o,
    output wire [6:0] rx_commit_payload_bytes_o,
    output wire rx_commit_last_o,
    output wire phy_forward_tx_valid_o,
    output wire [639:0] phy_forward_tx_flit_o,
    input wire phy_forward_rx_valid_i,
    input wire [639:0] phy_forward_rx_flit_i,
    output wire phy_reverse_tx_valid_o,
    output wire [127:0] phy_reverse_tx_word_o,
    input wire phy_reverse_rx_valid_i,
    input wire [127:0] phy_reverse_rx_word_i,
    output wire [127:0] tx_credit_count_o,
    output wire [REPLAY_SLOT_BITS:0] replay_occupancy_o,
    output wire retry_exhausted_o,
    output wire duplicate_drop_o,
    output wire credit_error_o,
    output wire reverse_error_o,
    output wire protocol_error_o,
    output wire cdc_error_o
);
    wire [607:0] tx_fifo_write_data;
    wire [607:0] tx_fifo_read_data;
    wire tx_fifo_read_valid;
    wire tx_fifo_read_ready;
    wire tx_fifo_overflow;
    wire tx_fifo_underflow;
    wire [2:0] normal_vc;
    wire normal_admitted;
    wire normal_send;
    wire replay_send;
    wire [7:0] credit_admit;
    wire credit_underflow;
    wire credit_overflow;
    wire credit_stale;
    wire replay_store_ready;
    wire replay_valid;
    wire [607:0] replay_body;
    wire replay_last;
    wire selected_tx_valid;
    wire [607:0] selected_tx_body;
    wire [6:0] selected_tx_bytes;
    wire packetized_valid;
    wire [639:0] packetized_flit;

    wire reverse_rx_message_valid;
    wire [3:0] reverse_rx_message_type;
    wire [2:0] reverse_rx_vc;
    wire [2:0] reverse_rx_plane;
    wire reverse_rx_slice;
    wire reverse_rx_phase;
    wire [4:0] reverse_rx_source;
    wire [11:0] reverse_rx_collective;
    wire [11:0] reverse_rx_sequence;
    wire [15:0] reverse_rx_ack_bitmap;
    wire [7:0] reverse_rx_status;
    wire reverse_credit_valid;
    wire reverse_ack_valid;
    wire reverse_nack_valid;
    wire reverse_link_reset;
    wire reverse_init_ack;
    wire reverse_keepalive_ack;
    wire reverse_lane_status;
    wire [127:0] reverse_credit_totals;
    wire reverse_link_up;
    wire reverse_crc_error;
    wire reverse_epoch_error;
    wire reverse_identity_error;
    wire reverse_protocol_error;

    wire depacketized_valid;
    wire depacketized_crc_good;
    wire [95:0] depacketized_header;
    wire [511:0] depacketized_payload;
    wire [6:0] depacketized_bytes;
    wire [615:0] rx_fifo_write_data;
    wire rx_fifo_write_ready;
    wire [615:0] rx_fifo_read_data;
    wire rx_fifo_read_valid;
    wire rx_fifo_read_ready;
    wire rx_fifo_overflow;
    wire rx_fifo_underflow;

    wire response_core_valid;
    wire response_core_ready;
    wire [3:0] response_core_type;
    wire [2:0] response_core_vc;
    wire [2:0] response_core_plane;
    wire response_core_phase;
    wire [4:0] response_core_destination;
    wire [11:0] response_core_collective;
    wire [11:0] response_core_sequence;
    wire [15:0] response_core_credit_total;
    wire [7:0] response_core_status;
    wire [63:0] response_fifo_write_data;
    wire [63:0] response_fifo_read_data;
    wire response_fifo_read_valid;
    wire response_fifo_overflow;
    wire response_fifo_underflow;
    wire commit_protocol_error;
    reg commit_protocol_sync1_q;
    reg commit_protocol_sync2_q;
    reg rx_fifo_backpressure_error_q;

    assign tx_fifo_write_data = {{1'b0, tx_payload_bytes_i,
        tx_header_i[87:4], 4'd2}, tx_payload_i};
    assign normal_vc = tx_fifo_read_data[527:525];
    assign normal_admitted = credit_admit[normal_vc];
    assign replay_send = replay_valid && credit_admit[`KDL2_VC_ROLE_REPLAY];
    assign normal_send = tx_fifo_read_valid && normal_admitted &&
        replay_store_ready && !replay_valid;
    assign tx_fifo_read_ready = normal_send;
    assign selected_tx_valid = replay_send || normal_send;
    assign selected_tx_body = replay_send ? replay_body : tx_fifo_read_data;
    assign selected_tx_bytes = selected_tx_body[606:600];

    coll_async_fifo #(.WIDTH(608), .ADDR_W(TX_FIFO_ADDR_BITS)) u_tx_cdc_fifo (
        .write_clk_i(core_clk_i), .write_rst_n_i(core_rst_n_i),
        .write_data_i(tx_fifo_write_data), .write_valid_i(tx_valid_i),
        .write_ready_o(tx_ready_o), .read_clk_i(phy_clk_i),
        .read_rst_n_i(phy_rst_n_i), .read_data_o(tx_fifo_read_data),
        .read_valid_o(tx_fifo_read_valid), .read_ready_i(tx_fifo_read_ready),
        .overflow_o(tx_fifo_overflow), .underflow_o(tx_fifo_underflow)
    );

    kdlink_v2_credit_bank8 #(.INITIAL_CREDITS(INITIAL_CREDITS)) u_credit_bank (
        .clk_i(phy_clk_i), .rst_n_i(phy_rst_n_i),
        .send_valid_i(selected_tx_valid),
        .send_vc_i(replay_send ? `KDL2_VC_ROLE_REPLAY : normal_vc),
        .return_valid_i(reverse_credit_valid), .return_vc_i(reverse_rx_vc),
        .return_total_i(reverse_credit_totals[reverse_rx_vc*16 +: 16]),
        .admit_o(credit_admit), .credit_count_o(tx_credit_count_o),
        .underflow_o(credit_underflow), .overflow_o(credit_overflow),
        .stale_return_o(credit_stale)
    );

    kdlink_v2_replay_window #(.SLOT_BITS(REPLAY_SLOT_BITS)) u_replay_window (
        .clk_i(phy_clk_i), .rst_n_i(phy_rst_n_i),
        .store_start_i(normal_send && tx_fifo_read_data[529]),
        .store_valid_i(normal_send), .store_body_i(tx_fifo_read_data),
        .store_last_i(tx_fifo_read_data[530]), .store_ready_o(replay_store_ready),
        .ack_valid_i(reverse_ack_valid),
        .ack_collective_id_i(reverse_rx_collective),
        .ack_phase_i(reverse_rx_phase), .ack_packet_seq_i(reverse_rx_sequence),
        .nack_valid_i(reverse_nack_valid),
        .nack_collective_id_i(reverse_rx_collective),
        .nack_phase_i(reverse_rx_phase), .nack_packet_seq_i(reverse_rx_sequence),
        .replay_valid_o(replay_valid), .replay_ready_i(replay_send),
        .replay_body_o(replay_body), .replay_last_o(replay_last),
        .retry_exhausted_o(retry_exhausted_o),
        .occupancy_o(replay_occupancy_o)
    );

    kdlink_v2_packetizer u_packetizer (
        .clk_i(phy_clk_i), .rst_n_i(phy_rst_n_i),
        .valid_i(selected_tx_valid), .header_i(selected_tx_body[607:512]),
        .payload_i(selected_tx_body[511:0]),
        .payload_bytes_i(selected_tx_bytes), .valid_o(packetized_valid),
        .flit_o(packetized_flit)
    );
    assign phy_forward_tx_valid_o = packetized_valid;
    assign phy_forward_tx_flit_o = packetized_flit;

    kdlink_v2_depacketizer u_depacketizer (
        .clk_i(phy_clk_i), .rst_n_i(phy_rst_n_i),
        .valid_i(phy_forward_rx_valid_i), .flit_i(phy_forward_rx_flit_i),
        .valid_o(depacketized_valid), .crc_good_o(depacketized_crc_good),
        .header_o(depacketized_header), .payload_o(depacketized_payload),
        .payload_bytes_o(depacketized_bytes)
    );
    assign rx_fifo_write_data = {depacketized_crc_good, depacketized_header,
        depacketized_payload, depacketized_bytes};

    coll_async_fifo #(.WIDTH(616), .ADDR_W(RX_FIFO_ADDR_BITS)) u_rx_cdc_fifo (
        .write_clk_i(phy_clk_i), .write_rst_n_i(phy_rst_n_i),
        .write_data_i(rx_fifo_write_data), .write_valid_i(depacketized_valid),
        .write_ready_o(rx_fifo_write_ready), .read_clk_i(core_clk_i),
        .read_rst_n_i(core_rst_n_i), .read_data_o(rx_fifo_read_data),
        .read_valid_o(rx_fifo_read_valid), .read_ready_i(rx_fifo_read_ready),
        .overflow_o(rx_fifo_overflow), .underflow_o(rx_fifo_underflow)
    );

    kdlink_v2_rx_commit u_rx_commit (
        .clk_i(core_clk_i), .rst_n_i(core_rst_n_i),
        .local_node_i(local_node_i), .link_epoch_i(link_epoch_i),
        .flit_valid_i(rx_fifo_read_valid), .crc_good_i(rx_fifo_read_data[615]),
        .header_i(rx_fifo_read_data[614:519]),
        .payload_i(rx_fifo_read_data[518:7]),
        .payload_bytes_i(rx_fifo_read_data[6:0]),
        .flit_ready_o(rx_fifo_read_ready), .commit_valid_o(rx_commit_valid_o),
        .commit_ready_i(rx_commit_ready_i), .commit_header_o(rx_commit_header_o),
        .commit_payload_o(rx_commit_payload_o),
        .commit_payload_bytes_o(rx_commit_payload_bytes_o),
        .commit_last_o(rx_commit_last_o), .response_valid_o(response_core_valid),
        .response_ready_i(response_core_ready), .response_type_o(response_core_type),
        .response_vc_o(response_core_vc), .response_plane_o(response_core_plane),
        .response_phase_o(response_core_phase),
        .response_dst_node_o(response_core_destination),
        .response_collective_id_o(response_core_collective),
        .response_packet_seq_o(response_core_sequence),
        .response_credit_total_o(response_core_credit_total),
        .response_status_o(response_core_status), .duplicate_o(duplicate_drop_o),
        .protocol_error_o(commit_protocol_error)
    );

    assign response_fifo_write_data = {response_core_status,
        response_core_credit_total, response_core_sequence,
        response_core_collective, response_core_destination,
        response_core_phase, response_core_plane, response_core_vc,
        response_core_type};
    coll_async_fifo #(.WIDTH(64), .ADDR_W(RESPONSE_FIFO_ADDR_BITS)) u_response_cdc_fifo (
        .write_clk_i(core_clk_i), .write_rst_n_i(core_rst_n_i),
        .write_data_i(response_fifo_write_data),
        .write_valid_i(response_core_valid), .write_ready_o(response_core_ready),
        .read_clk_i(phy_clk_i), .read_rst_n_i(phy_rst_n_i),
        .read_data_o(response_fifo_read_data),
        .read_valid_o(response_fifo_read_valid), .read_ready_i(1'b1),
        .overflow_o(response_fifo_overflow), .underflow_o(response_fifo_underflow)
    );

    kdlink_v2_reverse_ctrl u_reverse_ctrl (
        .clk_i(phy_clk_i), .rst_n_i(phy_rst_n_i), .local_node_i(local_node_i),
        .link_epoch_i(link_epoch_i), .tx_event_valid_i(response_fifo_read_valid),
        .tx_event_ready_o(), .tx_message_type_i(response_fifo_read_data[3:0]),
        .tx_vc_i(response_fifo_read_data[6:4]),
        .tx_plane_id_i(response_fifo_read_data[9:7]),
        .tx_slice_id_i(1'b0), .tx_phase_i(response_fifo_read_data[10]),
        .tx_dst_node_i(response_fifo_read_data[15:11]),
        .tx_collective_id_i(response_fifo_read_data[27:16]),
        .tx_packet_seq_i(response_fifo_read_data[39:28]),
        .tx_credit_delta_i(8'd1),
        .tx_credit_total_i(response_fifo_read_data[55:40]),
        .tx_ack_bitmap_i(16'd0), .tx_status_i(response_fifo_read_data[63:56]),
        .tx_word_valid_o(phy_reverse_tx_valid_o),
        .tx_word_o(phy_reverse_tx_word_o),
        .rx_word_valid_i(phy_reverse_rx_valid_i), .rx_word_ready_o(),
        .rx_word_i(phy_reverse_rx_word_i),
        .rx_message_valid_o(reverse_rx_message_valid),
        .rx_message_type_o(reverse_rx_message_type), .rx_vc_o(reverse_rx_vc),
        .rx_plane_id_o(reverse_rx_plane), .rx_slice_id_o(reverse_rx_slice),
        .rx_phase_o(reverse_rx_phase), .rx_src_node_o(reverse_rx_source),
        .rx_collective_id_o(reverse_rx_collective),
        .rx_packet_seq_o(reverse_rx_sequence),
        .rx_ack_bitmap_o(reverse_rx_ack_bitmap), .rx_status_o(reverse_rx_status),
        .credit_update_valid_o(reverse_credit_valid),
        .ack_valid_o(reverse_ack_valid), .nack_valid_o(reverse_nack_valid),
        .link_reset_valid_o(reverse_link_reset), .init_ack_valid_o(reverse_init_ack),
        .keepalive_ack_valid_o(reverse_keepalive_ack),
        .lane_status_valid_o(reverse_lane_status),
        .credit_totals_o(reverse_credit_totals), .link_up_o(reverse_link_up),
        .crc_error_o(reverse_crc_error), .epoch_error_o(reverse_epoch_error),
        .identity_error_o(reverse_identity_error),
        .protocol_error_o(reverse_protocol_error)
    );

    always @(posedge phy_clk_i or negedge phy_rst_n_i) begin
        if (!phy_rst_n_i) begin
            commit_protocol_sync1_q <= 1'b0;
            commit_protocol_sync2_q <= 1'b0;
            rx_fifo_backpressure_error_q <= 1'b0;
        end else begin
            commit_protocol_sync1_q <= commit_protocol_error;
            commit_protocol_sync2_q <= commit_protocol_sync1_q;
            if (depacketized_valid && !rx_fifo_write_ready)
                rx_fifo_backpressure_error_q <= 1'b1;
        end
    end

    assign credit_error_o = credit_underflow || credit_overflow || credit_stale;
    assign reverse_error_o = reverse_protocol_error || reverse_crc_error ||
        reverse_epoch_error || reverse_identity_error;
    assign protocol_error_o = commit_protocol_sync2_q ||
        rx_fifo_backpressure_error_q;
    assign cdc_error_o = tx_fifo_overflow || tx_fifo_underflow ||
        rx_fifo_overflow || rx_fifo_underflow || response_fifo_overflow ||
        response_fifo_underflow;
endmodule
