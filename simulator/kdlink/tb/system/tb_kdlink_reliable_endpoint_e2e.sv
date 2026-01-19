`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_reliable_endpoint_e2e;
    localparam integer PACKETS = 4095;
    localparam integer FAULT_SEQUENCE = 0;
    localparam integer ACK_DROP_SEQUENCE = 4094;
    localparam integer DUPLICATE_SEQUENCE = 4093;
    logic phy_clk;
    logic core_a_clk;
    logic core_b_clk;
    logic rst_n;
    logic admin_up;
    logic training;
    logic marker;
    logic [15:0] marker_sequence;

    logic a_tx_valid;
    wire a_tx_ready;
    logic [95:0] a_tx_header;
    logic [511:0] a_tx_payload;
    logic [6:0] a_tx_bytes;
    logic b_tx_valid;
    wire b_tx_ready;
    logic [95:0] b_tx_header;
    logic [511:0] b_tx_payload;
    logic [6:0] b_tx_bytes;

    wire a_commit_valid;
    wire [95:0] a_commit_header;
    wire [511:0] a_commit_payload;
    wire a_commit_last;
    wire b_commit_valid;
    wire [95:0] b_commit_header;
    wire [511:0] b_commit_payload;
    wire b_commit_last;

    wire a_forward_valid;
    wire [639:0] a_forward_flit;
    wire [639:0] a_forward_flit_faulted;
    wire b_forward_valid;
    wire [639:0] b_forward_flit;
    wire a_reverse_valid;
    wire [127:0] a_reverse_word;
    wire b_reverse_valid;
    wire [127:0] b_reverse_word;
    wire a_reverse_rx_valid;
    wire [127:0] a_reverse_rx_word;
    wire b_reverse_rx_valid;
    wire [127:0] b_reverse_rx_word;

    wire a_pcs_blocks_valid;
    wire [659:0] a_pcs_blocks;
    wire b_pcs_blocks_valid;
    wire [659:0] b_pcs_blocks;
    wire [9:0] a_pcs_rx_lane_valid;
    wire [659:0] a_pcs_rx_lane_blocks;
    wire [9:0] b_pcs_rx_lane_valid;
    wire [659:0] b_pcs_rx_lane_blocks;
    wire a_pcs_rx_flit_valid;
    wire [639:0] a_pcs_rx_flit;
    wire b_pcs_rx_flit_valid;
    wire [639:0] b_pcs_rx_flit;
    wire a_block_lock;
    wire a_deskew_lock;
    wire b_block_lock;
    wire b_deskew_lock;
    wire a_block_error;
    wire a_deskew_overflow;
    wire b_block_error;
    wire b_deskew_overflow;
    wire full_duplex_up;
    logic inject_forward_crc_fault;
    logic fault_armed;
    logic ack_drop_armed;
    wire drop_b_to_a_ack;

    wire [127:0] a_credits;
    wire [127:0] b_credits;
    wire [9:0] a_replay_occupancy;
    wire [9:0] b_replay_occupancy;
    wire a_retry_exhausted;
    wire b_retry_exhausted;
    wire a_duplicate;
    wire b_duplicate;
    wire a_credit_error;
    wire b_credit_error;
    wire a_reverse_error;
    wire b_reverse_error;
    wire a_protocol_error;
    wire b_protocol_error;
    wire a_cdc_error;
    wire b_cdc_error;
    wire a_link_up;
    wire b_link_up;

    bit [PACKETS-1:0] a_seen;
    bit [PACKETS-1:0] b_seen;
    integer a_commit_count;
    integer b_commit_count;
    integer a_replay_seen;
    integer b_replay_seen;
    integer zero_credit_seen;
    integer a_duplicate_seen;
    integer b_duplicate_seen;
    integer ack_drop_seen;
    integer timeout_replay_seen;
    integer ack_sequence_tx_count;
    integer source_index_a;
    integer source_index_b;
    integer timeout_count;
    integer check_index;
    integer credit_index;
    integer commits_before_hop_reject;

    always #0.5 phy_clk = ~phy_clk;
    always #0.7 core_a_clk = ~core_a_clk;
    always #0.8 core_b_clk = ~core_b_clk;
    assign a_forward_flit_faulted = inject_forward_crc_fault ?
        (a_forward_flit ^ 640'd1) : a_forward_flit;
    assign drop_b_to_a_ack = ack_drop_armed && b_reverse_valid &&
        (b_reverse_word[7:4] == `KDL_REVERSE_TYPE_ACK) &&
        (b_reverse_word[57:46] == ACK_DROP_SEQUENCE[11:0]);

    kdlink_reliable_endpoint #(
        .INITIAL_CREDITS(8), .REPLAY_SLOT_BITS(9)
    ) u_endpoint_a (
        .core_clk_i(core_a_clk), .core_rst_n_i(rst_n),
        .phy_clk_i(phy_clk), .phy_rst_n_i(rst_n),
        .local_node_i(5'd0), .peer_node_i(5'd1), .local_slice_i(1'b0),
        .link_enable_i(1'b1), .tx_service_grant_i(1'b1),
        .reverse_service_grant_i(1'b1),
        .link_epoch_i(8'h2a),
        .tx_valid_i(a_tx_valid), .tx_ready_o(a_tx_ready),
        .tx_header_i(a_tx_header), .tx_payload_i(a_tx_payload),
        .tx_payload_bytes_i(a_tx_bytes), .rx_commit_valid_o(a_commit_valid),
        .rx_commit_ready_i(1'b1), .rx_commit_header_o(a_commit_header),
        .rx_commit_payload_o(a_commit_payload), .rx_commit_payload_bytes_o(),
        .rx_commit_last_o(a_commit_last),
        .phy_forward_tx_valid_o(a_forward_valid),
        .phy_forward_tx_flit_o(a_forward_flit),
        .phy_forward_rx_valid_i(a_pcs_rx_flit_valid),
        .phy_forward_rx_flit_i(a_pcs_rx_flit),
        .phy_reverse_tx_valid_o(a_reverse_valid),
        .phy_reverse_tx_word_o(a_reverse_word),
        .phy_reverse_rx_valid_i(a_reverse_rx_valid),
        .phy_reverse_rx_word_i(a_reverse_rx_word),
        .tx_credit_count_o(a_credits), .replay_occupancy_o(a_replay_occupancy),
        .link_up_o(a_link_up), .link_state_o(), .replay_timeout_o(),
        .tx_service_request_o(), .reverse_service_request_o(),
        .retry_exhausted_o(a_retry_exhausted), .duplicate_drop_o(a_duplicate),
        .credit_error_o(a_credit_error), .reverse_error_o(a_reverse_error),
        .protocol_error_o(a_protocol_error), .cdc_error_o(a_cdc_error)
    );

    kdlink_reliable_endpoint #(
        .INITIAL_CREDITS(8), .REPLAY_SLOT_BITS(9)
    ) u_endpoint_b (
        .core_clk_i(core_b_clk), .core_rst_n_i(rst_n),
        .phy_clk_i(phy_clk), .phy_rst_n_i(rst_n),
        .local_node_i(5'd1), .peer_node_i(5'd0), .local_slice_i(1'b0),
        .link_enable_i(1'b1), .tx_service_grant_i(1'b1),
        .reverse_service_grant_i(1'b1),
        .link_epoch_i(8'h2a),
        .tx_valid_i(b_tx_valid), .tx_ready_o(b_tx_ready),
        .tx_header_i(b_tx_header), .tx_payload_i(b_tx_payload),
        .tx_payload_bytes_i(b_tx_bytes), .rx_commit_valid_o(b_commit_valid),
        .rx_commit_ready_i(1'b1), .rx_commit_header_o(b_commit_header),
        .rx_commit_payload_o(b_commit_payload), .rx_commit_payload_bytes_o(),
        .rx_commit_last_o(b_commit_last),
        .phy_forward_tx_valid_o(b_forward_valid),
        .phy_forward_tx_flit_o(b_forward_flit),
        .phy_forward_rx_valid_i(b_pcs_rx_flit_valid),
        .phy_forward_rx_flit_i(b_pcs_rx_flit),
        .phy_reverse_tx_valid_o(b_reverse_valid),
        .phy_reverse_tx_word_o(b_reverse_word),
        .phy_reverse_rx_valid_i(b_reverse_rx_valid),
        .phy_reverse_rx_word_i(b_reverse_rx_word),
        .tx_credit_count_o(b_credits), .replay_occupancy_o(b_replay_occupancy),
        .link_up_o(b_link_up), .link_state_o(), .replay_timeout_o(),
        .tx_service_request_o(), .reverse_service_request_o(),
        .retry_exhausted_o(b_retry_exhausted), .duplicate_drop_o(b_duplicate),
        .credit_error_o(b_credit_error), .reverse_error_o(b_reverse_error),
        .protocol_error_o(b_protocol_error), .cdc_error_o(b_cdc_error)
    );

    kdlink_pcs u_pcs_a (
        .clk_i(phy_clk), .rst_n_i(rst_n), .tx_flit_valid_i(a_forward_valid),
        .tx_flit_i(a_forward_flit_faulted), .tx_training_i(training),
        .tx_alignment_marker_i(marker), .tx_marker_sequence_i(marker_sequence),
        .tx_blocks_valid_o(a_pcs_blocks_valid), .tx_blocks_o(a_pcs_blocks),
        .rx_lane_valid_i(a_pcs_rx_lane_valid),
        .rx_lane_blocks_i(a_pcs_rx_lane_blocks),
        .rx_flit_valid_o(a_pcs_rx_flit_valid), .rx_flit_o(a_pcs_rx_flit),
        .rx_block_lock_o(a_block_lock), .rx_deskew_locked_o(a_deskew_lock),
        .rx_block_error_o(a_block_error),
        .rx_deskew_overflow_o(a_deskew_overflow)
    );

    kdlink_pcs u_pcs_b (
        .clk_i(phy_clk), .rst_n_i(rst_n), .tx_flit_valid_i(b_forward_valid),
        .tx_flit_i(b_forward_flit), .tx_training_i(training),
        .tx_alignment_marker_i(marker), .tx_marker_sequence_i(marker_sequence),
        .tx_blocks_valid_o(b_pcs_blocks_valid), .tx_blocks_o(b_pcs_blocks),
        .rx_lane_valid_i(b_pcs_rx_lane_valid),
        .rx_lane_blocks_i(b_pcs_rx_lane_blocks),
        .rx_flit_valid_o(b_pcs_rx_flit_valid), .rx_flit_o(b_pcs_rx_flit),
        .rx_block_lock_o(b_block_lock), .rx_deskew_locked_o(b_deskew_lock),
        .rx_block_error_o(b_block_error),
        .rx_deskew_overflow_o(b_deskew_overflow)
    );

    kdlink_v2_serdes_link_model #(
        .PROPAGATION_CYCLES(4), .MAX_LANE_SKEW_CYCLES(2),
        .TRAINING_CYCLES(8)
    ) u_forward_link (
        .clk_i(phy_clk), .rst_n_i(rst_n), .admin_up_i(admin_up),
        .a_to_b_lane_up_i(10'h3ff), .b_to_a_lane_up_i(10'h3ff),
        .a_tx_group_valid_i(a_pcs_blocks_valid),
        .a_tx_group_blocks_i(a_pcs_blocks),
        .b_tx_group_valid_i(b_pcs_blocks_valid),
        .b_tx_group_blocks_i(b_pcs_blocks),
        .inject_a_to_b_drop_i(10'd0),
        .inject_a_to_b_corrupt_i(10'd0),
        .inject_b_to_a_drop_i(10'd0), .inject_b_to_a_corrupt_i(10'd0),
        .ber_period_groups_i(32'd0), .ber_lane_i(4'd0),
        .a_rx_lane_valid_o(a_pcs_rx_lane_valid),
        .a_rx_lane_blocks_o(a_pcs_rx_lane_blocks),
        .b_rx_lane_valid_o(b_pcs_rx_lane_valid),
        .b_rx_lane_blocks_o(b_pcs_rx_lane_blocks), .a_to_b_state_o(),
        .b_to_a_state_o(), .full_duplex_up_o(full_duplex_up),
        .a_to_b_groups_o(), .b_to_a_groups_o(), .dropped_blocks_o(),
        .corrupted_blocks_o()
    );

    kdlink_reverse_channel_model #(.PROPAGATION_CYCLES(4)) u_reverse_link (
        .clk_i(phy_clk), .rst_n_i(rst_n),
        .a_tx_valid_i(a_reverse_valid), .a_tx_word_i(a_reverse_word),
        .b_tx_valid_i(b_reverse_valid), .b_tx_word_i(b_reverse_word),
        .inject_a_to_b_corrupt_i(1'b0), .inject_b_to_a_corrupt_i(1'b0),
        .inject_a_to_b_drop_i(1'b0), .inject_b_to_a_drop_i(drop_b_to_a_ack),
        .a_rx_valid_o(a_reverse_rx_valid), .a_rx_word_o(a_reverse_rx_word),
        .b_rx_valid_o(b_reverse_rx_valid), .b_rx_word_o(b_reverse_rx_word)
    );

    always @(negedge phy_clk) begin
        inject_forward_crc_fault <= 1'b0;
        if (rst_n && fault_armed && a_forward_valid && a_deskew_lock &&
            b_deskew_lock && !training && !marker) begin
            inject_forward_crc_fault <= 1'b1;
            fault_armed <= 1'b0;
        end
    end

    always @(posedge phy_clk) begin
        if (rst_n && drop_b_to_a_ack) begin
            ack_drop_armed <= 1'b0;
            ack_drop_seen <= ack_drop_seen + 1;
        end
        if (rst_n && b_reverse_valid &&
            (b_reverse_word[7:4] == `KDL_REVERSE_TYPE_ACK) &&
            (b_reverse_word[57:46] == ACK_DROP_SEQUENCE[11:0]))
            ack_sequence_tx_count <= ack_sequence_tx_count + 1;
        if (rst_n && a_forward_valid && a_forward_flit[531] &&
            (a_forward_flit[593:582] == FAULT_SEQUENCE[11:0]))
            a_replay_seen <= a_replay_seen + 1;
        if (rst_n && a_forward_valid && a_forward_flit[531] &&
            (a_forward_flit[593:582] == ACK_DROP_SEQUENCE[11:0]))
            timeout_replay_seen <= timeout_replay_seen + 1;
        if (rst_n && b_forward_valid && b_forward_flit[531])
            b_replay_seen <= b_replay_seen + 1;
        for (credit_index = 0; credit_index < 8; credit_index = credit_index + 1)
            if (a_credits[credit_index*16 +: 16] == 16'd0 ||
                b_credits[credit_index*16 +: 16] == 16'd0)
                zero_credit_seen <= 1;
        if (a_deskew_overflow || b_deskew_overflow)
            $fatal(1, "PCS deskew overflow");
    end

    always @(posedge core_a_clk) begin
        if (rst_n && a_commit_valid && a_commit_last) begin
            if (a_commit_payload[39:32] != 8'hb0 ||
                a_commit_payload[31:0] != {20'd0, a_commit_header[81:70]})
                $fatal(1, "A commit payload mismatch seq=%0d",
                    a_commit_header[81:70]);
            if (a_seen[a_commit_header[81:70]])
                $fatal(1, "A duplicate commit seq=%0d", a_commit_header[81:70]);
            a_seen[a_commit_header[81:70]] <= 1'b1;
            a_commit_count <= a_commit_count + 1;
        end
        if (a_duplicate) a_duplicate_seen <= 1;
    end

    always @(posedge core_b_clk) begin
        if (rst_n && b_commit_valid && b_commit_last) begin
            if (b_commit_payload[39:32] != 8'ha0 ||
                b_commit_payload[31:0] != {20'd0, b_commit_header[81:70]})
                $fatal(1, "B commit payload mismatch seq=%0d",
                    b_commit_header[81:70]);
            if (b_seen[b_commit_header[81:70]])
                $fatal(1, "B duplicate commit seq=%0d", b_commit_header[81:70]);
            b_seen[b_commit_header[81:70]] <= 1'b1;
            b_commit_count <= b_commit_count + 1;
        end
        if (b_duplicate) b_duplicate_seen <= 1;
    end

    initial begin
        phy_clk = 1'b0;
        core_a_clk = 1'b0;
        core_b_clk = 1'b0;
        rst_n = 1'b0;
        admin_up = 1'b0;
        training = 1'b0;
        marker = 1'b0;
        marker_sequence = 16'h31a5;
        inject_forward_crc_fault = 1'b0;
        fault_armed = 1'b1;
        ack_drop_armed = 1'b1;
        a_tx_valid = 1'b0;
        a_tx_header = 96'd0;
        a_tx_payload = 512'd0;
        a_tx_bytes = 7'd64;
        b_tx_valid = 1'b0;
        b_tx_header = 96'd0;
        b_tx_payload = 512'd0;
        b_tx_bytes = 7'd64;
        a_seen = '0;
        b_seen = '0;
        a_commit_count = 0;
        b_commit_count = 0;
        a_replay_seen = 0;
        b_replay_seen = 0;
        zero_credit_seen = 0;
        a_duplicate_seen = 0;
        b_duplicate_seen = 0;
        ack_drop_seen = 0;
        timeout_replay_seen = 0;
        ack_sequence_tx_count = 0;
        commits_before_hop_reject = 0;
        repeat (12) @(posedge phy_clk);
        @(negedge phy_clk); rst_n = 1'b1; admin_up = 1'b1;
        wait (full_duplex_up);
        repeat (20) begin
            @(negedge phy_clk); training = 1'b1;
        end
        @(negedge phy_clk); training = 1'b0;
        repeat (4) begin
            @(negedge phy_clk); marker = 1'b1;
        end
        @(negedge phy_clk); marker = 1'b0;
        wait (a_block_lock && a_deskew_lock && b_block_lock && b_deskew_lock);
        wait (a_link_up && b_link_up);

        fork
            begin
                for (source_index_a = 0; source_index_a < PACKETS;
                     source_index_a = source_index_a + 1) begin
                    @(negedge core_a_clk);
                    a_tx_header = 96'd0;
                    a_tx_header[7:4] = (source_index_a[2:0] <= 3'd4 ||
                        source_index_a[2:0] == 3'd6) ? 4'd0 :
                        (source_index_a[2:0] == 3'd5) ? 4'd1 : 4'd4;
                    a_tx_header[10:8] = 3'd2;
                    a_tx_header[12:11] = source_index_a[1:0];
                    a_tx_header[15:13] = (source_index_a[2:0] == 3'd6) ?
                        3'd4 : source_index_a[2:0];
                    a_tx_header[16] = source_index_a[0];
                    a_tx_header[17] = 1'b1;
                    a_tx_header[18] = 1'b1;
                    a_tx_header[19] = 1'b0;
                    a_tx_header[24:20] = 5'd0;
                    a_tx_header[29:25] = 5'd1;
                    a_tx_header[32:30] = source_index_a[2:0];
                    a_tx_header[37:33] = source_index_a[4:0] | 5'd1;
                    a_tx_header[45:38] = 8'h2a;
                    a_tx_header[57:46] = 12'h510 ^ {source_index_a[5:0], ~source_index_a[5:0]};
                    a_tx_header[69:58] = source_index_a[11:0] ^ {~source_index_a[5:0], source_index_a[5:0]};
                    a_tx_header[81:70] = source_index_a[11:0];
                    a_tx_header[87:82] = 6'd0;
                    a_tx_bytes = {1'b0, source_index_a[5:0]} + 7'd1;
                    a_tx_payload = 512'd0;
                    a_tx_payload[31:0] = source_index_a;
                    a_tx_payload[39:32] = 8'ha0;
                    a_tx_valid = 1'b1;
                    @(posedge core_a_clk);
                    while (!a_tx_ready) @(posedge core_a_clk);
                end
                @(negedge core_a_clk); a_tx_valid = 1'b0;
            end
            begin
                for (source_index_b = 0; source_index_b < PACKETS;
                     source_index_b = source_index_b + 1) begin
                    @(negedge core_b_clk);
                    b_tx_header = 96'd0;
                    b_tx_header[7:4] = (source_index_b[2:0] <= 3'd4 ||
                        source_index_b[2:0] == 3'd6) ? 4'd0 :
                        (source_index_b[2:0] == 3'd5) ? 4'd1 : 4'd4;
                    b_tx_header[10:8] = 3'd2;
                    b_tx_header[12:11] = source_index_b[1:0];
                    b_tx_header[15:13] = (source_index_b[2:0] == 3'd6) ?
                        3'd4 : source_index_b[2:0];
                    b_tx_header[16] = source_index_b[0];
                    b_tx_header[17] = 1'b1;
                    b_tx_header[18] = 1'b1;
                    b_tx_header[19] = 1'b0;
                    b_tx_header[24:20] = 5'd1;
                    b_tx_header[29:25] = 5'd0;
                    b_tx_header[32:30] = source_index_b[2:0];
                    b_tx_header[37:33] = source_index_b[4:0] | 5'd1;
                    b_tx_header[45:38] = 8'h2a;
                    b_tx_header[57:46] = 12'ha20 ^ {~source_index_b[5:0], source_index_b[5:0]};
                    b_tx_header[69:58] = source_index_b[11:0] ^ {source_index_b[5:0], ~source_index_b[5:0]};
                    b_tx_header[81:70] = source_index_b[11:0];
                    b_tx_header[87:82] = 6'd0;
                    b_tx_bytes = 7'd64 - {1'b0, source_index_b[5:0]};
                    b_tx_payload = 512'd0;
                    b_tx_payload[31:0] = source_index_b;
                    b_tx_payload[39:32] = 8'hb0;
                    b_tx_valid = 1'b1;
                    @(posedge core_b_clk);
                    while (!b_tx_ready) @(posedge core_b_clk);
                end
                @(negedge core_b_clk); b_tx_valid = 1'b0;
            end
        join

        timeout_count = 0;
        while ((a_commit_count < PACKETS || b_commit_count < PACKETS) &&
               timeout_count < 30000) begin
            @(posedge phy_clk);
            timeout_count = timeout_count + 1;
        end
        if (a_commit_count != PACKETS || b_commit_count != PACKETS)
            $fatal(1, "E2E commit timeout A=%0d B=%0d", a_commit_count,
                b_commit_count);

        @(negedge core_a_clk);
        a_tx_header = 96'd0;
        a_tx_header[7:4] = (DUPLICATE_SEQUENCE[2:0] <= 3'd4 ||
            DUPLICATE_SEQUENCE[2:0] == 3'd6) ? 4'd0 :
            (DUPLICATE_SEQUENCE[2:0] == 3'd5) ? 4'd1 : 4'd4;
        a_tx_header[10:8] = 3'd2;
        a_tx_header[12:11] = DUPLICATE_SEQUENCE[1:0];
        a_tx_header[15:13] = (DUPLICATE_SEQUENCE[2:0] == 3'd6) ?
            3'd4 : DUPLICATE_SEQUENCE[2:0];
        a_tx_header[16] = DUPLICATE_SEQUENCE[0];
        a_tx_header[17] = 1'b1;
        a_tx_header[18] = 1'b1;
        a_tx_header[24:20] = 5'd0;
        a_tx_header[29:25] = 5'd1;
        a_tx_header[32:30] = DUPLICATE_SEQUENCE[2:0];
        a_tx_header[37:33] = DUPLICATE_SEQUENCE[4:0] | 5'd1;
        a_tx_header[45:38] = 8'h2a;
        a_tx_header[57:46] = 12'h510 ^ {DUPLICATE_SEQUENCE[5:0], ~DUPLICATE_SEQUENCE[5:0]};
        a_tx_header[69:58] = DUPLICATE_SEQUENCE[11:0] ^ {~DUPLICATE_SEQUENCE[5:0], DUPLICATE_SEQUENCE[5:0]};
        a_tx_header[81:70] = DUPLICATE_SEQUENCE[11:0];
        a_tx_header[87:82] = 6'd0;
        a_tx_bytes = {1'b0, DUPLICATE_SEQUENCE[5:0]} + 7'd1;
        a_tx_payload = 512'd0;
        a_tx_payload[31:0] = DUPLICATE_SEQUENCE;
        a_tx_payload[39:32] = 8'ha0;
        a_tx_valid = 1'b1;
        @(posedge core_a_clk);
        while (!a_tx_ready) @(posedge core_a_clk);
        @(negedge core_a_clk); a_tx_valid = 1'b0;

        timeout_count = 0;
        while (((a_duplicate_seen == 0 && b_duplicate_seen == 0) ||
                a_replay_occupancy != 0 ||
                b_replay_occupancy != 0) && timeout_count < 20000) begin
            @(posedge phy_clk);
            timeout_count = timeout_count + 1;
        end
        repeat (20) @(posedge phy_clk);
        for (check_index = 0; check_index < PACKETS; check_index = check_index + 1)
            if (!a_seen[check_index] || !b_seen[check_index])
                $fatal(1, "E2E scoreboard missing sequence %0d", check_index);
        if (a_commit_count != PACKETS || b_commit_count != PACKETS ||
            a_replay_seen != 1 || b_replay_seen != 0 ||
            ack_drop_seen != 1 || timeout_replay_seen != 1 ||
            zero_credit_seen == 0 ||
            (a_duplicate_seen == 0 && b_duplicate_seen == 0) ||
            a_replay_occupancy != 0 || b_replay_occupancy != 0 ||
            a_retry_exhausted || b_retry_exhausted || a_credit_error ||
            b_credit_error || a_reverse_error || b_reverse_error ||
            a_protocol_error || b_protocol_error || a_cdc_error || b_cdc_error)
            $fatal(1, "E2E final failure commits=%0d/%0d replay=%0d/%0d ack_drop=%0d ack_tx=%0d timeout_replay=%0d zero=%0d duplicate=%0d occupancy=%0d/%0d errors=%b%b%b%b%b%b",
                a_commit_count, b_commit_count, a_replay_seen, b_replay_seen,
                ack_drop_seen, ack_sequence_tx_count, timeout_replay_seen, zero_credit_seen,
                ((a_duplicate_seen != 0) || (b_duplicate_seen != 0)),
                a_replay_occupancy,
                b_replay_occupancy, a_credit_error, b_credit_error,
                a_reverse_error, b_reverse_error, a_cdc_error, b_cdc_error);

        commits_before_hop_reject = b_commit_count;
        @(negedge core_a_clk);
        a_tx_header = 96'd0;
        a_tx_header[3:0] = `KDL_SCHEMA_VERSION;
        a_tx_header[7:4] = `KDL_MESSAGE_TYPE_DATA;
        a_tx_header[10:8] = `KDL_OPCODE_POINT_TO_POINT;
        a_tx_header[12:11] = 2'd0;
        a_tx_header[15:13] = `KDL_VC_ROLE_POINT_TO_POINT;
        a_tx_header[17] = 1'b1;
        a_tx_header[18] = 1'b1;
        a_tx_header[24:20] = 5'd0;
        a_tx_header[29:25] = 5'd1;
        a_tx_header[32:30] = 3'd0;
        a_tx_header[37:33] = 5'd0;
        a_tx_header[45:38] = 8'h2a;
        a_tx_header[57:46] = 12'h5f0;
        a_tx_header[69:58] = 12'd100;
        a_tx_header[81:70] = 12'd100;
        a_tx_header[87:82] = 6'd0;
        a_tx_bytes = 7'd64;
        a_tx_payload = 512'd0;
        a_tx_payload[31:0] = 32'hbad0_0000;
        a_tx_valid = 1'b1;
        @(posedge core_a_clk);
        while (!a_tx_ready) @(posedge core_a_clk);
        @(negedge core_a_clk); a_tx_valid = 1'b0;
        timeout_count = 0;
        while (!b_protocol_error && timeout_count < 5000) begin
            @(posedge phy_clk);
            timeout_count = timeout_count + 1;
        end
        repeat (20) @(posedge phy_clk);
        if (!b_protocol_error || b_commit_count != commits_before_hop_reject)
            $fatal(1, "hop-limit-zero packet was not rejected error=%b commits=%0d/%0d",
                b_protocol_error, b_commit_count, commits_before_hop_reject);
        @(negedge phy_clk); rst_n = 1'b0;
        repeat (12) @(posedge phy_clk);
        #0.01;
        if (a_link_up || b_link_up || a_replay_occupancy != 0 ||
            b_replay_occupancy != 0 || a_retry_exhausted ||
            b_retry_exhausted || a_credit_error || b_credit_error ||
            a_reverse_error || b_reverse_error || a_protocol_error ||
            b_protocol_error || a_cdc_error || b_cdc_error)
            $fatal(1, "runtime reset did not restore safe endpoint state");
        $display("TB_KDLINK_RELIABLE_ENDPOINT_E2E_PASS packets_per_direction=%0d vcs=8 autonomous_link=1 autonomous_nack=1 replay=1 ack_loss_timeout_replay=1 reverse_drop=1 exact_once=1 cumulative_credit=1 cdc=1 pcs=1 digital_serdes=1 hop_limit_zero_reject=1 runtime_reset=1",
            PACKETS);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "KDLink reliable endpoint E2E timeout");
    end
endmodule
