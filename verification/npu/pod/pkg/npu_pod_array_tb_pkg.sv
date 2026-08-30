`timescale 1ns/1ps

package npu_pod_array_tb_pkg;

    localparam logic [7:0] NPU_POD_ARRAY_ALL_SEEN = 8'hff;

    typedef struct packed {
        logic [7:0] task_completion_seen;
        logic [7:0] dma_completion_seen;
        logic [15:0] local_completion_seen;
        logic [7:0] malformed_completion_seen;
        logic [7:0] hbm_partition_seen;
        logic [7:0] noc_control_tx_seen;
        logic [7:0] noc_control_rx_seen;
        logic [7:0] noc_data_tx_seen;
        logic [7:0] noc_data_rx_seen;
        logic isolated_clear_seen;
        logic isolated_quiesce_seen;
        logic completion_backpressure_seen;
        logic hbm_backpressure_seen;
    } npu_pod_array_coverage_t;

    function automatic npu_command_pkg::npu_decoded_command_t
        make_array_task_command(
            input logic [2:0] pod_id,
            input logic [15:0] job_id,
            input logic [3:0] cluster
        );
        npu_command_pkg::npu_decoded_command_t command;
        npu_scheduler_pkg::npu_task_descriptor_t descriptor;
        descriptor = '0;
        descriptor.version = npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_VERSION;
        descriptor.operation = npu_scheduler_pkg::NPU_TASK_GEMM;
        descriptor.job_id = job_id;
        command = '0;
        command.version = npu_command_pkg::NPU_DECODED_COMMAND_VERSION;
        command.command_class = npu_command_pkg::NPU_DECODED_TASK;
        command.request_id = job_id;
        command.pod_id = pod_id;
        command.target_valid = 1'b1;
        command.target = cluster;
        command.payload = descriptor;
        return command;
    endfunction

    function automatic npu_command_pkg::npu_decoded_command_t
        make_array_dma_read_command(
            input logic [2:0] pod_id,
            input logic [15:0] command_id,
            input logic [34:0] hbm_address,
            input logic [23:0] sram_address
        );
        npu_command_pkg::npu_decoded_command_t command;
        npu_dma_pkg::npu_dma_command_t descriptor;
        descriptor = '0;
        descriptor.version = npu_dma_pkg::NPU_DMA_COMMAND_VERSION;
        descriptor.operation = npu_dma_pkg::NPU_DMA_HBM_TO_SRAM;
        descriptor.command_id = command_id;
        descriptor.hbm_base_address = hbm_address;
        descriptor.sram_base_address = sram_address;
        descriptor.x_beat_count = 18'd1;
        descriptor.y_count = 16'd1;
        descriptor.z_count = 16'd1;
        command = '0;
        command.version = npu_command_pkg::NPU_DECODED_COMMAND_VERSION;
        command.command_class = npu_command_pkg::NPU_DECODED_DMA;
        command.request_id = command_id;
        command.pod_id = pod_id;
        command.target_valid = 1'b1;
        command.target = 4'd0;
        command.payload[npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0] = descriptor;
        return command;
    endfunction

    function automatic npu_command_pkg::npu_decoded_command_t
        make_array_local_command(
            input logic [2:0] pod_id,
            input logic [15:0] transfer_id,
            input logic cluster,
            input logic [23:0] sram_address
        );
        npu_command_pkg::npu_decoded_command_t command;
        npu_pod_pkg::npu_pod_local_transfer_t descriptor;
        descriptor = '0;
        descriptor.version = npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_VERSION;
        descriptor.transfer_id = transfer_id;
        descriptor.target = cluster ?
            npu_pod_pkg::NPU_POD_TARGET_VECTOR_C :
            npu_pod_pkg::NPU_POD_TARGET_VECTOR_B;
        descriptor.buffer_id = 4'd1;
        descriptor.bank_start = cluster ? 4'd8 : 4'd0;
        descriptor.local_offset = 32'h0000_0040;
        descriptor.data_sram_address = sram_address;
        descriptor.scale_sram_address = sram_address;
        descriptor.word_count = 4'd1;
        command = '0;
        command.version = npu_command_pkg::NPU_DECODED_COMMAND_VERSION;
        command.command_class = npu_command_pkg::NPU_DECODED_LOCAL;
        command.request_id = transfer_id;
        command.pod_id = pod_id;
        command.target_valid = 1'b1;
        command.target = {3'd0, cluster};
        command.payload[npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0] =
            descriptor;
        return command;
    endfunction

    function automatic [npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH-1:0]
        make_array_control_flit(
            input logic [2:0] source,
            input logic [2:0] destination,
            input logic [1:0] traffic_class,
            input logic [127:0] payload
        );
        make_array_control_flit = {
            npu_pod_noc_pkg::NPU_POD_NOC_VERSION,
            1'b1,
            1'b1,
            source,
            destination,
            traffic_class,
            {npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_BYTES{1'b1}},
            payload
        };
    endfunction

    function automatic [npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH-1:0]
        make_array_data_flit(
            input logic [2:0] source,
            input logic [2:0] destination,
            input logic [1:0] traffic_class,
            input logic [7:0] payload_byte
        );
        make_array_data_flit = {
            npu_pod_noc_pkg::NPU_POD_NOC_VERSION,
            1'b1,
            1'b1,
            source,
            destination,
            traffic_class,
            {npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES{1'b1}},
            {npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES{payload_byte}}
        };
    endfunction

endpackage
