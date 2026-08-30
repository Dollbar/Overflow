`timescale 1ns/1ps
`default_nettype none

// Complete single-clock Pod v0.1 integration boundary. Two compute clusters,
// two local loaders, one DMA engine, and one shared SRAM are connected locally;
// no unapproved NoC, KD-ISA, runtime ABI, HBM-controller, or PHY fields escape.
module npu_compute_pod #(
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
    parameter int unsigned PARTITION_ID = 0,
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

    input  logic task_valid_i,
    output logic task_ready_o,
    input  logic task_preferred_cluster_valid_i,
    input  logic [CLUSTER_INDEX_WIDTH-1:0] task_preferred_cluster_i,
    input  logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_i,
    output logic task_completion_valid_o,
    input  logic task_completion_ready_i,
    output logic [CLUSTER_INDEX_WIDTH-1:0] task_completion_cluster_o,
    output logic [npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH-1:0]
                 task_completion_status_o,

    input  logic [CLUSTERS-1:0] local_command_valid_i,
    output logic [CLUSTERS-1:0] local_command_ready_o,
    input  logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0]
                 local_command_i,
    output logic [CLUSTERS-1:0] local_completion_valid_o,
    input  logic [CLUSTERS-1:0] local_completion_ready_i,
    output logic [CLUSTERS*npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH-1:0]
                 local_completion_o,

    input  logic [DMA_CHANNELS-1:0] dma_command_valid_i,
    output logic [DMA_CHANNELS-1:0] dma_command_ready_o,
    input  logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0]
                 dma_command_i,
    output logic [DMA_CHANNELS*DMA_COMMAND_LEVEL_WIDTH-1:0]
                 dma_command_level_o,
    output logic [DMA_CHANNELS*(LOCAL_TAG_WIDTH+1)-1:0]
                 dma_channel_outstanding_o,
    output logic [DMA_CHANNELS-1:0] dma_completion_valid_o,
    input  logic [DMA_CHANNELS-1:0] dma_completion_ready_i,
    output logic [DMA_CHANNELS*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH-1:0]
                 dma_completion_o,

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
    output logic [63:0] sram_write_conflict_cycles_o
);

    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned SRAM_ADDRESS_WIDTH =
        npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH;
    localparam int unsigned TASK_STATUS_WIDTH =
        npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH;

    npu_scheduler_pkg::npu_task_descriptor_t task_fields;
    npu_scheduler_pkg::npu_task_descriptor_t task_buffer_q;
    npu_scheduler_pkg::npu_task_status_t compute_status_fields
        [0:CLUSTERS-1];
    /* verilator lint_off UNUSEDSIGNAL */
    npu_scheduler_pkg::npu_task_status_t task_completion_fields;
    /* verilator lint_on UNUSEDSIGNAL */

    logic task_buffer_valid_q;
    logic task_descriptor_written_q;
    logic task_allocation_valid;
    logic task_allocation_ready;
    logic task_allocation_fire;
    logic [CLUSTERS-1:0] task_dispatch_valid;
    logic [CLUSTERS-1:0] task_dispatch_ready;
    logic [CLUSTERS*npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        task_dispatch_job_id;
    logic [npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        scoreboard_completion_job_id;
    logic scoreboard_completion_success;
    logic [CLUSTERS-1:0] descriptor_write_valid;
    logic [CLUSTERS-1:0] descriptor_write_ready;
    logic [CLUSTERS-1:0] descriptor_submit_valid;
    logic [CLUSTERS-1:0] descriptor_submit_ready;
    logic [CLUSTERS-1:0] compute_status_valid;
    logic [CLUSTERS-1:0] compute_status_ready;
    logic [CLUSTERS*TASK_STATUS_WIDTH-1:0] compute_status;
    logic [CLUSTERS*npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        compute_retire_job_id;
    logic [CLUSTERS-1:0] compute_retire_success;
    logic scoreboard_busy;
    logic scoreboard_quiesced;
    logic scoreboard_protocol_error;
    logic task_dispatch_metadata_error;
    logic task_completion_metadata_error;

    logic [CLUSTERS-1:0] tensor_write_valid;
    logic [CLUSTERS-1:0] tensor_write_ready;
    logic [CLUSTERS-1:0] tensor_write_weight;
    logic [CLUSTERS*4-1:0] tensor_write_buffer_id;
    logic [CLUSTERS*BANK_INDEX_WIDTH-1:0] tensor_write_bank;
    logic [CLUSTERS*32-1:0] tensor_write_offset;
    logic [CLUSTERS*128-1:0] tensor_write_data;
    logic [CLUSTERS*128-1:0] tensor_write_scale;
    logic [CLUSTERS-1:0] vector_write_valid;
    logic [CLUSTERS-1:0] vector_write_ready;
    logic [CLUSTERS-1:0] vector_write_c;
    logic [CLUSTERS*4-1:0] vector_write_buffer_id;
    logic [CLUSTERS*BANK_INDEX_WIDTH-1:0] vector_write_bank;
    logic [CLUSTERS*32-1:0] vector_write_offset;
    logic [CLUSTERS*128-1:0] vector_write_data;
    logic [CLUSTERS*8-1:0] vector_write_scale;
    logic [CLUSTERS-1:0] loader_quiesced;
    logic [CLUSTERS-1:0] loader_protocol_error;

    logic [CLUSTERS-1:0] loader_sram_request_valid;
    logic [CLUSTERS-1:0] loader_sram_request_ready;
    logic [CLUSTERS*SRAM_ADDRESS_WIDTH-1:0] loader_sram_request_address;
    logic [CLUSTERS-1:0] loader_sram_response_valid;
    logic [CLUSTERS-1:0] loader_sram_response_ready;
    logic [CLUSTERS*DATA_WIDTH-1:0] loader_sram_response_data;

    logic [DMA_CHANNELS-1:0] dma_sram_read_request_valid;
    logic [DMA_CHANNELS-1:0] dma_sram_read_request_ready;
    logic [DMA_CHANNELS*SRAM_ADDRESS_WIDTH-1:0]
        dma_sram_read_request_address;
    logic [DMA_CHANNELS-1:0] dma_sram_read_response_valid;
    logic [DMA_CHANNELS-1:0] dma_sram_read_response_ready;
    logic [DMA_CHANNELS*DATA_WIDTH-1:0] dma_sram_read_response_data;
    logic [DMA_CHANNELS-1:0] dma_sram_write_valid;
    logic [DMA_CHANNELS-1:0] dma_sram_write_ready;
    logic [DMA_CHANNELS*SRAM_ADDRESS_WIDTH-1:0] dma_sram_write_address;
    logic [DMA_CHANNELS*DATA_WIDTH-1:0] dma_sram_write_data;
    logic [DMA_CHANNELS*DATA_BYTES-1:0] dma_sram_write_byte_enable;
    logic dma_quiesced;
    logic dma_protocol_error;

    logic [DMA_CHANNELS-1:0] sram_read_request_valid;
    logic [DMA_CHANNELS-1:0] sram_read_request_ready;
    logic [DMA_CHANNELS*SRAM_ADDRESS_WIDTH-1:0] sram_read_request_address;
    logic [DMA_CHANNELS-1:0] sram_read_response_valid;
    logic [DMA_CHANNELS-1:0] sram_read_response_ready;
    logic [DMA_CHANNELS*DATA_WIDTH-1:0] sram_read_response_data;
    logic [CLUSTERS-1:0] sram_mux_busy;
    logic [CLUSTERS-1:0] sram_mux_protocol_error;
    logic sram_busy;
    logic sram_protocol_error;
    logic [CLUSTERS-1:0] compute_protocol_error;

    assign task_fields = task_i;
    assign task_completion_fields = task_completion_status_o;
    assign task_allocation_valid = task_valid_i && !task_buffer_valid_q;
    assign task_ready_o = task_allocation_ready && !task_buffer_valid_q;
    assign task_allocation_fire = task_allocation_valid &&
                                  task_allocation_ready;

    always_comb begin
        task_dispatch_metadata_error = 1'b0;
        for (integer cluster = 0; cluster < CLUSTERS; cluster++) begin
            if (task_dispatch_valid[cluster] && task_buffer_valid_q &&
                (task_dispatch_job_id[
                    cluster*npu_scheduler_pkg::NPU_JOB_ID_WIDTH +:
                    npu_scheduler_pkg::NPU_JOB_ID_WIDTH] !=
                 task_buffer_q.job_id)) begin
                task_dispatch_metadata_error = 1'b1;
            end
        end
    end
    assign task_completion_metadata_error = task_completion_valid_o &&
        ((scoreboard_completion_job_id != task_completion_fields.job_id) ||
         (scoreboard_completion_success != task_completion_fields.success));

    always_comb begin
        descriptor_write_valid = '0;
        descriptor_submit_valid = '0;
        task_dispatch_ready = '0;
        for (integer cluster = 0; cluster < CLUSTERS; cluster++) begin
            if (task_buffer_valid_q && task_dispatch_valid[cluster]) begin
                if (!task_descriptor_written_q) begin
                    descriptor_write_valid[cluster] = 1'b1;
                end else begin
                    descriptor_submit_valid[cluster] = 1'b1;
                    task_dispatch_ready[cluster] =
                        descriptor_submit_ready[cluster];
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            task_buffer_valid_q <= 1'b0;
            task_descriptor_written_q <= 1'b0;
            task_buffer_q <= '0;
        end else begin
            if (task_allocation_fire) begin
                task_buffer_valid_q <= 1'b1;
                task_descriptor_written_q <= 1'b0;
                task_buffer_q <= task_fields;
            end
            if (|(descriptor_write_valid & descriptor_write_ready)) begin
                task_descriptor_written_q <= 1'b1;
            end
            if (|(task_dispatch_valid & task_dispatch_ready)) begin
                task_buffer_valid_q <= 1'b0;
                task_descriptor_written_q <= 1'b0;
            end
        end
    end

    generate
        for (genvar cluster = 0; cluster < CLUSTERS; cluster++) begin : g_status
            assign compute_status_fields[cluster] = compute_status[
                cluster*TASK_STATUS_WIDTH +: TASK_STATUS_WIDTH];
            assign compute_retire_job_id[
                cluster*npu_scheduler_pkg::NPU_JOB_ID_WIDTH +:
                npu_scheduler_pkg::NPU_JOB_ID_WIDTH] =
                compute_status_fields[cluster].job_id;
            assign compute_retire_success[cluster] =
                compute_status_fields[cluster].success;
        end
    endgenerate

    npu_pod_scoreboard #(
        .CLUSTERS(CLUSTERS),
        .JOB_ID_WIDTH(npu_scheduler_pkg::NPU_JOB_ID_WIDTH),
        .RETIRE_INFO_WIDTH(TASK_STATUS_WIDTH)
    ) u_scoreboard (
        .clk_i,
        .rst_i,
        .clear_i,
        .quiesce_i,
        .allocation_valid_i(task_allocation_valid),
        .allocation_ready_o(task_allocation_ready),
        .allocation_preferred_valid_i(task_preferred_cluster_valid_i),
        .allocation_preferred_cluster_i(task_preferred_cluster_i),
        .allocation_job_id_i(task_fields.job_id),
        .dispatch_valid_o(task_dispatch_valid),
        .dispatch_ready_i(task_dispatch_ready),
        .dispatch_job_id_o(task_dispatch_job_id),
        .retire_valid_i(compute_status_valid),
        .retire_ready_o(compute_status_ready),
        .retire_job_id_i(compute_retire_job_id),
        .retire_success_i(compute_retire_success),
        .retire_info_i(compute_status),
        .completion_valid_o(task_completion_valid_o),
        .completion_ready_i(task_completion_ready_i),
        .completion_cluster_o(task_completion_cluster_o),
        .completion_job_id_o(scoreboard_completion_job_id),
        .completion_success_o(scoreboard_completion_success),
        .completion_info_o(task_completion_status_o),
        .cluster_busy_o(task_cluster_busy_o),
        .busy_o(scoreboard_busy),
        .quiesced_o(scoreboard_quiesced),
        .protocol_error_o(scoreboard_protocol_error)
    );

    generate
        for (genvar cluster = 0; cluster < CLUSTERS; cluster++) begin : g_loader
            npu_pod_local_loader #(
                .SRAM_ADDRESS_WIDTH(SRAM_ADDRESS_WIDTH),
                .SRAM_DATA_WIDTH(DATA_WIDTH),
                .LOCAL_BANKS(ARRAY_DIM),
                .LOCAL_BUFFER_COUNT(BUFFER_COUNT),
                .LOCAL_VECTOR_DEPTH(TENSOR_VECTOR_DEPTH),
                .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH)
            ) u_loader (
                .clk_i,
                .rst_i,
                .clear_i,
                .quiesce_i,
                .command_valid_i(local_command_valid_i[cluster]),
                .command_ready_o(local_command_ready_o[cluster]),
                .command_i(local_command_i[
                    cluster*npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH +:
                    npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH]),
                .shared_read_request_valid_o(
                    loader_sram_request_valid[cluster]),
                .shared_read_request_ready_i(
                    loader_sram_request_ready[cluster]),
                .shared_read_request_address_o(loader_sram_request_address[
                    cluster*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH]),
                .shared_read_response_valid_i(
                    loader_sram_response_valid[cluster]),
                .shared_read_response_ready_o(
                    loader_sram_response_ready[cluster]),
                .shared_read_response_data_i(loader_sram_response_data[
                    cluster*DATA_WIDTH +: DATA_WIDTH]),
                .tensor_write_valid_o(tensor_write_valid[cluster]),
                .tensor_write_ready_i(tensor_write_ready[cluster]),
                .tensor_write_weight_o(tensor_write_weight[cluster]),
                .tensor_write_buffer_id_o(tensor_write_buffer_id[
                    cluster*4 +: 4]),
                .tensor_write_bank_o(tensor_write_bank[
                    cluster*BANK_INDEX_WIDTH +: BANK_INDEX_WIDTH]),
                .tensor_write_offset_o(tensor_write_offset[
                    cluster*32 +: 32]),
                .tensor_write_data_o(tensor_write_data[
                    cluster*128 +: 128]),
                .tensor_write_scale_o(tensor_write_scale[
                    cluster*128 +: 128]),
                .vector_write_valid_o(vector_write_valid[cluster]),
                .vector_write_ready_i(vector_write_ready[cluster]),
                .vector_write_c_o(vector_write_c[cluster]),
                .vector_write_buffer_id_o(vector_write_buffer_id[
                    cluster*4 +: 4]),
                .vector_write_bank_o(vector_write_bank[
                    cluster*BANK_INDEX_WIDTH +: BANK_INDEX_WIDTH]),
                .vector_write_offset_o(vector_write_offset[
                    cluster*32 +: 32]),
                .vector_write_data_o(vector_write_data[
                    cluster*128 +: 128]),
                .vector_write_scale_o(vector_write_scale[
                    cluster*8 +: 8]),
                .completion_valid_o(local_completion_valid_o[cluster]),
                .completion_ready_i(local_completion_ready_i[cluster]),
                .completion_o(local_completion_o[
                    cluster*npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH +:
                    npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH]),
                .busy_o(loader_busy_o[cluster]),
                .quiesced_o(loader_quiesced[cluster]),
                .protocol_error_o(loader_protocol_error[cluster])
            );
        end
    endgenerate

    generate
        for (genvar cluster = 0; cluster < CLUSTERS; cluster++) begin : g_compute
            npu_square_gemm_system #(
                .ARRAY_DIM(ARRAY_DIM),
                .BUFFER_COUNT(BUFFER_COUNT),
                .DESCRIPTOR_ENTRIES(DESCRIPTOR_ENTRIES),
                .TENSOR_VECTOR_DEPTH(TENSOR_VECTOR_DEPTH),
                .TASK_SLOTS(TASK_SLOTS),
                .ACTIVE_CONTEXTS(ACTIVE_CONTEXTS),
                .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH),
                .DESCRIPTOR_INDEX_WIDTH(DESCRIPTOR_INDEX_WIDTH),
                .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH)
            ) u_compute (
                .clk_i,
                .rst_i,
                .clear_i,
                .descriptor_write_valid_i(descriptor_write_valid[cluster]),
                .descriptor_write_ready_o(descriptor_write_ready[cluster]),
                .descriptor_write_index_i('0),
                .descriptor_write_data_i(task_buffer_q),
                .descriptor_submit_valid_i(descriptor_submit_valid[cluster]),
                .descriptor_submit_ready_o(descriptor_submit_ready[cluster]),
                .descriptor_submit_index_i('0),
                .tensor_write_valid_i(tensor_write_valid[cluster]),
                .tensor_write_ready_o(tensor_write_ready[cluster]),
                .tensor_write_weight_i(tensor_write_weight[cluster]),
                .tensor_write_buffer_id_i(tensor_write_buffer_id[
                    cluster*4 +: 4]),
                .tensor_write_bank_i(tensor_write_bank[
                    cluster*BANK_INDEX_WIDTH +: BANK_INDEX_WIDTH]),
                .tensor_write_offset_i(tensor_write_offset[
                    cluster*32 +: 32]),
                .tensor_write_data_i(tensor_write_data[
                    cluster*128 +: 128]),
                .tensor_write_scale_i(tensor_write_scale[
                    cluster*128 +: 128]),
                .vector_operand_write_valid_i(vector_write_valid[cluster]),
                .vector_operand_write_ready_o(vector_write_ready[cluster]),
                .vector_operand_write_c_i(vector_write_c[cluster]),
                .vector_operand_write_buffer_id_i(vector_write_buffer_id[
                    cluster*4 +: 4]),
                .vector_operand_write_bank_i(vector_write_bank[
                    cluster*BANK_INDEX_WIDTH +: BANK_INDEX_WIDTH]),
                .vector_operand_write_offset_i(vector_write_offset[
                    cluster*32 +: 32]),
                .vector_operand_write_data_i(vector_write_data[
                    cluster*128 +: 128]),
                .vector_operand_write_scale_i(vector_write_scale[
                    cluster*8 +: 8]),
                .gemm_output_valid_o(gemm_output_valid_o[
                    cluster*ARRAY_DIM +: ARRAY_DIM]),
                .gemm_output_ready_i(gemm_output_ready_i[
                    cluster*ARRAY_DIM +: ARRAY_DIM]),
                .gemm_output_result_o(gemm_output_result_o[
                    cluster*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]),
                .gemm_output_command_o(gemm_output_command_o[
                    cluster*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]),
                .gemm_vector_valid_o(gemm_vector_valid_o[
                    cluster*ARRAY_DIM +: ARRAY_DIM]),
                .gemm_vector_ready_i(gemm_vector_ready_i[
                    cluster*ARRAY_DIM +: ARRAY_DIM]),
                .gemm_vector_result_o(gemm_vector_result_o[
                    cluster*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]),
                .gemm_vector_command_o(gemm_vector_command_o[
                    cluster*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]),
                .gemm_feedback_valid_o(gemm_feedback_valid_o[
                    cluster*ARRAY_DIM +: ARRAY_DIM]),
                .gemm_feedback_ready_i(gemm_feedback_ready_i[
                    cluster*ARRAY_DIM +: ARRAY_DIM]),
                .gemm_feedback_result_o(gemm_feedback_result_o[
                    cluster*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]),
                .gemm_feedback_command_o(gemm_feedback_command_o[
                    cluster*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]),
                .event_set_valid_i(event_set_valid_i[cluster]),
                .event_set_id_i(event_set_id_i[
                    cluster*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH +:
                    npu_scheduler_pkg::NPU_EVENT_ID_WIDTH]),
                .event_clear_valid_i(event_clear_valid_i[cluster]),
                .event_clear_id_i(event_clear_id_i[
                    cluster*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH +:
                    npu_scheduler_pkg::NPU_EVENT_ID_WIDTH]),
                .status_valid_o(compute_status_valid[cluster]),
                .status_ready_i(compute_status_ready[cluster]),
                .status_o(compute_status[
                    cluster*TASK_STATUS_WIDTH +: TASK_STATUS_WIDTH]),
                .busy_o(compute_busy_o[cluster]),
                .protocol_error_o(compute_protocol_error[cluster])
            );
        end
    endgenerate

    npu_dma_engine #(
        .CHANNELS(DMA_CHANNELS),
        .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS),
        .PARTITION_ID(PARTITION_ID),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES),
        .COMMAND_CONTEXTS_PER_CHANNEL(
            DMA_COMMAND_CONTEXTS_PER_CHANNEL)
    ) u_dma (
        .clk_i,
        .rst_i,
        .clear_i,
        .quiesce_i,
        .command_valid_i(dma_command_valid_i),
        .command_ready_o(dma_command_ready_o),
        .command_i(dma_command_i),
        .command_level_o(dma_command_level_o),
        .channel_outstanding_o(dma_channel_outstanding_o),
        .completion_valid_o(dma_completion_valid_o),
        .completion_ready_i(dma_completion_ready_i),
        .completion_o(dma_completion_o),
        .sram_read_request_valid_o(dma_sram_read_request_valid),
        .sram_read_request_ready_i(dma_sram_read_request_ready),
        .sram_read_request_address_o(dma_sram_read_request_address),
        .sram_read_response_valid_i(dma_sram_read_response_valid),
        .sram_read_response_ready_o(dma_sram_read_response_ready),
        .sram_read_response_data_i(dma_sram_read_response_data),
        .sram_write_valid_o(dma_sram_write_valid),
        .sram_write_ready_i(dma_sram_write_ready),
        .sram_write_address_o(dma_sram_write_address),
        .sram_write_data_o(dma_sram_write_data),
        .sram_write_byte_enable_o(dma_sram_write_byte_enable),
        .hbm_request_valid_o,
        .hbm_request_ready_i,
        .hbm_request_write_o,
        .hbm_request_partition_o,
        .hbm_request_address_o,
        .hbm_request_tag_o,
        .hbm_request_write_data_o,
        .hbm_request_byte_enable_o,
        .hbm_response_valid_i,
        .hbm_response_ready_o,
        .hbm_response_write_i,
        .hbm_response_partition_i,
        .hbm_response_tag_i,
        .hbm_response_read_data_i,
        .hbm_response_status_i,
        .busy_o(dma_busy_o),
        .quiesced_o(dma_quiesced),
        .protocol_error_o(dma_protocol_error),
        .outstanding_full_o,
        .outstanding_count_o,
        .outstanding_high_watermark_o,
        .accepted_beats_o,
        .issued_beats_o,
        .request_backpressure_cycles_o,
        .accepted_responses_o,
        .delivered_responses_o,
        .dropped_responses_o,
        .response_backpressure_cycles_o,
        .ok_responses_o,
        .corrected_responses_o,
        .uncorrectable_responses_o,
        .data_error_responses_o,
        .corrected_seen_o,
        .uncorrectable_seen_o,
        .data_error_seen_o
    );

    generate
        for (genvar cluster = 0; cluster < CLUSTERS; cluster++) begin : g_sram_mux
            npu_pod_sram_read_mux #(
                .ADDRESS_WIDTH(SRAM_ADDRESS_WIDTH),
                .DATA_WIDTH(DATA_WIDTH)
            ) u_read_mux (
                .clk_i,
                .rst_i,
                .clear_i,
                .dma_request_valid_i(dma_sram_read_request_valid[cluster]),
                .dma_request_ready_o(dma_sram_read_request_ready[cluster]),
                .dma_request_address_i(dma_sram_read_request_address[
                    cluster*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH]),
                .dma_response_valid_o(dma_sram_read_response_valid[cluster]),
                .dma_response_ready_i(dma_sram_read_response_ready[cluster]),
                .dma_response_data_o(dma_sram_read_response_data[
                    cluster*DATA_WIDTH +: DATA_WIDTH]),
                .loader_request_valid_i(loader_sram_request_valid[cluster]),
                .loader_request_ready_o(loader_sram_request_ready[cluster]),
                .loader_request_address_i(loader_sram_request_address[
                    cluster*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH]),
                .loader_response_valid_o(loader_sram_response_valid[cluster]),
                .loader_response_ready_i(loader_sram_response_ready[cluster]),
                .loader_response_data_o(loader_sram_response_data[
                    cluster*DATA_WIDTH +: DATA_WIDTH]),
                .downstream_request_valid_o(sram_read_request_valid[cluster]),
                .downstream_request_ready_i(sram_read_request_ready[cluster]),
                .downstream_request_address_o(sram_read_request_address[
                    cluster*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH]),
                .downstream_response_valid_i(sram_read_response_valid[cluster]),
                .downstream_response_ready_o(sram_read_response_ready[cluster]),
                .downstream_response_data_i(sram_read_response_data[
                    cluster*DATA_WIDTH +: DATA_WIDTH]),
                .busy_o(sram_mux_busy[cluster]),
                .protocol_error_o(sram_mux_protocol_error[cluster])
            );
        end
        for (genvar channel = CLUSTERS; channel < DMA_CHANNELS;
             channel++) begin : g_sram_direct
            assign sram_read_request_valid[channel] =
                dma_sram_read_request_valid[channel];
            assign dma_sram_read_request_ready[channel] =
                sram_read_request_ready[channel];
            assign sram_read_request_address[
                channel*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH] =
                dma_sram_read_request_address[
                    channel*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH];
            assign dma_sram_read_response_valid[channel] =
                sram_read_response_valid[channel];
            assign sram_read_response_ready[channel] =
                dma_sram_read_response_ready[channel];
            assign dma_sram_read_response_data[
                channel*DATA_WIDTH +: DATA_WIDTH] = sram_read_response_data[
                    channel*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate

    npu_pod_shared_sram #(
        .CLIENTS(DMA_CHANNELS),
        .DATA_BYTES(DATA_BYTES)
    ) u_shared_sram (
        .clk_i,
        .rst_i,
        .clear_i,
        .read_request_valid_i(sram_read_request_valid),
        .read_request_ready_o(sram_read_request_ready),
        .read_request_address_i(sram_read_request_address),
        .read_response_valid_o(sram_read_response_valid),
        .read_response_ready_i(sram_read_response_ready),
        .read_response_data_o(sram_read_response_data),
        .write_valid_i(dma_sram_write_valid),
        .write_ready_o(dma_sram_write_ready),
        .write_address_i(dma_sram_write_address),
        .write_data_i(dma_sram_write_data),
        .write_byte_enable_i(dma_sram_write_byte_enable),
        .busy_o(sram_busy),
        .protocol_error_o(sram_protocol_error),
        .accepted_reads_o(sram_accepted_reads_o),
        .accepted_writes_o(sram_accepted_writes_o),
        .read_conflict_cycles_o(sram_read_conflict_cycles_o),
        .write_conflict_cycles_o(sram_write_conflict_cycles_o)
    );

    assign busy_o = scoreboard_busy || (|compute_busy_o) ||
                    (|loader_busy_o) || dma_busy_o || sram_busy ||
                    (|sram_mux_busy);
    assign quiesced_o = quiesce_i && scoreboard_quiesced &&
                        (&loader_quiesced) && dma_quiesced &&
                        !(|compute_busy_o) && !sram_busy &&
                        !(|sram_mux_busy);
    assign protocol_error_o = scoreboard_protocol_error ||
                              task_dispatch_metadata_error ||
                              task_completion_metadata_error ||
                              (|compute_protocol_error) ||
                              (|loader_protocol_error) ||
                              dma_protocol_error || sram_protocol_error ||
                              (|sram_mux_protocol_error);

    initial begin
        if ((CLUSTERS != 2) || (ARRAY_DIM != 16) ||
            (DMA_CHANNELS != 16) || (HBM_LANES != 5) ||
            (PARTITION_BITS != 3) || (LOCAL_TAG_WIDTH != 8) ||
            (DATA_BYTES != 128)) begin
            $error("npu_compute_pod violates Pod v0.1 geometry");
        end
    end

endmodule

`default_nettype wire
