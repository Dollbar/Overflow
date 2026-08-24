`timescale 1ns/1ps
`default_nettype none

module npu_dma_hbm_egress #(
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
        CHANNEL_INDEX_WIDTH + LOCAL_TAG_WIDTH
) (
    input  logic clk_i,
    input  logic rst_i,

    input  logic [CHANNELS-1:0] request_valid_i,
    output logic [CHANNELS-1:0] request_ready_o,
    input  logic [CHANNELS-1:0] request_write_i,
    input  logic [CHANNELS*ADDRESS_WIDTH-1:0] request_address_i,
    input  logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] request_local_tag_i,
    input  logic [CHANNELS*DATA_BYTES*8-1:0] request_write_data_i,
    input  logic [CHANNELS*DATA_BYTES-1:0] request_byte_enable_i,
    input  logic [CHANNELS*2-1:0] request_qos_i,

    output logic [HBM_LANES-1:0] hbm_request_valid_o,
    input  logic [HBM_LANES-1:0] hbm_request_ready_i,
    output logic [HBM_LANES-1:0] hbm_request_write_o,
    output logic [HBM_LANES*PARTITION_BITS-1:0] hbm_request_partition_o,
    output logic [HBM_LANES*ADDRESS_WIDTH-1:0] hbm_request_address_o,
    output logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_request_tag_o,
    output logic [HBM_LANES*DATA_BYTES*8-1:0] hbm_request_write_data_o,
    output logic [HBM_LANES*DATA_BYTES-1:0] hbm_request_byte_enable_o,

    output logic busy_o,
    output logic [63:0] accepted_beats_o,
    output logic [63:0] issued_beats_o,
    output logic [63:0] backpressure_cycles_o
);
    localparam int unsigned AGE_MAX = 3 * AGE_PROMOTION_CYCLES;
    localparam int unsigned AGE_WIDTH =
        (AGE_MAX <= 1) ? 1 : $clog2(AGE_MAX + 1);
    localparam int unsigned ACCEPT_COUNT_WIDTH =
        (HBM_LANES <= 1) ? 1 : $clog2(HBM_LANES + 1);

    logic [HBM_LANES-1:0] slot_valid_q;
    logic [HBM_LANES-1:0] slot_write_q;
    logic [HBM_LANES*ADDRESS_WIDTH-1:0] slot_address_q;
    logic [HBM_LANES*HBM_TAG_WIDTH-1:0] slot_tag_q;
    logic [HBM_LANES*DATA_BYTES*8-1:0] slot_write_data_q;
    logic [HBM_LANES*DATA_BYTES-1:0] slot_byte_enable_q;

    logic [CHANNEL_INDEX_WIDTH-1:0] round_robin_q;
    logic [CHANNEL_INDEX_WIDTH-1:0] round_robin_d;
    logic [AGE_WIDTH-1:0] request_age_q [0:CHANNELS-1];

    logic [CHANNELS-1:0] selected_channel;
    logic [HBM_LANES-1:0] fill_slot;
    logic [HBM_LANES*CHANNEL_INDEX_WIDTH-1:0] fill_channel;
    logic [ACCEPT_COUNT_WIDTH-1:0] accepted_increment;
    logic [ACCEPT_COUNT_WIDTH-1:0] issued_increment;

    always_comb begin
        integer lane_index;
        integer channel_offset;
        integer candidate_index;
        integer candidate_priority;
        integer best_priority;
        integer best_channel;
        integer last_selected_channel;
        logic best_found;
        logic selected_any;

        request_ready_o = '0;
        selected_channel = '0;
        fill_slot = '0;
        fill_channel = '0;
        round_robin_d = round_robin_q;
        best_found = 1'b0;
        selected_any = 1'b0;
        lane_index = 0;
        channel_offset = 0;
        candidate_index = 0;
        candidate_priority = 0;
        best_priority = -1;
        best_channel = 0;
        last_selected_channel = 0;

        for (lane_index = 0; lane_index < HBM_LANES; lane_index = lane_index + 1) begin
            if (!slot_valid_q[lane_index] || hbm_request_ready_i[lane_index]) begin
                best_found = 1'b0;
                best_priority = -1;
                best_channel = 0;

                for (channel_offset = 0; channel_offset < CHANNELS;
                     channel_offset = channel_offset + 1) begin
                    candidate_index = channel_offset +
                        {{(32-CHANNEL_INDEX_WIDTH){1'b0}}, round_robin_q};
                    if (candidate_index >= CHANNELS) begin
                        candidate_index = candidate_index - CHANNELS;
                    end

                    candidate_priority = {30'd0,
                        request_qos_i[candidate_index*2 +: 2]};
                    if ({{(32-AGE_WIDTH){1'b0}}, request_age_q[candidate_index]} >=
                        3*AGE_PROMOTION_CYCLES) begin
                        candidate_priority = candidate_priority + 3;
                    end else if ({{(32-AGE_WIDTH){1'b0}},
                                  request_age_q[candidate_index]} >=
                                 2*AGE_PROMOTION_CYCLES) begin
                        candidate_priority = candidate_priority + 2;
                    end else if ({{(32-AGE_WIDTH){1'b0}},
                                  request_age_q[candidate_index]} >=
                                 AGE_PROMOTION_CYCLES) begin
                        candidate_priority = candidate_priority + 1;
                    end
                    if (candidate_priority > 3) begin
                        candidate_priority = 3;
                    end

                    if (request_valid_i[candidate_index] &&
                        !selected_channel[candidate_index] &&
                        (!best_found || (candidate_priority > best_priority))) begin
                        best_found = 1'b1;
                        best_priority = candidate_priority;
                        best_channel = candidate_index;
                    end
                end

                if (best_found) begin
                    fill_slot[lane_index] = 1'b1;
                    fill_channel[lane_index*CHANNEL_INDEX_WIDTH +:
                                 CHANNEL_INDEX_WIDTH] =
                        best_channel[CHANNEL_INDEX_WIDTH-1:0];
                    selected_channel[best_channel] = 1'b1;
                    request_ready_o[best_channel] = 1'b1;
                    selected_any = 1'b1;
                    last_selected_channel = best_channel;
                end
            end
        end

        if (selected_any) begin
            if (last_selected_channel == CHANNELS-1) begin
                round_robin_d = '0;
            end else begin
                round_robin_d =
                    last_selected_channel[CHANNEL_INDEX_WIDTH-1:0] + 1'b1;
            end
        end
    end

    always_comb begin
        integer lane_index;

        accepted_increment = '0;
        issued_increment = '0;
        for (lane_index = 0; lane_index < HBM_LANES; lane_index = lane_index + 1) begin
            if (fill_slot[lane_index]) begin
                accepted_increment = accepted_increment + 1'b1;
            end
            if (slot_valid_q[lane_index] && hbm_request_ready_i[lane_index]) begin
                issued_increment = issued_increment + 1'b1;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            slot_valid_q <= '0;
            round_robin_q <= '0;
            accepted_beats_o <= 64'd0;
            issued_beats_o <= 64'd0;
            backpressure_cycles_o <= 64'd0;
            for (int channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                request_age_q[channel_index] <= '0;
            end
        end else begin
            round_robin_q <= round_robin_d;
            accepted_beats_o <= accepted_beats_o +
                {{(64-ACCEPT_COUNT_WIDTH){1'b0}}, accepted_increment};
            issued_beats_o <= issued_beats_o +
                {{(64-ACCEPT_COUNT_WIDTH){1'b0}}, issued_increment};
            if (|(request_valid_i & ~request_ready_o)) begin
                backpressure_cycles_o <= backpressure_cycles_o + 64'd1;
            end

            for (int channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (!request_valid_i[channel_index] || request_ready_o[channel_index]) begin
                    request_age_q[channel_index] <= '0;
                end else if ({{(32-AGE_WIDTH){1'b0}},
                              request_age_q[channel_index]} < AGE_MAX) begin
                    request_age_q[channel_index] <= request_age_q[channel_index] + 1'b1;
                end
            end

            for (int lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin
                if (fill_slot[lane_index]) begin
                    slot_valid_q[lane_index] <= 1'b1;
                    slot_write_q[lane_index] <=
                        request_write_i[fill_channel[
                            lane_index*CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH]];
                    slot_address_q[lane_index*ADDRESS_WIDTH +: ADDRESS_WIDTH] <=
                        request_address_i[fill_channel[
                            lane_index*CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH]*ADDRESS_WIDTH +:
                            ADDRESS_WIDTH];
                    slot_tag_q[lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH] <= {
                        fill_channel[lane_index*CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH],
                        request_local_tag_i[fill_channel[
                            lane_index*CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH]*LOCAL_TAG_WIDTH +:
                            LOCAL_TAG_WIDTH]
                    };
                    slot_write_data_q[lane_index*DATA_BYTES*8 +: DATA_BYTES*8] <=
                        request_write_data_i[fill_channel[
                            lane_index*CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH]*DATA_BYTES*8 +:
                            DATA_BYTES*8];
                    slot_byte_enable_q[lane_index*DATA_BYTES +: DATA_BYTES] <=
                        request_byte_enable_i[fill_channel[
                            lane_index*CHANNEL_INDEX_WIDTH +: CHANNEL_INDEX_WIDTH]*DATA_BYTES +:
                            DATA_BYTES];
                end else if (slot_valid_q[lane_index] &&
                             hbm_request_ready_i[lane_index]) begin
                    slot_valid_q[lane_index] <= 1'b0;
                end
            end
        end
    end

    always_comb begin
        integer lane_index;

        hbm_request_valid_o = slot_valid_q;
        hbm_request_write_o = slot_write_q;
        hbm_request_address_o = slot_address_q;
        hbm_request_tag_o = slot_tag_q;
        hbm_request_write_data_o = slot_write_data_q;
        hbm_request_byte_enable_o = slot_byte_enable_q;
        hbm_request_partition_o = '0;
        for (lane_index = 0; lane_index < HBM_LANES; lane_index = lane_index + 1) begin
            hbm_request_partition_o[lane_index*PARTITION_BITS +: PARTITION_BITS] =
                PARTITION_ID[PARTITION_BITS-1:0];
        end
        busy_o = |slot_valid_q;
    end

    initial begin
        if ((CHANNELS < 1) || (HBM_LANES < 1) ||
            (HBM_LANES > CHANNELS) || (CHANNELS > (1 << CHANNEL_INDEX_WIDTH))) begin
            $error("NPU DMA HBM channel/lane geometry is invalid");
        end
        if ((PARTITION_BITS < 1) || (PARTITION_ID >= (1 << PARTITION_BITS)) ||
            (ADDRESS_WIDTH < 7) || (LOCAL_TAG_WIDTH < 1) ||
            (DATA_BYTES != 128) || (AGE_PROMOTION_CYCLES < 1)) begin
            $error("NPU DMA HBM interface parameters violate the v0.1 contract");
        end
        if (HBM_TAG_WIDTH != CHANNEL_INDEX_WIDTH + LOCAL_TAG_WIDTH) begin
            $error("NPU DMA HBM tag width must contain channel and local tag fields");
        end
    end
endmodule

`default_nettype wire
