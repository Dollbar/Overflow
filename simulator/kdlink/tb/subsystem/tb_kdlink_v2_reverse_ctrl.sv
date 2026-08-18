`timescale 1ns/1ps
module tb_kdlink_v2_reverse_ctrl;
    logic clk;
    logic rst_n;
    logic [7:0] tx_epoch;
    logic tx_event_valid;
    logic [3:0] tx_message_type;
    logic [2:0] tx_vc;
    logic [2:0] tx_plane;
    logic tx_slice;
    logic tx_phase;
    logic [4:0] tx_destination;
    logic [11:0] tx_collective;
    logic [11:0] tx_sequence;
    logic [7:0] tx_credit_delta;
    logic [15:0] tx_credit_total;
    logic [15:0] tx_ack_bitmap;
    logic [7:0] tx_status;
    wire tx_word_valid;
    wire [127:0] tx_word;
    logic loopback_enable;
    logic manual_rx_valid;
    logic [127:0] manual_rx_word;
    wire rx_message_valid;
    wire [3:0] rx_message_type;
    wire [2:0] rx_vc;
    wire [2:0] rx_plane;
    wire rx_slice;
    wire rx_phase;
    wire [4:0] rx_source;
    wire [11:0] rx_collective;
    wire [11:0] rx_sequence;
    wire [15:0] rx_ack_bitmap;
    wire [7:0] rx_status;
    wire credit_update_valid;
    wire ack_valid;
    wire nack_valid;
    wire link_reset_valid;
    wire init_ack_valid;
    wire keepalive_ack_valid;
    wire lane_status_valid;
    wire [127:0] credit_totals;
    wire link_up;
    wire crc_error;
    wire epoch_error;
    wire identity_error;
    wire protocol_error;
    integer received_count;
    integer ack_count;
    integer nack_count;
    integer credit_count;
    integer tx_sequence_count;
    integer tx_gap_count;
    logic sequence_window;
    logic previous_tx_valid;
    logic check_identity_enable;
    integer index;

    kdlink_v2_reverse_ctrl u_tx (
        .clk_i(clk), .rst_n_i(rst_n), .local_node_i(5'd29), .link_epoch_i(tx_epoch),
        .tx_event_valid_i(tx_event_valid), .tx_event_ready_o(),
        .tx_message_type_i(tx_message_type), .tx_vc_i(tx_vc), .tx_plane_id_i(tx_plane),
        .tx_slice_id_i(tx_slice), .tx_phase_i(tx_phase), .tx_dst_node_i(tx_destination),
        .tx_collective_id_i(tx_collective), .tx_packet_seq_i(tx_sequence),
        .tx_credit_delta_i(tx_credit_delta), .tx_credit_total_i(tx_credit_total),
        .tx_ack_bitmap_i(tx_ack_bitmap), .tx_status_i(tx_status),
        .tx_word_valid_o(tx_word_valid), .tx_word_o(tx_word),
        .rx_word_valid_i(1'b0), .rx_word_ready_o(), .rx_word_i(128'd0),
        .rx_message_valid_o(), .rx_message_type_o(), .rx_vc_o(), .rx_plane_id_o(),
        .rx_slice_id_o(), .rx_phase_o(), .rx_src_node_o(), .rx_collective_id_o(),
        .rx_packet_seq_o(), .rx_ack_bitmap_o(), .rx_status_o(),
        .credit_update_valid_o(), .ack_valid_o(), .nack_valid_o(), .link_reset_valid_o(),
        .init_ack_valid_o(), .keepalive_ack_valid_o(), .lane_status_valid_o(),
        .credit_totals_o(), .link_up_o(), .crc_error_o(), .epoch_error_o(),
        .identity_error_o(), .protocol_error_o()
    );

    kdlink_v2_reverse_ctrl u_rx (
        .clk_i(clk), .rst_n_i(rst_n), .local_node_i(5'd3), .link_epoch_i(8'hC9),
        .tx_event_valid_i(1'b0), .tx_event_ready_o(), .tx_message_type_i(4'd0),
        .tx_vc_i(3'd0), .tx_plane_id_i(3'd0), .tx_slice_id_i(1'b0), .tx_phase_i(1'b0),
        .tx_dst_node_i(5'd0), .tx_collective_id_i(12'd0), .tx_packet_seq_i(12'd0),
        .tx_credit_delta_i(8'd0), .tx_credit_total_i(16'd0), .tx_ack_bitmap_i(16'd0),
        .tx_status_i(8'd0), .tx_word_valid_o(), .tx_word_o(),
        .rx_word_valid_i(loopback_enable ? tx_word_valid : manual_rx_valid), .rx_word_ready_o(),
        .rx_word_i(loopback_enable ? tx_word : manual_rx_word),
        .rx_message_valid_o(rx_message_valid), .rx_message_type_o(rx_message_type),
        .rx_vc_o(rx_vc), .rx_plane_id_o(rx_plane), .rx_slice_id_o(rx_slice),
        .rx_phase_o(rx_phase), .rx_src_node_o(rx_source), .rx_collective_id_o(rx_collective),
        .rx_packet_seq_o(rx_sequence), .rx_ack_bitmap_o(rx_ack_bitmap), .rx_status_o(rx_status),
        .credit_update_valid_o(credit_update_valid), .ack_valid_o(ack_valid),
        .nack_valid_o(nack_valid), .link_reset_valid_o(link_reset_valid),
        .init_ack_valid_o(init_ack_valid), .keepalive_ack_valid_o(keepalive_ack_valid),
        .lane_status_valid_o(lane_status_valid), .credit_totals_o(credit_totals),
        .link_up_o(link_up), .crc_error_o(crc_error), .epoch_error_o(epoch_error),
        .identity_error_o(identity_error), .protocol_error_o(protocol_error)
    );

    always #0.5 clk = ~clk;

    always @(posedge clk) begin
        previous_tx_valid <= tx_word_valid;
        if (sequence_window && tx_word_valid) begin
            if ((tx_sequence_count != 0) && !previous_tx_valid) tx_gap_count = tx_gap_count + 1;
            tx_sequence_count = tx_sequence_count + 1;
            if (tx_sequence_count == 8) sequence_window <= 1'b0;
        end
        if (rx_message_valid && check_identity_enable) begin
            if (rx_source != 5'd29 || rx_collective != (12'h600 + received_count[11:0]) ||
                rx_sequence != (12'h100 + received_count[11:0]) || rx_vc != received_count[2:0])
                $fatal(1, "reverse decoded identity mismatch index=%0d", received_count);
            if (received_count < 7 && rx_message_type != received_count[3:0])
                $fatal(1, "reverse message type mismatch index=%0d type=%0d", received_count, rx_message_type);
            if (received_count == 7 && rx_message_type != 4'd0)
                $fatal(1, "reverse final credit type mismatch");
            received_count = received_count + 1;
        end
        if (ack_valid) ack_count = ack_count + 1;
        if (nack_valid) nack_count = nack_count + 1;
        if (credit_update_valid) credit_count = credit_count + 1;
    end

    task automatic drive_event(input [3:0] event_type, input [2:0] event_vc, input [11:0] event_id, input [11:0] event_seq, input [15:0] event_credit);
        begin
            @(negedge clk);
            tx_event_valid = 1'b1;
            tx_message_type = event_type;
            tx_vc = event_vc;
            tx_collective = event_id;
            tx_sequence = event_seq;
            tx_credit_total = event_credit;
            @(negedge clk);
            tx_event_valid = 1'b0;
        end
    endtask

    task automatic forward_one_manual(input [127:0] word);
        begin
            @(negedge clk);
            manual_rx_word = word;
            manual_rx_valid = 1'b1;
            @(negedge clk);
            manual_rx_valid = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tx_epoch = 8'hC9;
        tx_event_valid = 1'b0;
        tx_message_type = 4'd0;
        tx_vc = 3'd0;
        tx_plane = 3'd7;
        tx_slice = 1'b1;
        tx_phase = 1'b1;
        tx_destination = 5'd3;
        tx_collective = 12'hA35;
        tx_sequence = 12'hD91;
        tx_credit_delta = 8'd64;
        tx_credit_total = 16'hACE1;
        tx_ack_bitmap = 16'hA55A;
        tx_status = 8'h5C;
        loopback_enable = 1'b0;
        manual_rx_valid = 1'b0;
        manual_rx_word = 128'd0;
        received_count = 0;
        ack_count = 0;
        nack_count = 0;
        credit_count = 0;
        tx_sequence_count = 0;
        tx_gap_count = 0;
        sequence_window = 1'b0;
        previous_tx_valid = 1'b0;
        check_identity_enable = 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        drive_event(4'd1, 3'd2, 12'hA35, 12'hD91, 16'hACE1);
        wait (tx_word_valid);
        #0.01;
        if (tx_word !== 128'h9c260172956ab385036468d47dc9fa12)
            $fatal(1, "reverse CRC16 known-answer mismatch got=%h", tx_word);
        wait (!tx_word_valid);
        @(negedge clk);

        loopback_enable = 1'b1;
        sequence_window = 1'b1;
        for (index = 0; index < 8; index = index + 1) begin
            tx_event_valid = 1'b1;
            tx_message_type = (index == 7) ? 4'd0 : index[3:0];
            tx_vc = index[2:0];
            tx_plane = index[2:0];
            tx_slice = index[0];
            tx_phase = index[1];
            tx_collective = 12'h600 + index[11:0];
            tx_sequence = 12'h100 + index[11:0];
            tx_credit_delta = 8'h10 + index[7:0];
            tx_credit_total = 16'd100 + index[15:0];
            tx_ack_bitmap = 16'hA55A ^ (16'h003F << index);
            tx_status = 8'h80 + index[7:0];
            @(negedge clk);
        end
        tx_event_valid = 1'b0;
        wait (received_count == 8);
        @(negedge clk);
        if (tx_sequence_count != 8 || tx_gap_count != 0) $fatal(1, "reverse II=1 failure outputs=%0d gaps=%0d", tx_sequence_count, tx_gap_count);
        if (ack_count != 1 || nack_count != 1 || credit_count != 4) $fatal(1, "reverse classification counts ack=%0d nack=%0d credit=%0d", ack_count, nack_count, credit_count);
        if (!link_up) $fatal(1, "INIT_ACK did not transition link up");
        if (credit_totals[0*16 +: 16] != 16'd0 || credit_totals[1*16 +: 16] != 16'd0 ||
            credit_totals[2*16 +: 16] != 16'd0 || credit_totals[7*16 +: 16] != 16'd107)
            $fatal(1, "link reset or cumulative credit mismatch %h", credit_totals);
        if (protocol_error) $fatal(1, "unexpected reverse protocol error before fault tests");

        check_identity_enable = 1'b0;
        for (index = 0; index < 8; index = index + 1) begin
            tx_event_valid = 1'b1;
            tx_message_type = 4'd0;
            tx_vc = index[2:0];
            tx_plane = 3'd7 - index[2:0];
            tx_slice = ~index[0];
            tx_phase = ~index[1];
            tx_collective = 12'h680 + index[11:0];
            tx_sequence = 12'h180 + index[11:0];
            tx_credit_delta = 8'hE0 - index[7:0];
            tx_credit_total = 16'd200 + index[15:0];
            tx_ack_bitmap = 16'h5AA5 ^ (16'h00F0 << index);
            tx_status = 8'h40 + index[7:0];
            @(negedge clk);
        end
        tx_event_valid = 1'b0;
        wait (credit_count == 12);
        @(negedge clk);
        for (index = 0; index < 8; index = index + 1)
            if (credit_totals[index*16 +: 16] != (16'd200 + index[15:0])) $fatal(1, "VC%0d cumulative credit mismatch", index);

        for (index = 0; index < 8; index = index + 1) begin
            tx_event_valid = 1'b1;
            tx_message_type = 4'd0;
            tx_vc = index[2:0];
            tx_plane = 3'd7;
            tx_slice = 1'b1;
            tx_phase = 1'b1;
            tx_collective = 12'hFFF;
            tx_sequence = 12'hFFF;
            tx_credit_delta = 8'hFF;
            tx_credit_total = 16'hFFFF;
            tx_ack_bitmap = 16'hFFFF;
            tx_status = 8'hFF;
            @(negedge clk);
        end
        for (index = 0; index < 8; index = index + 1) begin
            tx_event_valid = 1'b1;
            tx_message_type = 4'd0;
            tx_vc = index[2:0];
            tx_plane = 3'd0;
            tx_slice = 1'b0;
            tx_phase = 1'b0;
            tx_collective = 12'h000;
            tx_sequence = 12'h000;
            tx_credit_delta = 8'h00;
            tx_credit_total = 16'h0000;
            tx_ack_bitmap = 16'h0000;
            tx_status = 8'h00;
            @(negedge clk);
        end
        tx_event_valid = 1'b0;
        wait (credit_count == 28);
        @(negedge clk);
        if (credit_totals != 128'd0) $fatal(1, "all-VC full-range credit toggle sequence did not return to zero");

        loopback_enable = 1'b0;
        forward_one_manual(tx_word ^ (128'd1 << 77));
        wait (crc_error);
        @(negedge clk);

        tx_epoch = 8'hC8;
        drive_event(4'd0, 3'd0, 12'h700, 12'h200, 16'd200);
        wait (tx_word_valid);
        manual_rx_word = tx_word;
        forward_one_manual(manual_rx_word);
        wait (epoch_error);
        @(negedge clk);

        tx_epoch = 8'hC9;
        tx_destination = 5'd4;
        drive_event(4'd0, 3'd0, 12'h701, 12'h201, 16'd201);
        wait (tx_word_valid);
        manual_rx_word = tx_word;
        forward_one_manual(manual_rx_word);
        wait (identity_error);
        if (!protocol_error) $fatal(1, "fault tests did not set sticky protocol error");

        $display("TB_KDLINK_V2_REVERSE_CTRL_PASS messages=%0d vcs=8 types=7 tx_gaps=%0d crc_kat=PASS crc_fault=PASS epoch_reject=PASS identity_reject=PASS", received_count, tx_gap_count);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "KDLink-v2 reverse control timeout");
    end
endmodule
