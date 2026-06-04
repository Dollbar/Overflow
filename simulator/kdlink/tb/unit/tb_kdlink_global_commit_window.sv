`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_global_commit_window;
    reg clk;
    reg rst_n;
    reg route_reset;
    reg commit_valid;
    wire commit_ready;
    reg [7:0] source_domain;
    reg [7:0] destination_domain;
    reg [4:0] source_node;
    reg [4:0] destination_node;
    reg [7:0] topology_epoch;
    reg [63:0] transaction_id;
    wire deliver_valid;
    wire [63:0] deliver_transaction_id;
    wire ack_valid;
    wire [63:0] ack_transaction_id;
    wire duplicate_seen;
    integer delivery_count;
    integer ack_count;
    integer watchdog;
    kdlink_global_commit_tracker #(
        .REPLAY_GRACE_CYCLES(12'd8)
    ) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .route_reset_i(route_reset),
        .commit_valid_i(commit_valid),
        .commit_ready_o(commit_ready),
        .source_domain_i(source_domain),
        .destination_domain_i(destination_domain),
        .source_node_i(source_node),
        .destination_node_i(destination_node),
        .topology_epoch_i(topology_epoch),
        .global_transaction_id_i(transaction_id),
        .deliver_valid_o(deliver_valid),
        .deliver_transaction_id_o(deliver_transaction_id),
        .global_ack_valid_o(ack_valid),
        .global_ack_source_domain_o(),
        .global_ack_destination_domain_o(),
        .global_ack_source_node_o(),
        .global_ack_destination_node_o(),
        .global_ack_topology_epoch_o(),
        .global_ack_transaction_id_o(ack_transaction_id),
        .global_ack_status_o(),
        .duplicate_seen_o(duplicate_seen)
    );
    always #0.5 clk = ~clk;
    always @(posedge clk) begin
        if (deliver_valid) delivery_count <= delivery_count + 1;
        if (ack_valid) ack_count <= ack_count + 1;
    end
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        route_reset = 1'b0;
        commit_valid = 1'b0;
        source_domain = 8'd3;
        destination_domain = 8'd17;
        source_node = 5'd2;
        destination_node = 5'd9;
        topology_epoch = 8'd7;
        transaction_id = 64'h1000;
        delivery_count = 0;
        ack_count = 0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        commit_valid = 1'b1;
        @(negedge clk);
        if (!commit_ready) $fatal(1, "identical consecutive commit was backpressured");
        topology_epoch = 8'd8;
        route_reset = 1'b1;
        @(negedge clk);
        commit_valid = 1'b0;
        route_reset = 1'b0;
        repeat (2) @(negedge clk);
        if (delivery_count != 1 || ack_count != 2 || !duplicate_seen) $fatal(1, "consecutive duplicate exact-once contract failed");
        transaction_id = 64'h2000;
        destination_domain = 8'd18;
        commit_valid = 1'b1;
        #0.1;
        if (commit_ready) $fatal(1, "different identity reused a protected direct-map slot");
        watchdog = 0;
        while (!commit_ready && watchdog < 16) begin
            @(negedge clk);
            watchdog = watchdog + 1;
        end
        if (!commit_ready) $fatal(1, "protected slot did not expire");
        @(negedge clk);
        commit_valid = 1'b0;
        repeat (2) @(negedge clk);
        if (delivery_count != 2 || ack_count != 3 || deliver_transaction_id != 64'h2000 || ack_transaction_id != 64'h2000) $fatal(1, "expired slot replacement did not commit exactly once");
        transaction_id = 64'h1000;
        destination_domain = 8'd17;
        commit_valid = 1'b1;
        #0.1;
        if (commit_ready) $fatal(1, "delayed old identity displaced a newly protected identity");
        @(negedge clk);
        commit_valid = 1'b0;
        repeat (2) @(negedge clk);
        if (delivery_count != 2 || ack_count != 3) $fatal(1, "backpressured collision changed architectural state");
        $display("TB_KDLINK_GLOBAL_COMMIT_WINDOW_PASS");
        $finish;
    end
endmodule
