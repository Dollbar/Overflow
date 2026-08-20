`timescale 1ns/1ps
module tb_kdlink_v2_serdes_channel;
    localparam integer NOMINAL_GROUPS = 128;
    localparam integer PROPAGATION_CYCLES = 3;
    localparam integer MAX_LANE_SKEW_CYCLES = 2;
    localparam integer TRAINING_CYCLES = 8;
    logic clk;
    logic rst_n;
    logic admin_up;
    logic [9:0] lane_up;
    logic tx_group_valid;
    logic [659:0] tx_group_blocks;
    logic [9:0] inject_drop;
    logic [9:0] inject_corrupt;
    logic [31:0] ber_period_groups;
    logic [3:0] ber_lane;
    wire [9:0] rx_lane_valid;
    wire [659:0] rx_lane_blocks;
    wire [1:0] link_state;
    wire link_up;
    wire [31:0] transmitted_groups;
    wire [31:0] dropped_blocks;
    wire [31:0] corrupted_blocks;
    integer send_group;
    integer drive_lane;
    integer check_lane;
    integer seen [0:9];
    integer bubbles [0:9];
    integer first_seen_cycle [0:9];
    integer cycle_count;
    integer launch_cycle;
    integer training_edges;
    logic nominal_window;
    logic admin_flush_window;
    logic lane_flush_window;
    logic started [0:9];

    kdlink_v2_serdes_channel_model #(
        .PROPAGATION_CYCLES(PROPAGATION_CYCLES),
        .MAX_LANE_SKEW_CYCLES(MAX_LANE_SKEW_CYCLES),
        .TRAINING_CYCLES(TRAINING_CYCLES)
    ) u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .admin_up_i(admin_up), .lane_up_i(lane_up),
        .tx_group_valid_i(tx_group_valid), .tx_group_blocks_i(tx_group_blocks),
        .inject_drop_i(inject_drop), .inject_corrupt_i(inject_corrupt),
        .ber_period_groups_i(ber_period_groups), .ber_lane_i(ber_lane),
        .rx_lane_valid_o(rx_lane_valid), .rx_lane_blocks_o(rx_lane_blocks),
        .link_state_o(link_state), .link_up_o(link_up),
        .transmitted_groups_o(transmitted_groups), .dropped_blocks_o(dropped_blocks),
        .corrupted_blocks_o(corrupted_blocks)
    );

    always #0.5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count = 0;
            for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin
                seen[check_lane] = 0;
                bubbles[check_lane] = 0;
                first_seen_cycle[check_lane] = -1;
                started[check_lane] = 1'b0;
            end
        end else begin
            cycle_count = cycle_count + 1;
            if (admin_flush_window && (rx_lane_valid != 10'd0)) begin
                $fatal(1, "SerDes admin-down did not flush all in-flight blocks valid=%h", rx_lane_valid);
            end
            if (lane_flush_window && rx_lane_valid[4]) begin
                $fatal(1, "SerDes lane-down did not flush lane 4");
            end
            if (nominal_window) begin
                for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin
                    if (rx_lane_valid[check_lane]) begin
                        if (!started[check_lane]) first_seen_cycle[check_lane] = cycle_count;
                        started[check_lane] = 1'b1;
                        if (rx_lane_blocks[check_lane*66 +: 16] != seen[check_lane][15:0]) begin
                            $fatal(1, "SerDes lane sequence mismatch lane=%0d expected=%0d observed=%0d",
                                check_lane, seen[check_lane], rx_lane_blocks[check_lane*66 +: 16]);
                        end
                        if (rx_lane_blocks[check_lane*66 + 16 +: 4] != check_lane[3:0]) begin
                            $fatal(1, "SerDes lane identity mismatch lane=%0d", check_lane);
                        end
                        seen[check_lane] = seen[check_lane] + 1;
                    end else if (started[check_lane] && (seen[check_lane] < NOMINAL_GROUPS)) begin
                        bubbles[check_lane] = bubbles[check_lane] + 1;
                    end
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        admin_up = 1'b0;
        lane_up = 10'd0;
        tx_group_valid = 1'b0;
        tx_group_blocks = 660'd0;
        inject_drop = 10'd0;
        inject_corrupt = 10'd0;
        ber_period_groups = 32'd0;
        ber_lane = 4'd0;
        nominal_window = 1'b0;
        admin_flush_window = 1'b0;
        lane_flush_window = 1'b0;
        launch_cycle = 0;
        training_edges = 0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1; admin_up = 1'b1; lane_up = 10'h3ff;
        while (!link_up) begin
            @(posedge clk); #0.01;
            training_edges = training_edges + 1;
        end
        if (training_edges != TRAINING_CYCLES) begin
            $fatal(1, "SerDes training duration mismatch expected=%0d observed=%0d",
                TRAINING_CYCLES, training_edges);
        end
        if (link_state != 2'd2) $fatal(1, "SerDes channel did not reach UP");

        nominal_window = 1'b1;
        for (send_group = 0; send_group < NOMINAL_GROUPS; send_group = send_group + 1) begin
            @(negedge clk);
            if (send_group == 0) launch_cycle = cycle_count + 1;
            tx_group_valid = 1'b1;
            for (drive_lane = 0; drive_lane < 10; drive_lane = drive_lane + 1) begin
                tx_group_blocks[drive_lane*66 +: 66] = 66'd0;
                tx_group_blocks[drive_lane*66 +: 16] = send_group[15:0];
                tx_group_blocks[drive_lane*66 + 16 +: 4] = drive_lane[3:0];
                tx_group_blocks[drive_lane*66 + 32 +: 32] = 32'hcafe_0000;
                tx_group_blocks[drive_lane*66 + 32 +: 16] = send_group[15:0];
            end
        end
        @(negedge clk); tx_group_valid = 1'b0;
        wait (seen[0] == NOMINAL_GROUPS && seen[9] == NOMINAL_GROUPS);
        repeat (4) @(posedge clk); #0.01;
        nominal_window = 1'b0;
        for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin
            if (seen[check_lane] != NOMINAL_GROUPS || bubbles[check_lane] != 0) begin
                $fatal(1, "SerDes nominal performance failure lane=%0d seen=%0d bubbles=%0d",
                    check_lane, seen[check_lane], bubbles[check_lane]);
            end
            if ((first_seen_cycle[check_lane] - launch_cycle) !=
                (PROPAGATION_CYCLES + (check_lane % (MAX_LANE_SKEW_CYCLES + 1)))) begin
                $fatal(1, "SerDes latency mismatch lane=%0d launch=%0d first=%0d",
                    check_lane, launch_cycle, first_seen_cycle[check_lane]);
            end
        end

        @(negedge clk);
        tx_group_valid = 1'b1;
        inject_drop = 10'b0000010001;
        inject_corrupt = 10'b1010000000;
        @(negedge clk);
        tx_group_valid = 1'b0;
        inject_drop = 10'd0;
        inject_corrupt = 10'd0;
        repeat (8) @(posedge clk); #0.01;
        if (dropped_blocks != 32'd2 || corrupted_blocks != 32'd2) begin
            $fatal(1, "SerDes directed fault counters mismatch drop=%0d corrupt=%0d",
                dropped_blocks, corrupted_blocks);
        end

        @(negedge clk);
        tx_group_valid = 1'b1;
        inject_drop[2] = 1'b1;
        inject_corrupt[2] = 1'b1;
        @(negedge clk);
        tx_group_valid = 1'b0;
        inject_drop = 10'd0;
        inject_corrupt = 10'd0;
        repeat (8) @(posedge clk); #0.01;
        if (dropped_blocks != 32'd3 || corrupted_blocks != 32'd2) begin
            $fatal(1, "SerDes drop precedence mismatch drop=%0d corrupt=%0d",
                dropped_blocks, corrupted_blocks);
        end

        @(negedge clk); tx_group_valid = 1'b1;
        @(negedge clk); tx_group_valid = 1'b0; admin_up = 1'b0; admin_flush_window = 1'b1;
        repeat (8) @(posedge clk); #0.01;
        admin_flush_window = 1'b0;
        if (link_state != 2'd0 || link_up) $fatal(1, "SerDes admin-down did not enter DOWN");
        @(negedge clk); admin_up = 1'b1;
        wait (link_up);

        @(negedge clk); tx_group_valid = 1'b1;
        @(negedge clk); tx_group_valid = 1'b0; lane_up[4] = 1'b0; lane_flush_window = 1'b1;
        repeat (8) @(posedge clk); #0.01;
        lane_flush_window = 1'b0;
        if (link_state != 2'd3 || link_up) $fatal(1, "SerDes lane failure did not enter DEGRADED");
        @(negedge clk); lane_up[4] = 1'b1;
        wait (link_state == 2'd1);
        wait (link_up);

        @(negedge clk);
        ber_period_groups = 32'd2;
        ber_lane = 4'd5;
        tx_group_valid = 1'b1;
        repeat (2) @(negedge clk);
        tx_group_valid = 1'b0;
        ber_period_groups = 32'd0;
        repeat (8) @(posedge clk); #0.01;
        if (corrupted_blocks != 32'd3) begin
            $fatal(1, "SerDes deterministic BER injection count mismatch count=%0d", corrupted_blocks);
        end
        if (transmitted_groups != NOMINAL_GROUPS + 6) begin
            $fatal(1, "SerDes transmitted group count mismatch count=%0d", transmitted_groups);
        end
        if (dropped_blocks != 32'd3) $fatal(1, "SerDes final drop count mismatch count=%0d", dropped_blocks);
        $display("TB_KDLINK_V2_SERDES_CHANNEL_PASS groups=%0d lanes=10 propagation=3 max_skew=2 bubbles=0 drops=3 corruptions=3 flushes=2 retrain=2",
            NOMINAL_GROUPS);
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "KDLink-v2 SerDes channel timeout");
    end
endmodule
