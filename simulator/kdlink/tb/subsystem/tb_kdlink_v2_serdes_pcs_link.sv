`timescale 1ns/1ps
module tb_kdlink_v2_serdes_pcs_link;
    localparam integer DATA_FLITS = 256;
    logic clk;
    logic rst_n;
    logic admin_up;
    logic a_tx_valid;
    logic [639:0] a_tx_flit;
    logic a_tx_training;
    logic a_tx_marker;
    logic [15:0] a_marker_sequence;
    logic b_tx_valid;
    logic [639:0] b_tx_flit;
    logic b_tx_training;
    logic b_tx_marker;
    logic [15:0] b_marker_sequence;
    wire a_tx_blocks_valid;
    wire [659:0] a_tx_blocks;
    wire b_tx_blocks_valid;
    wire [659:0] b_tx_blocks;
    wire [9:0] a_rx_lane_valid;
    wire [659:0] a_rx_lane_blocks;
    wire [9:0] b_rx_lane_valid;
    wire [659:0] b_rx_lane_blocks;
    wire a_rx_valid;
    wire [639:0] a_rx_flit;
    wire b_rx_valid;
    wire [639:0] b_rx_flit;
    wire a_block_lock;
    wire a_deskew_lock;
    wire a_block_error;
    wire a_deskew_overflow;
    wire b_block_lock;
    wire b_deskew_lock;
    wire b_block_error;
    wire b_deskew_overflow;
    logic [9:0] inject_a_to_b_drop;
    logic [9:0] inject_a_to_b_corrupt;
    logic [9:0] inject_b_to_a_drop;
    logic [9:0] inject_b_to_a_corrupt;
    wire [1:0] a_to_b_state;
    wire [1:0] b_to_a_state;
    wire full_duplex_up;
    wire [31:0] a_to_b_groups;
    wire [31:0] b_to_a_groups;
    wire [31:0] dropped_blocks;
    wire [31:0] corrupted_blocks;
    integer send_flit;
    integer a_received;
    integer b_received;
    integer a_bubbles;
    integer b_bubbles;
    logic a_started;
    logic b_started;
    logic b_error_seen;

    kdlink_v2_pcs u_pcs_a (
        .clk_i(clk), .rst_n_i(rst_n),
        .tx_flit_valid_i(a_tx_valid), .tx_flit_i(a_tx_flit),
        .tx_training_i(a_tx_training), .tx_alignment_marker_i(a_tx_marker),
        .tx_marker_sequence_i(a_marker_sequence),
        .tx_blocks_valid_o(a_tx_blocks_valid), .tx_blocks_o(a_tx_blocks),
        .rx_lane_valid_i(a_rx_lane_valid), .rx_lane_blocks_i(a_rx_lane_blocks),
        .rx_flit_valid_o(a_rx_valid), .rx_flit_o(a_rx_flit),
        .rx_block_lock_o(a_block_lock), .rx_deskew_locked_o(a_deskew_lock),
        .rx_block_error_o(a_block_error), .rx_deskew_overflow_o(a_deskew_overflow)
    );

    kdlink_v2_pcs u_pcs_b (
        .clk_i(clk), .rst_n_i(rst_n),
        .tx_flit_valid_i(b_tx_valid), .tx_flit_i(b_tx_flit),
        .tx_training_i(b_tx_training), .tx_alignment_marker_i(b_tx_marker),
        .tx_marker_sequence_i(b_marker_sequence),
        .tx_blocks_valid_o(b_tx_blocks_valid), .tx_blocks_o(b_tx_blocks),
        .rx_lane_valid_i(b_rx_lane_valid), .rx_lane_blocks_i(b_rx_lane_blocks),
        .rx_flit_valid_o(b_rx_valid), .rx_flit_o(b_rx_flit),
        .rx_block_lock_o(b_block_lock), .rx_deskew_locked_o(b_deskew_lock),
        .rx_block_error_o(b_block_error), .rx_deskew_overflow_o(b_deskew_overflow)
    );

    kdlink_v2_serdes_link_model #(
        .PROPAGATION_CYCLES(4),
        .MAX_LANE_SKEW_CYCLES(2),
        .TRAINING_CYCLES(8)
    ) u_link (
        .clk_i(clk), .rst_n_i(rst_n), .admin_up_i(admin_up),
        .a_to_b_lane_up_i(10'h3ff), .b_to_a_lane_up_i(10'h3ff),
        .a_tx_group_valid_i(a_tx_blocks_valid), .a_tx_group_blocks_i(a_tx_blocks),
        .b_tx_group_valid_i(b_tx_blocks_valid), .b_tx_group_blocks_i(b_tx_blocks),
        .inject_a_to_b_drop_i(inject_a_to_b_drop), .inject_a_to_b_corrupt_i(inject_a_to_b_corrupt),
        .inject_b_to_a_drop_i(inject_b_to_a_drop), .inject_b_to_a_corrupt_i(inject_b_to_a_corrupt),
        .ber_period_groups_i(32'd0), .ber_lane_i(4'd0),
        .a_rx_lane_valid_o(a_rx_lane_valid), .a_rx_lane_blocks_o(a_rx_lane_blocks),
        .b_rx_lane_valid_o(b_rx_lane_valid), .b_rx_lane_blocks_o(b_rx_lane_blocks),
        .a_to_b_state_o(a_to_b_state), .b_to_a_state_o(b_to_a_state),
        .full_duplex_up_o(full_duplex_up), .a_to_b_groups_o(a_to_b_groups),
        .b_to_a_groups_o(b_to_a_groups), .dropped_blocks_o(dropped_blocks),
        .corrupted_blocks_o(corrupted_blocks)
    );

    always #0.5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_received = 0;
            b_received = 0;
            a_bubbles = 0;
            b_bubbles = 0;
            a_started = 1'b0;
            b_started = 1'b0;
            b_error_seen = 1'b0;
        end else begin
            if (b_block_error) b_error_seen = 1'b1;
            if (a_rx_valid && (a_received < DATA_FLITS)) begin
                a_started = 1'b1;
                if (a_rx_flit[31:0] != a_received[31:0] ||
                    a_rx_flit[639:608] != (32'hb000_0000 | a_received[31:0])) begin
                    $fatal(1, "B-to-A PCS/SerDes data mismatch index=%0d", a_received);
                end
                a_received = a_received + 1;
            end else if (a_started && (a_received < DATA_FLITS)) begin
                a_bubbles = a_bubbles + 1;
            end
            if (b_rx_valid && (b_received < DATA_FLITS)) begin
                b_started = 1'b1;
                if (b_rx_flit[31:0] != b_received[31:0] ||
                    b_rx_flit[639:608] != (32'ha000_0000 | b_received[31:0])) begin
                    $fatal(1, "A-to-B PCS/SerDes data mismatch index=%0d", b_received);
                end
                b_received = b_received + 1;
            end else if (b_started && (b_received < DATA_FLITS)) begin
                b_bubbles = b_bubbles + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        admin_up = 1'b0;
        a_tx_valid = 1'b0;
        a_tx_flit = 640'd0;
        a_tx_training = 1'b0;
        a_tx_marker = 1'b0;
        a_marker_sequence = 16'h1234;
        b_tx_valid = 1'b0;
        b_tx_flit = 640'd0;
        b_tx_training = 1'b0;
        b_tx_marker = 1'b0;
        b_marker_sequence = 16'h5678;
        inject_a_to_b_drop = 10'd0;
        inject_a_to_b_corrupt = 10'd0;
        inject_b_to_a_drop = 10'd0;
        inject_b_to_a_corrupt = 10'd0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1; admin_up = 1'b1;
        wait (full_duplex_up);
        if (a_to_b_state != 2'd2 || b_to_a_state != 2'd2) begin
            $fatal(1, "SerDes full-duplex link did not reach UP");
        end

        repeat (24) begin
            @(negedge clk);
            a_tx_training = 1'b1;
            b_tx_training = 1'b1;
        end
        @(negedge clk);
        a_tx_training = 1'b0;
        b_tx_training = 1'b0;
        repeat (4) begin
            @(negedge clk);
            a_tx_marker = 1'b1;
            b_tx_marker = 1'b1;
        end
        @(negedge clk);
        a_tx_marker = 1'b0;
        b_tx_marker = 1'b0;
        repeat (8) @(posedge clk); #0.01;
        if (!a_block_lock || !a_deskew_lock || !b_block_lock || !b_deskew_lock) begin
            $fatal(1, "PCS did not lock through skewed SerDes channel a=%b/%b b=%b/%b",
                a_block_lock, a_deskew_lock, b_block_lock, b_deskew_lock);
        end

        for (send_flit = 0; send_flit < DATA_FLITS; send_flit = send_flit + 1) begin
            @(negedge clk);
            a_tx_valid = 1'b1;
            b_tx_valid = 1'b1;
            a_tx_flit = {640{send_flit[0]}};
            b_tx_flit = {640{~send_flit[0]}};
            a_tx_flit[31:0] = send_flit[31:0];
            a_tx_flit[639:608] = 32'ha000_0000 | send_flit[31:0];
            b_tx_flit[31:0] = send_flit[31:0];
            b_tx_flit[639:608] = 32'hb000_0000 | send_flit[31:0];
        end
        @(negedge clk);
        a_tx_valid = 1'b0;
        b_tx_valid = 1'b0;
        wait (a_received == DATA_FLITS && b_received == DATA_FLITS);
        repeat (4) @(posedge clk); #0.01;
        if (a_bubbles != 0 || b_bubbles != 0 || a_deskew_overflow || b_deskew_overflow) begin
            $fatal(1, "SerDes PCS steady-state performance failure bubbles=%0d/%0d overflow=%b/%b",
                a_bubbles, b_bubbles, a_deskew_overflow, b_deskew_overflow);
        end

        @(negedge clk);
        a_tx_valid = 1'b1;
        a_tx_flit[31:0] = DATA_FLITS;
        inject_a_to_b_corrupt[3] = 1'b1;
        @(negedge clk);
        a_tx_valid = 1'b0;
        inject_a_to_b_corrupt[3] = 1'b1;
        @(negedge clk);
        inject_a_to_b_corrupt = 10'd0;
        repeat (12) @(posedge clk); #0.01;
        if (!b_error_seen || b_block_lock || b_deskew_lock || corrupted_blocks != 32'd1) begin
            $fatal(1, "PCS SerDes corruption did not force loss of lock error=%b lock=%b/%b count=%0d",
                b_error_seen, b_block_lock, b_deskew_lock, corrupted_blocks);
        end
        if (dropped_blocks != 32'd0) $fatal(1, "Unexpected SerDes drop count=%0d", dropped_blocks);
        $display("TB_KDLINK_V2_SERDES_PCS_LINK_PASS directions=2 data_flits_per_direction=%0d propagation=4 max_skew=2 bubbles=0 corruption_detected=1",
            DATA_FLITS);
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "KDLink-v2 SerDes PCS link timeout");
    end
endmodule
