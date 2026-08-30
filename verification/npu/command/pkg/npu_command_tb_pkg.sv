`timescale 1ns/1ps

package npu_command_tb_pkg;

    function automatic npu_command_pkg::npu_decoded_command_t
        make_task_command(
            input logic [npu_pod_pkg::NPU_POD_ID_WIDTH-1:0] pod_id,
            input logic target_valid,
            input logic [npu_command_pkg::NPU_DECODED_TARGET_WIDTH-1:0]
                        target,
            input npu_scheduler_pkg::npu_task_descriptor_t descriptor
        );
        npu_command_pkg::npu_decoded_command_t command;
        command = '0;
        command.version = npu_command_pkg::NPU_DECODED_COMMAND_VERSION;
        command.command_class = npu_command_pkg::NPU_DECODED_TASK;
        command.request_id = descriptor.job_id;
        command.pod_id = pod_id;
        command.target_valid = target_valid;
        command.target = target;
        command.payload[npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] =
            descriptor;
        return command;
    endfunction

    function automatic npu_command_pkg::npu_decoded_command_t
        make_local_command(
            input logic [npu_pod_pkg::NPU_POD_ID_WIDTH-1:0] pod_id,
            input logic [npu_command_pkg::NPU_DECODED_TARGET_WIDTH-1:0]
                        target,
            input npu_pod_pkg::npu_pod_local_transfer_t transfer
        );
        npu_command_pkg::npu_decoded_command_t command;
        command = '0;
        command.version = npu_command_pkg::NPU_DECODED_COMMAND_VERSION;
        command.command_class = npu_command_pkg::NPU_DECODED_LOCAL;
        command.request_id = transfer.transfer_id;
        command.pod_id = pod_id;
        command.target_valid = 1'b1;
        command.target = target;
        command.payload[npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0] =
            transfer;
        return command;
    endfunction

    function automatic npu_command_pkg::npu_decoded_command_t
        make_dma_command(
            input logic [npu_pod_pkg::NPU_POD_ID_WIDTH-1:0] pod_id,
            input logic [npu_command_pkg::NPU_DECODED_TARGET_WIDTH-1:0]
                        target,
            input npu_dma_pkg::npu_dma_command_t descriptor
        );
        npu_command_pkg::npu_decoded_command_t command;
        command = '0;
        command.version = npu_command_pkg::NPU_DECODED_COMMAND_VERSION;
        command.command_class = npu_command_pkg::NPU_DECODED_DMA;
        command.request_id = descriptor.command_id;
        command.pod_id = pod_id;
        command.target_valid = 1'b1;
        command.target = target;
        command.payload[npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0] = descriptor;
        return command;
    endfunction

endpackage
