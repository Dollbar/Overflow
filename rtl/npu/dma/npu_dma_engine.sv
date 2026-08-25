`timescale 1ns/1ps
`default_nettype none

module npu_dma_engine #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned HBM_LANES = 5,
    parameter int unsigned PARTITION_BITS = 3,
    parameter int unsigned PARTITION_ID = 0,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned COMMAND_CONTEXTS_PER_CHANNEL = 4,
    parameter int unsigned COMMAND_LEVEL_WIDTH =
        $clog2(COMMAND_CONTEXTS_PER_CHANNEL + 1),
    parameter int unsigned HBM_TAG_WIDTH =
        $clog2(CHANNELS) + LOCAL_TAG_WIDTH,
    parameter int unsigned OUTSTANDING_COUNT_WIDTH =
        $clog2(CHANNELS * (1 << LOCAL_TAG_WIDTH) + 1)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic [CHANNELS-1:0] command_valid_i,
    output logic [CHANNELS-1:0] command_ready_o,
    input  logic [CHANNELS*npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0]
                 command_i,
    output logic [CHANNELS*COMMAND_LEVEL_WIDTH-1:0] command_level_o,
    output logic [CHANNELS*(LOCAL_TAG_WIDTH+1)-1:0]
                 channel_outstanding_o,

    output logic [CHANNELS-1:0] completion_valid_o,
    input  logic [CHANNELS-1:0] completion_ready_i,
    output logic [CHANNELS*npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH-1:0]
                 completion_o,

    output logic [CHANNELS-1:0] sram_read_request_valid_o,
    input  logic [CHANNELS-1:0] sram_read_request_ready_i,
    output logic [CHANNELS*npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH-1:0]
                 sram_read_request_address_o,
    input  logic [CHANNELS-1:0] sram_read_response_valid_i,
    output logic [CHANNELS-1:0] sram_read_response_ready_o,
    input  logic [CHANNELS*DATA_BYTES*8-1:0] sram_read_response_data_i,
    output logic [CHANNELS-1:0] sram_write_valid_o,
    input  logic [CHANNELS-1:0] sram_write_ready_i,
    output logic [CHANNELS*npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH-1:0]
                 sram_write_address_o,
    output logic [CHANNELS*DATA_BYTES*8-1:0] sram_write_data_o,
    output logic [CHANNELS*DATA_BYTES-1:0] sram_write_byte_enable_o,

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
    input  logic [HBM_LANES*PARTITION_BITS-1:0] hbm_response_partition_i,
    input  logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_response_tag_i,
    input  logic [HBM_LANES*DATA_BYTES*8-1:0] hbm_response_read_data_i,
    input  logic [HBM_LANES*2-1:0] hbm_response_status_i,

    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o,
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
    output logic data_error_seen_o
);

    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned COMMAND_WIDTH = npu_dma_pkg::NPU_DMA_COMMAND_WIDTH;
    localparam int unsigned COMPLETION_WIDTH =
        npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH;
    localparam int unsigned SRAM_ADDRESS_WIDTH =
        npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH;

    logic local_reset;
    logic [CHANNELS-1:0] queue_input_ready;
    logic [CHANNELS-1:0] queue_output_valid;
    logic [CHANNELS-1:0] queue_output_ready;
    logic [CHANNELS*COMMAND_WIDTH-1:0] queue_output_data;
    logic [CHANNELS*COMMAND_LEVEL_WIDTH-1:0] queue_level;
    logic [CHANNELS-1:0] command_slot_available;
    logic [CHANNELS-1:0] mover_busy;
    logic [CHANNELS-1:0] mover_protocol_error;

    logic [CHANNELS-1:0] channel_request_valid;
    logic [CHANNELS-1:0] channel_request_ready;
    logic [CHANNELS-1:0] channel_request_write;
    logic [CHANNELS*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
        channel_request_address;
    logic [CHANNELS*DATA_WIDTH-1:0] channel_request_write_data;
    logic [CHANNELS*DATA_BYTES-1:0] channel_request_byte_enable;
    logic [CHANNELS*2-1:0] channel_request_qos;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] channel_request_local_tag;
    logic [CHANNELS-1:0] channel_response_valid;
    logic [CHANNELS-1:0] channel_response_ready;
    logic [CHANNELS-1:0] channel_response_write;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] channel_response_local_tag;
    logic [CHANNELS*DATA_WIDTH-1:0] channel_response_read_data;
    logic [CHANNELS*2-1:0] channel_response_status;
    logic boundary_busy;
    logic boundary_quiesce;
    logic boundary_quiesced;
    logic boundary_protocol_error;
    logic queues_empty;
    logic movers_idle;

    assign local_reset = rst_i || clear_i;
    assign queues_empty = queue_level == '0;
    assign movers_idle = mover_busy == '0;
    assign boundary_quiesce = quiesce_i && queues_empty && movers_idle;
    assign quiesced_o = quiesce_i && queues_empty && movers_idle &&
                        boundary_quiesced;
    assign busy_o = !queues_empty || !movers_idle || boundary_busy;
    assign protocol_error_o = boundary_protocol_error ||
                              (|mover_protocol_error);
    generate
        for (genvar channel = 0; channel < CHANNELS;
             channel = channel + 1) begin : g_channel
            logic [COMMAND_LEVEL_WIDTH-1:0] total_context_level;

            assign total_context_level =
                queue_level[channel*COMMAND_LEVEL_WIDTH +:
                            COMMAND_LEVEL_WIDTH] +
                COMMAND_LEVEL_WIDTH'(mover_busy[channel]);
            assign command_slot_available[channel] =
                total_context_level <
                COMMAND_LEVEL_WIDTH'(COMMAND_CONTEXTS_PER_CHANNEL);
            assign command_level_o[channel*COMMAND_LEVEL_WIDTH +:
                                   COMMAND_LEVEL_WIDTH] = total_context_level;
            assign command_ready_o[channel] = !quiesce_i &&
                command_slot_available[channel] && queue_input_ready[channel];

            npu_dma_command_queue #(
                .WIDTH(COMMAND_WIDTH),
                .DEPTH(COMMAND_CONTEXTS_PER_CHANNEL)
            ) u_command_queue (
                .clk_i,
                .rst_i,
                .clear_i,
                .input_valid_i(command_valid_i[channel] &&
                    command_slot_available[channel] && !quiesce_i),
                .input_ready_o(queue_input_ready[channel]),
                .input_data_i(command_i[channel*COMMAND_WIDTH +:
                                       COMMAND_WIDTH]),
                .output_valid_o(queue_output_valid[channel]),
                .output_ready_i(queue_output_ready[channel]),
                .output_data_o(queue_output_data[
                    channel*COMMAND_WIDTH +: COMMAND_WIDTH]),
                .level_o(queue_level[channel*COMMAND_LEVEL_WIDTH +:
                                    COMMAND_LEVEL_WIDTH])
            );

            npu_dma_channel_mover #(
                .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
                .DATA_BYTES(DATA_BYTES)
            ) u_mover (
                .clk_i,
                .rst_i,
                .clear_i,
                .command_valid_i(queue_output_valid[channel]),
                .command_ready_o(queue_output_ready[channel]),
                .command_i(queue_output_data[
                    channel*COMMAND_WIDTH +: COMMAND_WIDTH]),
                .hbm_request_valid_o(channel_request_valid[channel]),
                .hbm_request_ready_i(channel_request_ready[channel]),
                .hbm_request_write_o(channel_request_write[channel]),
                .hbm_request_address_o(channel_request_address[
                    channel*npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH +:
                    npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH]),
                .hbm_request_write_data_o(channel_request_write_data[
                    channel*DATA_WIDTH +: DATA_WIDTH]),
                .hbm_request_byte_enable_o(channel_request_byte_enable[
                    channel*DATA_BYTES +: DATA_BYTES]),
                .hbm_request_qos_o(channel_request_qos[
                    channel*2 +: 2]),
                .hbm_request_local_tag_i(channel_request_local_tag[
                    channel*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]),
                .hbm_response_valid_i(channel_response_valid[channel]),
                .hbm_response_ready_o(channel_response_ready[channel]),
                .hbm_response_write_i(channel_response_write[channel]),
                .hbm_response_local_tag_i(channel_response_local_tag[
                    channel*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]),
                .hbm_response_read_data_i(channel_response_read_data[
                    channel*DATA_WIDTH +: DATA_WIDTH]),
                .hbm_response_status_i(channel_response_status[
                    channel*2 +: 2]),
                .sram_read_request_valid_o(
                    sram_read_request_valid_o[channel]),
                .sram_read_request_ready_i(
                    sram_read_request_ready_i[channel]),
                .sram_read_request_address_o(sram_read_request_address_o[
                    channel*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH]),
                .sram_read_response_valid_i(
                    sram_read_response_valid_i[channel]),
                .sram_read_response_ready_o(
                    sram_read_response_ready_o[channel]),
                .sram_read_response_data_i(sram_read_response_data_i[
                    channel*DATA_WIDTH +: DATA_WIDTH]),
                .sram_write_valid_o(sram_write_valid_o[channel]),
                .sram_write_ready_i(sram_write_ready_i[channel]),
                .sram_write_address_o(sram_write_address_o[
                    channel*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH]),
                .sram_write_data_o(sram_write_data_o[
                    channel*DATA_WIDTH +: DATA_WIDTH]),
                .sram_write_byte_enable_o(sram_write_byte_enable_o[
                    channel*DATA_BYTES +: DATA_BYTES]),
                .completion_valid_o(completion_valid_o[channel]),
                .completion_ready_i(completion_ready_i[channel]),
                .completion_o(completion_o[
                    channel*COMPLETION_WIDTH +: COMPLETION_WIDTH]),
                .busy_o(mover_busy[channel]),
                .outstanding_o(channel_outstanding_o[
                    channel*(LOCAL_TAG_WIDTH+1) +: LOCAL_TAG_WIDTH+1]),
                .protocol_error_o(mover_protocol_error[channel])
            );
        end
    endgenerate

    npu_dma_hbm_boundary #(
        .CHANNELS(CHANNELS),
        .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS),
        .PARTITION_ID(PARTITION_ID),
        .ADDRESS_WIDTH(npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES)
    ) u_hbm_boundary (
        .clk_i,
        .rst_i(local_reset),
        .quiesce_i(boundary_quiesce),
        .channel_request_valid_i(channel_request_valid),
        .channel_request_ready_o(channel_request_ready),
        .channel_request_write_i(channel_request_write),
        .channel_request_address_i(channel_request_address),
        .channel_request_write_data_i(channel_request_write_data),
        .channel_request_byte_enable_i(channel_request_byte_enable),
        .channel_request_qos_i(channel_request_qos),
        .channel_request_local_tag_o(channel_request_local_tag),
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
        .channel_response_valid_o(channel_response_valid),
        .channel_response_ready_i(channel_response_ready),
        .channel_response_write_o(channel_response_write),
        .channel_response_local_tag_o(channel_response_local_tag),
        .channel_response_read_data_o(channel_response_read_data),
        .channel_response_status_o(channel_response_status),
        .busy_o(boundary_busy),
        .quiesced_o(boundary_quiesced),
        .protocol_error_o(boundary_protocol_error),
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

    initial begin
        if ((CHANNELS != 16) || (HBM_LANES != 5) ||
            (PARTITION_BITS != 3) || (LOCAL_TAG_WIDTH != 8) ||
            (DATA_BYTES != 128) ||
            (COMMAND_CONTEXTS_PER_CHANNEL != 4)) begin
            $error("npu_dma_engine violates DMA v0.1 geometry");
        end
    end

endmodule

`default_nettype wire
