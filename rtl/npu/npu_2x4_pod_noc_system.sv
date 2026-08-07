`timescale 1ns/1ps
`default_nettype none

// Production integration boundary for the fixed 2x4 Pod array and its NoC.
// Packet payloads stay opaque here: remote DMA/SRAM/compute semantics belong
// in separately versioned packet-client adapters, not in the transport shell.
module npu_2x4_pod_noc_system #(
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
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH,
    parameter int unsigned NOC_PORTS = npu_noc_pkg::NPU_NOC_PORTS
) (
    input  logic [PODS-1:0] pod_clk_i,
    input  logic noc_clk_i,
    input  logic async_rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

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

    // Opaque packet-client boundary, one control stream and two data lanes
    // per Pod. The system top owns every attachment/CDC/router connection.
    input  logic [PODS-1:0] pod_control_tx_valid_i,
    output logic [PODS-1:0] pod_control_tx_ready_o,
    input  logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_tx_flit_i,
    output logic [PODS-1:0] pod_control_rx_valid_o,
    input  logic [PODS-1:0] pod_control_rx_ready_i,
    output logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_rx_flit_o,
    input  logic [PODS*DATA_LANES-1:0] pod_data_tx_valid_i,
    output logic [PODS*DATA_LANES-1:0] pod_data_tx_ready_o,
    input  logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_tx_flit_i,
    output logic [PODS*DATA_LANES-1:0] pod_data_rx_valid_o,
    input  logic [PODS*DATA_LANES-1:0] pod_data_rx_ready_i,
    output logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_rx_flit_o,

    output logic [PODS-1:0] pod_rst_o,
    output logic noc_rst_o,
    output logic [PODS-1:0] pod_quiesce_o,
    output logic [PODS-1:0] pod_busy_o,
    output logic [PODS-1:0] pod_quiesced_o,
    output logic [PODS-1:0] pod_protocol_error_o,
    output logic [PODS-1:0] command_busy_o,
    output logic [PODS-1:0] command_protocol_error_o,
    output logic [PODS-1:0] malformed_command_seen_o,
    output logic [PODS-1:0] attachment_busy_o,
    output logic [PODS-1:0] attachment_quiesced_o,
    output logic [PODS-1:0] attachment_protocol_error_o,
    output logic [PODS*64-1:0] accepted_commands_o,
    output logic [PODS*64-1:0] rejected_commands_o,
    output logic [PODS*64-1:0] delivered_completions_o,

    output logic noc_busy_o,
    output logic noc_quiesced_o,
    output logic noc_protocol_error_o,
    output logic system_busy_o,
    output logic system_quiesced_o,
    output logic system_protocol_error_o,
    output logic [PODS-1:0] pod_cdc_busy_o,
    output logic [PODS-1:0] noc_cdc_busy_o,
    output logic [PODS-1:0] control_router_busy_o,
    output logic [DATA_LANES*PODS-1:0] data_router_busy_o,
    output logic [PODS-1:0] control_router_protocol_error_o,
    output logic [DATA_LANES*PODS-1:0] data_router_protocol_error_o,
    output logic [PODS*NOC_PORTS*64-1:0] control_accepted_flits_o,
    output logic [PODS*NOC_PORTS*64-1:0] control_transmitted_flits_o,
    output logic [PODS*NOC_PORTS*64-1:0] control_blocked_cycles_o,
    output logic [PODS*NOC_PORTS*64-1:0] control_accepted_packets_o,
    output logic [PODS*NOC_PORTS*64-1:0] control_transmitted_packets_o,
    output logic [PODS*NOC_PORTS*64-1:0] control_maximum_wait_cycles_o,
    output logic [PODS*NOC_PORTS*64-1:0] control_credit_low_watermark_o,
    output logic [PODS*NOC_PORTS*64-1:0] control_invalid_route_events_o,
    output logic [DATA_LANES*PODS*NOC_PORTS*64-1:0]
                 data_accepted_flits_o,
    output logic [DATA_LANES*PODS*NOC_PORTS*64-1:0]
                 data_transmitted_flits_o,
    output logic [DATA_LANES*PODS*NOC_PORTS*64-1:0]
                 data_blocked_cycles_o,
    output logic [DATA_LANES*PODS*NOC_PORTS*64-1:0]
                 data_accepted_packets_o,
    output logic [DATA_LANES*PODS*NOC_PORTS*64-1:0]
                 data_transmitted_packets_o,
    output logic [DATA_LANES*PODS*NOC_PORTS*64-1:0]
                 data_maximum_wait_cycles_o,
    output logic [DATA_LANES*PODS*NOC_PORTS*64-1:0]
                 data_credit_low_watermark_o,
    output logic [DATA_LANES*PODS*NOC_PORTS*64-1:0]
                 data_invalid_route_events_o
);

    logic [PODS-1:0] array_control_tx_valid;
    logic [PODS-1:0] array_control_tx_ready;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] array_control_tx_flit;
    logic [PODS-1:0] array_control_rx_valid;
    logic [PODS-1:0] array_control_rx_ready;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] array_control_rx_flit;
    logic [PODS*DATA_LANES-1:0] array_data_tx_valid;
    logic [PODS*DATA_LANES-1:0] array_data_tx_ready;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] array_data_tx_flit;
    logic [PODS*DATA_LANES-1:0] array_data_rx_valid;
    logic [PODS*DATA_LANES-1:0] array_data_rx_ready;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] array_data_rx_flit;

    logic [PODS-1:0] pod_busy_sync;
    logic [PODS-1:0] pod_quiesced_sync;
    logic [PODS-1:0] pod_error_sync;
    logic [PODS-1:0] command_busy_sync;
    logic [PODS-1:0] command_error_sync;
    logic [PODS-1:0] attachment_busy_sync;
    logic [PODS-1:0] attachment_quiesced_sync;
    logic [PODS-1:0] attachment_error_sync;

    npu_2x4_pod_array #(
        .PODS(PODS), .CLUSTERS(CLUSTERS), .ARRAY_DIM(ARRAY_DIM),
        .DMA_CHANNELS(DMA_CHANNELS), .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS), .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES),
        .DMA_COMMAND_LEVEL_WIDTH(DMA_COMMAND_LEVEL_WIDTH),
        .HBM_TAG_WIDTH(HBM_TAG_WIDTH),
        .OUTSTANDING_COUNT_WIDTH(OUTSTANDING_COUNT_WIDTH),
        .CONTROL_FLIT_WIDTH(CONTROL_FLIT_WIDTH),
        .DATA_LANES(DATA_LANES), .DATA_FLIT_WIDTH(DATA_FLIT_WIDTH)
    ) u_pod_array (
        .pod_rst_i(pod_rst_o),
        .pod_clear_i('0),
        .pod_quiesce_i(pod_quiesce_o),
        .noc_control_tx_valid_o(array_control_tx_valid),
        .noc_control_tx_ready_i(array_control_tx_ready),
        .noc_control_tx_flit_o(array_control_tx_flit),
        .noc_data_tx_valid_o(array_data_tx_valid),
        .noc_data_tx_ready_i(array_data_tx_ready),
        .noc_data_tx_flit_o(array_data_tx_flit),
        .noc_control_rx_valid_i(array_control_rx_valid),
        .noc_control_rx_ready_o(array_control_rx_ready),
        .noc_control_rx_flit_i(array_control_rx_flit),
        .noc_data_rx_valid_i(array_data_rx_valid),
        .noc_data_rx_ready_o(array_data_rx_ready),
        .noc_data_rx_flit_i(array_data_rx_flit),
        .noc_busy_o(attachment_busy_o),
        .noc_quiesced_o(attachment_quiesced_o),
        .noc_protocol_error_o(attachment_protocol_error_o),
        .*
    );

    npu_noc_cdc_mesh #(
        .PODS(PODS), .DATA_LANES(DATA_LANES), .PORTS(NOC_PORTS),
        .CONTROL_FLIT_WIDTH(CONTROL_FLIT_WIDTH),
        .DATA_FLIT_WIDTH(DATA_FLIT_WIDTH)
    ) u_noc (
        .pod_control_tx_valid_i(array_control_tx_valid),
        .pod_control_tx_ready_o(array_control_tx_ready),
        .pod_control_tx_flit_i(array_control_tx_flit),
        .pod_control_rx_valid_o(array_control_rx_valid),
        .pod_control_rx_ready_i(array_control_rx_ready),
        .pod_control_rx_flit_o(array_control_rx_flit),
        .pod_data_tx_valid_i(array_data_tx_valid),
        .pod_data_tx_ready_o(array_data_tx_ready),
        .pod_data_tx_flit_i(array_data_tx_flit),
        .pod_data_rx_valid_o(array_data_rx_valid),
        .pod_data_rx_ready_i(array_data_rx_ready),
        .pod_data_rx_flit_o(array_data_rx_flit),
        .busy_o(noc_busy_o),
        .quiesced_o(noc_quiesced_o),
        .protocol_error_o(noc_protocol_error_o),
        .*
    );

    // All single-bit Pod-domain status is synchronized into the NoC clock
    // domain before producing the system-wide management summary.
    generate
        for (genvar pod = 0; pod < PODS; pod++) begin : g_status_sync
            npu_noc_level_sync u_pod_busy_sync (
                .clk_i(noc_clk_i), .rst_i(noc_rst_o),
                .async_level_i(pod_busy_o[pod]),
                .sync_level_o(pod_busy_sync[pod]));
            npu_noc_level_sync #(.RESET_VALUE(1'b1)) u_pod_quiesced_sync (
                .clk_i(noc_clk_i), .rst_i(noc_rst_o),
                .async_level_i(pod_quiesced_o[pod]),
                .sync_level_o(pod_quiesced_sync[pod]));
            npu_noc_level_sync u_pod_error_sync (
                .clk_i(noc_clk_i), .rst_i(noc_rst_o),
                .async_level_i(pod_protocol_error_o[pod]),
                .sync_level_o(pod_error_sync[pod]));
            npu_noc_level_sync u_command_busy_sync (
                .clk_i(noc_clk_i), .rst_i(noc_rst_o),
                .async_level_i(command_busy_o[pod]),
                .sync_level_o(command_busy_sync[pod]));
            npu_noc_level_sync u_command_error_sync (
                .clk_i(noc_clk_i), .rst_i(noc_rst_o),
                .async_level_i(command_protocol_error_o[pod]),
                .sync_level_o(command_error_sync[pod]));
            npu_noc_level_sync u_attachment_busy_sync (
                .clk_i(noc_clk_i), .rst_i(noc_rst_o),
                .async_level_i(attachment_busy_o[pod]),
                .sync_level_o(attachment_busy_sync[pod]));
            npu_noc_level_sync #(.RESET_VALUE(1'b1))
                u_attachment_quiesced_sync (
                    .clk_i(noc_clk_i), .rst_i(noc_rst_o),
                    .async_level_i(attachment_quiesced_o[pod]),
                    .sync_level_o(attachment_quiesced_sync[pod]));
            npu_noc_level_sync u_attachment_error_sync (
                .clk_i(noc_clk_i), .rst_i(noc_rst_o),
                .async_level_i(attachment_protocol_error_o[pod]),
                .sync_level_o(attachment_error_sync[pod]));
        end
    endgenerate

    assign system_busy_o = noc_busy_o || (|pod_busy_sync) ||
        (|command_busy_sync) || (|attachment_busy_sync);
    assign system_quiesced_o = noc_quiesced_o && (&pod_quiesced_sync) &&
        (&attachment_quiesced_sync) && !system_busy_o;
    assign system_protocol_error_o = noc_protocol_error_o ||
        (|pod_error_sync) || (|command_error_sync) ||
        (|attachment_error_sync);

`ifndef SYNTHESIS
    initial begin
        assert (PODS == 8 && NOC_PORTS == 5)
            else $error("npu_2x4_pod_noc_system requires the fixed 2x4 Mesh");
        assert (DATA_LANES == 2)
            else $error("npu_2x4_pod_noc_system requires two data lanes");
        assert (CONTROL_FLIT_WIDTH ==
                npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH &&
                DATA_FLIT_WIDTH ==
                npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH)
            else $error("Pod attachment and NoC flit widths must match");
    end
`endif

endmodule

`default_nettype wire
