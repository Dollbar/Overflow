`timescale 1ns/1ps
module tb_kdlink_multiboard_e2e;
    localparam integer NORMAL_PACKETS = 8;
    localparam integer FAULT_SEQUENCE = 3;
    localparam integer TRAINING_GROUPS = 24;
    logic clk;
    logic rst_n;
    logic admin_up;
    logic tx_source_valid;
    logic [95:0] tx_source_header;
    logic [511:0] tx_source_payload;
    logic [6:0] tx_source_bytes;
    wire tx_packet_valid;
    wire [639:0] tx_packet_flit;
    wire [607:0] replay_store_body;
    wire replay_store_ready;
    wire replay_valid;
    wire replay_last;
    wire [607:0] replay_body;
    wire [3:0] replay_occupancy;
    wire replay_retry_exhausted;
    logic replay_store_start;
    logic replay_store_valid;
    logic replay_store_last;
    logic ack_valid;
    logic [11:0] ack_collective_id;
    logic ack_phase;
    logic [11:0] ack_packet_seq;
    logic nack_valid;
    logic [11:0] nack_collective_id;
    logic nack_phase;
    logic [11:0] nack_packet_seq;
    wire packetizer_input_valid;
    wire [95:0] packetizer_input_header;
    wire [511:0] packetizer_input_payload;
    wire [6:0] packetizer_input_bytes;
    wire pcs_a_blocks_valid;
    wire [659:0] pcs_a_blocks;
    wire [9:0] pcs_b_lane_valid;
    wire [659:0] pcs_b_lane_blocks;
    wire pcs_b_flit_valid;
    wire [639:0] pcs_b_flit;
    wire pcs_b_block_lock;
    wire pcs_b_deskew_lock;
    wire pcs_b_block_error;
    wire pcs_b_deskew_overflow;
    wire [1:0] a_to_b_state;
    wire [1:0] b_to_a_state;
    wire full_duplex_up;
    wire [31:0] dropped_blocks;
    wire [31:0] corrupted_blocks;
    wire [31:0] a_to_b_groups;
    wire [31:0] b_to_a_groups;
    wire rx_codec_valid;
    wire rx_crc_good;
    wire [95:0] rx_header;
    wire [511:0] rx_payload;
    wire [6:0] rx_payload_bytes;
    wire [639:0] tx_flit_for_pcs;
    wire inject_logical_corruption;
    integer source_index;
    integer check_index;
    integer good_count;
    integer bad_count;
    integer replay_count;
    integer idle_cycles;
    integer observed_sequence;
    logic [NORMAL_PACKETS-1:0] good_seen;
    logic [NORMAL_PACKETS-1:0] retry_seen;
    logic marker_active;
    logic training_active;
    logic tx_data_active;
    logic source_done;
    logic nack_pending;
    logic nack_consumed;
    logic [11:0] nack_sequence_q;

    assign replay_store_body = {tx_source_header, tx_source_payload};
    assign packetizer_input_valid = replay_valid || tx_source_valid;
    assign packetizer_input_header = replay_valid ? replay_body[607:512] : tx_source_header;
    assign packetizer_input_payload = replay_valid ? replay_body[511:0] : tx_source_payload;
    assign packetizer_input_bytes = replay_valid ? replay_body[606:600] : tx_source_bytes;
    assign tx_flit_for_pcs = inject_logical_corruption ?
        (tx_packet_flit ^ (640'd1 << 32)) : tx_packet_flit;
    assign inject_logical_corruption = tx_packet_valid &&
        (tx_packet_flit[512 + 70 +: 12] == FAULT_SEQUENCE[11:0]) &&
        !tx_packet_flit[512 + 19];

    kdlink_packetizer u_packetizer (
        .clk_i(clk), .rst_n_i(rst_n), .valid_i(packetizer_input_valid),
        .header_i(packetizer_input_header), .payload_i(packetizer_input_payload),
        .payload_bytes_i(packetizer_input_bytes), .valid_o(tx_packet_valid),
        .flit_o(tx_packet_flit)
    );

    kdlink_replay_buffer #(.ENTRIES(8), .INDEX_WIDTH(3)) u_replay (
        .clk_i(clk), .rst_n_i(rst_n), .store_start_i(replay_store_start),
        .store_valid_i(replay_store_valid), .store_body_i(replay_store_body),
        .store_last_i(replay_store_last), .store_ready_o(replay_store_ready),
        .ack_valid_i(ack_valid), .ack_collective_id_i(ack_collective_id),
        .ack_phase_i(ack_phase), .ack_packet_seq_i(ack_packet_seq),
        .nack_valid_i(nack_valid), .nack_collective_id_i(nack_collective_id),
        .nack_phase_i(nack_phase), .nack_packet_seq_i(nack_packet_seq),
        .replay_valid_o(replay_valid), .replay_ready_i(1'b1),
        .replay_body_o(replay_body), .replay_last_o(replay_last),
        .retry_exhausted_o(replay_retry_exhausted), .occupancy_o(replay_occupancy)
    );

    kdlink_pcs_tx u_pcs_tx (
        .clk_i(clk), .rst_n_i(rst_n), .flit_valid_i(tx_packet_valid),
        .flit_i(tx_flit_for_pcs), .training_i(training_active),
        .alignment_marker_i(marker_active), .marker_sequence_i(16'h4e2a),
        .blocks_valid_o(pcs_a_blocks_valid), .blocks_o(pcs_a_blocks)
    );

    kdlink_serdes_link_model #(.PROPAGATION_CYCLES(4), .MAX_LANE_SKEW_CYCLES(2), .TRAINING_CYCLES(8)) u_link (
        .clk_i(clk), .rst_n_i(rst_n), .admin_up_i(admin_up),
        .a_to_b_lane_up_i(10'h3ff), .b_to_a_lane_up_i(10'h3ff),
        .a_tx_group_valid_i(pcs_a_blocks_valid), .a_tx_group_blocks_i(pcs_a_blocks),
        .b_tx_group_valid_i(1'b0), .b_tx_group_blocks_i(660'd0),
        .inject_a_to_b_drop_i(10'd0), .inject_a_to_b_corrupt_i(10'd0),
        .inject_b_to_a_drop_i(10'd0), .inject_b_to_a_corrupt_i(10'd0),
        .ber_period_groups_i(32'd0), .ber_lane_i(4'd0),
        .a_rx_lane_valid_o(), .a_rx_lane_blocks_o(),
        .b_rx_lane_valid_o(pcs_b_lane_valid), .b_rx_lane_blocks_o(pcs_b_lane_blocks),
        .a_to_b_state_o(a_to_b_state), .b_to_a_state_o(b_to_a_state),
        .full_duplex_up_o(full_duplex_up), .a_to_b_groups_o(a_to_b_groups),
        .b_to_a_groups_o(b_to_a_groups), .dropped_blocks_o(dropped_blocks),
        .corrupted_blocks_o(corrupted_blocks)
    );

    kdlink_pcs_rx u_pcs_rx (
        .clk_i(clk), .rst_n_i(rst_n), .lane_valid_i(pcs_b_lane_valid),
        .lane_blocks_i(pcs_b_lane_blocks), .flit_valid_o(pcs_b_flit_valid),
        .flit_o(pcs_b_flit), .block_lock_o(pcs_b_block_lock),
        .deskew_locked_o(pcs_b_deskew_lock), .block_error_o(pcs_b_block_error),
        .deskew_overflow_o(pcs_b_deskew_overflow)
    );

    kdlink_depacketizer u_depacketizer (
        .clk_i(clk), .rst_n_i(rst_n), .valid_i(pcs_b_flit_valid),
        .flit_i(pcs_b_flit), .valid_o(rx_codec_valid), .crc_good_o(rx_crc_good),
        .header_o(rx_header), .payload_o(rx_payload),
        .payload_bytes_o(rx_payload_bytes)
    );

    always #0.5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            good_count = 0;
            bad_count = 0;
            replay_count = 0;
            idle_cycles = 0;
            good_seen = '0;
            retry_seen = '0;
            nack_pending = 1'b0;
            nack_consumed = 1'b0;
            nack_sequence_q = 12'd0;
        end else begin
            if (rx_codec_valid) begin
                idle_cycles = 0;
                observed_sequence = {20'd0, rx_header[81:70]};
                if (!rx_crc_good) begin
                    bad_count = bad_count + 1;
                    if (observed_sequence != FAULT_SEQUENCE) begin
                        $fatal(1, "E2E CRC failure has wrong packet sequence=%0d", observed_sequence);
                    end
                    nack_pending = 1'b1;
                    nack_sequence_q = rx_header[81:70];
                end else begin
                    if (observed_sequence < NORMAL_PACKETS) begin
                        good_seen[observed_sequence] = 1'b1;
                        if (rx_header[19]) retry_seen[observed_sequence] = 1'b1;
                    end
                    good_count = good_count + 1;
                    if (rx_header[19]) replay_count = replay_count + 1;
                    if (rx_payload[31:0] != observed_sequence) begin
                        $fatal(1, "E2E payload/header mismatch sequence=%0d payload=%0d",
                            observed_sequence, rx_payload[31:0]);
                    end
                end
            end else if (source_done) begin
                idle_cycles = idle_cycles + 1;
            end
            if (replay_retry_exhausted) $fatal(1, "E2E replay unexpectedly exhausted");
            if (pcs_b_block_error || pcs_b_deskew_overflow) begin
                $fatal(1, "E2E PCS lock failed block_error=%b overflow=%b",
                    pcs_b_block_error, pcs_b_deskew_overflow);
            end
        end
    end

    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nack_valid = 1'b0;
            nack_collective_id = 12'd0;
            nack_phase = 1'b0;
            nack_packet_seq = 12'd0;
        end else begin
            nack_valid = 1'b0;
            if (nack_pending && !nack_consumed) begin
                nack_valid = 1'b1;
                nack_collective_id = 12'h4e2;
                nack_phase = 1'b0;
                nack_packet_seq = nack_sequence_q;
                nack_consumed = 1'b1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        admin_up = 1'b0;
        tx_source_valid = 1'b0;
        tx_source_header = 96'd0;
        tx_source_payload = 512'd0;
        tx_source_bytes = 7'd64;
        replay_store_start = 1'b0;
        replay_store_valid = 1'b0;
        replay_store_last = 1'b0;
        ack_valid = 1'b0;
        ack_collective_id = 12'd0;
        ack_phase = 1'b0;
        ack_packet_seq = 12'd0;
        nack_valid = 1'b0;
        nack_collective_id = 12'd0;
        nack_phase = 1'b0;
        nack_packet_seq = 12'd0;
        training_active = 1'b0;
        marker_active = 1'b0;
        source_done = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1; admin_up = 1'b1;
        wait (full_duplex_up);
        repeat (TRAINING_GROUPS) begin
            @(negedge clk); training_active = 1'b1;
        end
        @(negedge clk); training_active = 1'b0;
        repeat (4) begin
            @(negedge clk); marker_active = 1'b1;
        end
        @(negedge clk); marker_active = 1'b0;
        wait (pcs_b_block_lock && pcs_b_deskew_lock);
        for (source_index = 0; source_index < NORMAL_PACKETS; source_index = source_index + 1) begin
            @(negedge clk);
            tx_source_valid = 1'b1;
            replay_store_start = 1'b1;
            replay_store_valid = 1'b1;
            replay_store_last = 1'b1;
            tx_source_header = 96'd0;
            tx_source_header[7:4] = 4'd0;
            tx_source_header[10:8] = 3'd2;
            tx_source_header[12:11] = 2'd0;
            tx_source_header[15:13] = 3'd2;
            tx_source_header[16] = 1'b0;
            tx_source_header[17] = 1'b1;
            tx_source_header[18] = 1'b1;
            tx_source_header[19] = 1'b0;
            tx_source_header[24:20] = 5'd0;
            tx_source_header[29:25] = 5'd1;
            tx_source_header[37:33] = 5'd1;
            tx_source_header[45:38] = 8'd1;
            tx_source_header[57:46] = 12'h4e2;
            tx_source_header[69:58] = source_index[11:0];
            tx_source_header[81:70] = source_index[11:0];
            tx_source_header[87:82] = 6'd0;
            tx_source_header[94:88] = 7'd64;
            tx_source_payload = 512'd0;
            tx_source_payload[31:0] = source_index[31:0];
            if (!replay_store_ready) $fatal(1, "E2E replay store backpressure sequence=%0d", source_index);
        end
        @(negedge clk);
        tx_source_valid = 1'b0;
        replay_store_start = 1'b0;
        replay_store_valid = 1'b0;
        replay_store_last = 1'b0;
        source_done = 1'b1;
        wait (good_count == NORMAL_PACKETS && replay_count == 1 && bad_count == 1);
        repeat (8) @(posedge clk);
        for (check_index = 0; check_index < NORMAL_PACKETS; check_index = check_index + 1) begin
            if (!good_seen[check_index] || !retry_seen[FAULT_SEQUENCE]) begin
                $fatal(1, "E2E exact-once/replay scoreboard failure sequence=%0d good=%b retry=%b",
                    check_index, good_seen, retry_seen);
            end
        end
        if (!full_duplex_up || !pcs_b_block_lock || !pcs_b_deskew_lock || replay_occupancy != NORMAL_PACKETS[3:0]) begin
            $fatal(1, "E2E final link/replay state failure link=%b block=%b deskew=%b occupancy=%0d",
                full_duplex_up, pcs_b_block_lock, pcs_b_deskew_lock, replay_occupancy);
        end
        $display("TB_KDLINK_MULTIBOARD_E2E_PASS cards=8 representative_endpoints=2 packets=%0d crc_bad=1 nack=1 rtl_replay=1 exact_once=1 pcs=1 serdes=1",
            NORMAL_PACKETS);
        $finish;
    end

    initial begin
        #12000;
        $fatal(1, "KDLink multiboard E2E timeout");
    end
endmodule
