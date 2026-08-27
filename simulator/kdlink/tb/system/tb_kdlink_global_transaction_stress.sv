`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_global_transaction_stress;
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
    reg commit_valid;
    reg [63:0] commit_transaction_id;
    reg [7:0] commit_epoch;
    reg [1:0] commit_status;
    reg route_reset;
    reg [7:0] route_epoch;
    wire completion_valid;
    wire [63:0] completion_transaction_id;
    wire protocol_error;
    wire retry_exhausted;
    wire [4:0] outstanding_count;
    reg [15:0] initial_send_mask;
    reg [63:0] held_send_id;
    reg [7:0] held_send_epoch;
    reg [3:0] held_retry_count;
    integer completion_count;
    integer timeout_send_count;
    integer expected_timeout_retry;
    integer index;
    integer watchdog;
    kdlink_global_transaction_source #(
        .REPLAY_GRACE_CYCLES(12'd4)
    ) u_dut (
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
        .commit_valid_i(commit_valid),
        .commit_transaction_id_i(commit_transaction_id),
        .commit_topology_epoch_i(commit_epoch),
        .commit_status_i(commit_status),
        .route_reset_i(route_reset),
        .route_topology_epoch_i(route_epoch),
        .completion_valid_o(completion_valid),
        .completion_transaction_id_o(completion_transaction_id),
        .protocol_error_o(protocol_error),
        .retry_exhausted_o(retry_exhausted),
        .outstanding_count_o(outstanding_count)
    );
    always #0.5 clk = ~clk;
    always @(posedge clk) begin
        if (completion_valid) completion_count <= completion_count + 1;
        if (send_valid && send_ready && (send_retry_count == 4'd0) && (send_transaction_id[63:8] == 56'h0000_0000_00a5_00)) initial_send_mask[send_transaction_id[3:0]] <= 1'b1;
        if (send_valid && send_ready && (send_transaction_id == 64'h0000_0000_0000_3002)) begin
            if (send_retry_count != expected_timeout_retry[3:0]) $fatal(1, "timeout retry sequence was not monotonic");
            expected_timeout_retry <= expected_timeout_retry + 1;
            timeout_send_count <= timeout_send_count + 1;
        end
    end
    task automatic issue_one(input [63:0] transaction_id, input [7:0] epoch, input [11:0] timeout_quanta);
        begin
            @(negedge clk);
            issue_transaction_id = transaction_id;
            issue_epoch = epoch;
            issue_timeout = timeout_quanta;
            issue_valid = 1'b1;
            #0.1;
            if (!issue_ready) $fatal(1, "expected transaction issue was not accepted");
            @(negedge clk);
            issue_valid = 1'b0;
        end
    endtask
    task automatic send_commit(input [63:0] transaction_id, input [7:0] epoch, input [1:0] status);
        begin
            @(negedge clk);
            commit_transaction_id = transaction_id;
            commit_epoch = epoch;
            commit_status = status;
            commit_valid = 1'b1;
            @(negedge clk);
            commit_valid = 1'b0;
        end
    endtask
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        issue_valid = 1'b0;
        issue_transaction_id = 64'd0;
        issue_epoch = 8'd0;
        issue_timeout = 12'd16;
        send_ready = 1'b0;
        commit_valid = 1'b0;
        commit_transaction_id = 64'd0;
        commit_epoch = 8'd0;
        commit_status = `KDL_GLOBAL_STATUS_COMMITTED;
        route_reset = 1'b0;
        route_epoch = 8'd0;
        initial_send_mask = 16'd0;
        held_send_id = 64'd0;
        held_send_epoch = 8'd0;
        held_retry_count = 4'd0;
        completion_count = 0;
        timeout_send_count = 0;
        expected_timeout_retry = 0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        for (index = 0; index < 16; index = index + 1) issue_one(64'h0000_0000_00a5_0000 | {60'd0, index[3:0]}, 8'd9, 12'd100);
        if (outstanding_count != 5'd16 || !send_valid) $fatal(1, "sixteen-slot concurrent allocation failed");
        issue_transaction_id = 64'h0000_0000_00b6_0000;
        issue_valid = 1'b1;
        #0.1;
        if (issue_ready) $fatal(1, "seventeenth transaction collided with an occupied direct-map slot");
        issue_valid = 1'b0;
        held_send_id = send_transaction_id;
        held_send_epoch = send_epoch;
        held_retry_count = send_retry_count;
        repeat (3) begin
            @(negedge clk);
            if (!send_valid || send_transaction_id != held_send_id || send_epoch != held_send_epoch || send_retry_count != held_retry_count) $fatal(1, "send output changed under backpressure");
        end
        send_ready = 1'b1;
        watchdog = 0;
        while ((initial_send_mask != 16'hffff) && (watchdog < 80)) begin
            @(negedge clk);
            watchdog = watchdog + 1;
        end
        if (initial_send_mask != 16'hffff) $fatal(1, "not all sixteen concurrent transactions were sent");
        for (index = 15; index >= 0; index = index - 1) send_commit(64'h0000_0000_00a5_0000 | {60'd0, index[3:0]}, 8'd9, `KDL_GLOBAL_STATUS_COMMITTED);
        watchdog = 0;
        while ((outstanding_count != 0) && (watchdog < 10)) begin
            @(negedge clk);
            watchdog = watchdog + 1;
        end
        if (outstanding_count != 0) $fatal(1, "out-of-order commit completion failed outstanding=%0d", outstanding_count);
        issue_transaction_id = 64'h0000_0000_00c7_0000;
        issue_epoch = 8'd10;
        issue_timeout = 12'd20;
        issue_valid = 1'b1;
        #0.1;
        if (issue_ready) $fatal(1, "completed slot bypassed the source replay grace period");
        watchdog = 0;
        while (!issue_ready && watchdog < 12) begin
            @(negedge clk);
            watchdog = watchdog + 1;
        end
        if (!issue_ready) $fatal(1, "source replay grace period did not expire");
        if (completion_count != 16) $fatal(1, "out-of-order completion pulse count mismatch");
        @(negedge clk);
        issue_valid = 1'b0;
        watchdog = 0;
        while ((!send_valid || send_transaction_id != 64'h0000_0000_00c7_0000) && watchdog < 20) begin
            @(negedge clk);
            watchdog = watchdog + 1;
        end
        if (!send_valid) $fatal(1, "post-grace transaction was not sent");
        send_commit(64'h0000_0000_00c7_0000, 8'd11, `KDL_GLOBAL_STATUS_COMMITTED);
        repeat (4) @(negedge clk);
        if (!protocol_error || outstanding_count != 1) $fatal(1, "stale-epoch commit was not rejected");
        send_commit(64'h0000_0000_00c7_0000, 8'd10, `KDL_GLOBAL_STATUS_COMMITTED);
        repeat (5) @(negedge clk);
        if (outstanding_count != 0 || completion_count != 17 || completion_transaction_id != 64'h0000_0000_00c7_0000) $fatal(1, "valid commit did not recover after stale-epoch rejection");
        issue_one(64'h0000_0000_0000_3002, 8'd12, 12'd2);
        watchdog = 0;
        while (!retry_exhausted && watchdog < 160) begin
            @(negedge clk);
            watchdog = watchdog + 1;
        end
        if (!retry_exhausted || timeout_send_count != 16 || expected_timeout_retry != 16 || outstanding_count != 1) $fatal(1, "pure timeout retry exhaustion contract failed");
        $display("TB_KDLINK_GLOBAL_TRANSACTION_STRESS_PASS");
        $finish;
    end
endmodule
