`timescale 1ns/1ps
module tb_kdlink_v2_serdes_full_lane;
    localparam integer NOMINAL_BLOCKS = 20;
    logic clk;
    logic rst_n;
    logic admin_up;
    logic signal_detect;
    logic rx_ready;
    logic force_loss_of_lock;
    logic tx_valid;
    logic [65:0] tx_block;
    logic inject_drop;
    logic inject_corrupt;
    logic inject_burst;
    logic [31:0] error_period;
    wire normal_rx_valid;
    wire [65:0] normal_rx_block;
    wire normal_ready;
    wire [2:0] normal_state;
    wire [31:0] normal_offered;
    wire [31:0] normal_delivered;
    wire [31:0] normal_dropped;
    wire [31:0] normal_corrupted;
    wire [31:0] normal_overflow;
    wire [31:0] normal_retrain;
    wire overflow_rx_valid;
    wire [65:0] overflow_rx_block;
    wire overflow_ready;
    wire [31:0] overflow_offered;
    wire [31:0] overflow_delivered;
    wire [31:0] overflow_dropped;
    wire [31:0] overflow_overflow;
    integer send_index;
    integer normal_expected;
    integer overflow_last;
    logic nominal_window;
    logic overflow_started;

    kdlink_v2_serdes_lane_full_model #(
        .PROPAGATION_CYCLES(2), .STATIC_SKEW_CYCLES(1),
        .CDR_LOCK_CYCLES(2), .BLOCK_LOCK_CYCLES(2),
        .JITTER_PERIOD_BLOCKS(4), .JITTER_EXTRA_CYCLES(4),
        .BURST_ERROR_LENGTH_BLOCKS(3), .ELASTIC_DEPTH(64)
    ) u_ordered (
        .clk_i(clk), .rst_n_i(rst_n), .admin_up_i(admin_up),
        .signal_detect_i(signal_detect), .rx_ready_i(rx_ready),
        .force_loss_of_lock_i(force_loss_of_lock),
        .tx_block_valid_i(tx_valid), .tx_block_i(tx_block),
        .inject_drop_i(inject_drop), .inject_corrupt_i(inject_corrupt),
        .inject_burst_i(inject_burst), .error_period_blocks_i(error_period),
        .rx_block_valid_o(normal_rx_valid), .rx_block_o(normal_rx_block),
        .cdr_locked_o(), .block_locked_o(), .lane_ready_o(normal_ready),
        .lane_state_o(normal_state), .offered_blocks_o(normal_offered),
        .delivered_blocks_o(normal_delivered), .dropped_blocks_o(normal_dropped),
        .corrupted_blocks_o(normal_corrupted), .overflow_blocks_o(normal_overflow),
        .retrain_events_o(normal_retrain)
    );

    kdlink_v2_serdes_lane_full_model #(
        .PROPAGATION_CYCLES(2), .STATIC_SKEW_CYCLES(0),
        .CDR_LOCK_CYCLES(2), .BLOCK_LOCK_CYCLES(2),
        .JITTER_PERIOD_BLOCKS(4), .JITTER_EXTRA_CYCLES(4),
        .BURST_ERROR_LENGTH_BLOCKS(3), .ELASTIC_DEPTH(4)
    ) u_overflow (
        .clk_i(clk), .rst_n_i(rst_n), .admin_up_i(admin_up),
        .signal_detect_i(signal_detect), .rx_ready_i(rx_ready),
        .force_loss_of_lock_i(force_loss_of_lock),
        .tx_block_valid_i(tx_valid), .tx_block_i(tx_block),
        .inject_drop_i(inject_drop), .inject_corrupt_i(inject_corrupt),
        .inject_burst_i(inject_burst), .error_period_blocks_i(error_period),
        .rx_block_valid_o(overflow_rx_valid), .rx_block_o(overflow_rx_block),
        .cdr_locked_o(), .block_locked_o(), .lane_ready_o(overflow_ready),
        .lane_state_o(), .offered_blocks_o(overflow_offered),
        .delivered_blocks_o(overflow_delivered), .dropped_blocks_o(overflow_dropped),
        .corrupted_blocks_o(), .overflow_blocks_o(overflow_overflow),
        .retrain_events_o()
    );

    always #0.5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            normal_expected = 0;
            overflow_last = 0;
            overflow_started = 1'b0;
        end else begin
            if (nominal_window && normal_rx_valid) begin
                if (normal_rx_block[15:0] != normal_expected[15:0]) begin
                    $fatal(1, "Full SerDes lane lost ordering expected=%0d observed=%0d",
                        normal_expected, normal_rx_block[15:0]);
                end
                normal_expected = normal_expected + 1;
            end
            if (nominal_window && overflow_rx_valid) begin
                if (overflow_started && {16'd0, overflow_rx_block[15:0]} <= overflow_last) begin
                    $fatal(1, "Overflow SerDes lane reordered data last=%0d observed=%0d",
                        overflow_last, overflow_rx_block[15:0]);
                end
                overflow_last = {16'd0, overflow_rx_block[15:0]};
                overflow_started = 1'b1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        admin_up = 1'b0;
        signal_detect = 1'b0;
        rx_ready = 1'b0;
        force_loss_of_lock = 1'b0;
        tx_valid = 1'b0;
        tx_block = 66'd0;
        inject_drop = 1'b0;
        inject_corrupt = 1'b0;
        inject_burst = 1'b0;
        error_period = 32'd0;
        nominal_window = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        admin_up = 1'b1;
        signal_detect = 1'b1;
        rx_ready = 1'b1;
        wait (normal_ready && overflow_ready);

        nominal_window = 1'b1;
        for (send_index = 0; send_index < NOMINAL_BLOCKS; send_index = send_index + 1) begin
            @(negedge clk);
            tx_valid = 1'b1;
            tx_block = 66'd0;
            tx_block[15:0] = send_index[15:0];
        end
        @(negedge clk); tx_valid = 1'b0;
        wait (normal_delivered == NOMINAL_BLOCKS);
        wait (overflow_delivered + overflow_dropped == NOMINAL_BLOCKS);
        repeat (2) @(posedge clk); #0.01;
        nominal_window = 1'b0;
        if (normal_expected != NOMINAL_BLOCKS || normal_overflow != 0 || normal_dropped != 0) begin
            $fatal(1, "Full SerDes ordered lane failed delivered=%0d drop=%0d overflow=%0d",
                normal_delivered, normal_dropped, normal_overflow);
        end
        if (overflow_overflow == 0 || overflow_dropped != overflow_overflow) begin
            $fatal(1, "Full SerDes elastic overflow was not counted drop=%0d overflow=%0d",
                overflow_dropped, overflow_overflow);
        end

        @(negedge clk); tx_valid = 1'b1; inject_drop = 1'b1;
        @(negedge clk); tx_valid = 1'b0; inject_drop = 1'b0;
        @(negedge clk); tx_valid = 1'b1; inject_corrupt = 1'b1;
        @(negedge clk); tx_valid = 1'b0; inject_corrupt = 1'b0;
        @(negedge clk); tx_valid = 1'b1; inject_burst = 1'b1;
        @(negedge clk); inject_burst = 1'b0;
        repeat (2) @(negedge clk);
        tx_valid = 1'b0;
        @(negedge clk); error_period = 32'd2; tx_valid = 1'b1;
        repeat (2) @(negedge clk);
        tx_valid = 1'b0; error_period = 32'd0;
        wait (normal_delivered + normal_dropped == normal_offered);
        repeat (2) @(posedge clk); #0.01;
        if (normal_dropped != 1 || normal_corrupted != 5) begin
            $fatal(1, "Full SerDes fault counters mismatch drop=%0d corrupt=%0d",
                normal_dropped, normal_corrupted);
        end

        @(negedge clk); force_loss_of_lock = 1'b1;
        @(posedge clk); #0.01;
        if (normal_state != 3'd4 || normal_ready) $fatal(1, "Forced lock loss did not enter FAULT");
        @(negedge clk); force_loss_of_lock = 1'b0;
        wait (normal_ready);
        if (normal_retrain != 1) $fatal(1, "Retrain counter mismatch count=%0d", normal_retrain);

        @(negedge clk); signal_detect = 1'b0;
        @(posedge clk); #0.01;
        if (normal_state != 3'd0) $fatal(1, "Signal loss did not enter DOWN");
        $display("TB_KDLINK_V2_SERDES_FULL_LANE_PASS nominal=%0d faults=6 overflow=%0d retrain=1",
            NOMINAL_BLOCKS, overflow_overflow);
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "KDLink full SerDes lane timeout");
    end
endmodule
