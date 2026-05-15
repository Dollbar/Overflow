`timescale 1ns/1ps
`default_nettype none

module npu_dma_hbm_boundary #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned HBM_LANES = 5,
    parameter int unsigned PARTITION_BITS = 3,
    parameter int unsigned PARTITION_ID = 0,
    parameter int unsigned ADDRESS_WIDTH = 35,
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned AGE_PROMOTION_CYCLES = 256,
    parameter int unsigned CHANNEL_INDEX_WIDTH =
        (CHANNELS <= 1) ? 1 : $clog2(CHANNELS),
    parameter int unsigned HBM_TAG_WIDTH =
        CHANNEL_INDEX_WIDTH + LOCAL_TAG_WIDTH,
    parameter int unsigned OUTSTANDING_COUNT_WIDTH =
        $clog2(CHANNELS * (1 << LOCAL_TAG_WIDTH) + 1)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic quiesce_i,

    input  logic [CHANNELS-1:0] channel_request_valid_i,
    output logic [CHANNELS-1:0] channel_request_ready_o,
    input  logic [CHANNELS-1:0] channel_request_write_i,
    input  logic [CHANNELS*ADDRESS_WIDTH-1:0] channel_request_address_i,
    input  logic [CHANNELS*DATA_BYTES*8-1:0] channel_request_write_data_i,
    input  logic [CHANNELS*DATA_BYTES-1:0] channel_request_byte_enable_i,
    input  logic [CHANNELS*2-1:0] channel_request_qos_i,
    output logic [CHANNELS*LOCAL_TAG_WIDTH-1:0]
        channel_request_local_tag_o,

    output logic [HBM_LANES-1:0] hbm_request_valid_o,
    input  logic [HBM_LANES-1:0] hbm_request_ready_i,
    output logic [HBM_LANES-1:0] hbm_request_write_o,
    output logic [HBM_LANES*PARTITION_BITS-1:0] hbm_request_partition_o,
    output logic [HBM_LANES*ADDRESS_WIDTH-1:0] hbm_request_address_o,
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

    output logic [CHANNELS-1:0] channel_response_valid_o,
    input  logic [CHANNELS-1:0] channel_response_ready_i,
    output logic [CHANNELS-1:0] channel_response_write_o,
    output logic [CHANNELS*LOCAL_TAG_WIDTH-1:0]
        channel_response_local_tag_o,
    output logic [CHANNELS*DATA_BYTES*8-1:0]
        channel_response_read_data_o,
    output logic [CHANNELS*2-1:0] channel_response_status_o,

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
    localparam int unsigned CAPTURE_GROUP_BITS = 32;
    localparam int unsigned DATA_CAPTURE_GROUPS =
        DATA_WIDTH / CAPTURE_GROUP_BITS;
    localparam int unsigned ENABLE_CAPTURE_GROUPS =
        DATA_BYTES / CAPTURE_GROUP_BITS;
    localparam int unsigned METADATA_CAPTURE_GROUP = 0;
    localparam int unsigned DATA_CAPTURE_GROUP_BASE = 1;
    localparam int unsigned ENABLE_CAPTURE_GROUP_BASE =
        DATA_CAPTURE_GROUP_BASE + DATA_CAPTURE_GROUPS;
    localparam int unsigned CAPTURE_CONTROL_COPIES =
        ENABLE_CAPTURE_GROUP_BASE + ENABLE_CAPTURE_GROUPS;
    localparam int unsigned TAGS_PER_CHANNEL = 1 << LOCAL_TAG_WIDTH;
    localparam int unsigned TAG_CREDIT_WIDTH = LOCAL_TAG_WIDTH + 1;
    localparam logic [1:0] QUIESCE_SETTLE_CYCLES = 2'd3;

    logic [CHANNELS-1:0] buffer_valid_q;
    logic [CHANNELS-1:0] buffer_write_q;
    logic [CHANNELS*ADDRESS_WIDTH-1:0] buffer_address_q;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] buffer_local_tag_q;
    logic [CHANNELS*DATA_WIDTH-1:0] buffer_write_data_q;
    logic [CHANNELS*DATA_BYTES-1:0] buffer_byte_enable_q;
    logic [CHANNELS*2-1:0] buffer_qos_q;
    logic [CHANNELS-1:0] buffer_accept;
    logic [CHANNELS-1:0] buffer_dequeue;
    logic [CHANNELS*CAPTURE_CONTROL_COPIES-1:0]
        buffer_accept_control;
    logic [CHANNELS-1:0] buffer_capture_accept;
    logic [CHANNELS-1:0] allocator_allocation_request;
    logic [CHANNELS*TAG_CREDIT_WIDTH-1:0] tag_credit_count_q;
    logic [CHANNELS-1:0] tag_credit_available;

    logic [CHANNELS-1:0] allocation_available;
    logic [CHANNELS-1:0] allocation_grant;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] allocation_local_tag;
    logic [CHANNELS-1:0] allocator_release_commit;
    logic [CHANNELS-1:0] allocator_release_known;
    logic [CHANNELS-1:0] allocation_failure;
    logic [CHANNELS-1:0] unknown_release;
    logic allocator_protocol_error;

    logic egress_busy;
    logic response_busy;
    logic response_protocol_error;

    logic [CHANNELS-1:0] response_delivered;
    logic [CHANNELS-1:0] response_retirement_commit_q;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] response_retirement_tag_q;
    logic [CHANNELS-1:0] tracker_allocation_permitted;
    logic [CHANNELS-1:0] tracker_retirement_known;
    logic [CHANNELS-1:0] duplicate_allocation;
    logic [CHANNELS-1:0] unknown_retirement;
    logic tracker_protocol_error;
    logic tracker_empty;
    logic tracker_full;
    logic boundary_consistency_error;
    logic boundary_consistency_error_q;
    logic [CHANNELS-1:0] allocator_allocation_request_q;
    logic [CHANNELS-1:0] allocation_grant_q;
    logic [CHANNELS-1:0] allocator_release_commit_q;
    logic [CHANNELS-1:0] allocator_release_known_q;
    logic [CHANNELS-1:0] buffer_dequeue_q;
    logic [CHANNELS-1:0] tracker_allocation_permitted_q;
    logic [CHANNELS-1:0] allocation_failure_q;
    logic [CHANNELS-1:0] unknown_release_q;
    logic [CHANNELS-1:0] duplicate_allocation_q;
    logic [CHANNELS-1:0] unknown_retirement_q;
    logic [1:0] quiesce_idle_count_q;

    assign channel_request_ready_o = tag_credit_available & ~buffer_valid_q &
                                     {CHANNELS{~quiesce_i}};
    assign buffer_accept = channel_request_valid_i & channel_request_ready_o;
    assign channel_request_local_tag_o = allocation_local_tag;
    assign response_delivered = channel_response_valid_o &
                                channel_response_ready_i;
    assign allocator_release_commit = response_retirement_commit_q &
                                      tracker_retirement_known;
    assign boundary_consistency_error =
        (|(allocator_allocation_request_q ^ allocation_grant_q)) ||
        (|(allocator_release_commit_q & ~allocator_release_known_q)) ||
        (|(buffer_dequeue_q & ~tracker_allocation_permitted_q)) ||
        (|(tag_credit_available ^ allocation_available)) ||
        (|allocation_failure_q) || (|unknown_release_q) ||
        (|duplicate_allocation_q) || (|unknown_retirement_q);

    generate
        for (genvar channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin : g_channel_buffer
            assign tag_credit_available[channel_index] =
                |tag_credit_count_q[
                    channel_index*TAG_CREDIT_WIDTH +: TAG_CREDIT_WIDTH];

            npu_dma_hbm_wide_control_buffer u_capture_accept_buffer (
                .data_i(buffer_accept[channel_index]),
                .data_o(buffer_capture_accept[channel_index])
            );

            npu_dma_hbm_wide_control_buffer u_allocator_accept_buffer (
                .data_i(buffer_accept[channel_index]),
                .data_o(allocator_allocation_request[channel_index])
            );

            for (genvar control_copy_index = 0;
                 control_copy_index < CAPTURE_CONTROL_COPIES;
                 control_copy_index = control_copy_index + 1) begin : g_capture_control
                npu_dma_hbm_control_buffer u_capture_control_buffer (
                    .data_i(buffer_capture_accept[channel_index]),
                    .data_o(buffer_accept_control[
                        channel_index*CAPTURE_CONTROL_COPIES +
                        control_copy_index])
                );
            end

            always_ff @(posedge clk_i) begin
                if (rst_i) begin
                    tag_credit_count_q[
                        channel_index*TAG_CREDIT_WIDTH +:
                        TAG_CREDIT_WIDTH] <=
                        TAG_CREDIT_WIDTH'(TAGS_PER_CHANNEL);
                end else begin
                    case ({allocator_release_commit[channel_index],
                           buffer_accept[channel_index]})
                        2'b01: tag_credit_count_q[
                            channel_index*TAG_CREDIT_WIDTH +:
                            TAG_CREDIT_WIDTH] <=
                            tag_credit_count_q[
                                channel_index*TAG_CREDIT_WIDTH +:
                                TAG_CREDIT_WIDTH] - 1'b1;
                        2'b10: tag_credit_count_q[
                            channel_index*TAG_CREDIT_WIDTH +:
                            TAG_CREDIT_WIDTH] <=
                            tag_credit_count_q[
                                channel_index*TAG_CREDIT_WIDTH +:
                                TAG_CREDIT_WIDTH] + 1'b1;
                        default: tag_credit_count_q[
                            channel_index*TAG_CREDIT_WIDTH +:
                            TAG_CREDIT_WIDTH] <=
                            tag_credit_count_q[
                                channel_index*TAG_CREDIT_WIDTH +:
                                TAG_CREDIT_WIDTH];
                    endcase
                end
            end

            always_ff @(posedge clk_i) begin
                if (rst_i) begin
                    buffer_valid_q[channel_index] <= 1'b0;
                end else if (buffer_accept_control[
                                 channel_index*CAPTURE_CONTROL_COPIES +
                                 METADATA_CAPTURE_GROUP]) begin
                    buffer_valid_q[channel_index] <= 1'b1;
                end else if (buffer_dequeue[channel_index]) begin
                    buffer_valid_q[channel_index] <= 1'b0;
                end
            end

            always_ff @(posedge clk_i) begin
                if (buffer_accept_control[
                        channel_index*CAPTURE_CONTROL_COPIES +
                        METADATA_CAPTURE_GROUP]) begin
                    buffer_write_q[channel_index] <=
                        channel_request_write_i[channel_index];
                    buffer_address_q[
                        channel_index*ADDRESS_WIDTH +: ADDRESS_WIDTH] <=
                        channel_request_address_i[
                            channel_index*ADDRESS_WIDTH +: ADDRESS_WIDTH];
                    buffer_local_tag_q[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] <=
                        allocation_local_tag[
                            channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH];
                    buffer_qos_q[channel_index*2 +: 2] <=
                        channel_request_qos_i[channel_index*2 +: 2];
                end
            end

            for (genvar data_group_index = 0;
                 data_group_index < DATA_CAPTURE_GROUPS;
                 data_group_index = data_group_index + 1) begin : g_data_capture
                always_ff @(posedge clk_i) begin
                    if (buffer_accept_control[
                            channel_index*CAPTURE_CONTROL_COPIES +
                            DATA_CAPTURE_GROUP_BASE + data_group_index]) begin
                        buffer_write_data_q[
                            channel_index*DATA_WIDTH +
                            data_group_index*CAPTURE_GROUP_BITS +:
                            CAPTURE_GROUP_BITS] <=
                            channel_request_write_data_i[
                                channel_index*DATA_WIDTH +
                                data_group_index*CAPTURE_GROUP_BITS +:
                                CAPTURE_GROUP_BITS];
                    end
                end
            end

            for (genvar enable_group_index = 0;
                 enable_group_index < ENABLE_CAPTURE_GROUPS;
                 enable_group_index = enable_group_index + 1) begin : g_enable_capture
                always_ff @(posedge clk_i) begin
                    if (buffer_accept_control[
                            channel_index*CAPTURE_CONTROL_COPIES +
                            ENABLE_CAPTURE_GROUP_BASE + enable_group_index]) begin
                        buffer_byte_enable_q[
                            channel_index*DATA_BYTES +
                            enable_group_index*CAPTURE_GROUP_BITS +:
                            CAPTURE_GROUP_BITS] <=
                            channel_request_byte_enable_i[
                                channel_index*DATA_BYTES +
                                enable_group_index*CAPTURE_GROUP_BITS +:
                                CAPTURE_GROUP_BITS];
                    end
                end
            end
        end
    endgenerate

    npu_dma_local_tag_allocator #(
        .CHANNELS(CHANNELS),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH)
    ) u_local_tag_allocator (
        .clk_i,
        .rst_i,
        .allocation_request_i(allocator_allocation_request),
        .allocation_available_o(allocation_available),
        .allocation_grant_o(allocation_grant),
        .allocation_local_tag_o(allocation_local_tag),
        .release_commit_i(allocator_release_commit),
        .release_local_tag_i(response_retirement_tag_q),
        .release_known_o(allocator_release_known),
        .allocation_failure_o(allocation_failure),
        .unknown_release_o(unknown_release),
        .protocol_error_o(allocator_protocol_error)
    );

    npu_dma_hbm_egress #(
        .CHANNELS(CHANNELS),
        .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS),
        .PARTITION_ID(PARTITION_ID),
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES),
        .AGE_PROMOTION_CYCLES(AGE_PROMOTION_CYCLES)
    ) u_egress (
        .clk_i,
        .rst_i,
        .request_valid_i(buffer_valid_q),
        .request_ready_o(buffer_dequeue),
        .request_write_i(buffer_write_q),
        .request_address_i(buffer_address_q),
        .request_local_tag_i(buffer_local_tag_q),
        .request_write_data_i(buffer_write_data_q),
        .request_byte_enable_i(buffer_byte_enable_q),
        .request_qos_i(buffer_qos_q),
        .hbm_request_valid_o,
        .hbm_request_ready_i,
        .hbm_request_write_o,
        .hbm_request_partition_o,
        .hbm_request_address_o,
        .hbm_request_tag_o,
        .hbm_request_write_data_o,
        .hbm_request_byte_enable_o,
        .busy_o(egress_busy),
        .accepted_beats_o,
        .issued_beats_o,
        .backpressure_cycles_o(request_backpressure_cycles_o)
    );

    npu_dma_hbm_response_router #(
        .CHANNELS(CHANNELS),
        .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS),
        .PARTITION_ID(PARTITION_ID),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES)
    ) u_response_router (
        .clk_i,
        .rst_i,
        .hbm_response_valid_i,
        .hbm_response_ready_o,
        .hbm_response_write_i,
        .hbm_response_partition_i,
        .hbm_response_tag_i,
        .hbm_response_read_data_i,
        .hbm_response_status_i,
        .channel_response_valid_o,
        .channel_response_ready_i,
        .channel_response_write_o,
        .channel_response_local_tag_o,
        .channel_response_read_data_o,
        .channel_response_status_o,
        .busy_o(response_busy),
        .protocol_error_o(response_protocol_error),
        .accepted_responses_o,
        .delivered_responses_o,
        .dropped_responses_o,
        .backpressure_cycles_o(response_backpressure_cycles_o)
    );

    npu_dma_hbm_tag_tracker #(
        .CHANNELS(CHANNELS),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH)
    ) u_tag_tracker (
        .clk_i,
        .rst_i,
        .allocation_commit_i(buffer_dequeue_q),
        .allocation_local_tag_i(buffer_local_tag_q),
        .allocation_permitted_o(tracker_allocation_permitted),
        .retirement_commit_i(response_retirement_commit_q),
        .retirement_local_tag_i(response_retirement_tag_q),
        .retirement_known_o(tracker_retirement_known),
        .duplicate_allocation_o(duplicate_allocation),
        .unknown_retirement_o(unknown_retirement),
        .protocol_error_o(tracker_protocol_error),
        .empty_o(tracker_empty),
        .full_o(tracker_full),
        .outstanding_count_o
    );

    npu_dma_hbm_status_monitor #(
        .CHANNELS(CHANNELS)
    ) u_status_monitor (
        .clk_i,
        .rst_i,
        .response_commit_i(response_delivered),
        .response_status_i(channel_response_status_o),
        .ok_responses_o,
        .corrected_responses_o,
        .uncorrectable_responses_o,
        .data_error_responses_o,
        .corrected_seen_o,
        .uncorrectable_seen_o,
        .data_error_seen_o
    );

    assign busy_o = (|buffer_valid_q) || egress_busy || response_busy ||
                    (|response_retirement_commit_q) || !tracker_empty;
    assign quiesced_o = quiesce_i &&
                        (quiesce_idle_count_q == QUIESCE_SETTLE_CYCLES);
    assign outstanding_full_o = tracker_full;
    assign protocol_error_o = allocator_protocol_error ||
                              response_protocol_error ||
                              tracker_protocol_error ||
                              boundary_consistency_error_q;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            response_retirement_commit_q <= '0;
            response_retirement_tag_q <= '0;
        end else begin
            response_retirement_commit_q <= response_delivered;
            for (int unsigned channel_index = 0;
                 channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (response_delivered[channel_index]) begin
                    response_retirement_tag_q[
                        channel_index*LOCAL_TAG_WIDTH +:
                        LOCAL_TAG_WIDTH] <= channel_response_local_tag_o[
                            channel_index*LOCAL_TAG_WIDTH +:
                            LOCAL_TAG_WIDTH];
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            quiesce_idle_count_q <= '0;
        end else if (!quiesce_i || busy_o) begin
            quiesce_idle_count_q <= '0;
        end else if (quiesce_idle_count_q != QUIESCE_SETTLE_CYCLES) begin
            quiesce_idle_count_q <= quiesce_idle_count_q + 2'd1;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            outstanding_high_watermark_o <= '0;
        end else if (outstanding_count_o >
                     outstanding_high_watermark_o) begin
            outstanding_high_watermark_o <= outstanding_count_o;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            boundary_consistency_error_q <= 1'b0;
            allocator_allocation_request_q <= '0;
            allocation_grant_q <= '0;
            allocator_release_commit_q <= '0;
            allocator_release_known_q <= '0;
            buffer_dequeue_q <= '0;
            tracker_allocation_permitted_q <= '0;
            allocation_failure_q <= '0;
            unknown_release_q <= '0;
            duplicate_allocation_q <= '0;
            unknown_retirement_q <= '0;
        end else if (boundary_consistency_error) begin
            boundary_consistency_error_q <= 1'b1;
            allocator_allocation_request_q <= allocator_allocation_request;
            allocation_grant_q <= allocation_grant;
            allocator_release_commit_q <= allocator_release_commit;
            allocator_release_known_q <= allocator_release_known;
            buffer_dequeue_q <= buffer_dequeue;
            tracker_allocation_permitted_q <= tracker_allocation_permitted;
            allocation_failure_q <= allocation_failure;
            unknown_release_q <= unknown_release;
            duplicate_allocation_q <= duplicate_allocation;
            unknown_retirement_q <= unknown_retirement;
        end else begin
            allocator_allocation_request_q <= allocator_allocation_request;
            allocation_grant_q <= allocation_grant;
            allocator_release_commit_q <= allocator_release_commit;
            allocator_release_known_q <= allocator_release_known;
            buffer_dequeue_q <= buffer_dequeue;
            tracker_allocation_permitted_q <= tracker_allocation_permitted;
            allocation_failure_q <= allocation_failure;
            unknown_release_q <= unknown_release;
            duplicate_allocation_q <= duplicate_allocation;
            unknown_retirement_q <= unknown_retirement;
        end
    end

    initial begin
        if ((CHANNELS != 16) || (HBM_LANES != 5) ||
            (PARTITION_BITS != 3) || (ADDRESS_WIDTH != 35) ||
            (LOCAL_TAG_WIDTH != 8) || (DATA_BYTES != 128) ||
            (HBM_TAG_WIDTH != 12) ||
            (OUTSTANDING_COUNT_WIDTH != 13) ||
            ((DATA_WIDTH % CAPTURE_GROUP_BITS) != 0) ||
            ((DATA_BYTES % CAPTURE_GROUP_BITS) != 0)) begin
            $error("NPU DMA HBM boundary violates the v0.1 beat contract");
        end
    end
endmodule

`default_nettype wire
