`timescale 1ns/1ps
`default_nettype none

// Two-cluster Pod resource tracker. Jobs are reserved only after the selected
// cluster accepts dispatch, and retirement is buffered independently from
// downstream completion backpressure.
module npu_pod_scoreboard #(
    parameter int unsigned CLUSTERS = 2,
    parameter int unsigned JOB_ID_WIDTH = 16,
    parameter int unsigned RETIRE_INFO_WIDTH = 1,
    parameter int unsigned CLUSTER_INDEX_WIDTH =
        (CLUSTERS <= 1) ? 1 : $clog2(CLUSTERS)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic allocation_valid_i,
    output logic allocation_ready_o,
    input  logic allocation_preferred_valid_i,
    input  logic [CLUSTER_INDEX_WIDTH-1:0] allocation_preferred_cluster_i,
    input  logic [JOB_ID_WIDTH-1:0] allocation_job_id_i,

    output logic [CLUSTERS-1:0] dispatch_valid_o,
    input  logic [CLUSTERS-1:0] dispatch_ready_i,
    output logic [CLUSTERS*JOB_ID_WIDTH-1:0] dispatch_job_id_o,

    input  logic [CLUSTERS-1:0] retire_valid_i,
    output logic [CLUSTERS-1:0] retire_ready_o,
    input  logic [CLUSTERS*JOB_ID_WIDTH-1:0] retire_job_id_i,
    input  logic [CLUSTERS-1:0] retire_success_i,
    input  logic [CLUSTERS*RETIRE_INFO_WIDTH-1:0] retire_info_i,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [CLUSTER_INDEX_WIDTH-1:0] completion_cluster_o,
    output logic [JOB_ID_WIDTH-1:0] completion_job_id_o,
    output logic completion_success_o,
    output logic [RETIRE_INFO_WIDTH-1:0] completion_info_o,

    output logic [CLUSTERS-1:0] cluster_busy_o,
    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o
);

    localparam int unsigned COMPLETION_DEPTH = CLUSTERS;
    localparam int unsigned COMPLETION_COUNT_WIDTH =
        $clog2(COMPLETION_DEPTH + 1);

    logic [CLUSTERS-1:0] cluster_busy_q;
    logic [CLUSTERS*JOB_ID_WIDTH-1:0] cluster_job_id_q;
    logic issue_valid_q;
    logic [CLUSTER_INDEX_WIDTH-1:0] issue_cluster_q;
    logic [JOB_ID_WIDTH-1:0] issue_job_id_q;
    logic [CLUSTER_INDEX_WIDTH-1:0] round_robin_q;

    logic [CLUSTER_INDEX_WIDTH-1:0] completion_cluster_mem
        [0:COMPLETION_DEPTH-1];
    logic [JOB_ID_WIDTH-1:0] completion_job_mem
        [0:COMPLETION_DEPTH-1];
    logic completion_success_mem [0:COMPLETION_DEPTH-1];
    logic [RETIRE_INFO_WIDTH-1:0] completion_info_mem
        [0:COMPLETION_DEPTH-1];
    logic [CLUSTER_INDEX_WIDTH-1:0] completion_read_pointer_q;
    logic [CLUSTER_INDEX_WIDTH-1:0] completion_write_pointer_q;
    logic [COMPLETION_COUNT_WIDTH-1:0] completion_count_q;

    logic selected_free;
    logic [CLUSTER_INDEX_WIDTH-1:0] selected_cluster;
    logic duplicate_job;
    logic allocation_fire;
    logic dispatch_fire;
    logic completion_fire;
    logic [CLUSTERS-1:0] retire_fire;
    logic [COMPLETION_COUNT_WIDTH-1:0] completion_slots;
    logic [COMPLETION_COUNT_WIDTH-1:0] retire_count;
    logic [CLUSTERS*CLUSTER_INDEX_WIDTH-1:0] retire_write_index;
    logic [CLUSTER_INDEX_WIDTH-1:0] candidate_index;
    logic [COMPLETION_COUNT_WIDTH-1:0] write_offset;
    logic [CLUSTER_INDEX_WIDTH-1:0] write_index;

    always_comb begin
        selected_free = 1'b0;
        selected_cluster = '0;
        candidate_index = '0;
        if (allocation_preferred_valid_i) begin
            if (({1'b0, allocation_preferred_cluster_i} <
                 (CLUSTER_INDEX_WIDTH+1)'(CLUSTERS)) &&
                !cluster_busy_q[allocation_preferred_cluster_i]) begin
                selected_free = 1'b1;
                selected_cluster = allocation_preferred_cluster_i;
            end
        end else begin
            for (integer offset = 0; offset < CLUSTERS; offset++) begin
                candidate_index = CLUSTER_INDEX_WIDTH'(
                    (int'(round_robin_q) + offset) % CLUSTERS);
                if (!selected_free && !cluster_busy_q[candidate_index]) begin
                    selected_free = 1'b1;
                    selected_cluster = CLUSTER_INDEX_WIDTH'(candidate_index);
                end
            end
        end

        duplicate_job = 1'b0;
        for (integer cluster = 0; cluster < CLUSTERS; cluster++) begin
            if (cluster_busy_q[cluster] &&
                (cluster_job_id_q[cluster*JOB_ID_WIDTH +: JOB_ID_WIDTH] ==
                 allocation_job_id_i)) begin
                duplicate_job = 1'b1;
            end
        end
        if (issue_valid_q && (issue_job_id_q == allocation_job_id_i)) begin
            duplicate_job = 1'b1;
        end

        allocation_ready_o = !rst_i && !clear_i && !quiesce_i &&
                             !issue_valid_q && selected_free;
        dispatch_valid_o = '0;
        dispatch_job_id_o = '0;
        if (issue_valid_q) begin
            dispatch_valid_o[issue_cluster_q] = 1'b1;
            dispatch_job_id_o[
                issue_cluster_q*JOB_ID_WIDTH +: JOB_ID_WIDTH] =
                issue_job_id_q;
        end

        completion_slots = COMPLETION_COUNT_WIDTH'(COMPLETION_DEPTH) -
                           completion_count_q;
        if (completion_valid_o && completion_ready_i) begin
            completion_slots = completion_slots + 1'b1;
        end
        retire_ready_o = '0;
        retire_count = '0;
        retire_write_index = '0;
        write_offset = '0;
        write_index = '0;
        for (integer cluster = 0; cluster < CLUSTERS; cluster++) begin
            if (cluster_busy_q[cluster] &&
                (retire_job_id_i[cluster*JOB_ID_WIDTH +: JOB_ID_WIDTH] ==
                 cluster_job_id_q[cluster*JOB_ID_WIDTH +: JOB_ID_WIDTH]) &&
                (retire_count < completion_slots)) begin
                retire_ready_o[cluster] = 1'b1;
                if (retire_valid_i[cluster]) begin
                    write_index = CLUSTER_INDEX_WIDTH'(
                        (int'(completion_write_pointer_q) +
                         int'(write_offset)) % COMPLETION_DEPTH);
                    retire_write_index[
                        cluster*CLUSTER_INDEX_WIDTH +:
                        CLUSTER_INDEX_WIDTH] =
                        CLUSTER_INDEX_WIDTH'(write_index);
                    write_offset = write_offset + 1;
                    retire_count = retire_count + 1'b1;
                end
            end
        end
    end

    assign allocation_fire = allocation_valid_i && allocation_ready_o;
    assign dispatch_fire = issue_valid_q &&
                           dispatch_ready_i[issue_cluster_q];
    assign completion_valid_o = completion_count_q != '0;
    assign completion_cluster_o =
        completion_cluster_mem[completion_read_pointer_q];
    assign completion_job_id_o =
        completion_job_mem[completion_read_pointer_q];
    assign completion_success_o =
        completion_success_mem[completion_read_pointer_q];
    assign completion_info_o =
        completion_info_mem[completion_read_pointer_q];
    assign completion_fire = completion_valid_o && completion_ready_i;
    assign retire_fire = retire_valid_i & retire_ready_o;
    assign cluster_busy_o = cluster_busy_q;
    assign busy_o = issue_valid_q || (|cluster_busy_q) || completion_valid_o;
    assign quiesced_o = quiesce_i && !issue_valid_q &&
                        !(|cluster_busy_q) && !completion_valid_o;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            cluster_busy_q <= '0;
            cluster_job_id_q <= '0;
            issue_valid_q <= 1'b0;
            issue_cluster_q <= '0;
            issue_job_id_q <= '0;
            round_robin_q <= '0;
            completion_read_pointer_q <= '0;
            completion_write_pointer_q <= '0;
            completion_count_q <= '0;
            protocol_error_o <= 1'b0;
            for (integer entry = 0; entry < COMPLETION_DEPTH; entry++) begin
                completion_cluster_mem[entry] <= '0;
                completion_job_mem[entry] <= '0;
                completion_success_mem[entry] <= 1'b0;
                completion_info_mem[entry] <= '0;
            end
        end else begin
            if (allocation_fire) begin
                if (duplicate_job) begin
                    protocol_error_o <= 1'b1;
                end
                issue_valid_q <= 1'b1;
                issue_cluster_q <= selected_cluster;
                issue_job_id_q <= allocation_job_id_i;
            end
            if (dispatch_fire) begin
                issue_valid_q <= 1'b0;
                cluster_busy_q[issue_cluster_q] <= 1'b1;
                cluster_job_id_q[
                    issue_cluster_q*JOB_ID_WIDTH +: JOB_ID_WIDTH] <=
                    issue_job_id_q;
                if (issue_cluster_q ==
                    CLUSTER_INDEX_WIDTH'(CLUSTERS-1)) begin
                    round_robin_q <= '0;
                end else begin
                    round_robin_q <= issue_cluster_q + 1'b1;
                end
            end

            for (integer cluster = 0; cluster < CLUSTERS; cluster++) begin
                if (retire_valid_i[cluster] &&
                    (!cluster_busy_q[cluster] ||
                     (retire_job_id_i[cluster*JOB_ID_WIDTH +: JOB_ID_WIDTH] !=
                      cluster_job_id_q[cluster*JOB_ID_WIDTH +:
                                       JOB_ID_WIDTH]))) begin
                    protocol_error_o <= 1'b1;
                end
                if (retire_fire[cluster]) begin
                    cluster_busy_q[cluster] <= 1'b0;
                end
            end

            if (completion_fire) begin
                if (completion_read_pointer_q ==
                    CLUSTER_INDEX_WIDTH'(COMPLETION_DEPTH-1)) begin
                    completion_read_pointer_q <= '0;
                end else begin
                    completion_read_pointer_q <=
                        completion_read_pointer_q + 1'b1;
                end
            end
            for (integer cluster = 0; cluster < CLUSTERS; cluster++) begin
                if (retire_fire[cluster]) begin
                    completion_cluster_mem[retire_write_index[
                        cluster*CLUSTER_INDEX_WIDTH +:
                        CLUSTER_INDEX_WIDTH]] <=
                        CLUSTER_INDEX_WIDTH'(cluster);
                    completion_job_mem[retire_write_index[
                        cluster*CLUSTER_INDEX_WIDTH +:
                        CLUSTER_INDEX_WIDTH]] <=
                        retire_job_id_i[cluster*JOB_ID_WIDTH +: JOB_ID_WIDTH];
                    completion_success_mem[retire_write_index[
                        cluster*CLUSTER_INDEX_WIDTH +:
                        CLUSTER_INDEX_WIDTH]] <=
                        retire_success_i[cluster];
                    completion_info_mem[retire_write_index[
                        cluster*CLUSTER_INDEX_WIDTH +:
                        CLUSTER_INDEX_WIDTH]] <=
                        retire_info_i[
                            cluster*RETIRE_INFO_WIDTH +:
                            RETIRE_INFO_WIDTH];
                end
            end
            if (retire_count != '0) begin
                if ((int'(completion_write_pointer_q) + int'(retire_count)) >=
                    COMPLETION_DEPTH) begin
                    completion_write_pointer_q <= CLUSTER_INDEX_WIDTH'(
                        int'(completion_write_pointer_q) +
                        int'(retire_count) - COMPLETION_DEPTH);
                end else begin
                    completion_write_pointer_q <=
                        CLUSTER_INDEX_WIDTH'(
                            completion_write_pointer_q + retire_count);
                end
            end
            completion_count_q <= completion_count_q + retire_count -
                                  COMPLETION_COUNT_WIDTH'(completion_fire);
        end
    end

endmodule

`default_nettype wire
