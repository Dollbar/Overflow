`timescale 1ns/1ps
module tb_kdlink_v2_serdes_full_link;
    localparam integer GROUPS = 12;
    localparam [63:0] GROUP_COUNT = 64'd12;
    localparam [63:0] NOMINAL_DELIVERED_BLOCKS = 64'd240;
    logic clk;
    logic rst_n;
    logic a_to_b_admin_up;
    logic b_to_a_admin_up;
    logic [9:0] a_to_b_signal_detect;
    logic [9:0] b_to_a_signal_detect;
    logic [9:0] a_to_b_rx_ready;
    logic [9:0] b_to_a_rx_ready;
    logic [9:0] a_to_b_force_loss;
    logic [9:0] b_to_a_force_loss;
    logic a_tx_valid;
    logic [659:0] a_tx_blocks;
    logic b_tx_valid;
    logic [659:0] b_tx_blocks;
    logic [9:0] a_to_b_drop;
    logic [9:0] a_to_b_corrupt;
    logic [9:0] a_to_b_burst;
    logic [9:0] b_to_a_drop;
    logic [9:0] b_to_a_corrupt;
    logic [9:0] b_to_a_burst;
    wire [9:0] a_rx_valid;
    wire [659:0] a_rx_blocks;
    wire [9:0] b_rx_valid;
    wire [659:0] b_rx_blocks;
    wire [9:0] a_to_b_cdr_locked;
    wire [9:0] b_to_a_cdr_locked;
    wire [9:0] a_to_b_block_locked;
    wire [9:0] b_to_a_block_locked;
    wire [9:0] a_to_b_lane_ready;
    wire [9:0] b_to_a_lane_ready;
    wire [1:0] a_to_b_state;
    wire [1:0] b_to_a_state;
    wire full_duplex_up;
    wire [63:0] a_to_b_offered;
    wire [63:0] b_to_a_offered;
    wire [63:0] delivered_blocks;
    wire [63:0] dropped_blocks;
    wire [63:0] corrupted_blocks;
    wire [63:0] overflow_blocks;
    wire [63:0] retrain_events;
    integer send_group;
    integer drive_lane;
    integer check_lane;
    integer a_seen [0:9];
    integer b_seen [0:9];
    logic nominal_window;

    kdlink_v2_serdes_link_full_model #(
        .LANES(10), .A_TO_B_PROPAGATION_CYCLES(2), .B_TO_A_PROPAGATION_CYCLES(4),
        .A_TO_B_MAX_LANE_SKEW_CYCLES(2), .B_TO_A_MAX_LANE_SKEW_CYCLES(1),
        .CDR_LOCK_CYCLES(2), .BLOCK_LOCK_CYCLES(2),
        .JITTER_PERIOD_BLOCKS(0), .JITTER_EXTRA_CYCLES(0), .ELASTIC_DEPTH(16)
    ) u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .a_to_b_admin_up_i(a_to_b_admin_up), .b_to_a_admin_up_i(b_to_a_admin_up),
        .a_to_b_signal_detect_i(a_to_b_signal_detect),
        .b_to_a_signal_detect_i(b_to_a_signal_detect),
        .a_to_b_rx_ready_i(a_to_b_rx_ready), .b_to_a_rx_ready_i(b_to_a_rx_ready),
        .a_to_b_force_loss_of_lock_i(a_to_b_force_loss),
        .b_to_a_force_loss_of_lock_i(b_to_a_force_loss),
        .a_tx_group_valid_i(a_tx_valid), .a_tx_group_blocks_i(a_tx_blocks),
        .b_tx_group_valid_i(b_tx_valid), .b_tx_group_blocks_i(b_tx_blocks),
        .inject_a_to_b_drop_i(a_to_b_drop), .inject_a_to_b_corrupt_i(a_to_b_corrupt),
        .inject_a_to_b_burst_i(a_to_b_burst), .inject_b_to_a_drop_i(b_to_a_drop),
        .inject_b_to_a_corrupt_i(b_to_a_corrupt), .inject_b_to_a_burst_i(b_to_a_burst),
        .a_to_b_error_period_blocks_i(32'd0), .b_to_a_error_period_blocks_i(32'd0),
        .a_to_b_error_lane_i(4'd0), .b_to_a_error_lane_i(4'd0),
        .a_rx_lane_valid_o(a_rx_valid), .a_rx_lane_blocks_o(a_rx_blocks),
        .b_rx_lane_valid_o(b_rx_valid), .b_rx_lane_blocks_o(b_rx_blocks),
        .a_to_b_cdr_locked_o(a_to_b_cdr_locked), .b_to_a_cdr_locked_o(b_to_a_cdr_locked),
        .a_to_b_block_locked_o(a_to_b_block_locked),
        .b_to_a_block_locked_o(b_to_a_block_locked),
        .a_to_b_lane_ready_o(a_to_b_lane_ready), .b_to_a_lane_ready_o(b_to_a_lane_ready),
        .a_to_b_state_o(a_to_b_state), .b_to_a_state_o(b_to_a_state),
        .full_duplex_up_o(full_duplex_up), .a_to_b_offered_groups_o(a_to_b_offered),
        .b_to_a_offered_groups_o(b_to_a_offered), .delivered_blocks_o(delivered_blocks),
        .dropped_blocks_o(dropped_blocks), .corrupted_blocks_o(corrupted_blocks),
        .overflow_blocks_o(overflow_blocks), .retrain_events_o(retrain_events)
    );

    always #0.5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin
                a_seen[check_lane] = 0;
                b_seen[check_lane] = 0;
            end
        end else if (nominal_window) begin
            for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin
                if (a_rx_valid[check_lane]) begin
                    if (a_rx_blocks[check_lane*66 +: 16] != a_seen[check_lane][15:0]) begin
                        $fatal(1, "B-to-A full link sequence mismatch lane=%0d", check_lane);
                    end
                    a_seen[check_lane] = a_seen[check_lane] + 1;
                end
                if (b_rx_valid[check_lane]) begin
                    if (b_rx_blocks[check_lane*66 +: 16] != b_seen[check_lane][15:0]) begin
                        $fatal(1, "A-to-B full link sequence mismatch lane=%0d", check_lane);
                    end
                    b_seen[check_lane] = b_seen[check_lane] + 1;
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        a_to_b_admin_up = 1'b0;
        b_to_a_admin_up = 1'b0;
        a_to_b_signal_detect = 10'h3ff;
        b_to_a_signal_detect = 10'h3ff;
        a_to_b_rx_ready = 10'h3ff;
        b_to_a_rx_ready = 10'h3ff;
        a_to_b_force_loss = 10'd0;
        b_to_a_force_loss = 10'd0;
        a_tx_valid = 1'b0;
        b_tx_valid = 1'b0;
        a_tx_blocks = 660'd0;
        b_tx_blocks = 660'd0;
        a_to_b_drop = 10'd0;
        a_to_b_corrupt = 10'd0;
        a_to_b_burst = 10'd0;
        b_to_a_drop = 10'd0;
        b_to_a_corrupt = 10'd0;
        b_to_a_burst = 10'd0;
        nominal_window = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1; a_to_b_admin_up = 1'b1;
        wait (a_to_b_state == 2'd2);
        if (full_duplex_up || b_to_a_state != 2'd0) $fatal(1, "Independent direction admin failed");
        @(negedge clk); b_to_a_admin_up = 1'b1;
        wait (full_duplex_up);
        if (a_to_b_cdr_locked != 10'h3ff || b_to_a_cdr_locked != 10'h3ff ||
            a_to_b_block_locked != 10'h3ff || b_to_a_block_locked != 10'h3ff) begin
            $fatal(1, "Full SerDes link did not acquire all locks");
        end

        nominal_window = 1'b1;
        for (send_group = 0; send_group < GROUPS; send_group = send_group + 1) begin
            @(negedge clk);
            a_tx_valid = 1'b1;
            b_tx_valid = 1'b1;
            for (drive_lane = 0; drive_lane < 10; drive_lane = drive_lane + 1) begin
                a_tx_blocks[drive_lane*66 +: 66] = 66'd0;
                b_tx_blocks[drive_lane*66 +: 66] = 66'd0;
                a_tx_blocks[drive_lane*66 +: 16] = send_group[15:0];
                b_tx_blocks[drive_lane*66 +: 16] = send_group[15:0];
                a_tx_blocks[drive_lane*66 + 16 +: 4] = drive_lane[3:0];
                b_tx_blocks[drive_lane*66 + 16 +: 4] = drive_lane[3:0];
            end
        end
        @(negedge clk); a_tx_valid = 1'b0; b_tx_valid = 1'b0;
        wait (a_seen[0] == GROUPS && a_seen[9] == GROUPS &&
              b_seen[0] == GROUPS && b_seen[9] == GROUPS);
        repeat (3) @(posedge clk); #0.01;
        nominal_window = 1'b0;
        for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin
            if (a_seen[check_lane] != GROUPS || b_seen[check_lane] != GROUPS) begin
                $fatal(1, "Full SerDes link lost nominal blocks lane=%0d a=%0d b=%0d",
                    check_lane, a_seen[check_lane], b_seen[check_lane]);
            end
        end
        if (a_to_b_offered != GROUP_COUNT || b_to_a_offered != GROUP_COUNT ||
            delivered_blocks != NOMINAL_DELIVERED_BLOCKS || overflow_blocks != 0) begin
            $fatal(1, "Full SerDes link nominal counters mismatch offered=%0d/%0d delivered=%0d overflow=%0d",
                a_to_b_offered, b_to_a_offered, delivered_blocks, overflow_blocks);
        end

        @(negedge clk);
        a_tx_valid = 1'b1;
        b_tx_valid = 1'b1;
        a_to_b_drop[0] = 1'b1;
        b_to_a_corrupt[1] = 1'b1;
        @(negedge clk);
        a_tx_valid = 1'b0;
        b_tx_valid = 1'b0;
        a_to_b_drop = 10'd0;
        b_to_a_corrupt = 10'd0;
        wait (dropped_blocks == 1 && corrupted_blocks == 1);

        @(negedge clk); a_to_b_force_loss[4] = 1'b1;
        @(posedge clk); #0.01;
        if (a_to_b_state != 2'd3 || full_duplex_up || a_to_b_lane_ready[4]) begin
            $fatal(1, "Full SerDes link did not enter DEGRADED on lane lock loss");
        end
        @(negedge clk); a_to_b_force_loss = 10'd0;
        wait (full_duplex_up);
        if (retrain_events != 1) $fatal(1, "Full SerDes link retrain count mismatch=%0d", retrain_events);

        @(negedge clk); b_to_a_admin_up = 1'b0;
        @(posedge clk); #0.01;
        if (b_to_a_state != 2'd0 || full_duplex_up || a_to_b_state != 2'd2) begin
            $fatal(1, "Full SerDes independent direction shutdown failed");
        end
        $display("TB_KDLINK_V2_SERDES_FULL_LINK_PASS groups=%0d lanes=10 directions=2 drop=1 corrupt=1 retrain=1",
            GROUPS);
        $finish;
    end

    initial begin
        #4000;
        $fatal(1, "KDLink full SerDes link timeout");
    end
endmodule
