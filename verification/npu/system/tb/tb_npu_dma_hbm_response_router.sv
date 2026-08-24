`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_hbm_response_router;
    localparam int unsigned CHANNELS = 16;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned PARTITION_BITS = 3;
    localparam int unsigned LOCAL_TAG_WIDTH = 8;
    localparam int unsigned DATA_BYTES = 128;
    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned CHANNEL_INDEX_WIDTH = $clog2(CHANNELS);
    localparam int unsigned HBM_TAG_WIDTH = CHANNEL_INDEX_WIDTH + LOCAL_TAG_WIDTH;
    localparam int unsigned QUEUE_DEPTH = 2048;

    logic clk_i;
    logic rst_i;
    logic [HBM_LANES-1:0] hbm_response_valid_i;
    logic [HBM_LANES-1:0] hbm_response_ready_o;
    logic [HBM_LANES-1:0] hbm_response_write_i;
    logic [HBM_LANES*PARTITION_BITS-1:0] hbm_response_partition_i;
    logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_response_tag_i;
    logic [HBM_LANES*DATA_WIDTH-1:0] hbm_response_read_data_i;
    logic [HBM_LANES*2-1:0] hbm_response_status_i;
    logic [CHANNELS-1:0] channel_response_valid_o;
    logic [CHANNELS-1:0] channel_response_ready_i;
    logic [CHANNELS-1:0] channel_response_write_o;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] channel_response_local_tag_o;
    logic [CHANNELS*DATA_WIDTH-1:0] channel_response_read_data_o;
    logic [CHANNELS*2-1:0] channel_response_status_o;
    logic busy_o;
    logic protocol_error_o;
    logic [63:0] accepted_responses_o;
    logic [63:0] delivered_responses_o;
    logic [63:0] dropped_responses_o;
    logic [63:0] backpressure_cycles_o;

    logic expected_write [0:CHANNELS-1][0:QUEUE_DEPTH-1];
    logic [LOCAL_TAG_WIDTH-1:0] expected_local_tag [0:CHANNELS-1][0:QUEUE_DEPTH-1];
    logic [DATA_WIDTH-1:0] expected_data [0:CHANNELS-1][0:QUEUE_DEPTH-1];
    logic [1:0] expected_status [0:CHANNELS-1][0:QUEUE_DEPTH-1];
    integer queue_head [0:CHANNELS-1];
    integer queue_tail [0:CHANNELS-1];
    logic [LOCAL_TAG_WIDTH-1:0] next_local_tag [0:CHANNELS-1];
    logic [HBM_LANES-1:0] source_advance;

    logic [CHANNELS-1:0] held_valid;
    logic [CHANNELS-1:0] held_write;
    logic [LOCAL_TAG_WIDTH-1:0] held_local_tag [0:CHANNELS-1];
    logic [DATA_WIDTH-1:0] held_data [0:CHANNELS-1];
    logic [1:0] held_status [0:CHANNELS-1];

    logic [31:0] lfsr_q;
    integer accepted_valid_count;
    integer delivered_count;
    integer malformed_count;

    npu_dma_hbm_response_router #(
        .CHANNELS(CHANNELS),
        .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS),
        .PARTITION_ID(3),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES)
    ) dut (
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
        .busy_o,
        .protocol_error_o,
        .accepted_responses_o,
        .delivered_responses_o,
        .dropped_responses_o,
        .backpressure_cycles_o
    );

    always #0.5 clk_i = ~clk_i;

    task automatic present_response(
        input integer lane_index,
        input integer channel_index,
        input logic [PARTITION_BITS-1:0] partition
    );
        logic [HBM_TAG_WIDTH-1:0] full_tag;
        integer byte_index;
        begin
            full_tag = {
                CHANNEL_INDEX_WIDTH'(channel_index),
                next_local_tag[channel_index]
            };
            hbm_response_valid_i[lane_index] = 1'b1;
            hbm_response_write_i[lane_index] = next_local_tag[channel_index][0];
            hbm_response_partition_i[
                lane_index*PARTITION_BITS +: PARTITION_BITS] = partition;
            hbm_response_tag_i[lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH] = full_tag;
            hbm_response_status_i[lane_index*2 +: 2] =
                next_local_tag[channel_index][1:0];
            for (byte_index = 0; byte_index < DATA_BYTES;
                 byte_index = byte_index + 1) begin
                hbm_response_read_data_i[
                    lane_index*DATA_WIDTH + byte_index*8 +: 8] =
                    next_local_tag[channel_index] ^
                    LOCAL_TAG_WIDTH'(byte_index) ^
                    LOCAL_TAG_WIDTH'(channel_index*13);
            end
            next_local_tag[channel_index] = next_local_tag[channel_index] + 1'b1;
        end
    endtask

    task automatic monitor_cycle;
        integer lane_index;
        integer channel_index;
        logic [CHANNEL_INDEX_WIDTH-1:0] observed_channel;
        logic [LOCAL_TAG_WIDTH-1:0] observed_local_tag;
        begin
            @(posedge clk_i);
            source_advance = '0;

            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (held_valid[channel_index]) begin
                    if (!channel_response_valid_o[channel_index] ||
                        channel_response_write_o[channel_index] !==
                            held_write[channel_index] ||
                        channel_response_local_tag_o[
                            channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] !==
                            held_local_tag[channel_index] ||
                        channel_response_read_data_o[
                            channel_index*DATA_WIDTH +: DATA_WIDTH] !==
                            held_data[channel_index] ||
                        channel_response_status_o[channel_index*2 +: 2] !==
                            held_status[channel_index]) begin
                        $fatal(1, "channel %0d response changed while stalled",
                               channel_index);
                    end
                end

                held_valid[channel_index] = channel_response_valid_o[channel_index] &&
                    !channel_response_ready_i[channel_index];
                held_write[channel_index] = channel_response_write_o[channel_index];
                held_local_tag[channel_index] = channel_response_local_tag_o[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH];
                held_data[channel_index] = channel_response_read_data_o[
                    channel_index*DATA_WIDTH +: DATA_WIDTH];
                held_status[channel_index] =
                    channel_response_status_o[channel_index*2 +: 2];

                if (channel_response_valid_o[channel_index] &&
                    channel_response_ready_i[channel_index]) begin
                    if (queue_head[channel_index] >= queue_tail[channel_index]) begin
                        $fatal(1, "channel %0d delivered an unexpected response",
                               channel_index);
                    end
                    if (channel_response_write_o[channel_index] !==
                            expected_write[channel_index][queue_head[channel_index]] ||
                        channel_response_local_tag_o[
                            channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] !==
                            expected_local_tag[channel_index][queue_head[channel_index]] ||
                        channel_response_read_data_o[
                            channel_index*DATA_WIDTH +: DATA_WIDTH] !==
                            expected_data[channel_index][queue_head[channel_index]] ||
                        channel_response_status_o[channel_index*2 +: 2] !==
                            expected_status[channel_index][queue_head[channel_index]]) begin
                        $fatal(1, "channel %0d response mismatch head=%0d actual_tag=%0h expected_tag=%0h actual_status=%0h expected_status=%0h",
                               channel_index, queue_head[channel_index],
                               channel_response_local_tag_o[
                                   channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH],
                               expected_local_tag[channel_index][queue_head[channel_index]],
                               channel_response_status_o[channel_index*2 +: 2],
                               expected_status[channel_index][queue_head[channel_index]]);
                    end
                    queue_head[channel_index] = queue_head[channel_index] + 1;
                    delivered_count = delivered_count + 1;
                end
            end

            for (lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin
                if (hbm_response_valid_i[lane_index] &&
                    hbm_response_ready_o[lane_index]) begin
                    source_advance[lane_index] = 1'b1;
                    if (hbm_response_partition_i[
                            lane_index*PARTITION_BITS +: PARTITION_BITS] == 3'd3) begin
                        observed_channel = hbm_response_tag_i[
                            lane_index*HBM_TAG_WIDTH + LOCAL_TAG_WIDTH +:
                            CHANNEL_INDEX_WIDTH];
                        observed_local_tag = hbm_response_tag_i[
                            lane_index*HBM_TAG_WIDTH +: LOCAL_TAG_WIDTH];
                        if (queue_tail[observed_channel] >= QUEUE_DEPTH) begin
                            $fatal(1, "expected response queue overflow");
                        end
                        expected_write[observed_channel][queue_tail[observed_channel]] =
                            hbm_response_write_i[lane_index];
                        expected_local_tag[observed_channel][queue_tail[observed_channel]] =
                            observed_local_tag;
                        expected_data[observed_channel][queue_tail[observed_channel]] =
                            hbm_response_read_data_i[
                                lane_index*DATA_WIDTH +: DATA_WIDTH];
                        expected_status[observed_channel][queue_tail[observed_channel]] =
                            hbm_response_status_i[lane_index*2 +: 2];
                        queue_tail[observed_channel] = queue_tail[observed_channel] + 1;
                        accepted_valid_count = accepted_valid_count + 1;
                    end else begin
                        malformed_count = malformed_count + 1;
                    end
                end
            end
        end
    endtask

    task automatic clear_advanced_sources;
        integer lane_index;
        begin
            @(negedge clk_i);
            for (lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin
                if (source_advance[lane_index]) begin
                    hbm_response_valid_i[lane_index] = 1'b0;
                end
            end
        end
    endtask

    initial begin
        integer index;
        integer lane_index;
        integer cycle_index;
        integer phase_accepted_start;
        integer drain_cycles;
        integer random_channel;
        logic queues_empty;

        clk_i = 1'b0;
        rst_i = 1'b1;
        hbm_response_valid_i = '0;
        hbm_response_write_i = '0;
        hbm_response_partition_i = '0;
        hbm_response_tag_i = '0;
        hbm_response_read_data_i = '0;
        hbm_response_status_i = '0;
        channel_response_ready_i = '0;
        source_advance = '0;
        held_valid = '0;
        lfsr_q = 32'hc001_cafe;
        accepted_valid_count = 0;
        delivered_count = 0;
        malformed_count = 0;

        for (index = 0; index < CHANNELS; index = index + 1) begin
            queue_head[index] = 0;
            queue_tail[index] = 0;
            next_local_tag[index] = '0;
            held_write[index] = 1'b0;
            held_local_tag[index] = '0;
            held_data[index] = '0;
            held_status[index] = '0;
        end

        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        channel_response_ready_i = '1;

        for (lane_index = 0; lane_index < HBM_LANES;
             lane_index = lane_index + 1) begin
            present_response(lane_index, 3, 3'd3);
        end
        monitor_cycle();
        clear_advanced_sources();
        while (delivered_count < HBM_LANES) begin
            monitor_cycle();
            clear_advanced_sources();
        end
        if (queue_head[3] != HBM_LANES) begin
            $fatal(1, "same-channel five-lane ordered retirement failed");
        end

        for (lane_index = 0; lane_index < HBM_LANES;
             lane_index = lane_index + 1) begin
            present_response(lane_index, lane_index, 3'd3);
        end
        phase_accepted_start = 0;
        for (cycle_index = 0; cycle_index < 44; cycle_index = cycle_index + 1) begin
            monitor_cycle();
            if (cycle_index == 3) begin
                phase_accepted_start = accepted_valid_count;
            end
            @(negedge clk_i);
            for (lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin
                if (source_advance[lane_index] && (cycle_index != 43)) begin
                    present_response(
                        lane_index,
                        (cycle_index*HBM_LANES + lane_index + HBM_LANES) % CHANNELS,
                        3'd3
                    );
                end else if (source_advance[lane_index]) begin
                    hbm_response_valid_i[lane_index] = 1'b0;
                end
            end
        end
        if ((accepted_valid_count - phase_accepted_start) != 40*HBM_LANES) begin
            $fatal(1, "five-lane response acceptance throughput failed");
        end

        for (cycle_index = 0; cycle_index < 400; cycle_index = cycle_index + 1) begin
            lfsr_q = {lfsr_q[30:0],
                      lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            channel_response_ready_i = {
                lfsr_q[15:0] ^ 16'h5a5a
            };
            for (lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin
                if (!hbm_response_valid_i[lane_index] ||
                    source_advance[lane_index]) begin
                    random_channel = lane_index +
                        {28'd0, lfsr_q[(lane_index*5) % 28 +: 4]};
                    present_response(
                        lane_index,
                        random_channel % CHANNELS,
                        3'd3
                    );
                end
            end
            monitor_cycle();
            @(negedge clk_i);
        end

        hbm_response_valid_i = '0;
        channel_response_ready_i = '1;
        drain_cycles = 0;
        queues_empty = 1'b0;
        while ((!queues_empty || busy_o) && (drain_cycles < 2048)) begin
            monitor_cycle();
            clear_advanced_sources();
            queues_empty = 1'b1;
            for (index = 0; index < CHANNELS; index = index + 1) begin
                if (queue_head[index] != queue_tail[index]) begin
                    queues_empty = 1'b0;
                end
            end
            drain_cycles = drain_cycles + 1;
        end
        if (!queues_empty || busy_o) begin
            $fatal(1, "response router failed to drain");
        end

        @(negedge clk_i);
        present_response(0, 7, 3'd4);
        monitor_cycle();
        clear_advanced_sources();
        repeat (3) begin
            monitor_cycle();
            clear_advanced_sources();
        end

        if (!protocol_error_o || (malformed_count != 1) ||
            (dropped_responses_o != 64'd1)) begin
            $fatal(1, "malformed partition handling failed");
        end
        if (accepted_responses_o !=
                64'(accepted_valid_count + malformed_count) ||
            delivered_responses_o != 64'(delivered_count) ||
            delivered_count != accepted_valid_count ||
            backpressure_cycles_o == 64'd0 || busy_o) begin
            $fatal(1, "response counters or final empty state mismatch");
        end

        $display("[RTL_SIM PASS] npu_dma_hbm_response_router accepted=%0d delivered=%0d dropped=%0d backpressure=%0d",
                 accepted_responses_o, delivered_responses_o,
                 dropped_responses_o, backpressure_cycles_o);
        $finish;
    end
endmodule

`default_nettype wire
