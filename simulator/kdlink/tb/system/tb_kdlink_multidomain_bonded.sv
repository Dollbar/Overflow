`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_multidomain_bonded;
    localparam [11:0] CONTEXT_SEQUENCE_0 = 12'd100;
    localparam [11:0] DATA_SEQUENCE_0 = 12'd102;
    localparam [11:0] CONTEXT_SEQUENCE_1 = 12'd201;
    localparam [11:0] DATA_SEQUENCE_1 = 12'd203;
    logic phy_clk;
    logic core_a_clk;
    logic core_b_clk;
    logic rst_n;
    logic admin_up;
    logic training;
    logic marker;
    logic [15:0] marker_sequence;
    logic [1:0] ingress_valid;
    wire [1:0] ingress_ready;
    logic [1279:0] ingress_flit;
    wire [1:0] pair_tx_valid;
    wire [1:0] pair_tx_ready;
    wire [191:0] pair_tx_header;
    wire [1023:0] pair_tx_payload;
    wire [13:0] pair_tx_bytes;
    wire [1:0] pair_waiting_ack;
    wire [1:0] pair_complete;
    wire [1:0] pair_protocol_error;
    wire [1:0] a_ack_valid;
    wire [5:0] a_ack_vc;
    wire [1:0] a_ack_phase;
    wire [23:0] a_ack_collective;
    wire [23:0] a_ack_sequence;
    wire [1:0] a_forward_valid;
    wire [1279:0] a_forward_flit;
    wire [1279:0] a_forward_faulted;
    wire [1:0] b_forward_valid;
    wire [1279:0] b_forward_flit;
    wire [1:0] a_reverse_valid;
    wire [255:0] a_reverse_word;
    wire [1:0] b_reverse_valid;
    wire [255:0] b_reverse_word;
    wire [1:0] a_reverse_rx_valid;
    wire [255:0] a_reverse_rx_word;
    wire [1:0] b_reverse_rx_valid;
    wire [255:0] b_reverse_rx_word;
    wire [1:0] a_pcs_blocks_valid;
    wire [1319:0] a_pcs_blocks;
    wire [1:0] b_pcs_blocks_valid;
    wire [1319:0] b_pcs_blocks;
    wire [19:0] a_pcs_rx_lane_valid;
    wire [1319:0] a_pcs_rx_lane_blocks;
    wire [19:0] b_pcs_rx_lane_valid;
    wire [1319:0] b_pcs_rx_lane_blocks;
    wire [1:0] a_pcs_rx_flit_valid;
    wire [1279:0] a_pcs_rx_flit;
    wire [1:0] b_pcs_rx_flit_valid;
    wire [1279:0] b_pcs_rx_flit;
    wire [1:0] a_block_lock;
    wire [1:0] a_deskew_lock;
    wire [1:0] b_block_lock;
    wire [1:0] b_deskew_lock;
    wire [1:0] a_block_error;
    wire [1:0] a_deskew_overflow;
    wire [1:0] b_block_error;
    wire [1:0] b_deskew_overflow;
    wire [1:0] full_duplex_up;
    wire [1:0] b_commit_valid;
    wire [1:0] b_commit_ready;
    wire [191:0] b_commit_header;
    wire [1023:0] b_commit_payload;
    wire [13:0] b_commit_bytes;
    wire [1:0] b_commit_last;
    wire [1279:0] b_commit_flit;
    wire [1:0] b_local_valid;
    wire [1279:0] b_local_flit;
    wire [1:0] b_remote_valid;
    wire [1279:0] b_remote_flit;
    wire [1:0] adapter_protocol_error;
    wire [1:0] a_link_up;
    wire [1:0] b_link_up;
    wire [1:0] a_active_mask;
    wire [1:0] b_active_mask;
    wire a_reliability_error;
    wire b_reliability_error;
    wire [19:0] a_replay_occupancy;
    wire [19:0] b_replay_occupancy;
    logic context_fault_armed;
    logic data_fault_armed;
    wire [1:0] fault_now;
    integer context_fault_seen;
    integer data_fault_seen;
    integer context_replay_seen;
    integer data_replay_seen;
    integer ack_seen_0;
    integer ack_seen_1;
    integer blocked_cycles_0;
    integer blocked_cycles_1;
    integer pair_complete_seen_0;
    integer pair_complete_seen_1;
    integer local_seen_0;
    integer local_seen_1;
    logic [1:0] data_attempt_active;
    integer timeout_count;

    always #0.5 phy_clk = ~phy_clk;
    always #0.7 core_a_clk = ~core_a_clk;
    always #0.8 core_b_clk = ~core_b_clk;
    assign fault_now[0] = context_fault_armed && a_forward_valid[0] && !a_forward_flit[531] && (a_forward_flit[593:582] == CONTEXT_SEQUENCE_0);
    assign fault_now[1] = data_fault_armed && a_forward_valid[1] && !a_forward_flit[640+531] && (a_forward_flit[640+593 -: 12] == DATA_SEQUENCE_1);
    assign a_forward_faulted[639:0] = fault_now[0] ? (a_forward_flit[639:0] ^ 640'd1) : a_forward_flit[639:0];
    assign a_forward_faulted[1279:640] = fault_now[1] ? (a_forward_flit[1279:640] ^ 640'd1) : a_forward_flit[1279:640];

    genvar logical_slice;
    generate
        for (logical_slice = 0; logical_slice < 2; logical_slice = logical_slice + 1) begin : g_slice
            kdlink_route_pair_tx u_pair_tx (
                .clk_i(core_a_clk), .rst_n_i(rst_n),
                .ingress_valid_i(ingress_valid[logical_slice]), .ingress_ready_o(ingress_ready[logical_slice]),
                .ingress_flit_i(ingress_flit[logical_slice*640 +: 640]),
                .tx_valid_o(pair_tx_valid[logical_slice]), .tx_ready_i(pair_tx_ready[logical_slice]),
                .tx_header_o(pair_tx_header[logical_slice*96 +: 96]),
                .tx_payload_o(pair_tx_payload[logical_slice*512 +: 512]),
                .tx_payload_bytes_o(pair_tx_bytes[logical_slice*7 +: 7]),
                .ack_valid_i(a_ack_valid[logical_slice]), .ack_phase_i(a_ack_phase[logical_slice]),
                .ack_collective_id_i(a_ack_collective[logical_slice*12 +: 12]),
                .ack_packet_seq_i(a_ack_sequence[logical_slice*12 +: 12]),
                .waiting_for_ack_o(pair_waiting_ack[logical_slice]),
                .pair_complete_o(pair_complete[logical_slice]),
                .protocol_error_o(pair_protocol_error[logical_slice])
            );
            assign b_commit_flit[logical_slice*640 +: 640] = {32'd0,
                b_commit_header[logical_slice*96 +: 96], b_commit_payload[logical_slice*512 +: 512]};
            kdlink_domain_adapter u_domain_adapter (
                .clk_i(core_b_clk), .rst_n_i(rst_n), .local_domain_i(8'd1),
                .ingress_valid_i(b_commit_valid[logical_slice]), .ingress_ready_o(b_commit_ready[logical_slice]),
                .ingress_flit_i(b_commit_flit[logical_slice*640 +: 640]),
                .local_valid_o(b_local_valid[logical_slice]), .local_ready_i(1'b1),
                .local_flit_o(b_local_flit[logical_slice*640 +: 640]),
                .remote_valid_o(b_remote_valid[logical_slice]), .remote_ready_i(1'b1),
                .remote_flit_o(b_remote_flit[logical_slice*640 +: 640]),
                .protocol_error_o(adapter_protocol_error[logical_slice])
            );
            kdlink_pcs u_pcs_a (
                .clk_i(phy_clk), .rst_n_i(rst_n),
                .tx_flit_valid_i(a_forward_valid[logical_slice]),
                .tx_flit_i(a_forward_faulted[logical_slice*640 +: 640]),
                .tx_training_i(training), .tx_alignment_marker_i(marker), .tx_marker_sequence_i(marker_sequence),
                .tx_blocks_valid_o(a_pcs_blocks_valid[logical_slice]),
                .tx_blocks_o(a_pcs_blocks[logical_slice*660 +: 660]),
                .rx_lane_valid_i(a_pcs_rx_lane_valid[logical_slice*10 +: 10]),
                .rx_lane_blocks_i(a_pcs_rx_lane_blocks[logical_slice*660 +: 660]),
                .rx_flit_valid_o(a_pcs_rx_flit_valid[logical_slice]),
                .rx_flit_o(a_pcs_rx_flit[logical_slice*640 +: 640]),
                .rx_block_lock_o(a_block_lock[logical_slice]), .rx_deskew_locked_o(a_deskew_lock[logical_slice]),
                .rx_block_error_o(a_block_error[logical_slice]), .rx_deskew_overflow_o(a_deskew_overflow[logical_slice])
            );
            kdlink_pcs u_pcs_b (
                .clk_i(phy_clk), .rst_n_i(rst_n),
                .tx_flit_valid_i(b_forward_valid[logical_slice]),
                .tx_flit_i(b_forward_flit[logical_slice*640 +: 640]),
                .tx_training_i(training), .tx_alignment_marker_i(marker), .tx_marker_sequence_i(marker_sequence),
                .tx_blocks_valid_o(b_pcs_blocks_valid[logical_slice]),
                .tx_blocks_o(b_pcs_blocks[logical_slice*660 +: 660]),
                .rx_lane_valid_i(b_pcs_rx_lane_valid[logical_slice*10 +: 10]),
                .rx_lane_blocks_i(b_pcs_rx_lane_blocks[logical_slice*660 +: 660]),
                .rx_flit_valid_o(b_pcs_rx_flit_valid[logical_slice]),
                .rx_flit_o(b_pcs_rx_flit[logical_slice*640 +: 640]),
                .rx_block_lock_o(b_block_lock[logical_slice]), .rx_deskew_locked_o(b_deskew_lock[logical_slice]),
                .rx_block_error_o(b_block_error[logical_slice]), .rx_deskew_overflow_o(b_deskew_overflow[logical_slice])
            );
            kdlink_serdes_link_model #(
                .PROPAGATION_CYCLES(4), .MAX_LANE_SKEW_CYCLES(2), .TRAINING_CYCLES(8)
            ) u_serdes_link (
                .clk_i(phy_clk), .rst_n_i(rst_n), .admin_up_i(admin_up),
                .a_to_b_lane_up_i(10'h3ff), .b_to_a_lane_up_i(10'h3ff),
                .a_tx_group_valid_i(a_pcs_blocks_valid[logical_slice]),
                .a_tx_group_blocks_i(a_pcs_blocks[logical_slice*660 +: 660]),
                .b_tx_group_valid_i(b_pcs_blocks_valid[logical_slice]),
                .b_tx_group_blocks_i(b_pcs_blocks[logical_slice*660 +: 660]),
                .inject_a_to_b_drop_i(10'd0), .inject_a_to_b_corrupt_i(10'd0),
                .inject_b_to_a_drop_i(10'd0), .inject_b_to_a_corrupt_i(10'd0),
                .ber_period_groups_i(32'd0), .ber_lane_i(4'd0),
                .a_rx_lane_valid_o(a_pcs_rx_lane_valid[logical_slice*10 +: 10]),
                .a_rx_lane_blocks_o(a_pcs_rx_lane_blocks[logical_slice*660 +: 660]),
                .b_rx_lane_valid_o(b_pcs_rx_lane_valid[logical_slice*10 +: 10]),
                .b_rx_lane_blocks_o(b_pcs_rx_lane_blocks[logical_slice*660 +: 660]),
                .a_to_b_state_o(), .b_to_a_state_o(), .full_duplex_up_o(full_duplex_up[logical_slice]),
                .a_to_b_groups_o(), .b_to_a_groups_o(), .dropped_blocks_o(), .corrupted_blocks_o()
            );
            kdlink_reverse_channel_model #(.PROPAGATION_CYCLES(4)) u_reverse_link (
                .clk_i(phy_clk), .rst_n_i(rst_n),
                .a_tx_valid_i(a_reverse_valid[logical_slice]),
                .a_tx_word_i(a_reverse_word[logical_slice*128 +: 128]),
                .b_tx_valid_i(b_reverse_valid[logical_slice]),
                .b_tx_word_i(b_reverse_word[logical_slice*128 +: 128]),
                .inject_a_to_b_corrupt_i(1'b0), .inject_b_to_a_corrupt_i(1'b0),
                .inject_a_to_b_drop_i(1'b0), .inject_b_to_a_drop_i(1'b0),
                .a_rx_valid_o(a_reverse_rx_valid[logical_slice]),
                .a_rx_word_o(a_reverse_rx_word[logical_slice*128 +: 128]),
                .b_rx_valid_o(b_reverse_rx_valid[logical_slice]),
                .b_rx_word_o(b_reverse_rx_word[logical_slice*128 +: 128])
            );
        end
    endgenerate

    kdlink_reliable_bonded_endpoint #(
        .INITIAL_CREDITS(16'd8), .REPLAY_SLOT_BITS(9), .AUTO_LINK_MANAGEMENT(1'b0),
        .ALLOW_ROUTE_CONTEXT(1'b1), .REPLAY_TIMEOUT_CYCLES(16'd4096)
    ) u_endpoint_a (
        .core_clk_i(core_a_clk), .core_rst_n_i(rst_n), .phy_clk_i(phy_clk), .phy_rst_n_i(rst_n),
        .local_node_i(5'd3), .peer_node_i(5'd29), .link_epoch_i(8'h2a), .link_enable_i(1'b1),
        .configured_slice_mask_i(2'b11), .slice_fault_i(2'b00),
        .tx_valid_i(pair_tx_valid), .tx_ready_o(pair_tx_ready), .tx_header_i(pair_tx_header),
        .tx_payload_i(pair_tx_payload), .tx_payload_bytes_i(pair_tx_bytes),
        .rx_commit_valid_o(), .rx_commit_ready_i(2'b11), .rx_commit_header_o(), .rx_commit_payload_o(),
        .rx_commit_payload_bytes_o(), .rx_commit_last_o(),
        .phy_forward_tx_valid_o(a_forward_valid), .phy_forward_tx_flit_o(a_forward_flit),
        .phy_forward_rx_valid_i(a_pcs_rx_flit_valid), .phy_forward_rx_flit_i(a_pcs_rx_flit),
        .phy_reverse_tx_valid_o(a_reverse_valid), .phy_reverse_tx_word_o(a_reverse_word),
        .phy_reverse_rx_valid_i(a_reverse_rx_valid), .phy_reverse_rx_word_i(a_reverse_rx_word),
        .logical_link_up_o(a_link_up), .active_slice_mask_o(a_active_mask), .degraded_o(), .link_down_o(),
        .tx_ack_valid_o(a_ack_valid), .tx_ack_vc_o(a_ack_vc), .tx_ack_phase_o(a_ack_phase),
        .tx_ack_collective_id_o(a_ack_collective), .tx_ack_packet_seq_o(a_ack_sequence),
        .epoch_recovery_required_o(), .mapping_error_o(), .reliability_error_o(a_reliability_error),
        .replay_occupancy_o(a_replay_occupancy)
    );

    kdlink_reliable_bonded_endpoint #(
        .INITIAL_CREDITS(16'd8), .REPLAY_SLOT_BITS(9), .AUTO_LINK_MANAGEMENT(1'b0),
        .ALLOW_ROUTE_CONTEXT(1'b1), .REPLAY_TIMEOUT_CYCLES(16'd4096)
    ) u_endpoint_b (
        .core_clk_i(core_b_clk), .core_rst_n_i(rst_n), .phy_clk_i(phy_clk), .phy_rst_n_i(rst_n),
        .local_node_i(5'd29), .peer_node_i(5'd3), .link_epoch_i(8'h2a), .link_enable_i(1'b1),
        .configured_slice_mask_i(2'b11), .slice_fault_i(2'b00),
        .tx_valid_i(2'b00), .tx_ready_o(), .tx_header_i(192'd0), .tx_payload_i(1024'd0),
        .tx_payload_bytes_i(14'd0), .rx_commit_valid_o(b_commit_valid), .rx_commit_ready_i(b_commit_ready),
        .rx_commit_header_o(b_commit_header), .rx_commit_payload_o(b_commit_payload),
        .rx_commit_payload_bytes_o(b_commit_bytes), .rx_commit_last_o(b_commit_last),
        .phy_forward_tx_valid_o(b_forward_valid), .phy_forward_tx_flit_o(b_forward_flit),
        .phy_forward_rx_valid_i(b_pcs_rx_flit_valid), .phy_forward_rx_flit_i(b_pcs_rx_flit),
        .phy_reverse_tx_valid_o(b_reverse_valid), .phy_reverse_tx_word_o(b_reverse_word),
        .phy_reverse_rx_valid_i(b_reverse_rx_valid), .phy_reverse_rx_word_i(b_reverse_rx_word),
        .logical_link_up_o(b_link_up), .active_slice_mask_o(b_active_mask), .degraded_o(), .link_down_o(),
        .tx_ack_valid_o(), .tx_ack_vc_o(), .tx_ack_phase_o(), .tx_ack_collective_id_o(), .tx_ack_packet_seq_o(),
        .epoch_recovery_required_o(), .mapping_error_o(), .reliability_error_o(b_reliability_error),
        .replay_occupancy_o(b_replay_occupancy)
    );

    task automatic send_flit;
        input integer lane;
        input [95:0] header_value;
        input [511:0] payload_value;
        begin
            @(negedge core_a_clk);
            ingress_flit[lane*640 +: 640] = {32'd0, header_value, payload_value};
            ingress_flit[lane*640 + 512 + 94 -: 7] = 7'd64;
            ingress_valid[lane] = 1'b1;
            @(posedge core_a_clk);
            while (!ingress_ready[lane]) @(posedge core_a_clk);
            @(negedge core_a_clk);
            ingress_valid[lane] = 1'b0;
            ingress_flit[lane*640 +: 640] = 640'd0;
        end
    endtask

    task automatic send_pair;
        input integer lane;
        input [11:0] context_sequence;
        input [11:0] data_sequence;
        input [31:0] marker_value;
        reg [95:0] header_value;
        reg [511:0] payload_value;
        begin
            header_value = 96'd0;
            header_value[3:0] = `KDL_ROUTE_SCHEMA;
            header_value[7:4] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
            header_value[15:13] = `KDL_VC_ROLE_POINT_TO_POINT;
            header_value[17] = 1'b1;
            header_value[18] = 1'b1;
            header_value[24:20] = 5'd3;
            header_value[29:25] = 5'd29;
            header_value[32:30] = lane[2:0];
            header_value[37:33] = 5'd2;
            header_value[45:38] = 8'h2a;
            header_value[57:46] = 12'h620 + lane[11:0];
            header_value[81:70] = context_sequence;
            header_value[94:88] = 7'd64;
            payload_value = 512'd0;
            payload_value[7:0] = 8'd0;
            payload_value[15:8] = 8'd1;
            payload_value[20:16] = 5'd3;
            payload_value[25:21] = 5'd29;
            payload_value[33:26] = 8'd7;
            payload_value[41:34] = 8'd1;
            payload_value[44:42] = lane[2:0];
            payload_value[46:45] = 2'b11;
            payload_value[54:50] = 5'd1;
            payload_value[66:55] = data_sequence;
            payload_value[130:67] = 64'h1000_0000_0000_0000 + {63'd0, lane[0]};
            payload_value[162:131] = 32'h2000_0000 + lane;
            payload_value[165:163] = `KDL_VC_ROLE_POINT_TO_POINT;
            send_flit(lane, header_value, payload_value);
            header_value = 96'd0;
            header_value[3:0] = `KDL_SCHEMA_VERSION;
            header_value[7:4] = `KDL_MESSAGE_TYPE_DATA;
            header_value[10:8] = `KDL_OPCODE_POINT_TO_POINT;
            header_value[15:13] = `KDL_VC_ROLE_POINT_TO_POINT;
            header_value[17] = 1'b1;
            header_value[18] = 1'b1;
            header_value[24:20] = 5'd3;
            header_value[29:25] = 5'd29;
            header_value[32:30] = lane[2:0];
            header_value[37:33] = 5'd2;
            header_value[45:38] = 8'h2a;
            header_value[57:46] = 12'h620 + lane[11:0];
            header_value[81:70] = data_sequence;
            header_value[94:88] = 7'd64;
            payload_value = {512{1'b1}};
            payload_value[31:0] = marker_value;
            data_attempt_active[lane] = 1'b1;
            send_flit(lane, header_value, payload_value);
            data_attempt_active[lane] = 1'b0;
        end
    endtask

    always @(posedge phy_clk or negedge rst_n) begin
        if (!rst_n) begin
            context_fault_armed <= 1'b1;
            data_fault_armed <= 1'b1;
            context_fault_seen <= 0;
            data_fault_seen <= 0;
            context_replay_seen <= 0;
            data_replay_seen <= 0;
        end else begin
            if (fault_now[0]) begin context_fault_armed <= 1'b0; context_fault_seen <= context_fault_seen + 1; end
            if (fault_now[1]) begin data_fault_armed <= 1'b0; data_fault_seen <= data_fault_seen + 1; end
            if (a_forward_valid[0] && a_forward_flit[531] && (a_forward_flit[593:582] == CONTEXT_SEQUENCE_0)) context_replay_seen <= context_replay_seen + 1;
            if (a_forward_valid[1] && a_forward_flit[640+531] && (a_forward_flit[640+593 -: 12] == DATA_SEQUENCE_1)) data_replay_seen <= data_replay_seen + 1;
            if ((|a_deskew_overflow) || (|b_deskew_overflow)) $fatal(1, "bonded PCS deskew overflow");
        end
    end

    always @(posedge core_a_clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_seen_0 <= 0; ack_seen_1 <= 0; blocked_cycles_0 <= 0; blocked_cycles_1 <= 0;
            pair_complete_seen_0 <= 0; pair_complete_seen_1 <= 0;
        end else begin
            if (a_ack_valid[0] && (a_ack_sequence[11:0] == CONTEXT_SEQUENCE_0)) ack_seen_0 <= ack_seen_0 + 1;
            if (a_ack_valid[1] && (a_ack_sequence[23:12] == CONTEXT_SEQUENCE_1)) ack_seen_1 <= ack_seen_1 + 1;
            if (data_attempt_active[0] && pair_waiting_ack[0] && !ingress_ready[0]) blocked_cycles_0 <= blocked_cycles_0 + 1;
            if (data_attempt_active[1] && pair_waiting_ack[1] && !ingress_ready[1]) blocked_cycles_1 <= blocked_cycles_1 + 1;
            if (pair_complete[0]) pair_complete_seen_0 <= pair_complete_seen_0 + 1;
            if (pair_complete[1]) pair_complete_seen_1 <= pair_complete_seen_1 + 1;
        end
    end

    always @(posedge core_b_clk or negedge rst_n) begin
        if (!rst_n) begin local_seen_0 <= 0; local_seen_1 <= 0; end
        else begin
            if (b_local_valid[0]) begin
                local_seen_0 <= local_seen_0 + 1;
                if (b_local_flit[31:0] != 32'hcafe_0000) $fatal(1, "slice zero local payload mismatch");
            end
            if (b_local_valid[1]) begin
                local_seen_1 <= local_seen_1 + 1;
                if (b_local_flit[640 +: 32] != 32'hcafe_0001) $fatal(1, "slice one local payload mismatch got=%h", b_local_flit[640 +: 32]);
            end
        end
    end

    initial begin
        phy_clk = 1'b0; core_a_clk = 1'b0; core_b_clk = 1'b0; rst_n = 1'b0;
        admin_up = 1'b0; training = 1'b0; marker = 1'b0; marker_sequence = 16'h45a3;
        ingress_valid = 2'b00; ingress_flit = 1280'd0; data_attempt_active = 2'b00;
        repeat (12) @(posedge phy_clk);
        @(negedge phy_clk); rst_n = 1'b1; admin_up = 1'b1;
        wait (&full_duplex_up);
        repeat (20) begin @(negedge phy_clk); training = 1'b1; end
        @(negedge phy_clk); training = 1'b0;
        repeat (4) begin @(negedge phy_clk); marker = 1'b1; end
        @(negedge phy_clk); marker = 1'b0;
        wait (&a_block_lock && &a_deskew_lock && &b_block_lock && &b_deskew_lock);
        send_pair(0, CONTEXT_SEQUENCE_0, DATA_SEQUENCE_0, 32'hcafe_0000);
        send_pair(1, CONTEXT_SEQUENCE_1, DATA_SEQUENCE_1, 32'hcafe_0001);
        timeout_count = 0;
        while (((local_seen_0 != 1) || (local_seen_1 != 1) || (a_replay_occupancy != 20'd0)) && (timeout_count < 20000)) begin
            @(posedge phy_clk); timeout_count = timeout_count + 1;
        end
        repeat (30) @(posedge phy_clk);
        if (local_seen_0 != 1 || local_seen_1 != 1) $fatal(1, "bonded exact-once delivery mismatch %0d/%0d", local_seen_0, local_seen_1);
        if (context_fault_seen != 1 || data_fault_seen != 1 || context_replay_seen != 1 || data_replay_seen != 1) $fatal(1, "bonded replay evidence mismatch fault=%0d/%0d replay=%0d/%0d", context_fault_seen, data_fault_seen, context_replay_seen, data_replay_seen);
        if (ack_seen_0 != 1 || ack_seen_1 != 1 || blocked_cycles_0 == 0 || blocked_cycles_1 == 0) $fatal(1, "bonded production barrier mismatch ack=%0d/%0d blocked=%0d/%0d", ack_seen_0, ack_seen_1, blocked_cycles_0, blocked_cycles_1);
        if (pair_complete_seen_0 != 1 || pair_complete_seen_1 != 1) $fatal(1, "bonded pair completion mismatch %0d/%0d", pair_complete_seen_0, pair_complete_seen_1);
        if (a_active_mask != 2'b11 || b_active_mask != 2'b11 || a_link_up != 2'b11 || b_link_up != 2'b11) $fatal(1, "bonded slice map or link state mismatch");
        if ((|b_remote_valid) || (|pair_protocol_error) || (|adapter_protocol_error) || a_reliability_error || b_reliability_error || (|a_block_error) || (|b_block_error) || (|a_deskew_overflow) || (|b_deskew_overflow)) $fatal(1, "unexpected bonded multidomain reliability error");
        $display("TB_KDLINK_MULTIDOMAIN_BONDED_PASS route_context=1 production_ack_barrier=2 dual_slice=1 pcs_instances=4 serdes_links=2 serdes_lanes=20 context_replay=1 data_replay=1 exact_once=2");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "KDLink bonded multidomain timeout local=%0d/%0d replay=%0d/%0d occupancy=%h", local_seen_0, local_seen_1, context_replay_seen, data_replay_seen, a_replay_occupancy);
    end
endmodule
