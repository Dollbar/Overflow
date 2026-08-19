`timescale 1ns/1ps
module tb_kdlink_v2_serdes_channel;
    localparam integer NOMINAL_GROUPS = 128;
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
    logic nominal_window;
    logic started [0:9];

    kdlink_v2_serdes_channel_model #(
        .PROPAGATION_CYCLES(3),
        .MAX_LANE_SKEW_CYCLES(2),
        .TRAINING_CYCLES(8)
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
            for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin
                seen[check_lane] = 0;
                bubbles[check_lane] = 0;
                started[check_lane] = 1'b0;
            end
        end else if (nominal_window) begin
            for (check_lane = 0; check_lane < 10; check_lane = check_lane + 1) begin
                if (rx_lane_valid[check_lane]) begin
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
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1; admin_up = 1'b1; lane_up = 10'h3ff;
        wait (link_up);
        if (link_state != 2'd2) $fatal(1, "SerDes channel did not reach UP");

        nominal_window = 1'b1;
        for (send_group = 0; send_group < NOMINAL_GROUPS; send_group = send_group + 1) begin
            @(negedge clk);
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

        @(negedge clk); lane_up[4] = 1'b0;
        repeat (2) @(posedge clk); #0.01;
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
        if (transmitted_groups != NOMINAL_GROUPS + 3) begin
            $fatal(1, "SerDes transmitted group count mismatch count=%0d", transmitted_groups);
        end
        $display("TB_KDLINK_V2_SERDES_CHANNEL_PASS groups=%0d lanes=10 propagation=3 max_skew=2 bubbles=0 drops=2 corruptions=3 retrain=1",
            NOMINAL_GROUPS);
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "KDLink-v2 SerDes channel timeout");
    end
endmodule
