`timescale 1ns/1ps
`default_nettype none

// Production-facing one-Pod boundary. The command gateway owns decoded
// task/local/DMA fanout and unified completion serialization; npu_compute_pod
// remains available as the raw leaf integration boundary for debug and VIPs.
module npu_managed_compute_pod #(
    parameter int unsigned POD_ID = 0,
    parameter int unsigned CLUSTERS = 2,
    parameter int unsigned ARRAY_DIM = 16,
    parameter int unsigned BUFFER_COUNT = 4,
    parameter int unsigned DESCRIPTOR_ENTRIES = 16,
    parameter int unsigned TENSOR_VECTOR_DEPTH = 8192,
    parameter int unsigned TASK_SLOTS = 8,
    parameter int unsigned ACTIVE_CONTEXTS = 16,
    parameter int unsigned COMMAND_FIFO_DEPTH = 4,
    parameter int unsigned DESCRIPTOR_INDEX_WIDTH =
        (DESCRIPTOR_ENTRIES <= 1) ? 1 : $clog2(DESCRIPTOR_ENTRIES),
    parameter int unsigned BANK_INDEX_WIDTH =
        (ARRAY_DIM <= 1) ? 1 : $clog2(ARRAY_DIM),
    parameter int unsigned CLUSTER_INDEX_WIDTH =
        (CLUSTERS <= 1) ? 1 : $clog2(CLUSTERS),
    parameter int unsigned DMA_CHANNELS = 16,
    parameter int unsigned HBM_LANES = 5,
    parameter int unsigned PARTITION_BITS = 3,
    parameter int unsigned PARTITION_ID = POD_ID,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned DMA_COMMAND_CONTEXTS_PER_CHANNEL = 4,
    parameter int unsigned DMA_COMMAND_LEVEL_WIDTH =
        $clog2(DMA_COMMAND_CONTEXTS_PER_CHANNEL + 1),
    parameter int unsigned HBM_TAG_WIDTH =
        $clog2(DMA_CHANNELS) + LOCAL_TAG_WIDTH,
    parameter int unsigned OUTSTANDING_COUNT_WIDTH =
        $clog2(DMA_CHANNELS * (1 << LOCAL_TAG_WIDTH) + 1)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic command_valid_i,
    output logic command_ready_o,
    input  logic [npu_command_pkg::NPU_DECODED_COMMAND_WIDTH-1:0]
                 command_i,
    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH-1:0]
                 completion_o,

    output logic [HBM_LANES-1:0] hbm_request_valid_o,
    input  logic [HBM_LANES-1:0] hbm_request_ready_i,
    output logic [HBM_LANES-1:0] hbm_request_write_o,
    output logic [HBM_LANES*PARTITION_BITS-1:0] hbm_request_partition_o,
    output logic [HBM_LANES*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
                 hbm_request_address_o,
    output logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_request_tag_o,
    output logic [HBM_LANES*DATA_BYTES*8-1:0] hbm_request_write_data_o,
    output logic [HBM_LANES*DATA_BYTES-1:0] hbm_request_byte_enable_o,
    input  logic [HBM_LANES-1:0] hbm_response_valid_i,
    output logic [HBM_LANES-1:0] hbm_response_ready_o,
    input  logic [HBM_LANES-1:0] hbm_response_write_i,
    input  logic [HBM_LANES*PARTITION_BITS-1:0]
                 hbm_response_partition_i,
    input  logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_response_tag_i,
    input  logic [HBM_LANES*DATA_BYTES*8-1:0] hbm_response_read_data_i,
    input  logic [HBM_LANES*2-1:0] hbm_response_status_i,

    output logic [CLUSTERS*ARRAY_DIM-1:0] gemm_output_valid_o,
    input  logic [CLUSTERS*ARRAY_DIM-1:0] gemm_output_ready_i,
    output logic [CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_output_result_o,
    output logic [CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_output_command_o,
    output logic [CLUSTERS*ARRAY_DIM-1:0] gemm_vector_valid_o,
    input  logic [CLUSTERS*ARRAY_DIM-1:0] gemm_vector_ready_i,
    output logic [CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_vector_result_o,
    output logic [CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_vector_command_o,
    output logic [CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_valid_o,
    input  logic [CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_ready_i,
    output logic [CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_feedback_result_o,
    output logic [CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_feedback_command_o,

    input  logic [CLUSTERS-1:0] event_set_valid_i,
    input  logic [CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
                 event_set_id_i,
    input  logic [CLUSTERS-1:0] event_clear_valid_i,
    input  logic [CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
                 event_clear_id_i,

    output logic [DMA_CHANNELS*DMA_COMMAND_LEVEL_WIDTH-1:0]
                 dma_command_level_o,
    output logic [DMA_CHANNELS*(LOCAL_TAG_WIDTH+1)-1:0]
                 dma_channel_outstanding_o,
    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o,
    output logic [CLUSTERS-1:0] task_cluster_busy_o,
    output logic [CLUSTERS-1:0] compute_busy_o,
    output logic [CLUSTERS-1:0] loader_busy_o,
    output logic dma_busy_o,
    output logic outstanding_full_o,
    output logic [OUTSTANDING_COUNT_WIDTH-1:0] outstanding_count_o,
    output logic [OUTSTANDING_COUNT_WIDTH-1:0]
                 outstanding_high_watermark_o,
    output logic [63:0] accepted_beats_o,
    output logic [63:0] issued_beats_o,
    output logic [63:0] request_backpressure_cycles_o,
    output logic [63:0] accepted_responses_o,
    output logic [63:0] delivered_responses_o,
    output logic [63:0] dropped_responses_o,
    output logic [63:0] response_backpressure_cycles_o,
    output logic [63:0] ok_responses_o,
    output logic [63:0] corrected_responses_o,
    output logic [63:0] uncorrectable_responses_o,
    output logic [63:0] data_error_responses_o,
    output logic corrected_seen_o,
    output logic uncorrectable_seen_o,
    output logic data_error_seen_o,
    output logic [63:0] sram_accepted_reads_o,
    output logic [63:0] sram_accepted_writes_o,
    output logic [63:0] sram_read_conflict_cycles_o,
    output logic [63:0] sram_write_conflict_cycles_o,

    output logic [63:0] accepted_commands_o,
    output logic [63:0] rejected_commands_o,
    output logic [63:0] delivered_completions_o,
    output logic malformed_command_seen_o,
    output logic command_busy_o,
    output logic command_protocol_error_o
);

    logic task_valid;
    logic task_ready;
    logic task_preferred_cluster_valid;
    logic [CLUSTER_INDEX_WIDTH-1:0] task_preferred_cluster;
    logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_payload;
    logic task_completion_valid;
    logic task_completion_ready;
    logic [CLUSTER_INDEX_WIDTH-1:0] task_completion_cluster;
    logic [npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH-1:0]
        task_completion_status;
    logic [CLUSTERS-1:0] local_command_valid;
    logic [CLUSTERS-1:0] local_command_ready;
    logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0]
        local_command;
    logic [CLUSTERS-1:0] local_completion_valid;
    logic [CLUSTERS-1:0] local_completion_ready;
    logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH-1:0]
        local_completion;
    logic [DMA_CHANNELS-1:0] dma_command_valid;
    logic [DMA_CHANNELS-1:0] dma_command_ready;
    logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0]
        dma_command;
    logic [DMA_CHANNELS-1:0] dma_completion_valid;
    logic [DMA_CHANNELS-1:0] dma_completion_ready;
    logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH-1:0]
        dma_completion;

    npu_pod_command_gateway #(
        .POD_ID(POD_ID), .CLUSTERS(CLUSTERS),
        .DMA_CHANNELS(DMA_CHANNELS),
        .CLUSTER_INDEX_WIDTH(CLUSTER_INDEX_WIDTH)
    ) u_command_gateway (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .quiesce_i(quiesce_i),
        .command_valid_i(command_valid_i),
        .command_ready_o(command_ready_o), .command_i(command_i),
        .task_valid_o(task_valid), .task_ready_i(task_ready),
        .task_preferred_cluster_valid_o(task_preferred_cluster_valid),
        .task_preferred_cluster_o(task_preferred_cluster),
        .task_o(task_payload),
        .local_command_valid_o(local_command_valid),
        .local_command_ready_i(local_command_ready),
        .local_command_o(local_command),
        .dma_command_valid_o(dma_command_valid),
        .dma_command_ready_i(dma_command_ready), .dma_command_o(dma_command),
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
        .completion_valid_o(completion_valid_o),
        .completion_ready_i(completion_ready_i),
        .completion_o(completion_o),
        .accepted_commands_o(accepted_commands_o),
        .rejected_commands_o(rejected_commands_o),
        .delivered_completions_o(delivered_completions_o),
        .malformed_seen_o(malformed_command_seen_o),
        .busy_o(command_busy_o),
        .protocol_error_o(command_protocol_error_o)
    );

    npu_compute_pod #(
        .CLUSTERS(CLUSTERS), .ARRAY_DIM(ARRAY_DIM),
        .BUFFER_COUNT(BUFFER_COUNT),
        .DESCRIPTOR_ENTRIES(DESCRIPTOR_ENTRIES),
        .TENSOR_VECTOR_DEPTH(TENSOR_VECTOR_DEPTH), .TASK_SLOTS(TASK_SLOTS),
        .ACTIVE_CONTEXTS(ACTIVE_CONTEXTS),
        .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH),
        .DESCRIPTOR_INDEX_WIDTH(DESCRIPTOR_INDEX_WIDTH),
        .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH),
        .CLUSTER_INDEX_WIDTH(CLUSTER_INDEX_WIDTH),
        .DMA_CHANNELS(DMA_CHANNELS), .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS), .PARTITION_ID(PARTITION_ID),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH), .DATA_BYTES(DATA_BYTES),
        .DMA_COMMAND_CONTEXTS_PER_CHANNEL(
            DMA_COMMAND_CONTEXTS_PER_CHANNEL),
        .DMA_COMMAND_LEVEL_WIDTH(DMA_COMMAND_LEVEL_WIDTH),
        .HBM_TAG_WIDTH(HBM_TAG_WIDTH),
        .OUTSTANDING_COUNT_WIDTH(OUTSTANDING_COUNT_WIDTH)
    ) u_compute_pod (
        .task_valid_i(task_valid), .task_ready_o(task_ready),
        .task_preferred_cluster_valid_i(task_preferred_cluster_valid),
        .task_preferred_cluster_i(task_preferred_cluster),
        .task_i(task_payload),
        .task_completion_valid_o(task_completion_valid),
        .task_completion_ready_i(task_completion_ready),
        .task_completion_cluster_o(task_completion_cluster),
        .task_completion_status_o(task_completion_status),
        .local_command_valid_i(local_command_valid),
        .local_command_ready_o(local_command_ready),
        .local_command_i(local_command),
        .local_completion_valid_o(local_completion_valid),
        .local_completion_ready_i(local_completion_ready),
        .local_completion_o(local_completion),
        .dma_command_valid_i(dma_command_valid),
        .dma_command_ready_o(dma_command_ready),
        .dma_command_i(dma_command),
        .dma_completion_valid_o(dma_completion_valid),
        .dma_completion_ready_i(dma_completion_ready),
        .dma_completion_o(dma_completion),
        .*
    );

`ifndef SYNTHESIS
    initial begin
        assert (POD_ID < npu_pod_pkg::NPU_POD_COUNT)
            else $error("npu_managed_compute_pod POD_ID is out of range");
        assert (PARTITION_ID == POD_ID)
            else $error("managed Pod must retain local HBM affinity");
    end
`endif

endmodule

`default_nettype wire
