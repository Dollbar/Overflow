`timescale 1ns/1ps
`default_nettype none

// Structural eight-Pod NPU boundary. It fixes logical placement and local HBM
// affinity, but deliberately contains no NoC router, VC, credit, routing, CDC,
// HBM controller, or HBM PHY behavior.
module npu_2x4_pod_array #(
    parameter int unsigned PODS = npu_pod_pkg::NPU_POD_COUNT,
    parameter int unsigned CLUSTERS = npu_pod_pkg::NPU_CLUSTERS_PER_POD,
    parameter int unsigned ARRAY_DIM = 16,
    parameter int unsigned DMA_CHANNELS = 16,
    parameter int unsigned HBM_LANES = npu_pod_pkg::NPU_POD_HBM_LANES,
    parameter int unsigned PARTITION_BITS = 3,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned DMA_COMMAND_LEVEL_WIDTH = 3,
    parameter int unsigned HBM_TAG_WIDTH =
        $clog2(DMA_CHANNELS) + LOCAL_TAG_WIDTH,
    parameter int unsigned OUTSTANDING_COUNT_WIDTH =
        $clog2(DMA_CHANNELS * (1 << LOCAL_TAG_WIDTH) + 1),
    parameter int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH,
    parameter int unsigned DATA_LANES =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_LANES,
    parameter int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH
) (
    input  logic [PODS-1:0] pod_clk_i,
    input  logic [PODS-1:0] pod_rst_i,
    input  logic [PODS-1:0] pod_clear_i,
    input  logic [PODS-1:0] pod_quiesce_i,

    input  logic [PODS-1:0] command_valid_i,
    output logic [PODS-1:0] command_ready_o,
    input  logic [PODS*npu_command_pkg::NPU_DECODED_COMMAND_WIDTH-1:0]
                 command_i,
    output logic [PODS-1:0] completion_valid_o,
    input  logic [PODS-1:0] completion_ready_i,
    output logic [PODS*npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH-1:0]
                 completion_o,

    output logic [PODS*HBM_LANES-1:0] hbm_request_valid_o,
    input  logic [PODS*HBM_LANES-1:0] hbm_request_ready_i,
    output logic [PODS*HBM_LANES-1:0] hbm_request_write_o,
    output logic [PODS*HBM_LANES*PARTITION_BITS-1:0]
                 hbm_request_partition_o,
    output logic [PODS*HBM_LANES*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
                 hbm_request_address_o,
    output logic [PODS*HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_request_tag_o,
    output logic [PODS*HBM_LANES*DATA_BYTES*8-1:0]
                 hbm_request_write_data_o,
    output logic [PODS*HBM_LANES*DATA_BYTES-1:0]
                 hbm_request_byte_enable_o,
    input  logic [PODS*HBM_LANES-1:0] hbm_response_valid_i,
    output logic [PODS*HBM_LANES-1:0] hbm_response_ready_o,
    input  logic [PODS*HBM_LANES-1:0] hbm_response_write_i,
    input  logic [PODS*HBM_LANES*PARTITION_BITS-1:0]
                 hbm_response_partition_i,
    input  logic [PODS*HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_response_tag_i,
    input  logic [PODS*HBM_LANES*DATA_BYTES*8-1:0]
                 hbm_response_read_data_i,
    input  logic [PODS*HBM_LANES*2-1:0] hbm_response_status_i,

    output logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_output_valid_o,
    input  logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_output_ready_i,
    output logic [PODS*CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_output_result_o,
    output logic [PODS*CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_output_command_o,
    output logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_vector_valid_o,
    input  logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_vector_ready_i,
    output logic [PODS*CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_vector_result_o,
    output logic [PODS*CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_vector_command_o,
    output logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_valid_o,
    input  logic [PODS*CLUSTERS*ARRAY_DIM-1:0] gemm_feedback_ready_i,
    output logic [PODS*CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_feedback_result_o,
    output logic [PODS*CLUSTERS*ARRAY_DIM*
                  npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_feedback_command_o,
    input  logic [PODS*CLUSTERS-1:0] event_set_valid_i,
    input  logic [PODS*CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
                 event_set_id_i,
    input  logic [PODS*CLUSTERS-1:0] event_clear_valid_i,
    input  logic [PODS*CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
                 event_clear_id_i,

    input  logic [PODS-1:0] pod_control_tx_valid_i,
    output logic [PODS-1:0] pod_control_tx_ready_o,
    input  logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_tx_flit_i,
    output logic [PODS-1:0] noc_control_tx_valid_o,
    input  logic [PODS-1:0] noc_control_tx_ready_i,
    output logic [PODS*CONTROL_FLIT_WIDTH-1:0] noc_control_tx_flit_o,
    input  logic [PODS*DATA_LANES-1:0] pod_data_tx_valid_i,
    output logic [PODS*DATA_LANES-1:0] pod_data_tx_ready_o,
    input  logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_tx_flit_i,
    output logic [PODS*DATA_LANES-1:0] noc_data_tx_valid_o,
    input  logic [PODS*DATA_LANES-1:0] noc_data_tx_ready_i,
    output logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_tx_flit_o,
    input  logic [PODS-1:0] noc_control_rx_valid_i,
    output logic [PODS-1:0] noc_control_rx_ready_o,
    input  logic [PODS*CONTROL_FLIT_WIDTH-1:0] noc_control_rx_flit_i,
    output logic [PODS-1:0] pod_control_rx_valid_o,
    input  logic [PODS-1:0] pod_control_rx_ready_i,
    output logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_rx_flit_o,
    input  logic [PODS*DATA_LANES-1:0] noc_data_rx_valid_i,
    output logic [PODS*DATA_LANES-1:0] noc_data_rx_ready_o,
    input  logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_rx_flit_i,
    output logic [PODS*DATA_LANES-1:0] pod_data_rx_valid_o,
    input  logic [PODS*DATA_LANES-1:0] pod_data_rx_ready_i,
    output logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_rx_flit_o,

    output logic [PODS-1:0] pod_busy_o,
    output logic [PODS-1:0] pod_quiesced_o,
    output logic [PODS-1:0] pod_protocol_error_o,
    output logic [PODS-1:0] command_busy_o,
    output logic [PODS-1:0] command_protocol_error_o,
    output logic [PODS-1:0] malformed_command_seen_o,
    output logic [PODS-1:0] noc_busy_o,
    output logic [PODS-1:0] noc_quiesced_o,
    output logic [PODS-1:0] noc_protocol_error_o,
    output logic [PODS*64-1:0] accepted_commands_o,
    output logic [PODS*64-1:0] rejected_commands_o,
    output logic [PODS*64-1:0] delivered_completions_o
);

    logic [PODS*DMA_CHANNELS*DMA_COMMAND_LEVEL_WIDTH-1:0]
        dma_command_level;
    logic [PODS*DMA_CHANNELS*(LOCAL_TAG_WIDTH+1)-1:0]
        dma_channel_outstanding;
    logic [PODS*CLUSTERS-1:0] task_cluster_busy;
    logic [PODS*CLUSTERS-1:0] compute_busy;
    logic [PODS*CLUSTERS-1:0] loader_busy;
    logic [PODS-1:0] dma_busy;
    logic [PODS-1:0] outstanding_full;
    logic [PODS*OUTSTANDING_COUNT_WIDTH-1:0] outstanding_count;
    logic [PODS*OUTSTANDING_COUNT_WIDTH-1:0] outstanding_high_watermark;
    logic [PODS*64-1:0] accepted_beats;
    logic [PODS*64-1:0] issued_beats;
    logic [PODS*64-1:0] request_backpressure_cycles;
    logic [PODS*64-1:0] accepted_responses;
    logic [PODS*64-1:0] delivered_responses;
    logic [PODS*64-1:0] dropped_responses;
    logic [PODS*64-1:0] response_backpressure_cycles;
    logic [PODS*64-1:0] ok_responses;
    logic [PODS*64-1:0] corrected_responses;
    logic [PODS*64-1:0] uncorrectable_responses;
    logic [PODS*64-1:0] data_error_responses;
    logic [PODS-1:0] corrected_seen;
    logic [PODS-1:0] uncorrectable_seen;
    logic [PODS-1:0] data_error_seen;
    logic [PODS*64-1:0] sram_accepted_reads;
    logic [PODS*64-1:0] sram_accepted_writes;
    logic [PODS*64-1:0] sram_read_conflict_cycles;
    logic [PODS*64-1:0] sram_write_conflict_cycles;
    logic [PODS-1:0] noc_control_tx_busy;
    logic [PODS*DATA_LANES-1:0] noc_data_tx_busy;
    logic [PODS-1:0] noc_control_rx_busy;
    logic [PODS*DATA_LANES-1:0] noc_data_rx_busy;

    generate
        for (genvar pod_index = 0; pod_index < PODS; pod_index++) begin : g_pod
            npu_managed_compute_pod #(
                .POD_ID(pod_index), .CLUSTERS(CLUSTERS),
                .ARRAY_DIM(ARRAY_DIM), .DMA_CHANNELS(DMA_CHANNELS),
                .HBM_LANES(HBM_LANES), .PARTITION_BITS(PARTITION_BITS),
                .PARTITION_ID(pod_index), .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
                .DATA_BYTES(DATA_BYTES),
                .DMA_COMMAND_LEVEL_WIDTH(DMA_COMMAND_LEVEL_WIDTH),
                .HBM_TAG_WIDTH(HBM_TAG_WIDTH),
                .OUTSTANDING_COUNT_WIDTH(OUTSTANDING_COUNT_WIDTH)
            ) u_pod (
                .clk_i(pod_clk_i[pod_index]), .rst_i(pod_rst_i[pod_index]),
                .clear_i(pod_clear_i[pod_index]),
                .quiesce_i(pod_quiesce_i[pod_index]),
                .command_valid_i(command_valid_i[pod_index]),
                .command_ready_o(command_ready_o[pod_index]),
                .command_i(command_i[
                    pod_index*npu_command_pkg::NPU_DECODED_COMMAND_WIDTH +:
                    npu_command_pkg::NPU_DECODED_COMMAND_WIDTH]),
                .completion_valid_o(completion_valid_o[pod_index]),
                .completion_ready_i(completion_ready_i[pod_index]),
                .completion_o(completion_o[
                    pod_index*npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH +:
                    npu_command_pkg::NPU_UNIFIED_COMPLETION_WIDTH]),
                .hbm_request_valid_o(hbm_request_valid_o[
                    pod_index*HBM_LANES +: HBM_LANES]),
                .hbm_request_ready_i(hbm_request_ready_i[
                    pod_index*HBM_LANES +: HBM_LANES]),
                .hbm_request_write_o(hbm_request_write_o[
                    pod_index*HBM_LANES +: HBM_LANES]),
                .hbm_request_partition_o(hbm_request_partition_o[
                    pod_index*HBM_LANES*PARTITION_BITS +:
                    HBM_LANES*PARTITION_BITS]),
                .hbm_request_address_o(hbm_request_address_o[
                    pod_index*HBM_LANES*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH +:
                    HBM_LANES*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH]),
                .hbm_request_tag_o(hbm_request_tag_o[
                    pod_index*HBM_LANES*HBM_TAG_WIDTH +:
                    HBM_LANES*HBM_TAG_WIDTH]),
                .hbm_request_write_data_o(hbm_request_write_data_o[
                    pod_index*HBM_LANES*DATA_BYTES*8 +:
                    HBM_LANES*DATA_BYTES*8]),
                .hbm_request_byte_enable_o(hbm_request_byte_enable_o[
                    pod_index*HBM_LANES*DATA_BYTES +: HBM_LANES*DATA_BYTES]),
                .hbm_response_valid_i(hbm_response_valid_i[
                    pod_index*HBM_LANES +: HBM_LANES]),
                .hbm_response_ready_o(hbm_response_ready_o[
                    pod_index*HBM_LANES +: HBM_LANES]),
                .hbm_response_write_i(hbm_response_write_i[
                    pod_index*HBM_LANES +: HBM_LANES]),
                .hbm_response_partition_i(hbm_response_partition_i[
                    pod_index*HBM_LANES*PARTITION_BITS +:
                    HBM_LANES*PARTITION_BITS]),
                .hbm_response_tag_i(hbm_response_tag_i[
                    pod_index*HBM_LANES*HBM_TAG_WIDTH +:
                    HBM_LANES*HBM_TAG_WIDTH]),
                .hbm_response_read_data_i(hbm_response_read_data_i[
                    pod_index*HBM_LANES*DATA_BYTES*8 +:
                    HBM_LANES*DATA_BYTES*8]),
                .hbm_response_status_i(hbm_response_status_i[
                    pod_index*HBM_LANES*2 +: HBM_LANES*2]),
                .gemm_output_valid_o(gemm_output_valid_o[
                    pod_index*CLUSTERS*ARRAY_DIM +: CLUSTERS*ARRAY_DIM]),
                .gemm_output_ready_i(gemm_output_ready_i[
                    pod_index*CLUSTERS*ARRAY_DIM +: CLUSTERS*ARRAY_DIM]),
                .gemm_output_result_o(gemm_output_result_o[
                    pod_index*CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]),
                .gemm_output_command_o(gemm_output_command_o[
                    pod_index*CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]),
                .gemm_vector_valid_o(gemm_vector_valid_o[
                    pod_index*CLUSTERS*ARRAY_DIM +: CLUSTERS*ARRAY_DIM]),
                .gemm_vector_ready_i(gemm_vector_ready_i[
                    pod_index*CLUSTERS*ARRAY_DIM +: CLUSTERS*ARRAY_DIM]),
                .gemm_vector_result_o(gemm_vector_result_o[
                    pod_index*CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]),
                .gemm_vector_command_o(gemm_vector_command_o[
                    pod_index*CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]),
                .gemm_feedback_valid_o(gemm_feedback_valid_o[
                    pod_index*CLUSTERS*ARRAY_DIM +: CLUSTERS*ARRAY_DIM]),
                .gemm_feedback_ready_i(gemm_feedback_ready_i[
                    pod_index*CLUSTERS*ARRAY_DIM +: CLUSTERS*ARRAY_DIM]),
                .gemm_feedback_result_o(gemm_feedback_result_o[
                    pod_index*CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]),
                .gemm_feedback_command_o(gemm_feedback_command_o[
                    pod_index*CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    CLUSTERS*ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]),
                .event_set_valid_i(event_set_valid_i[
                    pod_index*CLUSTERS +: CLUSTERS]),
                .event_set_id_i(event_set_id_i[
                    pod_index*CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH +:
                    CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH]),
                .event_clear_valid_i(event_clear_valid_i[
                    pod_index*CLUSTERS +: CLUSTERS]),
                .event_clear_id_i(event_clear_id_i[
                    pod_index*CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH +:
                    CLUSTERS*npu_scheduler_pkg::NPU_EVENT_ID_WIDTH]),
                .dma_command_level_o(dma_command_level[
                    pod_index*DMA_CHANNELS*DMA_COMMAND_LEVEL_WIDTH +:
                    DMA_CHANNELS*DMA_COMMAND_LEVEL_WIDTH]),
                .dma_channel_outstanding_o(dma_channel_outstanding[
                    pod_index*DMA_CHANNELS*(LOCAL_TAG_WIDTH+1) +:
                    DMA_CHANNELS*(LOCAL_TAG_WIDTH+1)]),
                .busy_o(pod_busy_o[pod_index]),
                .quiesced_o(pod_quiesced_o[pod_index]),
                .protocol_error_o(pod_protocol_error_o[pod_index]),
                .task_cluster_busy_o(task_cluster_busy[
                    pod_index*CLUSTERS +: CLUSTERS]),
                .compute_busy_o(compute_busy[pod_index*CLUSTERS +: CLUSTERS]),
                .loader_busy_o(loader_busy[pod_index*CLUSTERS +: CLUSTERS]),
                .dma_busy_o(dma_busy[pod_index]),
                .outstanding_full_o(outstanding_full[pod_index]),
                .outstanding_count_o(outstanding_count[
                    pod_index*OUTSTANDING_COUNT_WIDTH +:
                    OUTSTANDING_COUNT_WIDTH]),
                .outstanding_high_watermark_o(outstanding_high_watermark[
                    pod_index*OUTSTANDING_COUNT_WIDTH +:
                    OUTSTANDING_COUNT_WIDTH]),
                .accepted_beats_o(accepted_beats[pod_index*64 +: 64]),
                .issued_beats_o(issued_beats[pod_index*64 +: 64]),
                .request_backpressure_cycles_o(request_backpressure_cycles[
                    pod_index*64 +: 64]),
                .accepted_responses_o(accepted_responses[pod_index*64 +: 64]),
                .delivered_responses_o(delivered_responses[pod_index*64 +: 64]),
                .dropped_responses_o(dropped_responses[pod_index*64 +: 64]),
                .response_backpressure_cycles_o(response_backpressure_cycles[
                    pod_index*64 +: 64]),
                .ok_responses_o(ok_responses[pod_index*64 +: 64]),
                .corrected_responses_o(corrected_responses[pod_index*64 +: 64]),
                .uncorrectable_responses_o(uncorrectable_responses[
                    pod_index*64 +: 64]),
                .data_error_responses_o(data_error_responses[
                    pod_index*64 +: 64]),
                .corrected_seen_o(corrected_seen[pod_index]),
                .uncorrectable_seen_o(uncorrectable_seen[pod_index]),
                .data_error_seen_o(data_error_seen[pod_index]),
                .sram_accepted_reads_o(sram_accepted_reads[pod_index*64 +: 64]),
                .sram_accepted_writes_o(sram_accepted_writes[pod_index*64 +: 64]),
                .sram_read_conflict_cycles_o(sram_read_conflict_cycles[
                    pod_index*64 +: 64]),
                .sram_write_conflict_cycles_o(sram_write_conflict_cycles[
                    pod_index*64 +: 64]),
                .accepted_commands_o(accepted_commands_o[
                    pod_index*64 +: 64]),
                .rejected_commands_o(rejected_commands_o[
                    pod_index*64 +: 64]),
                .delivered_completions_o(delivered_completions_o[
                    pod_index*64 +: 64]),
                .malformed_command_seen_o(malformed_command_seen_o[pod_index]),
                .command_busy_o(command_busy_o[pod_index]),
                .command_protocol_error_o(command_protocol_error_o[pod_index])
            );

            npu_pod_noc_attachment #(
                .POD_ID(pod_index), .DATA_LANES(DATA_LANES),
                .CONTROL_FLIT_WIDTH(CONTROL_FLIT_WIDTH),
                .DATA_FLIT_WIDTH(DATA_FLIT_WIDTH)
            ) u_noc_attachment (
                .clk_i(pod_clk_i[pod_index]), .rst_i(pod_rst_i[pod_index]),
                .clear_i(pod_clear_i[pod_index]),
                .quiesce_i(pod_quiesce_i[pod_index]),
                .pod_control_tx_valid_i(pod_control_tx_valid_i[pod_index]),
                .pod_control_tx_ready_o(pod_control_tx_ready_o[pod_index]),
                .pod_control_tx_flit_i(pod_control_tx_flit_i[
                    pod_index*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]),
                .noc_control_tx_valid_o(noc_control_tx_valid_o[pod_index]),
                .noc_control_tx_ready_i(noc_control_tx_ready_i[pod_index]),
                .noc_control_tx_flit_o(noc_control_tx_flit_o[
                    pod_index*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]),
                .pod_data_tx_valid_i(pod_data_tx_valid_i[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .pod_data_tx_ready_o(pod_data_tx_ready_o[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .pod_data_tx_flit_i(pod_data_tx_flit_i[
                    pod_index*DATA_LANES*DATA_FLIT_WIDTH +:
                    DATA_LANES*DATA_FLIT_WIDTH]),
                .noc_data_tx_valid_o(noc_data_tx_valid_o[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .noc_data_tx_ready_i(noc_data_tx_ready_i[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .noc_data_tx_flit_o(noc_data_tx_flit_o[
                    pod_index*DATA_LANES*DATA_FLIT_WIDTH +:
                    DATA_LANES*DATA_FLIT_WIDTH]),
                .noc_control_rx_valid_i(noc_control_rx_valid_i[pod_index]),
                .noc_control_rx_ready_o(noc_control_rx_ready_o[pod_index]),
                .noc_control_rx_flit_i(noc_control_rx_flit_i[
                    pod_index*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]),
                .pod_control_rx_valid_o(pod_control_rx_valid_o[pod_index]),
                .pod_control_rx_ready_i(pod_control_rx_ready_i[pod_index]),
                .pod_control_rx_flit_o(pod_control_rx_flit_o[
                    pod_index*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]),
                .noc_data_rx_valid_i(noc_data_rx_valid_i[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .noc_data_rx_ready_o(noc_data_rx_ready_o[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .noc_data_rx_flit_i(noc_data_rx_flit_i[
                    pod_index*DATA_LANES*DATA_FLIT_WIDTH +:
                    DATA_LANES*DATA_FLIT_WIDTH]),
                .pod_data_rx_valid_o(pod_data_rx_valid_o[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .pod_data_rx_ready_i(pod_data_rx_ready_i[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .pod_data_rx_flit_o(pod_data_rx_flit_o[
                    pod_index*DATA_LANES*DATA_FLIT_WIDTH +:
                    DATA_LANES*DATA_FLIT_WIDTH]),
                .busy_o(noc_busy_o[pod_index]),
                .quiesced_o(noc_quiesced_o[pod_index]),
                .protocol_error_o(noc_protocol_error_o[pod_index]),
                .control_tx_busy_o(noc_control_tx_busy[pod_index]),
                .data_tx_busy_o(noc_data_tx_busy[
                    pod_index*DATA_LANES +: DATA_LANES]),
                .control_rx_busy_o(noc_control_rx_busy[pod_index]),
                .data_rx_busy_o(noc_data_rx_busy[
                    pod_index*DATA_LANES +: DATA_LANES])
            );
        end
    endgenerate

    // Retain detailed Pod telemetry in the hierarchy without widening the
    // frozen array boundary before the management-register contract exists.
    wire _unused_detailed_telemetry = &{1'b0, dma_command_level,
        dma_channel_outstanding, task_cluster_busy, compute_busy, loader_busy,
        dma_busy, outstanding_full, outstanding_count,
        outstanding_high_watermark, accepted_beats, issued_beats,
        request_backpressure_cycles, accepted_responses, delivered_responses,
        dropped_responses, response_backpressure_cycles, ok_responses,
        corrected_responses, uncorrectable_responses, data_error_responses,
        corrected_seen, uncorrectable_seen, data_error_seen,
        sram_accepted_reads, sram_accepted_writes,
        sram_read_conflict_cycles, sram_write_conflict_cycles,
        noc_control_tx_busy, noc_data_tx_busy, noc_control_rx_busy,
        noc_data_rx_busy};

`ifndef SYNTHESIS
    initial begin
        assert (PODS == 8 && npu_pod_pkg::NPU_POD_MESH_ROWS == 2 &&
                npu_pod_pkg::NPU_POD_MESH_COLUMNS == 4)
            else $error("npu_2x4_pod_array geometry is fixed at 2 by 4");
        assert (HBM_LANES == npu_pod_pkg::NPU_POD_HBM_LANES)
            else $error("each Pod must retain its five-lane HBM boundary");
    end
`endif

endmodule

`default_nettype wire
