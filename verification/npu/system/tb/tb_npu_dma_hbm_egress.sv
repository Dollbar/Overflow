`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_hbm_egress;
    localparam int unsigned CHANNELS = 16;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned PARTITION_BITS = 3;
    localparam int unsigned ADDRESS_WIDTH = 35;
    localparam int unsigned LOCAL_TAG_WIDTH = 8;
    localparam int unsigned CHANNEL_INDEX_WIDTH = 4;
    localparam int unsigned HBM_TAG_WIDTH = 12;
    localparam int unsigned DATA_BYTES = 128;
    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned TAG_COUNT = 1 << HBM_TAG_WIDTH;

    logic clk_i;
    logic rst_i;
    logic [CHANNELS-1:0] request_valid_i;
    logic [CHANNELS-1:0] request_ready_o;
    logic [CHANNELS-1:0] request_write_i;
    logic [CHANNELS*ADDRESS_WIDTH-1:0] request_address_i;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] request_local_tag_i;
    logic [CHANNELS*DATA_WIDTH-1:0] request_write_data_i;
    logic [CHANNELS*DATA_BYTES-1:0] request_byte_enable_i;
    logic [CHANNELS*2-1:0] request_qos_i;
    logic [HBM_LANES-1:0] hbm_request_valid_o;
    logic [HBM_LANES-1:0] hbm_request_ready_i;
    logic [HBM_LANES-1:0] hbm_request_write_o;
    logic [HBM_LANES*PARTITION_BITS-1:0] hbm_request_partition_o;
    logic [HBM_LANES*ADDRESS_WIDTH-1:0] hbm_request_address_o;
    logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_request_tag_o;
    logic [HBM_LANES*DATA_WIDTH-1:0] hbm_request_write_data_o;
    logic [HBM_LANES*DATA_BYTES-1:0] hbm_request_byte_enable_o;
    logic busy_o;
    logic [63:0] accepted_beats_o;
    logic [63:0] issued_beats_o;
    logic [63:0] backpressure_cycles_o;

    logic expected_valid [0:TAG_COUNT-1];
    logic expected_write [0:TAG_COUNT-1];
    logic [ADDRESS_WIDTH-1:0] expected_address [0:TAG_COUNT-1];
    logic [DATA_WIDTH-1:0] expected_data [0:TAG_COUNT-1];
    logic [DATA_BYTES-1:0] expected_byte_enable [0:TAG_COUNT-1];
    logic [LOCAL_TAG_WIDTH-1:0] next_local_tag [0:CHANNELS-1];
    logic source_update [0:CHANNELS-1];
    integer channel_accept_count [0:CHANNELS-1];

    logic held_valid [0:HBM_LANES-1];
    logic held_write [0:HBM_LANES-1];
    logic [PARTITION_BITS-1:0] held_partition [0:HBM_LANES-1];
    logic [ADDRESS_WIDTH-1:0] held_address [0:HBM_LANES-1];
    logic [HBM_TAG_WIDTH-1:0] held_tag [0:HBM_LANES-1];
    logic [DATA_WIDTH-1:0] held_data [0:HBM_LANES-1];
    logic [DATA_BYTES-1:0] held_byte_enable [0:HBM_LANES-1];

    integer accepted_count;
    integer issued_count;
    integer outstanding_count;
    logic [31:0] lfsr_q;

    npu_dma_hbm_egress #(
        .CHANNELS(CHANNELS),
        .HBM_LANES(HBM_LANES),
        .PARTITION_BITS(PARTITION_BITS),
        .PARTITION_ID(3),
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .LOCAL_TAG_WIDTH(LOCAL_TAG_WIDTH),
        .DATA_BYTES(DATA_BYTES),
        .AGE_PROMOTION_CYCLES(4)
    ) dut (
        .clk_i,
        .rst_i,
        .request_valid_i,
        .request_ready_o,
        .request_write_i,
        .request_address_i,
        .request_local_tag_i,
        .request_write_data_i,
        .request_byte_enable_i,
        .request_qos_i,
        .hbm_request_valid_o,
        .hbm_request_ready_i,
        .hbm_request_write_o,
        .hbm_request_partition_o,
        .hbm_request_address_o,
        .hbm_request_tag_o,
        .hbm_request_write_data_o,
        .hbm_request_byte_enable_o,
        .busy_o,
        .accepted_beats_o,
        .issued_beats_o,
        .backpressure_cycles_o
    );

    always #0.5 clk_i = ~clk_i;

    task automatic drive_channel(input integer channel_index);
        integer byte_index;
        integer address_value;
        logic [7:0] pattern;
        begin
            pattern = 8'(channel_index) ^ next_local_tag[channel_index];
            address_value = (channel_index*256 +
                int'(next_local_tag[channel_index])) * DATA_BYTES;
            request_write_i[channel_index] = next_local_tag[channel_index][0];
            request_address_i[channel_index*ADDRESS_WIDTH +: ADDRESS_WIDTH] =
                ADDRESS_WIDTH'(address_value);
            request_local_tag_i[channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                next_local_tag[channel_index];
            for (byte_index = 0; byte_index < DATA_BYTES; byte_index = byte_index + 1) begin
                request_write_data_i[channel_index*DATA_WIDTH + byte_index*8 +: 8] =
                    pattern ^ 8'(byte_index);
                request_byte_enable_i[channel_index*DATA_BYTES + byte_index] =
                    request_write_i[channel_index] &&
                    ((byte_index + channel_index) % 5 != 0);
            end
        end
    endtask

    task automatic monitor_cycle;
        integer channel_index;
        integer lane_index;
        logic [HBM_TAG_WIDTH-1:0] tag_index;
        logic [HBM_TAG_WIDTH-1:0] observed_tag;
        begin
            @(posedge clk_i);

            for (lane_index = 0; lane_index < HBM_LANES; lane_index = lane_index + 1) begin
                if (held_valid[lane_index]) begin
                    if (!hbm_request_valid_o[lane_index] ||
                        hbm_request_write_o[lane_index] !== held_write[lane_index] ||
                        hbm_request_partition_o[lane_index*PARTITION_BITS +: PARTITION_BITS] !==
                            held_partition[lane_index] ||
                        hbm_request_address_o[lane_index*ADDRESS_WIDTH +: ADDRESS_WIDTH] !==
                            held_address[lane_index] ||
                        hbm_request_tag_o[lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH] !==
                            held_tag[lane_index] ||
                        hbm_request_write_data_o[lane_index*DATA_WIDTH +: DATA_WIDTH] !==
                            held_data[lane_index] ||
                        hbm_request_byte_enable_o[lane_index*DATA_BYTES +: DATA_BYTES] !==
                            held_byte_enable[lane_index]) begin
                        $fatal(1, "HBM lane %0d payload changed while stalled", lane_index);
                    end
                end

                held_valid[lane_index] =
                    hbm_request_valid_o[lane_index] && !hbm_request_ready_i[lane_index];
                held_write[lane_index] = hbm_request_write_o[lane_index];
                held_partition[lane_index] =
                    hbm_request_partition_o[lane_index*PARTITION_BITS +: PARTITION_BITS];
                held_address[lane_index] =
                    hbm_request_address_o[lane_index*ADDRESS_WIDTH +: ADDRESS_WIDTH];
                held_tag[lane_index] =
                    hbm_request_tag_o[lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH];
                held_data[lane_index] =
                    hbm_request_write_data_o[lane_index*DATA_WIDTH +: DATA_WIDTH];
                held_byte_enable[lane_index] =
                    hbm_request_byte_enable_o[lane_index*DATA_BYTES +: DATA_BYTES];
            end

            for (lane_index = 0; lane_index < HBM_LANES; lane_index = lane_index + 1) begin
                if (hbm_request_valid_o[lane_index] && hbm_request_ready_i[lane_index]) begin
                    observed_tag =
                        hbm_request_tag_o[lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH];
                    tag_index = observed_tag;
                    if (!expected_valid[tag_index]) begin
                        $fatal(1, "HBM lane %0d issued unknown or duplicate tag %0h",
                               lane_index, observed_tag);
                    end
                    if (hbm_request_partition_o[
                            lane_index*PARTITION_BITS +: PARTITION_BITS] !== 3'd3 ||
                        hbm_request_write_o[lane_index] !== expected_write[tag_index] ||
                        hbm_request_address_o[
                            lane_index*ADDRESS_WIDTH +: ADDRESS_WIDTH] !==
                            expected_address[tag_index] ||
                        hbm_request_write_data_o[
                            lane_index*DATA_WIDTH +: DATA_WIDTH] !== expected_data[tag_index] ||
                        hbm_request_byte_enable_o[
                            lane_index*DATA_BYTES +: DATA_BYTES] !==
                            expected_byte_enable[tag_index]) begin
                        $fatal(1, "HBM lane %0d payload mismatch for tag %0h",
                               lane_index, observed_tag);
                    end
                    expected_valid[tag_index] = 1'b0;
                    issued_count = issued_count + 1;
                    outstanding_count = outstanding_count - 1;
                end
            end

            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (request_valid_i[channel_index] && request_ready_o[channel_index]) begin
                    observed_tag = {
                        CHANNEL_INDEX_WIDTH'(channel_index),
                        request_local_tag_i[
                            channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]
                    };
                    tag_index = observed_tag;
                    if (expected_valid[tag_index]) begin
                        $fatal(1, "DMA channel %0d reused outstanding tag %0h",
                               channel_index, observed_tag);
                    end
                    expected_valid[tag_index] = 1'b1;
                    expected_write[tag_index] = request_write_i[channel_index];
                    expected_address[tag_index] = request_address_i[
                        channel_index*ADDRESS_WIDTH +: ADDRESS_WIDTH];
                    expected_data[tag_index] = request_write_data_i[
                        channel_index*DATA_WIDTH +: DATA_WIDTH];
                    expected_byte_enable[tag_index] = request_byte_enable_i[
                        channel_index*DATA_BYTES +: DATA_BYTES];
                    source_update[channel_index] = 1'b1;
                    channel_accept_count[channel_index] =
                        channel_accept_count[channel_index] + 1;
                    accepted_count = accepted_count + 1;
                    outstanding_count = outstanding_count + 1;
                end
            end
        end
    endtask

    task automatic update_sources;
        integer channel_index;
        begin
            @(negedge clk_i);
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (source_update[channel_index]) begin
                    next_local_tag[channel_index] =
                        next_local_tag[channel_index] + 1'b1;
                    drive_channel(channel_index);
                    source_update[channel_index] = 1'b0;
                end
            end
        end
    endtask

    initial begin
        integer index;
        integer lane_index;
        integer phase_issued_start;
        integer drain_cycles;

        clk_i = 1'b0;
        rst_i = 1'b1;
        request_valid_i = '0;
        request_write_i = '0;
        request_address_i = '0;
        request_local_tag_i = '0;
        request_byte_enable_i = '0;
        request_qos_i = '0;
        hbm_request_ready_i = '0;
        accepted_count = 0;
        issued_count = 0;
        outstanding_count = 0;
        lfsr_q = 32'h1ace_b00c;

        for (index = 0; index < TAG_COUNT; index = index + 1) begin
            expected_valid[index] = 1'b0;
            expected_write[index] = 1'b0;
            expected_address[index] = '0;
            expected_data[index] = '0;
            expected_byte_enable[index] = '0;
        end
        for (index = 0; index < CHANNELS; index = index + 1) begin
            next_local_tag[index] = '0;
            source_update[index] = 1'b0;
            channel_accept_count[index] = 0;
            request_qos_i[index*2 +: 2] = (index == 0) ? 2'd0 : 2'd3;
            drive_channel(index);
        end
        for (lane_index = 0; lane_index < HBM_LANES; lane_index = lane_index + 1) begin
            held_valid[lane_index] = 1'b0;
            held_write[lane_index] = 1'b0;
            held_partition[lane_index] = '0;
            held_address[lane_index] = '0;
            held_tag[lane_index] = '0;
            held_data[lane_index] = '0;
            held_byte_enable[lane_index] = '0;
        end

        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        request_valid_i = '1;

        monitor_cycle();
        update_sources();
        for (index = 0; index < 3; index = index + 1) begin
            monitor_cycle();
            update_sources();
        end
        if (accepted_count != HBM_LANES || issued_count != 0 ||
            !busy_o || backpressure_cycles_o == 0) begin
            $fatal(1, "initial fill/backpressure contract failed");
        end

        hbm_request_ready_i = '1;
        phase_issued_start = issued_count;
        for (index = 0; index < 32; index = index + 1) begin
            monitor_cycle();
            update_sources();
        end
        if ((issued_count - phase_issued_start) != 32*HBM_LANES) begin
            $fatal(1, "five-lane saturation failed: issued %0d expected %0d",
                   issued_count - phase_issued_start, 32*HBM_LANES);
        end

        for (index = 0; index < 400; index = index + 1) begin
            lfsr_q = {lfsr_q[30:0],
                      lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            hbm_request_ready_i = lfsr_q[HBM_LANES-1:0];
            monitor_cycle();
            update_sources();
        end

        request_valid_i = '0;
        hbm_request_ready_i = '1;
        drain_cycles = 0;
        while ((busy_o || (outstanding_count != 0)) && (drain_cycles < 32)) begin
            monitor_cycle();
            update_sources();
            drain_cycles = drain_cycles + 1;
        end
        @(negedge clk_i);

        if (busy_o || (outstanding_count != 0) ||
            (accepted_count != issued_count)) begin
            $fatal(1, "DMA HBM egress did not drain: accepted=%0d issued=%0d outstanding=%0d",
                   accepted_count, issued_count, outstanding_count);
        end
        if ((accepted_beats_o != 64'(accepted_count)) ||
            (issued_beats_o != 64'(issued_count))) begin
            $fatal(1, "DMA HBM performance counters mismatch");
        end
        for (index = 0; index < CHANNELS; index = index + 1) begin
            if (channel_accept_count[index] == 0) begin
                $fatal(1, "DMA channel %0d starved", index);
            end
        end

        $display("[RTL_SIM PASS] npu_dma_hbm_egress accepted=%0d issued=%0d backpressure=%0d",
                 accepted_count, issued_count, backpressure_cycles_o);
        $finish;
    end
endmodule

`default_nettype wire
