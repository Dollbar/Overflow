`timescale 1ns/1ps
`default_nettype none

module tb_npu_compute_pod;

    /* verilator lint_off UNUSEDSIGNAL */
    localparam int unsigned CLUSTERS = 2;
    localparam int unsigned ARRAY_DIM = 16;
    localparam int unsigned DMA_CHANNELS = 16;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned PARTITION_BITS = 3;
    localparam int unsigned PARTITION_ID = 3;
    localparam int unsigned LOCAL_TAG_WIDTH = 8;
    localparam int unsigned DATA_BYTES = 128;
    localparam int unsigned DMA_COMMAND_LEVEL_WIDTH = 3;
    localparam int unsigned HBM_TAG_WIDTH = 12;
    localparam int unsigned OUTSTANDING_COUNT_WIDTH = 13;
    localparam int unsigned TASK_WIDTH =
        npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH;
    localparam int unsigned STATUS_WIDTH =
        npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH;
    localparam int unsigned DMA_COMMAND_WIDTH =
        npu_dma_pkg::NPU_DMA_COMMAND_WIDTH;
    localparam int unsigned DMA_COMPLETION_WIDTH =
        npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH;
    localparam int unsigned LOCAL_COMMAND_WIDTH =
        npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH;
    localparam int unsigned LOCAL_COMPLETION_WIDTH =
        npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic quiesce_i;
    logic task_valid_i;
    logic task_ready_o;
    logic task_preferred_cluster_valid_i;
    logic task_preferred_cluster_i;
    logic [TASK_WIDTH-1:0] task_i;
    npu_scheduler_pkg::npu_task_descriptor_t task_fields;
    logic task_completion_valid_o;
    logic task_completion_ready_i;
    logic task_completion_cluster_o;
    logic [STATUS_WIDTH-1:0] task_completion_status_o;
    npu_scheduler_pkg::npu_task_status_t task_completion_fields;
    logic [CLUSTERS-1:0] local_command_valid_i;
    logic [CLUSTERS-1:0] local_command_ready_o;
    logic [CLUSTERS*LOCAL_COMMAND_WIDTH-1:0] local_command_i;
    logic [CLUSTERS-1:0] local_completion_valid_o;
    logic [CLUSTERS-1:0] local_completion_ready_i;
    logic [CLUSTERS*LOCAL_COMPLETION_WIDTH-1:0] local_completion_o;
    logic [DMA_CHANNELS-1:0] dma_command_valid_i;
    logic [DMA_CHANNELS-1:0] dma_command_ready_o;
    logic [DMA_CHANNELS*DMA_COMMAND_WIDTH-1:0] dma_command_i;
    npu_dma_pkg::npu_dma_command_t dma_command_fields;
    logic [DMA_CHANNELS*DMA_COMMAND_LEVEL_WIDTH-1:0]
          dma_command_level_o;
    logic [DMA_CHANNELS*(LOCAL_TAG_WIDTH+1)-1:0]
          dma_channel_outstanding_o;
    logic [DMA_CHANNELS-1:0] dma_completion_valid_o;
    logic [DMA_CHANNELS-1:0] dma_completion_ready_i;
    logic [DMA_CHANNELS*DMA_COMPLETION_WIDTH-1:0] dma_completion_o;
    npu_dma_pkg::npu_dma_completion_t dma_completion_fields;
    logic [HBM_LANES-1:0] hbm_request_valid_o;
    logic [HBM_LANES-1:0] hbm_request_ready_i;
    logic [HBM_LANES-1:0] hbm_request_write_o;
    logic [HBM_LANES*PARTITION_BITS-1:0] hbm_request_partition_o;
    logic [HBM_LANES*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
          hbm_request_address_o;
    logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_request_tag_o;
    logic [HBM_LANES*DATA_BYTES*8-1:0] hbm_request_write_data_o;
    logic [HBM_LANES*DATA_BYTES-1:0] hbm_request_byte_enable_o;
    logic [HBM_LANES-1:0] hbm_response_valid_i;
    logic [HBM_LANES-1:0] hbm_response_ready_o;
    logic [HBM_LANES-1:0] hbm_response_write_i;
    logic [HBM_LANES*PARTITION_BITS-1:0] hbm_response_partition_i;
    logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_response_tag_i;
    logic [HBM_LANES*DATA_BYTES*8-1:0] hbm_response_read_data_i;
    logic [HBM_LANES*2-1:0] hbm_response_status_i;
    logic [CLUSTERS*ARRAY_DIM-1:0] gemm_output_valid_o;
    logic [CLUSTERS*ARRAY_DIM-1:0] gemm_output_ready_i;
    logic [CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
          gemm_output_result_o;
    logic [CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
          gemm_output_command_o;
    logic [CLUSTERS*ARRAY_DIM-1:0] gemm_vector_valid_o;
    logic [CLUSTERS*ARRAY_DIM-1:0] gemm_vector_ready_i;
    logic [CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
          gemm_vector_result_o;
    logic [CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
          gemm_vector_command_o;
    logic [CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_valid_o;
    logic [CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_ready_i;
    logic [CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
          gemm_feedback_result_o;
    logic [CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
          gemm_feedback_command_o;
    logic [CLUSTERS-1:0] event_set_valid_i;
    logic [CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
          event_set_id_i;
    logic [CLUSTERS-1:0] event_clear_valid_i;
    logic [CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
          event_clear_id_i;
    logic busy_o;
    logic quiesced_o;
    logic protocol_error_o;
    logic [CLUSTERS-1:0] task_cluster_busy_o;
    logic [CLUSTERS-1:0] compute_busy_o;
    logic [CLUSTERS-1:0] loader_busy_o;
    logic dma_busy_o;
    logic outstanding_full_o;
    logic [OUTSTANDING_COUNT_WIDTH-1:0] outstanding_count_o;
    logic [OUTSTANDING_COUNT_WIDTH-1:0] outstanding_high_watermark_o;
    logic [63:0] accepted_beats_o;
    logic [63:0] issued_beats_o;
    logic [63:0] request_backpressure_cycles_o;
    logic [63:0] accepted_responses_o;
    logic [63:0] delivered_responses_o;
    logic [63:0] dropped_responses_o;
    logic [63:0] response_backpressure_cycles_o;
    logic [63:0] ok_responses_o;
    logic [63:0] corrected_responses_o;
    logic [63:0] uncorrectable_responses_o;
    logic [63:0] data_error_responses_o;
    logic corrected_seen_o;
    logic uncorrectable_seen_o;
    logic data_error_seen_o;
    logic [63:0] sram_accepted_reads_o;
    logic [63:0] sram_accepted_writes_o;
    logic [63:0] sram_read_conflict_cycles_o;
    logic [63:0] sram_write_conflict_cycles_o;
    logic [1023:0] test_data;
    logic [1023:0] test_scale;
    integer checked_tasks;
    integer checked_local_writes;
    /* verilator lint_on UNUSEDSIGNAL */

    assign task_i = task_fields;
    assign task_completion_fields = task_completion_status_o;
    assign dma_completion_fields = dma_completion_o[0 +:
        DMA_COMPLETION_WIDTH];

    npu_compute_pod #(
        .PARTITION_ID(PARTITION_ID)
    ) dut (.*);

    always #0.5 clk_i = ~clk_i;

    task automatic send_task;
        input logic [15:0] job_id;
        input logic preferred_valid;
        input logic preferred_cluster;
        input logic expected_cluster;
        begin
            @(negedge clk_i);
            task_fields = '0;
            task_fields.version =
                npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_VERSION;
            task_fields.job_id = job_id;
            task_preferred_cluster_valid_i = preferred_valid;
            task_preferred_cluster_i = preferred_cluster;
            task_valid_i = 1'b1;
            while (!task_ready_o) @(negedge clk_i);
            @(posedge clk_i);
            @(negedge clk_i);
            task_valid_i = 1'b0;
            while (!task_completion_valid_o) @(negedge clk_i);
            if ((task_completion_cluster_o != expected_cluster) ||
                (task_completion_fields.job_id != job_id) ||
                !task_completion_fields.success ||
                (task_completion_fields.code !=
                 npu_scheduler_pkg::NPU_TASK_STATUS_OK)) begin
                $fatal(1, "Pod task completion mismatch job=%0h", job_id);
            end
            repeat (2) begin
                @(posedge clk_i);
                @(negedge clk_i);
                if (!task_completion_valid_o ||
                    (task_completion_fields.job_id != job_id)) begin
                    $fatal(1, "Pod task completion changed under backpressure");
                end
            end
            task_completion_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            task_completion_ready_i = 1'b0;
            checked_tasks = checked_tasks + 1;
        end
    endtask

    task automatic preload_sram_beat;
        input logic [15:0] command_id;
        input logic [34:0] hbm_address;
        input logic [23:0] sram_address;
        input logic [1023:0] data;
        integer lane;
        begin
            @(negedge clk_i);
            dma_command_fields = '0;
            dma_command_fields.version = npu_dma_pkg::NPU_DMA_COMMAND_VERSION;
            dma_command_fields.operation = npu_dma_pkg::NPU_DMA_HBM_TO_SRAM;
            dma_command_fields.command_id = command_id;
            dma_command_fields.hbm_base_address = hbm_address;
            dma_command_fields.sram_base_address = sram_address;
            dma_command_fields.x_beat_count = 18'd1;
            dma_command_fields.y_count = 16'd1;
            dma_command_fields.z_count = 16'd1;
            dma_command_i[0 +: DMA_COMMAND_WIDTH] = dma_command_fields;
            dma_command_valid_i[0] = 1'b1;
            while (!dma_command_ready_o[0]) @(negedge clk_i);
            @(posedge clk_i);
            @(negedge clk_i);
            dma_command_valid_i[0] = 1'b0;

            while (!(|hbm_request_valid_o)) @(negedge clk_i);
            lane = -1;
            for (integer lane_index = 0; lane_index < HBM_LANES;
                 lane_index++) begin
                if (hbm_request_valid_o[lane_index]) lane = lane_index;
            end
            if ((lane < 0) || hbm_request_write_o[lane] ||
                (hbm_request_address_o[
                    lane*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH +:
                    npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH] != hbm_address)) begin
                $fatal(1, "DMA preload HBM request mismatch");
            end
            hbm_request_ready_i[lane] = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            hbm_request_ready_i = '0;

            hbm_response_write_i[lane] = 1'b0;
            hbm_response_partition_i[
                lane*PARTITION_BITS +: PARTITION_BITS] =
                PARTITION_BITS'(PARTITION_ID);
            hbm_response_tag_i[lane*HBM_TAG_WIDTH +: HBM_TAG_WIDTH] =
                hbm_request_tag_o[lane*HBM_TAG_WIDTH +: HBM_TAG_WIDTH];
            hbm_response_read_data_i[lane*1024 +: 1024] = data;
            hbm_response_status_i[lane*2 +: 2] = 2'd0;
            hbm_response_valid_i[lane] = 1'b1;
            while (!hbm_response_ready_o[lane]) @(negedge clk_i);
            @(posedge clk_i);
            @(negedge clk_i);
            hbm_response_valid_i = '0;
            hbm_response_write_i = '0;
            hbm_response_partition_i = '0;
            hbm_response_tag_i = '0;
            hbm_response_read_data_i = '0;
            hbm_response_status_i = '0;

            while (!dma_completion_valid_o[0]) @(negedge clk_i);
            if ((dma_completion_fields.command_id != command_id) ||
                !dma_completion_fields.success ||
                (dma_completion_fields.beats_completed != 18'd1)) begin
                $fatal(1, "DMA preload completion mismatch");
            end
            dma_completion_ready_i[0] = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            dma_completion_ready_i[0] = 1'b0;
        end
    endtask

    task automatic run_local_transfer;
        input integer cluster;
        input logic [15:0] transfer_id;
        input npu_pod_pkg::npu_pod_local_target_e target;
        input logic [3:0] bank_start;
        npu_pod_pkg::npu_pod_local_transfer_t local_fields;
        npu_pod_pkg::npu_pod_local_completion_t observed_completion;
        begin
            @(negedge clk_i);
            local_fields = '0;
            local_fields.version =
                npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_VERSION;
            local_fields.transfer_id = transfer_id;
            local_fields.target = target;
            local_fields.buffer_id = 4'd1;
            local_fields.bank_start = bank_start;
            local_fields.local_offset = 32'h0000_0040;
            local_fields.data_sram_address = 24'h000100;
            local_fields.scale_sram_address = 24'h000200;
            local_fields.word_count = 4'd2;
            local_command_i[cluster*LOCAL_COMMAND_WIDTH +:
                            LOCAL_COMMAND_WIDTH] = local_fields;
            local_command_valid_i[cluster] = 1'b1;
            while (!local_command_ready_o[cluster]) @(negedge clk_i);
            @(posedge clk_i);
            @(negedge clk_i);
            local_command_valid_i[cluster] = 1'b0;
            while (!local_completion_valid_o[cluster]) @(negedge clk_i);
            observed_completion = local_completion_o[
                cluster*LOCAL_COMPLETION_WIDTH +: LOCAL_COMPLETION_WIDTH];
            if ((observed_completion.transfer_id != transfer_id) ||
                !observed_completion.success ||
                (observed_completion.error_code !=
                 npu_pod_pkg::NPU_POD_LOCAL_OK)) begin
                $fatal(1, "Pod local completion mismatch cluster=%0d", cluster);
            end
            local_completion_ready_i[cluster] = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            local_completion_ready_i[cluster] = 1'b0;
            checked_local_writes = checked_local_writes + 2;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        quiesce_i = 1'b0;
        task_valid_i = 1'b0;
        task_preferred_cluster_valid_i = 1'b0;
        task_preferred_cluster_i = 1'b0;
        task_fields = '0;
        task_completion_ready_i = 1'b0;
        local_command_valid_i = '0;
        local_command_i = '0;
        local_completion_ready_i = '0;
        dma_command_valid_i = '0;
        dma_command_i = '0;
        dma_command_fields = '0;
        dma_completion_ready_i = '0;
        hbm_request_ready_i = '0;
        hbm_response_valid_i = '0;
        hbm_response_write_i = '0;
        hbm_response_partition_i = '0;
        hbm_response_tag_i = '0;
        hbm_response_read_data_i = '0;
        hbm_response_status_i = '0;
        gemm_output_ready_i = '1;
        gemm_vector_ready_i = '1;
        gemm_feedback_ready_i = '1;
        event_set_valid_i = '0;
        event_set_id_i = '0;
        event_clear_valid_i = '0;
        event_clear_id_i = '0;
        checked_tasks = 0;
        checked_local_writes = 0;
        for (integer word_index = 0; word_index < 8; word_index++) begin
            test_data[word_index*128 +: 128] =
                {16{8'(8'h20 + word_index)}};
            test_scale[word_index*128 +: 128] =
                {16{8'(8'h80 + word_index)}};
        end

        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        send_task(16'h1101, 1'b0, 1'b0, 1'b0);
        send_task(16'h2202, 1'b1, 1'b1, 1'b1);

        preload_sram_beat(16'h3303, 35'h0000_01000,
                          24'h000100, test_data);
        preload_sram_beat(16'h4404, 35'h0000_02000,
                          24'h000200, test_scale);
        if (sram_accepted_writes_o != 64'd2) begin
            $fatal(1, "Pod shared SRAM did not accept two DMA writes");
        end

        run_local_transfer(0, 16'h5505,
            npu_pod_pkg::NPU_POD_TARGET_TENSOR_WEIGHT, 4'd2);
        if ((dut.g_compute[0].u_compute.tensor_write_count_q != 32'd2) ||
            (dut.g_compute[0].u_compute.last_tensor_bank_q != 4'd3) ||
            (dut.g_compute[0].u_compute.last_tensor_data_q !=
             test_data[128 +: 128]) ||
            (dut.g_compute[0].u_compute.last_tensor_scale_q !=
             test_scale[128 +: 128])) begin
            $fatal(1, "Tensor loader-to-compute integration mismatch");
        end

        run_local_transfer(1, 16'h6606,
            npu_pod_pkg::NPU_POD_TARGET_VECTOR_C, 4'd4);
        if ((dut.g_compute[1].u_compute.vector_write_count_q != 32'd2) ||
            (dut.g_compute[1].u_compute.last_vector_bank_q != 4'd5) ||
            (dut.g_compute[1].u_compute.last_vector_data_q !=
             test_data[128 +: 128]) ||
            (dut.g_compute[1].u_compute.last_vector_scale_q !=
             test_scale[8 +: 8])) begin
            $fatal(1, "Vector loader-to-compute integration mismatch");
        end

        quiesce_i = 1'b1;
        for (integer timeout = 0; timeout < 100; timeout++) begin
            @(posedge clk_i);
            @(negedge clk_i);
            if (quiesced_o) break;
        end
        if (!quiesced_o || protocol_error_o) begin
            $fatal(1, "complete Pod failed clean quiesce");
        end

        $display("[RTL_SIM PASS] npu_compute_pod tasks=%0d local_writes=%0d dma_writes=%0d sram_reads=%0d",
                 checked_tasks, checked_local_writes,
                 sram_accepted_writes_o, sram_accepted_reads_o);
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "npu_compute_pod timeout");
    end

endmodule

`default_nettype wire
