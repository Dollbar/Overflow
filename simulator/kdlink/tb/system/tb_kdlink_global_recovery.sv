`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_global_recovery;
    reg clk;
    reg rst_n;
    reg issue_valid;
    wire issue_ready;
    reg [63:0] issue_transaction_id;
    reg [7:0] issue_epoch;
    reg [11:0] issue_timeout;
    wire send_valid;
    reg send_ready;
    wire [63:0] send_transaction_id;
    wire [7:0] send_epoch;
    wire [3:0] send_retry_count;
    reg route_reset;
    reg [7:0] route_epoch;
    reg destination_commit_valid;
    wire destination_commit_ready;
    wire deliver_valid;
    wire [63:0] deliver_transaction_id;
    wire ack_valid;
    wire [7:0] ack_source_domain;
    wire [7:0] ack_destination_domain;
    wire [4:0] ack_source_node;
    wire [4:0] ack_destination_node;
    wire [7:0] ack_epoch;
    wire [63:0] ack_transaction_id;
    wire [1:0] ack_status;
    wire duplicate_seen;
    reg forward_ack;
    reg [7:0] tracker_source_domain;
    reg [7:0] tracker_destination_domain;
    reg [4:0] tracker_source_node;
    reg [4:0] tracker_destination_node;
    reg [63:0] sweep_lfsr;
    wire [511:0] ack_payload;
    wire [7:0] decoded_source_domain;
    wire [7:0] decoded_destination_domain;
    wire [4:0] decoded_source_node;
    wire [4:0] decoded_destination_node;
    wire [7:0] decoded_epoch;
    wire [63:0] decoded_transaction_id;
    wire [1:0] decoded_status;
    wire decoded_valid;
    wire completion_valid;
    wire [63:0] completion_transaction_id;
    wire source_error;
    wire retry_exhausted;
    wire [4:0] outstanding_count;
    integer delivery_count;
    integer ack_count;
    integer cycle_count;
    integer transaction_slot;
    integer recovery_watchdog;
    integer retry_pulses;
    integer retry_index;
    kdlink_global_transaction_source #(
        .REPLAY_GRACE_CYCLES(12'd32)
    ) u_source (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .issue_valid_i(issue_valid),
        .issue_ready_o(issue_ready),
        .issue_transaction_id_i(issue_transaction_id),
        .issue_topology_epoch_i(issue_epoch),
        .issue_timeout_quanta_i(issue_timeout),
        .send_valid_o(send_valid),
        .send_ready_i(send_ready),
        .send_transaction_id_o(send_transaction_id),
        .send_topology_epoch_o(send_epoch),
        .send_retry_count_o(send_retry_count),
        .commit_valid_i(ack_valid && forward_ack && decoded_valid),
        .commit_transaction_id_i(decoded_transaction_id),
        .commit_topology_epoch_i(decoded_epoch),
        .commit_status_i(decoded_status),
        .route_reset_i(route_reset),
        .route_topology_epoch_i(route_epoch),
        .completion_valid_o(completion_valid),
        .completion_transaction_id_o(completion_transaction_id),
        .protocol_error_o(source_error),
        .retry_exhausted_o(retry_exhausted),
        .outstanding_count_o(outstanding_count)
    );
    kdlink_global_commit_tracker #(
        .REPLAY_GRACE_CYCLES(12'd32)
    ) u_tracker (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .route_reset_i(route_reset),
        .commit_valid_i(destination_commit_valid),
        .commit_ready_o(destination_commit_ready),
        .source_domain_i(tracker_source_domain),
        .destination_domain_i(tracker_destination_domain),
        .source_node_i(tracker_source_node),
        .destination_node_i(tracker_destination_node),
        .topology_epoch_i(send_epoch),
        .global_transaction_id_i(send_transaction_id),
        .deliver_valid_o(deliver_valid),
        .deliver_transaction_id_o(deliver_transaction_id),
        .global_ack_valid_o(ack_valid),
        .global_ack_source_domain_o(ack_source_domain),
        .global_ack_destination_domain_o(ack_destination_domain),
        .global_ack_source_node_o(ack_source_node),
        .global_ack_destination_node_o(ack_destination_node),
        .global_ack_topology_epoch_o(ack_epoch),
        .global_ack_transaction_id_o(ack_transaction_id),
        .global_ack_status_o(ack_status),
        .duplicate_seen_o(duplicate_seen)
    );
    kdlink_global_commit_codec u_ack_encoder (
        .source_domain_i(ack_source_domain),
        .destination_domain_i(ack_destination_domain),
        .source_node_i(ack_source_node),
        .destination_node_i(ack_destination_node),
        .topology_epoch_i(ack_epoch),
        .global_transaction_id_i(ack_transaction_id),
        .status_i(ack_status),
        .payload_o(ack_payload)
    );
    kdlink_global_commit_decoder u_ack_decoder (
        .payload_i(ack_payload),
        .source_domain_o(decoded_source_domain),
        .destination_domain_o(decoded_destination_domain),
        .source_node_o(decoded_source_node),
        .destination_node_o(decoded_destination_node),
        .topology_epoch_o(decoded_epoch),
        .global_transaction_id_o(decoded_transaction_id),
        .status_o(decoded_status),
        .payload_valid_o(decoded_valid)
    );
    always #0.5 clk = ~clk;
    always @(posedge clk) begin
        if (deliver_valid) delivery_count <= delivery_count + 1;
        if (ack_valid) ack_count <= ack_count + 1;
    end
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        issue_valid = 1'b0;
        issue_transaction_id = 64'h1234_5678_9abc_def0;
        issue_epoch = 8'd7;
        issue_timeout = 12'd100;
        send_ready = 1'b1;
        route_reset = 1'b0;
        route_epoch = 8'd8;
        destination_commit_valid = 1'b0;
        forward_ack = 1'b0;
        tracker_source_domain = 8'd3;
        tracker_destination_domain = 8'd255;
        tracker_source_node = 5'd17;
        tracker_destination_node = 5'd4;
        sweep_lfsr = 64'hd6e8_feb8_6659_fd93;
        delivery_count = 0;
        ack_count = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        issue_valid = 1'b1;
        @(negedge clk);
        issue_valid = 1'b0;
        cycle_count = 0;
        while (!send_valid && cycle_count < 20) begin
            @(negedge clk);
            cycle_count = cycle_count + 1;
        end
        if (!send_valid || send_retry_count != 0 || send_epoch != 7) $fatal(1, "initial global send missing");
        @(negedge clk);
        destination_commit_valid = 1'b1;
        @(negedge clk);
        if (!destination_commit_ready) $fatal(1, "back-to-back duplicate was not accepted");
        @(negedge clk);
        destination_commit_valid = 1'b0;
        repeat (4) @(negedge clk);
        if (delivery_count != 1 || ack_count != 2 || outstanding_count != 1) $fatal(1, "back-to-back duplicate or lost global ACK setup failed");
        route_reset = 1'b1;
        @(negedge clk);
        route_reset = 1'b0;
        cycle_count = 0;
        while ((!send_valid || send_retry_count != 1 || send_epoch != 8) && cycle_count < 20) begin
            @(negedge clk);
            cycle_count = cycle_count + 1;
        end
        if (!send_valid || send_transaction_id != issue_transaction_id) $fatal(1, "route-reset retransmission missing");
        @(negedge clk);
        destination_commit_valid = 1'b1;
        forward_ack = 1'b1;
        @(negedge clk);
        destination_commit_valid = 1'b0;
        repeat (7) @(negedge clk);
        if (delivery_count != 1) $fatal(1, "duplicate transaction was delivered twice");
        if (ack_count != 3 || !duplicate_seen) $fatal(1, "duplicate transaction was not re-acknowledged");
        if (!completion_valid && outstanding_count != 0) $fatal(1, "source did not release after destination commit");
        if (completion_transaction_id != issue_transaction_id || source_error || retry_exhausted) $fatal(1, "global recovery status mismatch");
        if (decoded_source_domain != 3 || decoded_destination_domain != 255 || decoded_source_node != 17 || decoded_destination_node != 4) $fatal(1, "global commit codec identity mismatch");
        repeat (32) @(negedge clk);
        for (transaction_slot = 0; transaction_slot < 512; transaction_slot = transaction_slot + 1) begin
            sweep_lfsr = {sweep_lfsr[62:0], sweep_lfsr[63] ^ sweep_lfsr[62] ^ sweep_lfsr[60] ^ sweep_lfsr[59]};
            issue_transaction_id = {sweep_lfsr[63:4], transaction_slot[3:0]};
            issue_epoch = sweep_lfsr[15:8];
            issue_timeout = {1'b1, sweep_lfsr[26:16]};
            tracker_source_domain = sweep_lfsr[34:27];
            tracker_destination_domain = sweep_lfsr[42:35];
            tracker_source_node = sweep_lfsr[47:43];
            tracker_destination_node = sweep_lfsr[52:48];
            route_epoch = sweep_lfsr[63:56];
            issue_valid = 1'b1;
            @(negedge clk);
            issue_valid = 1'b0;
            retry_pulses = (transaction_slot >> 4) & 15;
            for (retry_index = 0; retry_index < retry_pulses; retry_index = retry_index + 1) begin
                route_reset = 1'b1;
                @(negedge clk);
                route_reset = 1'b0;
                @(negedge clk);
            end
            recovery_watchdog = 0;
            while ((!send_valid || send_transaction_id != issue_transaction_id) && recovery_watchdog < 30) begin
                @(negedge clk);
                recovery_watchdog = recovery_watchdog + 1;
            end
            if (!send_valid || send_transaction_id != issue_transaction_id) $fatal(1, "transaction-slot sweep send missing");
            if (transaction_slot == 511) begin
                issue_valid = 1'b1;
                @(negedge clk);
                issue_valid = 1'b0;
            end
            destination_commit_valid = 1'b1;
            @(negedge clk);
            destination_commit_valid = 1'b0;
            recovery_watchdog = 0;
            while (outstanding_count != 0 && recovery_watchdog < 30) begin
                @(negedge clk);
                recovery_watchdog = recovery_watchdog + 1;
            end
            if (outstanding_count != 0) $fatal(1, "transaction-slot sweep completion missing");
        end
        repeat (4) @(negedge clk);
        if (delivery_count != 513 || !source_error || retry_exhausted) $fatal(1, "transaction-slot sweep status mismatch");
        $display("TB_KDLINK_GLOBAL_RECOVERY_PASS");
        $finish;
    end
endmodule
