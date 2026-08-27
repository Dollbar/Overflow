`timescale 1ns/1ps
module tb_kdlink_reliable_bonded_endpoint;
    localparam integer NORMAL_PACKETS_PER_SLICE = 8;
    localparam integer BUBBLE_FREE_PACKETS_PER_SLICE = 64;
    localparam integer DEGRADED_PACKETS_PER_SLICE = 512;
    localparam integer SECONDARY_DEGRADED_PACKETS_PER_SLICE = 8;
    localparam integer EXPECTED_FIRST_DEGRADED_COMMIT_FLITS = 2*NORMAL_PACKETS_PER_SLICE + 4 + 2*DEGRADED_PACKETS_PER_SLICE;
    localparam integer EXPECTED_COMMIT_FLITS = EXPECTED_FIRST_DEGRADED_COMMIT_FLITS + 2*SECONDARY_DEGRADED_PACKETS_PER_SLICE;
    reg clk;
    reg rst_n;
    reg [1:0] slice_fault;
    reg [7:0] link_epoch;
    reg [1:0] a_tx_valid;
    wire [1:0] a_tx_ready;
    reg [191:0] a_tx_header;
    reg [1023:0] a_tx_payload;
    reg [13:0] a_tx_bytes;
    wire [1:0] a_forward_tx_valid;
    wire [1279:0] a_forward_tx_flit;
    reg [1:0] a_forward_rx_valid;
    reg [1279:0] a_forward_rx_flit;
    wire [1:0] a_reverse_tx_valid;
    wire [255:0] a_reverse_tx_word;
    reg [1:0] a_reverse_rx_valid;
    reg [255:0] a_reverse_rx_word;
    wire [1:0] b_forward_tx_valid;
    wire [1279:0] b_forward_tx_flit;
    reg [1:0] b_forward_rx_valid;
    reg [1279:0] b_forward_rx_flit;
    wire [1:0] b_reverse_tx_valid;
    wire [255:0] b_reverse_tx_word;
    reg [1:0] b_reverse_rx_valid;
    reg [255:0] b_reverse_rx_word;
    wire [1:0] a_link_up;
    wire [1:0] b_link_up;
    wire [1:0] a_active_mask;
    wire [1:0] b_active_mask;
    wire a_reliability_error;
    wire b_reliability_error;
    wire a_mapping_error;
    wire b_mapping_error;
    wire a_epoch_recovery_required;
    wire b_epoch_recovery_required;
    wire [1:0] b_commit_valid;
    wire [191:0] b_commit_header;
    wire [1023:0] b_commit_payload;
    wire [1:0] b_commit_last;
    wire [19:0] a_replay_occupancy;
    wire [19:0] b_replay_occupancy;
    reg drop_and_fail_armed;
    integer commit_flits;
    integer committed_packets;
    integer replay_commits;
    integer normal_index;
    integer fault_flit;
    integer timeout_cycles;
    integer degraded_physical_flits;
    integer degraded_bubbles;
    integer degraded_gap_length;
    integer cycle_count;
    integer stage;
    reg degraded_monitor;
    reg degraded_started;
    reg degraded_physical_slice;
    bit [4095:0] sequence_seen;

    always #0.5 clk = ~clk;

    kdlink_reliable_bonded_endpoint #(
        .INITIAL_CREDITS(16'd64), .REPLAY_SLOT_BITS(9),
        .REPLAY_TIMEOUT_CYCLES(16'd2048), .KEEPALIVE_CYCLES(128),
        .LINK_TIMEOUT_CYCLES(1024)
    ) u_endpoint_a (
        .core_clk_i(clk), .core_rst_n_i(rst_n), .phy_clk_i(clk), .phy_rst_n_i(rst_n),
        .local_node_i(5'd0), .peer_node_i(5'd1), .link_epoch_i(link_epoch),
        .link_enable_i(1'b1), .configured_slice_mask_i(2'b11), .slice_fault_i(slice_fault),
        .tx_valid_i(a_tx_valid), .tx_ready_o(a_tx_ready), .tx_header_i(a_tx_header),
        .tx_payload_i(a_tx_payload), .tx_payload_bytes_i(a_tx_bytes),
        .rx_commit_valid_o(), .rx_commit_ready_i(2'b11), .rx_commit_header_o(),
        .rx_commit_payload_o(), .rx_commit_payload_bytes_o(), .rx_commit_last_o(),
        .phy_forward_tx_valid_o(a_forward_tx_valid), .phy_forward_tx_flit_o(a_forward_tx_flit),
        .phy_forward_rx_valid_i(a_forward_rx_valid), .phy_forward_rx_flit_i(a_forward_rx_flit),
        .phy_reverse_tx_valid_o(a_reverse_tx_valid), .phy_reverse_tx_word_o(a_reverse_tx_word),
        .phy_reverse_rx_valid_i(a_reverse_rx_valid), .phy_reverse_rx_word_i(a_reverse_rx_word),
        .logical_link_up_o(a_link_up), .active_slice_mask_o(a_active_mask),
        .degraded_o(), .link_down_o(), .epoch_recovery_required_o(a_epoch_recovery_required),
        .mapping_error_o(a_mapping_error),
        .reliability_error_o(a_reliability_error), .replay_occupancy_o(a_replay_occupancy)
    );

    kdlink_reliable_bonded_endpoint #(
        .INITIAL_CREDITS(16'd64), .REPLAY_SLOT_BITS(9),
        .REPLAY_TIMEOUT_CYCLES(16'd2048), .KEEPALIVE_CYCLES(128),
        .LINK_TIMEOUT_CYCLES(1024)
    ) u_endpoint_b (
        .core_clk_i(clk), .core_rst_n_i(rst_n), .phy_clk_i(clk), .phy_rst_n_i(rst_n),
        .local_node_i(5'd1), .peer_node_i(5'd0), .link_epoch_i(link_epoch),
        .link_enable_i(1'b1), .configured_slice_mask_i(2'b11), .slice_fault_i(slice_fault),
        .tx_valid_i(2'b00), .tx_ready_o(), .tx_header_i(192'd0),
        .tx_payload_i(1024'd0), .tx_payload_bytes_i(14'd0),
        .rx_commit_valid_o(b_commit_valid), .rx_commit_ready_i(2'b11),
        .rx_commit_header_o(b_commit_header), .rx_commit_payload_o(b_commit_payload),
        .rx_commit_payload_bytes_o(), .rx_commit_last_o(b_commit_last),
        .phy_forward_tx_valid_o(b_forward_tx_valid), .phy_forward_tx_flit_o(b_forward_tx_flit),
        .phy_forward_rx_valid_i(b_forward_rx_valid), .phy_forward_rx_flit_i(b_forward_rx_flit),
        .phy_reverse_tx_valid_o(b_reverse_tx_valid), .phy_reverse_tx_word_o(b_reverse_tx_word),
        .phy_reverse_rx_valid_i(b_reverse_rx_valid), .phy_reverse_rx_word_i(b_reverse_rx_word),
        .logical_link_up_o(b_link_up), .active_slice_mask_o(b_active_mask),
        .degraded_o(), .link_down_o(), .epoch_recovery_required_o(b_epoch_recovery_required),
        .mapping_error_o(b_mapping_error),
        .reliability_error_o(b_reliability_error), .replay_occupancy_o(b_replay_occupancy)
    );

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (!rst_n) begin
            a_forward_rx_valid <= 2'b00;
            b_forward_rx_valid <= 2'b00;
            a_reverse_rx_valid <= 2'b00;
            b_reverse_rx_valid <= 2'b00;
            slice_fault <= 2'b00;
        end else begin
            a_forward_rx_valid <= b_forward_tx_valid;
            a_forward_rx_flit <= b_forward_tx_flit;
            b_forward_rx_valid <= a_forward_tx_valid;
            b_forward_rx_flit <= a_forward_tx_flit;
            a_reverse_rx_valid <= b_reverse_tx_valid;
            a_reverse_rx_word <= b_reverse_tx_word;
            b_reverse_rx_valid <= a_reverse_tx_valid;
            b_reverse_rx_word <= a_reverse_tx_word;
            if (drop_and_fail_armed && a_forward_tx_valid[1]) begin
                b_forward_rx_valid[1] <= 1'b0;
                slice_fault <= 2'b10;
                drop_and_fail_armed <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && (|b_commit_valid))
            commit_flits <= commit_flits + b_commit_valid[0] + b_commit_valid[1];
        if (rst_n && (|b_commit_last))
            committed_packets <= committed_packets + b_commit_last[0] + b_commit_last[1];
        if (rst_n && b_commit_valid[0]) begin
            if (b_commit_header[70] != 1'b0) $fatal(1, "logical slice zero committed an odd sequence");
            if (b_commit_payload[31:0] != {20'd0, b_commit_header[81:70]})
                $fatal(1, "logical slice zero payload mismatch");
            if (b_commit_last[0]) begin
                if (sequence_seen[b_commit_header[81:70]]) $fatal(1, "duplicate slice-zero packet commit");
                sequence_seen[b_commit_header[81:70]] <= 1'b1;
            end
        end
        if (rst_n && b_commit_valid[1]) begin
            if (b_commit_header[96+70] != 1'b1) $fatal(1, "logical slice one committed an even sequence");
            if (b_commit_payload[512 +: 32] != {20'd0, b_commit_header[96+70 +: 12]})
                $fatal(1, "logical slice one payload mismatch");
            if (b_commit_last[1]) begin
                if (sequence_seen[b_commit_header[96+70 +: 12]]) $fatal(1, "duplicate slice-one packet commit");
                sequence_seen[b_commit_header[96+70 +: 12]] <= 1'b1;
                if (b_commit_header[96+81 -: 12] == 12'd101) replay_commits <= replay_commits + 1;
            end
        end
        if (rst_n && degraded_monitor) begin
            if (a_forward_tx_valid[!degraded_physical_slice]) $fatal(1, "failed physical slice transmitted in degraded mode");
            if (degraded_started) begin
                if (a_forward_tx_valid[degraded_physical_slice]) begin
                    degraded_physical_flits <= degraded_physical_flits + 1;
                    if (degraded_gap_length != 0) begin
                        degraded_gap_length <= 0;
                    end
                end else if (degraded_physical_flits < 2*BUBBLE_FREE_PACKETS_PER_SLICE) begin
                    degraded_bubbles <= degraded_bubbles + 1;
                    degraded_gap_length <= degraded_gap_length + 1;
                end
            end else if (a_forward_tx_valid[degraded_physical_slice]) begin
                degraded_started <= 1'b1;
                degraded_physical_flits <= 1;
            end
        end
    end

    task build_header;
        input integer lane;
        input [11:0] seq_value;
        input [5:0] flit_sequence;
        input sop;
        input eop;
        begin
            a_tx_header[lane*96 +: 96] = 96'd0;
            a_tx_header[lane*96 + 3 -: 4] = 4'd2;
            a_tx_header[lane*96 + 7 -: 4] = 4'd0;
            a_tx_header[lane*96 + 10 -: 3] = 3'd2;
            a_tx_header[lane*96 + 12 -: 2] = 2'd0;
            a_tx_header[lane*96 + 15 -: 3] = 3'd2;
            a_tx_header[lane*96 + 17] = sop;
            a_tx_header[lane*96 + 18] = eop;
            a_tx_header[lane*96 + 24 -: 5] = 5'd0;
            a_tx_header[lane*96 + 29 -: 5] = 5'd1;
            a_tx_header[lane*96 + 32 -: 3] = 3'd0;
            a_tx_header[lane*96 + 37 -: 5] = 5'd1;
            a_tx_header[lane*96 + 45 -: 8] = 8'h2a;
            a_tx_header[lane*96 + 57 -: 12] = 12'h610;
            a_tx_header[lane*96 + 69 -: 12] = seq_value;
            a_tx_header[lane*96 + 81 -: 12] = seq_value;
            a_tx_header[lane*96 + 87 -: 6] = flit_sequence;
        end
    endtask

    task automatic drive_degraded_lane;
        input integer lane;
        input integer packet_count;
        input integer sequence_base;
        integer packet_index;
        reg [11:0] sequence_value;
        begin
            packet_index = 0;
            while (packet_index < packet_count) begin
                @(negedge clk);
                if (a_tx_ready[lane]) begin
                    sequence_value = 12'(sequence_base + packet_index*2 + lane);
                    build_header(lane, sequence_value, 6'd0, 1'b1, 1'b1);
                    a_tx_payload[lane*512 +: 512] = 512'd0;
                    a_tx_payload[lane*512 +: 32] = {20'd0, sequence_value};
                    a_tx_valid[lane] = 1'b1;
                    packet_index = packet_index + 1;
                end else begin
                    a_tx_valid[lane] = 1'b0;
                end
            end
            @(negedge clk);
            a_tx_valid[lane] = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        slice_fault = 2'b00;
        link_epoch = 8'h2a;
        a_tx_valid = 2'b00;
        a_tx_header = 192'd0;
        a_tx_payload = 1024'd0;
        a_tx_bytes = {7'd64, 7'd64};
        a_forward_rx_valid = 2'b00;
        a_forward_rx_flit = 1280'd0;
        b_forward_rx_valid = 2'b00;
        b_forward_rx_flit = 1280'd0;
        a_reverse_rx_valid = 2'b00;
        a_reverse_rx_word = 256'd0;
        b_reverse_rx_valid = 2'b00;
        b_reverse_rx_word = 256'd0;
        drop_and_fail_armed = 1'b0;
        commit_flits = 0;
        committed_packets = 0;
        replay_commits = 0;
        degraded_physical_flits = 0;
        degraded_bubbles = 0;
        degraded_gap_length = 0;
        cycle_count = 0;
        degraded_monitor = 1'b0;
        degraded_started = 1'b0;
        degraded_physical_slice = 1'b0;
        sequence_seen = '0;
        stage = 0;
        repeat (12) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait (&a_link_up && &b_link_up);
        stage = 1;

        for (normal_index = 0; normal_index < NORMAL_PACKETS_PER_SLICE; normal_index = normal_index + 1) begin
            @(negedge clk);
            build_header(0, 12'(normal_index*2), 6'd0, 1'b1, 1'b1);
            build_header(1, 12'(normal_index*2+1), 6'd0, 1'b1, 1'b1);
            a_tx_payload = 1024'd0;
            a_tx_payload[31:0] = normal_index*2;
            a_tx_payload[512 +: 32] = normal_index*2+1;
            if (a_tx_ready != 2'b11) $fatal(1, "normal bonded source unexpectedly backpressured");
            a_tx_valid = 2'b11;
        end
        @(negedge clk); a_tx_valid = 2'b00;
        stage = 2;
        wait (committed_packets == 2*NORMAL_PACKETS_PER_SLICE);
        stage = 3;
        repeat (700) @(posedge clk);

        drop_and_fail_armed = 1'b1;
        for (fault_flit = 0; fault_flit < 4; fault_flit = fault_flit + 1) begin
            @(negedge clk);
            build_header(1, 12'd101, fault_flit[5:0], fault_flit == 0, fault_flit == 3);
            a_tx_payload[1023:512] = 512'd0;
            a_tx_payload[512 +: 32] = 32'd101;
            a_tx_valid = 2'b10;
            if (!a_tx_ready[1]) $fatal(1, "fault packet source backpressured");
        end
        @(negedge clk); a_tx_valid = 2'b00;
        stage = 4;
        wait (slice_fault == 2'b10);
        stage = 5;
        wait (replay_commits == 1);
        stage = 6;
        wait (a_replay_occupancy == 0 && b_replay_occupancy == 0);
        stage = 7;
        if (a_active_mask != 2'b01 || b_active_mask != 2'b01) $fatal(1, "bonded endpoints did not enter degraded mapping");
        if (!a_epoch_recovery_required || !b_epoch_recovery_required)
            $fatal(1, "slice-map change did not request coordinated epoch recovery");
        repeat (32) @(posedge clk);
        @(negedge clk); link_epoch = link_epoch + 1'b1;
        wait (!(&a_link_up) && !(&b_link_up));
        wait (&a_link_up && &b_link_up);
        if (a_epoch_recovery_required || b_epoch_recovery_required)
            $fatal(1, "epoch recovery request did not clear after renegotiation");
        repeat (32) @(posedge clk);

        degraded_monitor = 1'b1;
        fork
            drive_degraded_lane(0, DEGRADED_PACKETS_PER_SLICE, 200);
            drive_degraded_lane(1, DEGRADED_PACKETS_PER_SLICE, 200);
        join
        stage = 8;
        timeout_cycles = 0;
        while ((commit_flits < EXPECTED_FIRST_DEGRADED_COMMIT_FLITS) && (timeout_cycles < 20000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        degraded_monitor = 1'b0;
        if (commit_flits != EXPECTED_FIRST_DEGRADED_COMMIT_FLITS) $fatal(1, "first degraded commit count mismatch got %0d", commit_flits);
        if (degraded_physical_flits != 2*DEGRADED_PACKETS_PER_SLICE || degraded_bubbles != 0)
            $fatal(1, "degraded stream mismatch flits=%0d initial_burst_bubbles=%0d", degraded_physical_flits, degraded_bubbles);
        if (a_reliability_error || b_reliability_error || a_mapping_error || b_mapping_error)
            $fatal(1, "unexpected bonded reliability or mapping error");
        stage = 9;
        @(negedge clk); degraded_monitor = 1'b0; slice_fault = 2'b01;
        wait (a_active_mask == 2'b10 && b_active_mask == 2'b10);
        repeat (2) @(posedge clk);
        if (!a_epoch_recovery_required || !b_epoch_recovery_required) $fatal(1, "opposite slice-map change did not request epoch recovery");
        repeat (32) @(posedge clk);
        @(negedge clk); link_epoch = link_epoch + 1'b1;
        wait (!(&a_link_up) && !(&b_link_up));
        wait (&a_link_up && &b_link_up);
        if (a_epoch_recovery_required || b_epoch_recovery_required) $fatal(1, "opposite slice epoch recovery did not clear");
        @(negedge clk); degraded_physical_flits = 0; degraded_bubbles = 0; degraded_gap_length = 0; degraded_started = 1'b0; degraded_physical_slice = 1'b1; degraded_monitor = 1'b1;
        fork
            drive_degraded_lane(0, SECONDARY_DEGRADED_PACKETS_PER_SLICE, 2000);
            drive_degraded_lane(1, SECONDARY_DEGRADED_PACKETS_PER_SLICE, 2000);
        join
        stage = 10;
        timeout_cycles = 0;
        while ((commit_flits < EXPECTED_COMMIT_FLITS) && (timeout_cycles < 4000)) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end
        degraded_monitor = 1'b0;
        if (commit_flits != EXPECTED_COMMIT_FLITS) $fatal(1, "second degraded commit count mismatch got %0d", commit_flits);
        if (degraded_physical_flits != 2*SECONDARY_DEGRADED_PACKETS_PER_SLICE) $fatal(1, "physical-one degraded stream mismatch flits=%0d", degraded_physical_flits);
        if (a_reliability_error || b_reliability_error || a_mapping_error || b_mapping_error) $fatal(1, "unexpected opposite-slice reliability or mapping error");
        $display("TB_KDLINK_RELIABLE_BONDED_ENDPOINT_PASS normal_dual_slice=1 active_packet_loss=1 replay_migration=1 exact_once=1 degraded_physical_zero=1 degraded_physical_one=1 initial_burst_bubbles=0");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "canonical reliable bonded endpoint timeout stage=%0d links=%b/%b commits=%0d packets=%0d replay_commit=%0d fault=%b occupancy=%h/%h errors=%b%b%b%b",
            stage, a_link_up, b_link_up, commit_flits, committed_packets, replay_commits,
            slice_fault, a_replay_occupancy, b_replay_occupancy,
            a_reliability_error, b_reliability_error, a_mapping_error, b_mapping_error);
    end
endmodule
