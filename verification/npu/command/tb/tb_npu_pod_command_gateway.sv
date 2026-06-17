`timescale 1ns/1ps
`default_nettype none

module tb_npu_pod_command_gateway;
    import npu_command_pkg::*;
    import npu_command_tb_pkg::*;
    import npu_scheduler_pkg::*;

    localparam int unsigned POD_ID = 3;
    localparam int unsigned CLUSTERS = 2;
    localparam int unsigned DMA_CHANNELS = 4;
    localparam int unsigned CLUSTER_INDEX_WIDTH = 1;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic quiesce_i;
    logic command_valid;
    logic command_ready;
    logic [NPU_DECODED_COMMAND_WIDTH-1:0] command;
    logic source_valid;
    logic source_ready;
    logic [NPU_DECODED_COMMAND_WIDTH-1:0] source_command;
    logic [31:0] source_transactions;
    logic source_protocol_error;

    logic task_valid;
    logic task_ready;
    logic task_preferred_valid;
    logic [CLUSTER_INDEX_WIDTH-1:0] task_preferred_cluster;
    logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_payload;
    logic [CLUSTERS-1:0] local_valid;
    logic [CLUSTERS-1:0] local_ready;
    logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0]
        local_command;
    logic [DMA_CHANNELS-1:0] dma_valid;
    logic [DMA_CHANNELS-1:0] dma_ready;
    logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0]
        dma_command;
    logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0]
        expected_local_command;
    logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0]
        expected_dma_command;

    logic task_completion_valid;
    logic task_completion_ready;
    logic [CLUSTER_INDEX_WIDTH-1:0] task_completion_cluster;
    logic [npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH-1:0]
        task_completion_status;
    logic [CLUSTERS-1:0] local_completion_valid;
    logic [CLUSTERS-1:0] local_completion_ready;
    logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH-1:0]
        local_completion;
    logic [DMA_CHANNELS-1:0] dma_completion_valid;
    logic [DMA_CHANNELS-1:0] dma_completion_ready;
    logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH-1:0]
        dma_completion;

    logic completion_valid;
    logic completion_ready;
    logic [NPU_UNIFIED_COMPLETION_WIDTH-1:0] completion;
    logic completion_accept;
    logic completion_monitor_valid;
    logic [NPU_UNIFIED_COMPLETION_WIDTH-1:0] completion_monitor;
    logic [31:0] completion_transactions;
    logic completion_protocol_error;
    logic [63:0] accepted_commands;
    logic [63:0] rejected_commands;
    logic [63:0] delivered_completions;
    logic malformed_seen;
    logic busy;
    logic protocol_error;
    integer checks;

    npu_decoded_command_source_vip u_source (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .command_valid_i(command_valid), .command_ready_o(command_ready),
        .command_i(command), .source_valid_o(source_valid),
        .source_ready_i(source_ready), .source_command_o(source_command),
        .transaction_count_o(source_transactions),
        .protocol_error_o(source_protocol_error)
    );

    npu_pod_command_gateway #(
        .POD_ID(POD_ID), .CLUSTERS(CLUSTERS),
        .DMA_CHANNELS(DMA_CHANNELS)
    ) u_dut (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .quiesce_i(quiesce_i),
        .command_valid_i(source_valid), .command_ready_o(source_ready),
        .command_i(source_command),
        .task_valid_o(task_valid), .task_ready_i(task_ready),
        .task_preferred_cluster_valid_o(task_preferred_valid),
        .task_preferred_cluster_o(task_preferred_cluster),
        .task_o(task_payload),
        .local_command_valid_o(local_valid),
        .local_command_ready_i(local_ready), .local_command_o(local_command),
        .dma_command_valid_o(dma_valid), .dma_command_ready_i(dma_ready),
        .dma_command_o(dma_command),
        .task_completion_valid_i(task_completion_valid),
        .task_completion_ready_o(task_completion_ready),
        .task_completion_cluster_i(task_completion_cluster),
        .task_completion_status_i(task_completion_status),
        .local_completion_valid_i(local_completion_valid),
        .local_completion_ready_o(local_completion_ready),
        .local_completion_i(local_completion),
        .dma_completion_valid_i(dma_completion_valid),
        .dma_completion_ready_o(dma_completion_ready),
        .dma_completion_i(dma_completion),
        .completion_valid_o(completion_valid),
        .completion_ready_i(completion_ready), .completion_o(completion),
        .accepted_commands_o(accepted_commands),
        .rejected_commands_o(rejected_commands),
        .delivered_completions_o(delivered_completions),
        .malformed_seen_o(malformed_seen), .busy_o(busy),
        .protocol_error_o(protocol_error)
    );

    npu_unified_completion_sink_vip u_sink (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .accept_enable_i(completion_accept),
        .source_valid_i(completion_valid), .source_ready_o(completion_ready),
        .source_completion_i(completion),
        .monitor_valid_o(completion_monitor_valid),
        .monitor_completion_o(completion_monitor),
        .transaction_count_o(completion_transactions),
        .protocol_error_o(completion_protocol_error)
    );

    always #2 clk_i = ~clk_i;

    task automatic send_command(
        input npu_decoded_command_t next_command
    );
        begin
            @(negedge clk_i);
            command = next_command;
            command_valid = 1'b1;
            do begin
                @(posedge clk_i);
            end while (!command_ready);
            @(negedge clk_i);
            command_valid = 1'b0;
            command = '0;
        end
    endtask

    task automatic expect_completion(
        input npu_completion_source_e source,
        input logic [15:0] request_id,
        input logic [3:0] target,
        input logic success,
        input logic [7:0] code,
        input logic [31:0] detail
    );
        npu_unified_completion_t observed;
        begin
            completion_accept = 1'b1;
            while (!completion_monitor_valid) @(negedge clk_i);
            observed = npu_unified_completion_t'(completion_monitor);
            if ((observed.source != source) ||
                (observed.request_id != request_id) ||
                (observed.pod_id != npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID)) ||
                (observed.target != target) ||
                (observed.success != success) || (observed.code != code) ||
                (observed.detail != detail)) begin
                $fatal(1, "FAIL: completion mismatch source=%0d id=%0h target=%0d success=%0b code=%0d",
                       observed.source, observed.request_id, observed.target,
                       observed.success, observed.code);
            end
            completion_accept = 1'b0;
            checks = checks + 1;
            @(negedge clk_i);
        end
    endtask

    initial begin
        npu_task_descriptor_t task_descriptor;
        npu_pod_pkg::npu_pod_local_transfer_t local_descriptor;
        npu_dma_pkg::npu_dma_command_t dma_descriptor;
        npu_decoded_command_t decoded;
        npu_scheduler_pkg::npu_task_status_t task_status;
        npu_pod_pkg::npu_pod_local_completion_t local_status;
        npu_dma_pkg::npu_dma_completion_t dma_status;

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        quiesce_i = 1'b0;
        command_valid = 1'b0;
        command = '0;
        task_ready = 1'b0;
        local_ready = '0;
        dma_ready = '0;
        task_completion_valid = 1'b0;
        task_completion_cluster = '0;
        task_completion_status = '0;
        local_completion_valid = '0;
        local_completion = '0;
        dma_completion_valid = '0;
        dma_completion = '0;
        completion_accept = 1'b0;
        checks = 0;

        repeat (4) @(negedge clk_i);
        rst_i = 1'b0;

        task_descriptor = '0;
        task_descriptor.version =
            npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_VERSION;
        task_descriptor.operation = npu_scheduler_pkg::NPU_TASK_GEMM;
        task_descriptor.job_id = 16'h0101;
        decoded = make_task_command(
            npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID), 1'b1, 4'd1,
            task_descriptor);

        fork
            send_command(decoded);
            begin
                repeat (3) @(negedge clk_i);
                if (!task_valid || !task_preferred_valid ||
                    (task_preferred_cluster != 1'b1) ||
                    (task_payload != task_descriptor)) begin
                    $fatal(1, "FAIL: task route/backpressure mismatch");
                end
                task_ready = 1'b1;
            end
        join
        task_ready = 1'b0;
        checks = checks + 1;

        local_descriptor = '0;
        local_descriptor.version =
            npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_VERSION;
        local_descriptor.transfer_id = 16'h0202;
        decoded = make_local_command(
            npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID), 4'd1,
            local_descriptor);
        expected_local_command = '0;
        expected_local_command[
            npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH +:
            npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH] = local_descriptor;
        fork
            send_command(decoded);
            begin
                repeat (2) @(negedge clk_i);
                if ((local_valid != 2'b10) ||
                    (local_command != expected_local_command)) begin
                    $fatal(1, "FAIL: local payload route mismatch");
                end
                local_ready[1] = 1'b1;
            end
        join
        local_ready = '0;
        checks = checks + 1;

        dma_descriptor = '0;
        dma_descriptor.version = npu_dma_pkg::NPU_DMA_COMMAND_VERSION;
        dma_descriptor.command_id = 16'h0303;
        decoded = make_dma_command(
            npu_pod_pkg::NPU_POD_ID_WIDTH'(POD_ID), 4'd2,
            dma_descriptor);
        expected_dma_command = '0;
        expected_dma_command[
            2*npu_dma_pkg::NPU_DMA_COMMAND_WIDTH +:
            npu_dma_pkg::NPU_DMA_COMMAND_WIDTH] = dma_descriptor;
        fork
            send_command(decoded);
            begin
                repeat (2) @(negedge clk_i);
                if ((dma_valid != 4'b0100) ||
                    (dma_command != expected_dma_command)) begin
                    $fatal(1, "FAIL: DMA payload route mismatch");
                end
                dma_ready[2] = 1'b1;
            end
        join
        dma_ready = '0;
        checks = checks + 1;

        decoded.pod_id = 3'd7;
        send_command(decoded);
        completion_accept = 1'b0;
        while (!completion_valid) @(negedge clk_i);
        repeat (3) @(negedge clk_i);
        expect_completion(NPU_COMPLETION_COMMAND, 16'h0303, 4'd2, 1'b0,
                          8'(NPU_COMMAND_ERROR_POD), 32'd0);

        task_status = '0;
        task_status.job_id = 16'h0101;
        task_status.tag = 8'h5a;
        task_status.success = 1'b1;
        task_status.code = npu_scheduler_pkg::NPU_TASK_STATUS_OK;
        task_completion_cluster = 1'b1;
        task_completion_status = task_status;
        task_completion_valid = 1'b1;

        local_status = '0;
        local_status.transfer_id = 16'h0202;
        local_status.success = 1'b1;
        local_status.error_code = npu_pod_pkg::NPU_POD_LOCAL_OK;
        local_completion[
            npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH +:
            npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH] = local_status;
        local_completion_valid[1] = 1'b1;

        dma_status = '0;
        dma_status.command_id = 16'h0303;
        dma_status.success = 1'b1;
        dma_status.error_code = npu_dma_pkg::NPU_DMA_ERROR_OK;
        dma_status.beats_completed = 18'd9;
        dma_completion[
            2*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH +:
            npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH] = dma_status;
        dma_completion_valid[2] = 1'b1;

        fork
            begin
                do begin
                    @(posedge clk_i);
                end while (!task_completion_ready);
                @(negedge clk_i);
                task_completion_valid = 1'b0;
            end
            begin
                do begin
                    @(posedge clk_i);
                end while (!local_completion_ready[1]);
                @(negedge clk_i);
                local_completion_valid[1] = 1'b0;
            end
            begin
                do begin
                    @(posedge clk_i);
                end while (!dma_completion_ready[2]);
                @(negedge clk_i);
                dma_completion_valid[2] = 1'b0;
            end
            begin
                expect_completion(NPU_COMPLETION_TASK, 16'h0101, 4'd1,
                                  1'b1, 8'd0, 32'h0000_005a);
                expect_completion(NPU_COMPLETION_LOCAL, 16'h0202, 4'd1,
                                  1'b1, 8'd0, 32'd0);
                expect_completion(NPU_COMPLETION_DMA, 16'h0303, 4'd2,
                                  1'b1, 8'd0, 32'd9);
            end
        join

        repeat (3) @(negedge clk_i);
        if ((accepted_commands != 64'd3) ||
            (rejected_commands != 64'd1) ||
            (source_transactions != 32'd4) ||
            (completion_transactions != 32'd4) ||
            (delivered_completions != 64'd4) || !malformed_seen || busy ||
            protocol_error || source_protocol_error ||
            completion_protocol_error) begin
            $fatal(1, "FAIL: command gateway closure accepted=%0d rejected=%0d source=%0d completions=%0d delivered=%0d busy=%0b protocol=%0b/%0b/%0b",
                   accepted_commands, rejected_commands, source_transactions,
                   completion_transactions, delivered_completions, busy,
                   protocol_error, source_protocol_error,
                   completion_protocol_error);
        end
        checks = checks + 1;

        $display("[RTL_SIM PASS] pod_command_gateway commands=%0d completions=%0d checks=%0d",
                 source_transactions, completion_transactions, checks);
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clk_i);
        $fatal(1, "FAIL: pod command gateway timeout");
    end

    wire _unused_leaf_ready = &{1'b0, task_completion_ready,
        local_completion_ready, dma_completion_ready};

endmodule

`default_nettype wire
