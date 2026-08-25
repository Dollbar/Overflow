`timescale 1ns/1ps
`default_nettype none

module npu_dma_pod #(
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
    output logic data_error_seen_o,
    output logic [63:0] sram_accepted_reads_o,
    output logic [63:0] sram_accepted_writes_o,
    output logic [63:0] sram_read_conflict_cycles_o,
    output logic [63:0] sram_write_conflict_cycles_o
);

    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned SRAM_ADDRESS_WIDTH =
        npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH;

    logic [CHANNELS-1:0] sram_read_request_valid;
    logic [CHANNELS-1:0] sram_read_request_ready;
    logic [CHANNELS*SRAM_ADDRESS_WIDTH-1:0] sram_read_request_address;
    logic [CHANNELS-1:0] sram_read_response_valid;
    logic [CHANNELS-1:0] sram_read_response_ready;
    logic [CHANNELS*DATA_WIDTH-1:0] sram_read_response_data;
    logic [CHANNELS-1:0] sram_write_valid;
    logic [CHANNELS-1:0] sram_write_ready;
    logic [CHANNELS*SRAM_ADDRESS_WIDTH-1:0] sram_write_address;
    logic [CHANNELS*DATA_WIDTH-1:0] sram_write_data;
    logic [CHANNELS*DATA_BYTES-1:0] sram_write_byte_enable;
    logic engine_busy;
    logic engine_quiesced;
    logic engine_protocol_error;
    logic sram_busy;
    logic sram_protocol_error;

    assign busy_o = engine_busy || sram_busy;
    assign quiesced_o = engine_quiesced && !sram_busy;
    assign protocol_error_o = engine_protocol_error || sram_protocol_error;

    npu_dma_engine #(
        .CHANNELS(CHANNELS),
        .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS),
        .PARTITION_ID(PARTITION_ID),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES),
        .COMMAND_CONTEXTS_PER_CHANNEL(COMMAND_CONTEXTS_PER_CHANNEL)
    ) u_engine (
        .clk_i,
        .rst_i,
        .clear_i,
        .quiesce_i,
        .command_valid_i,
        .command_ready_o,
        .command_i,
        .command_level_o,
        .channel_outstanding_o,
        .completion_valid_o,
        .completion_ready_i,
        .completion_o,
        .sram_read_request_valid_o(sram_read_request_valid),
        .sram_read_request_ready_i(sram_read_request_ready),
        .sram_read_request_address_o(sram_read_request_address),
        .sram_read_response_valid_i(sram_read_response_valid),
        .sram_read_response_ready_o(sram_read_response_ready),
        .sram_read_response_data_i(sram_read_response_data),
        .sram_write_valid_o(sram_write_valid),
        .sram_write_ready_i(sram_write_ready),
        .sram_write_address_o(sram_write_address),
        .sram_write_data_o(sram_write_data),
        .sram_write_byte_enable_o(sram_write_byte_enable),
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
        .busy_o(engine_busy),
        .quiesced_o(engine_quiesced),
        .protocol_error_o(engine_protocol_error),
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

    npu_pod_shared_sram #(
        .CLIENTS(CHANNELS),
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
        .write_valid_i(sram_write_valid),
        .write_ready_o(sram_write_ready),
        .write_address_i(sram_write_address),
        .write_data_i(sram_write_data),
        .write_byte_enable_i(sram_write_byte_enable),
        .busy_o(sram_busy),
        .protocol_error_o(sram_protocol_error),
        .accepted_reads_o(sram_accepted_reads_o),
        .accepted_writes_o(sram_accepted_writes_o),
        .read_conflict_cycles_o(sram_read_conflict_cycles_o),
        .write_conflict_cycles_o(sram_write_conflict_cycles_o)
    );

    initial begin
        if ((CHANNELS != 16) || (DATA_BYTES != 128)) begin
            $error("npu_dma_pod violates the v0.1 shared SRAM geometry");
        end
    end

endmodule

`default_nettype wire
