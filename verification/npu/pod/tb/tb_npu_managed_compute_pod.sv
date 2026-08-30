`timescale 1ns/1ps
`default_nettype none

module tb_npu_managed_compute_pod;
    import npu_command_pkg::*;

    localparam int unsigned POD_ID = 3;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned PARTITION_BITS = 3;
    localparam int unsigned DATA_BYTES = 128;
    localparam int unsigned HBM_TAG_WIDTH = 12;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic quiesce_i;
    logic command_valid_i;
    logic command_ready_o;
    logic [NPU_DECODED_COMMAND_WIDTH-1:0] command_i;
    logic completion_valid_o;
    logic completion_ready_i;
    logic [NPU_UNIFIED_COMPLETION_WIDTH-1:0] completion_o;
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
    logic busy_o;
    logic quiesced_o;
    logic protocol_error_o;
    logic [63:0] sram_accepted_writes_o;
    logic [63:0] accepted_commands_o;
    logic [63:0] rejected_commands_o;
    logic [63:0] delivered_completions_o;
    logic malformed_command_seen_o;
    logic command_busy_o;
    logic command_protocol_error_o;
    integer checks;

    /* verilator lint_off PINCONNECTEMPTY */
    npu_managed_compute_pod #(
        .POD_ID(POD_ID), .PARTITION_ID(POD_ID)
    ) dut (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .quiesce_i(quiesce_i),
        .command_valid_i(command_valid_i),
        .command_ready_o(command_ready_o), .command_i(command_i),
        .completion_valid_o(completion_valid_o),
        .completion_ready_i(completion_ready_i),
        .completion_o(completion_o),
        .hbm_request_valid_o(hbm_request_valid_o),
        .hbm_request_ready_i(hbm_request_ready_i),
        .hbm_request_write_o(hbm_request_write_o),
        .hbm_request_partition_o(hbm_request_partition_o),
        .hbm_request_address_o(hbm_request_address_o),
        .hbm_request_tag_o(hbm_request_tag_o),
        .hbm_request_write_data_o(hbm_request_write_data_o),
        .hbm_request_byte_enable_o(hbm_request_byte_enable_o),
        .hbm_response_valid_i(hbm_response_valid_i),
        .hbm_response_ready_o(hbm_response_ready_o),
        .hbm_response_write_i(hbm_response_write_i),
        .hbm_response_partition_i(hbm_response_partition_i),
        .hbm_response_tag_i(hbm_response_tag_i),
        .hbm_response_read_data_i(hbm_response_read_data_i),
        .hbm_response_status_i(hbm_response_status_i),
        .gemm_output_valid_o(), .gemm_output_ready_i('1),
        .gemm_output_result_o(), .gemm_output_command_o(),
        .gemm_vector_valid_o(), .gemm_vector_ready_i('1),
        .gemm_vector_result_o(), .gemm_vector_command_o(),
        .gemm_feedback_valid_o(), .gemm_feedback_ready_i('1),
        .gemm_feedback_result_o(), .gemm_feedback_command_o(),
        .event_set_valid_i('0), .event_set_id_i('0),
        .event_clear_valid_i('0), .event_clear_id_i('0),
        .dma_command_level_o(), .dma_channel_outstanding_o(),
        .busy_o(busy_o), .quiesced_o(quiesced_o),
        .protocol_error_o(protocol_error_o),
        .task_cluster_busy_o(), .compute_busy_o(), .loader_busy_o(),
        .dma_busy_o(), .outstanding_full_o(), .outstanding_count_o(),
        .outstanding_high_watermark_o(), .accepted_beats_o(),
        .issued_beats_o(), .request_backpressure_cycles_o(),
        .accepted_responses_o(), .delivered_responses_o(),
        .dropped_responses_o(), .response_backpressure_cycles_o(),
        .ok_responses_o(), .corrected_responses_o(),
        .uncorrectable_responses_o(), .data_error_responses_o(),
        .corrected_seen_o(), .uncorrectable_seen_o(), .data_error_seen_o(),
        .sram_accepted_reads_o(),
        .sram_accepted_writes_o(sram_accepted_writes_o),
        .sram_read_conflict_cycles_o(), .sram_write_conflict_cycles_o(),
        .accepted_commands_o(accepted_commands_o),
        .rejected_commands_o(rejected_commands_o),
        .delivered_completions_o(delivered_completions_o),
        .malformed_command_seen_o(malformed_command_seen_o),
        .command_busy_o(command_busy_o),
        .command_protocol_error_o(command_protocol_error_o)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #0.5 clk_i = ~clk_i;

    task automatic send_command(input npu_decoded_command_t command);
        begin
            @(negedge clk_i);
            command_i = command;
            command_valid_i = 1'b1;
            do begin
                @(posedge clk_i);
            end while (!command_ready_o);
            @(negedge clk_i);
            command_valid_i = 1'b0;
            command_i = '0;
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
        logic [NPU_UNIFIED_COMPLETION_WIDTH-1:0] held;
        begin
            completion_ready_i = 1'b0;
            while (!completion_valid_o) @(negedge clk_i);
            held = completion_o;
            repeat (2) begin
                @(negedge clk_i);
                if (!completion_valid_o || (completion_o != held)) begin
                    $fatal(1, "managed completion changed under backpressure");
                end
            end
            observed = npu_unified_completion_t'(held);
            if ((observed.source != source) ||
                (observed.request_id != request_id) ||
                (observed.pod_id != 3'(POD_ID)) ||
                (observed.target != target) ||
                (observed.success != success) || (observed.code != code) ||
                (observed.detail != detail)) begin
                $fatal(1, "managed completion mismatch source=%0d id=%0h code=%0d",
                       observed.source, observed.request_id, observed.code);
            end
            completion_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            completion_ready_i = 1'b0;
            checks = checks + 1;
        end
    endtask

    task automatic issue_dma_read(
        input logic [15:0] command_id,
        input logic [34:0] hbm_address,
        input logic [23:0] sram_address,
        input logic [1023:0] read_data
    );
        npu_dma_pkg::npu_dma_command_t dma;
        npu_decoded_command_t command;
        integer lane;
        logic [HBM_TAG_WIDTH-1:0] tag;
        begin
            dma = '0;
            dma.version = npu_dma_pkg::NPU_DMA_COMMAND_VERSION;
            dma.operation = npu_dma_pkg::NPU_DMA_HBM_TO_SRAM;
            dma.command_id = command_id;
            dma.hbm_base_address = hbm_address;
            dma.sram_base_address = sram_address;
            dma.x_beat_count = 18'd1;
            dma.y_count = 16'd1;
            dma.z_count = 16'd1;
            command = '0;
            command.version = NPU_DECODED_COMMAND_VERSION;
            command.command_class = NPU_DECODED_DMA;
            command.request_id = command_id;
            command.pod_id = 3'(POD_ID);
            command.target_valid = 1'b1;
            command.target = 4'd0;
            command.payload[npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0] = dma;
            send_command(command);

            while (!(|hbm_request_valid_o)) @(negedge clk_i);
            lane = -1;
            for (integer index = 0; index < HBM_LANES; index++) begin
                if (hbm_request_valid_o[index]) lane = index;
            end
            if ((lane < 0) || hbm_request_write_o[lane] ||
                (hbm_request_address_o[
                    lane*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH +:
                    npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH] != hbm_address) ||
                (hbm_request_partition_o[
                    lane*PARTITION_BITS +: PARTITION_BITS] != 3'(POD_ID))) begin
                $fatal(1, "managed DMA request mismatch");
            end
            tag = hbm_request_tag_o[lane*HBM_TAG_WIDTH +: HBM_TAG_WIDTH];
            hbm_request_ready_i[lane] = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            hbm_request_ready_i = '0;

            hbm_response_partition_i[
                lane*PARTITION_BITS +: PARTITION_BITS] = 3'(POD_ID);
            hbm_response_tag_i[lane*HBM_TAG_WIDTH +: HBM_TAG_WIDTH] = tag;
            hbm_response_read_data_i[lane*1024 +: 1024] = read_data;
            hbm_response_status_i[lane*2 +: 2] = 2'd0;
            hbm_response_valid_i[lane] = 1'b1;
            do begin
                @(posedge clk_i);
            end while (!hbm_response_ready_o[lane]);
            @(negedge clk_i);
            hbm_response_valid_i = '0;
            hbm_response_partition_i = '0;
            hbm_response_tag_i = '0;
            hbm_response_read_data_i = '0;
            hbm_response_status_i = '0;
            expect_completion(NPU_COMPLETION_DMA, command_id, 4'd0,
                              1'b1, 8'd0, 32'd1);
        end
    endtask

    initial begin
        npu_scheduler_pkg::npu_task_descriptor_t task_descriptor;
        npu_pod_pkg::npu_pod_local_transfer_t local_descriptor;
        npu_decoded_command_t command;
        logic [1023:0] data_beat;
        logic [1023:0] scale_beat;

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        quiesce_i = 1'b0;
        command_valid_i = 1'b0;
        command_i = '0;
        completion_ready_i = 1'b0;
        hbm_request_ready_i = '0;
        hbm_response_valid_i = '0;
        hbm_response_write_i = '0;
        hbm_response_partition_i = '0;
        hbm_response_tag_i = '0;
        hbm_response_read_data_i = '0;
        hbm_response_status_i = '0;
        checks = 0;
        for (integer word = 0; word < 8; word++) begin
            data_beat[word*128 +: 128] = {16{8'(8'h20 + word)}};
            scale_beat[word*128 +: 128] = {16{8'(8'h80 + word)}};
        end

        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        task_descriptor = '0;
        task_descriptor.version =
            npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_VERSION;
        task_descriptor.operation = npu_scheduler_pkg::NPU_TASK_GEMM;
        task_descriptor.job_id = 16'h1101;
        command = '0;
        command.version = NPU_DECODED_COMMAND_VERSION;
        command.command_class = NPU_DECODED_TASK;
        command.request_id = task_descriptor.job_id;
        command.pod_id = 3'(POD_ID);
        command.target_valid = 1'b1;
        command.target = 4'd1;
        command.payload = task_descriptor;
        send_command(command);
        expect_completion(NPU_COMPLETION_TASK, 16'h1101, 4'd1,
                          1'b1, 8'd0, 32'd0);

        command.pod_id = 3'd7;
        send_command(command);
        expect_completion(NPU_COMPLETION_COMMAND, 16'h1101, 4'd1,
                          1'b0, 8'(NPU_COMMAND_ERROR_POD), 32'd0);

        issue_dma_read(16'h2202, 35'h0000_01000, 24'h000100, data_beat);
        issue_dma_read(16'h3303, 35'h0000_02000, 24'h000200, scale_beat);

        local_descriptor = '0;
        local_descriptor.version =
            npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_VERSION;
        local_descriptor.transfer_id = 16'h4404;
        local_descriptor.target =
            npu_pod_pkg::NPU_POD_TARGET_VECTOR_C;
        local_descriptor.buffer_id = 4'd1;
        local_descriptor.bank_start = 4'd4;
        local_descriptor.local_offset = 32'h0000_0040;
        local_descriptor.data_sram_address = 24'h000100;
        local_descriptor.scale_sram_address = 24'h000200;
        local_descriptor.word_count = 4'd2;
        command = '0;
        command.version = NPU_DECODED_COMMAND_VERSION;
        command.command_class = NPU_DECODED_LOCAL;
        command.request_id = local_descriptor.transfer_id;
        command.pod_id = 3'(POD_ID);
        command.target_valid = 1'b1;
        command.target = 4'd0;
        command.payload[npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0] =
            local_descriptor;
        send_command(command);
        expect_completion(NPU_COMPLETION_LOCAL, 16'h4404, 4'd0,
                          1'b1, 8'd0, 32'd0);

        if ((dut.u_compute_pod.g_compute[0].u_compute.vector_write_count_q !=
             32'd2) ||
            (dut.u_compute_pod.g_compute[0].u_compute.last_vector_bank_q !=
             4'd5) ||
            (dut.u_compute_pod.g_compute[0].u_compute.last_vector_data_q !=
             data_beat[128 +: 128]) ||
            (dut.u_compute_pod.g_compute[0].u_compute.last_vector_scale_q !=
             scale_beat[8 +: 8])) begin
            $fatal(1, "managed local Vector load mismatch");
        end
        checks = checks + 1;

        quiesce_i = 1'b1;
        while (!quiesced_o) @(negedge clk_i);
        repeat (2) @(negedge clk_i);
        if (busy_o || command_busy_o || protocol_error_o ||
            command_protocol_error_o ||
            (accepted_commands_o != 64'd4) ||
            (rejected_commands_o != 64'd1) ||
            (delivered_completions_o != 64'd5) ||
            (sram_accepted_writes_o != 64'd2) ||
            !malformed_command_seen_o) begin
            $fatal(1, "managed Pod closure counters/state mismatch");
        end
        checks = checks + 1;

        $display("[RTL_SIM PASS] npu_managed_compute_pod commands=5 completions=5 checks=%0d",
                 checks);
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "managed Pod timeout");
    end

    wire _unused_hbm_write = &{1'b0, hbm_request_write_data_o,
        hbm_request_byte_enable_o};

endmodule

`default_nettype wire
