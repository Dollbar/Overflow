`timescale 1ns/1ps
`default_nettype none

module tb_npu_pod_scoreboard;

    localparam int unsigned CLUSTERS = 2;
    localparam int unsigned JOB_ID_WIDTH = 16;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic quiesce_i;
    logic allocation_valid_i;
    logic allocation_ready_o;
    logic allocation_preferred_valid_i;
    logic allocation_preferred_cluster_i;
    logic [JOB_ID_WIDTH-1:0] allocation_job_id_i;
    logic [CLUSTERS-1:0] dispatch_valid_o;
    logic [CLUSTERS-1:0] dispatch_ready_i;
    logic [CLUSTERS*JOB_ID_WIDTH-1:0] dispatch_job_id_o;
    logic [CLUSTERS-1:0] retire_valid_i;
    logic [CLUSTERS-1:0] retire_ready_o;
    logic [CLUSTERS*JOB_ID_WIDTH-1:0] retire_job_id_i;
    logic [CLUSTERS-1:0] retire_success_i;
    logic [CLUSTERS-1:0] retire_info_i;
    logic completion_valid_o;
    logic completion_ready_i;
    logic completion_cluster_o;
    logic [JOB_ID_WIDTH-1:0] completion_job_id_o;
    logic completion_success_o;
    logic completion_info_o;
    logic [CLUSTERS-1:0] cluster_busy_o;
    logic busy_o;
    logic quiesced_o;
    logic protocol_error_o;
    integer checked_jobs;

    npu_pod_scoreboard #(
        .CLUSTERS(CLUSTERS),
        .JOB_ID_WIDTH(JOB_ID_WIDTH)
    ) dut (
        .clk_i,
        .rst_i,
        .clear_i,
        .quiesce_i,
        .allocation_valid_i,
        .allocation_ready_o,
        .allocation_preferred_valid_i,
        .allocation_preferred_cluster_i,
        .allocation_job_id_i,
        .dispatch_valid_o,
        .dispatch_ready_i,
        .dispatch_job_id_o,
        .retire_valid_i,
        .retire_ready_o,
        .retire_job_id_i,
        .retire_success_i,
        .retire_info_i,
        .completion_valid_o,
        .completion_ready_i,
        .completion_cluster_o,
        .completion_job_id_o,
        .completion_success_o,
        .completion_info_o,
        .cluster_busy_o,
        .busy_o,
        .quiesced_o,
        .protocol_error_o
    );

    always #0.5 clk_i = ~clk_i;

    task automatic allocate_and_dispatch;
        input logic preferred_valid;
        input logic preferred_cluster;
        input logic [JOB_ID_WIDTH-1:0] job_id;
        input logic expected_cluster;
        begin
            @(negedge clk_i);
            allocation_preferred_valid_i = preferred_valid;
            allocation_preferred_cluster_i = preferred_cluster;
            allocation_job_id_i = job_id;
            allocation_valid_i = 1'b1;
            while (!allocation_ready_o) begin
                @(negedge clk_i);
            end
            @(posedge clk_i);
            @(negedge clk_i);
            allocation_valid_i = 1'b0;
            if (!dispatch_valid_o[expected_cluster] ||
                (dispatch_job_id_o[expected_cluster*JOB_ID_WIDTH +:
                                   JOB_ID_WIDTH] != job_id)) begin
                $fatal(1, "dispatch mismatch job=%0h expected_cluster=%0d",
                       job_id, expected_cluster);
            end
            @(posedge clk_i);
            @(negedge clk_i);
            if (!cluster_busy_o[expected_cluster]) begin
                $fatal(1, "cluster reservation missing");
            end
            checked_jobs = checked_jobs + 1;
        end
    endtask

    task automatic consume_completion;
        input logic expected_cluster;
        input logic [JOB_ID_WIDTH-1:0] expected_job;
        input logic expected_success;
        logic held_cluster;
        logic [JOB_ID_WIDTH-1:0] held_job;
        logic held_success;
        begin
            while (!completion_valid_o) begin
                @(negedge clk_i);
            end
            if ((completion_cluster_o != expected_cluster) ||
                (completion_job_id_o != expected_job) ||
                (completion_success_o != expected_success) ||
                (completion_info_o != expected_success)) begin
                $fatal(1, "completion mismatch expected job=%0h cluster=%0d",
                       expected_job, expected_cluster);
            end
            held_cluster = completion_cluster_o;
            held_job = completion_job_id_o;
            held_success = completion_success_o;
            repeat (3) begin
                @(posedge clk_i);
                @(negedge clk_i);
                if (!completion_valid_o ||
                    (completion_cluster_o != held_cluster) ||
                    (completion_job_id_o != held_job) ||
                    (completion_success_o != held_success)) begin
                    $fatal(1, "completion changed under backpressure");
                end
            end
            completion_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            completion_ready_i = 1'b0;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        quiesce_i = 1'b0;
        allocation_valid_i = 1'b0;
        allocation_preferred_valid_i = 1'b0;
        allocation_preferred_cluster_i = 1'b0;
        allocation_job_id_i = '0;
        dispatch_ready_i = '1;
        retire_valid_i = '0;
        retire_job_id_i = '0;
        retire_success_i = '0;
        retire_info_i = '0;
        completion_ready_i = 1'b0;
        checked_jobs = 0;

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        allocate_and_dispatch(1'b0, 1'b0, 16'h1010, 1'b0);
        allocate_and_dispatch(1'b0, 1'b0, 16'h2020, 1'b1);
        if (allocation_ready_o || (cluster_busy_o != 2'b11)) begin
            $fatal(1, "full-cluster backpressure missing");
        end

        retire_job_id_i[0 +: JOB_ID_WIDTH] = 16'h1010;
        retire_job_id_i[JOB_ID_WIDTH +: JOB_ID_WIDTH] = 16'h2020;
        retire_success_i = 2'b01;
        retire_info_i = 2'b01;
        retire_valid_i = 2'b11;
        #0.01;
        if (retire_ready_o != 2'b11) begin
            $fatal(1, "simultaneous retirement was not accepted ready=%b busy=%b jobs=%h expected=%h",
                   retire_ready_o, cluster_busy_o, dut.cluster_job_id_q,
                   retire_job_id_i);
        end
        @(posedge clk_i);
        @(negedge clk_i);
        retire_valid_i = '0;
        if (cluster_busy_o != 2'b00) begin
            $fatal(1, "retired clusters remained busy");
        end
        consume_completion(1'b0, 16'h1010, 1'b1);
        consume_completion(1'b1, 16'h2020, 1'b0);

        dispatch_ready_i = 2'b01;
        allocation_preferred_valid_i = 1'b1;
        allocation_preferred_cluster_i = 1'b1;
        allocation_job_id_i = 16'h3030;
        allocation_valid_i = 1'b1;
        #0.01;
        if (!allocation_ready_o) begin
            $fatal(1, "preferred cluster allocation was not accepted");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        allocation_valid_i = 1'b0;
        repeat (3) begin
            if (!dispatch_valid_o[1] ||
                (dispatch_job_id_o[JOB_ID_WIDTH +: JOB_ID_WIDTH] !=
                 16'h3030)) begin
                $fatal(1, "dispatch changed under backpressure");
            end
            @(posedge clk_i);
            @(negedge clk_i);
        end
        dispatch_ready_i[1] = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        if (!cluster_busy_o[1]) begin
            $fatal(1, "preferred cluster reservation missing");
        end
        checked_jobs = checked_jobs + 1;

        retire_job_id_i[JOB_ID_WIDTH +: JOB_ID_WIDTH] = 16'h3030;
        retire_success_i[1] = 1'b1;
        retire_info_i[1] = 1'b1;
        retire_valid_i[1] = 1'b1;
        wait (retire_ready_o[1]);
        @(posedge clk_i);
        @(negedge clk_i);
        retire_valid_i[1] = 1'b0;
        consume_completion(1'b1, 16'h3030, 1'b1);

        quiesce_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        if (!quiesced_o || busy_o || allocation_ready_o) begin
            $fatal(1, "quiesce state mismatch");
        end
        quiesce_i = 1'b0;
        retire_job_id_i[0 +: JOB_ID_WIDTH] = 16'hdead;
        retire_valid_i[0] = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        retire_valid_i[0] = 1'b0;
        if (!protocol_error_o) begin
            $fatal(1, "unknown retirement did not set protocol error");
        end
        $display("[RTL_SIM PASS] npu_pod_scoreboard checked_jobs=%0d",
                 checked_jobs);
        $finish;
    end

endmodule

`default_nettype wire
