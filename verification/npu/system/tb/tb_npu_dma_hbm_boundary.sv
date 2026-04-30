`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_hbm_boundary;
    localparam int unsigned CHANNELS = 16;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned PARTITION_BITS = 3;
    localparam int unsigned PARTITION_ID = 3;
    localparam int unsigned ADDRESS_WIDTH = 35;
    localparam int unsigned LOCAL_TAG_WIDTH = 8;
    localparam int unsigned HBM_TAG_WIDTH = 12;
    localparam int unsigned DATA_BYTES = 128;
    localparam int unsigned DATA_WIDTH = DATA_BYTES * 8;
    localparam int unsigned TAGS_PER_CHANNEL = 256;
    localparam int unsigned TOTAL_TAGS = CHANNELS * TAGS_PER_CHANNEL;
    localparam int unsigned REQUESTS_PER_CHANNEL = 96;
    localparam int unsigned TOTAL_REQUESTS =
        CHANNELS * REQUESTS_PER_CHANNEL;

    logic clk_i;
    logic rst_i;
    logic [CHANNELS-1:0] channel_request_valid_i;
    logic [CHANNELS-1:0] channel_request_ready_o;
    logic [CHANNELS-1:0] channel_request_write_i;
    logic [CHANNELS*ADDRESS_WIDTH-1:0] channel_request_address_i;
    logic [CHANNELS*DATA_WIDTH-1:0] channel_request_write_data_i;
    logic [CHANNELS*DATA_BYTES-1:0] channel_request_byte_enable_i;
    logic [CHANNELS*2-1:0] channel_request_qos_i;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] channel_request_local_tag_o;
    logic [HBM_LANES-1:0] hbm_request_valid_o;
    logic [HBM_LANES-1:0] hbm_request_ready_i;
    logic [HBM_LANES-1:0] hbm_request_write_o;
    logic [HBM_LANES*PARTITION_BITS-1:0] hbm_request_partition_o;
    logic [HBM_LANES*ADDRESS_WIDTH-1:0] hbm_request_address_o;
    logic [HBM_LANES*HBM_TAG_WIDTH-1:0] hbm_request_tag_o;
    logic [HBM_LANES*DATA_WIDTH-1:0] hbm_request_write_data_o;
    logic [HBM_LANES*DATA_BYTES-1:0] hbm_request_byte_enable_o;
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
    logic outstanding_full_o;
    logic [12:0] outstanding_count_o;
    logic [63:0] accepted_beats_o;
    logic [63:0] issued_beats_o;
    logic [63:0] request_backpressure_cycles_o;
    logic [63:0] accepted_responses_o;
    logic [63:0] delivered_responses_o;
    logic [63:0] dropped_responses_o;
    logic [63:0] response_backpressure_cycles_o;

    logic [TOTAL_TAGS-1:0] reserved_tag;
    logic [TOTAL_TAGS-1:0] issued_tag;
    logic [TOTAL_TAGS-1:0] expected_write;
    logic [ADDRESS_WIDTH-1:0] expected_address [0:TOTAL_TAGS-1];
    logic [DATA_WIDTH-1:0] expected_write_data [0:TOTAL_TAGS-1];
    logic [DATA_BYTES-1:0] expected_byte_enable [0:TOTAL_TAGS-1];
    logic [DATA_WIDTH-1:0] expected_response_data [0:TOTAL_TAGS-1];
    logic [1:0] expected_response_status [0:TOTAL_TAGS-1];

    logic [HBM_TAG_WIDTH-1:0] response_tag_queue [0:TOTAL_REQUESTS-1];
    logic response_write_queue [0:TOTAL_REQUESTS-1];
    logic [DATA_WIDTH-1:0] response_data_queue [0:TOTAL_REQUESTS-1];
    logic [1:0] response_status_queue [0:TOTAL_REQUESTS-1];

    logic [CHANNELS-1:0] request_accepted_q;
    logic drive_enable;
    logic drain_mode;
    logic [31:0] lfsr_q;
    integer next_sequence [0:CHANNELS-1];
    integer channel_source_count [0:CHANNELS-1];
    integer channel_response_count [0:CHANNELS-1];
    integer source_accepted_count;
    integer hbm_issued_count;
    integer response_head;
    integer response_tail;
    integer delivered_count;
    integer five_lane_issue_cycles;

    npu_dma_hbm_boundary #(
        .PARTITION_ID(PARTITION_ID)
    ) dut (
        .clk_i,
        .rst_i,
        .channel_request_valid_i,
        .channel_request_ready_o,
        .channel_request_write_i,
        .channel_request_address_i,
        .channel_request_write_data_i,
        .channel_request_byte_enable_i,
        .channel_request_qos_i,
        .channel_request_local_tag_o,
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
        .channel_response_valid_o,
        .channel_response_ready_i,
        .channel_response_write_o,
        .channel_response_local_tag_o,
        .channel_response_read_data_o,
        .channel_response_status_o,
        .busy_o,
        .protocol_error_o,
        .outstanding_full_o,
        .outstanding_count_o,
        .accepted_beats_o,
        .issued_beats_o,
        .request_backpressure_cycles_o,
        .accepted_responses_o,
        .delivered_responses_o,
        .dropped_responses_o,
        .response_backpressure_cycles_o
    );

    always #0.5 clk_i = ~clk_i;

    always_comb begin
        hbm_response_valid_i = '0;
        hbm_response_write_i = '0;
        hbm_response_partition_i = '0;
        hbm_response_tag_i = '0;
        hbm_response_read_data_i = '0;
        hbm_response_status_i = '0;
        if (response_head < response_tail) begin
            hbm_response_valid_i[0] = 1'b1;
            hbm_response_write_i[0] = response_write_queue[response_head];
            hbm_response_partition_i[0 +: PARTITION_BITS] =
                PARTITION_BITS'(PARTITION_ID);
            hbm_response_tag_i[0 +: HBM_TAG_WIDTH] =
                response_tag_queue[response_head];
            hbm_response_read_data_i[0 +: DATA_WIDTH] =
                response_data_queue[response_head];
            hbm_response_status_i[0 +: 2] =
                response_status_queue[response_head];
        end
    end

    /* verilator lint_off BLKSEQ */
    always @(posedge clk_i) begin
        integer channel_index;
        integer lane_index;
        integer full_tag_index;
        integer tail_next;
        integer issued_this_cycle;
        logic [HBM_TAG_WIDTH-1:0] hbm_tag;
        logic [LOCAL_TAG_WIDTH-1:0] local_tag;
        logic [DATA_WIDTH-1:0] response_data;
        logic [1:0] response_status;

        request_accepted_q = '0;
        if (rst_i) begin
            response_head = 0;
            response_tail = 0;
        end else begin
            if ((^hbm_response_ready_o) === 1'bx) begin
                $fatal(1, "boundary response ready contains unknown state");
            end
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (channel_request_valid_i[channel_index] &&
                    channel_request_ready_o[channel_index]) begin
                    local_tag = channel_request_local_tag_o[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH];
                    full_tag_index = channel_index*TAGS_PER_CHANNEL +
                                     int'(local_tag);
                    if (reserved_tag[full_tag_index]) begin
                        $fatal(1, "boundary reused reserved tag=%0h",
                               full_tag_index);
                    end
                    reserved_tag[full_tag_index] = 1'b1;
                    expected_write[full_tag_index] =
                        channel_request_write_i[channel_index];
                    expected_address[full_tag_index] =
                        channel_request_address_i[
                            channel_index*ADDRESS_WIDTH +: ADDRESS_WIDTH];
                    expected_write_data[full_tag_index] =
                        channel_request_write_data_i[
                            channel_index*DATA_WIDTH +: DATA_WIDTH];
                    expected_byte_enable[full_tag_index] =
                        channel_request_byte_enable_i[
                            channel_index*DATA_BYTES +: DATA_BYTES];
                    request_accepted_q[channel_index] = 1'b1;
                    source_accepted_count = source_accepted_count + 1;
                    channel_source_count[channel_index] =
                        channel_source_count[channel_index] + 1;
                end
            end

            tail_next = response_tail;
            issued_this_cycle = 0;
            for (lane_index = 0; lane_index < HBM_LANES;
                 lane_index = lane_index + 1) begin
                if (hbm_request_valid_o[lane_index] &&
                    hbm_request_ready_i[lane_index]) begin
                    hbm_tag = hbm_request_tag_o[
                        lane_index*HBM_TAG_WIDTH +: HBM_TAG_WIDTH];
                    full_tag_index = int'(hbm_tag);
                    if (!reserved_tag[full_tag_index] ||
                        issued_tag[full_tag_index]) begin
                        $fatal(1, "boundary issued invalid tag=%0h", hbm_tag);
                    end
                    if ((hbm_request_partition_o[
                             lane_index*PARTITION_BITS +: PARTITION_BITS] !=
                         PARTITION_BITS'(PARTITION_ID)) ||
                        (hbm_request_write_o[lane_index] !==
                         expected_write[full_tag_index]) ||
                        (hbm_request_address_o[
                             lane_index*ADDRESS_WIDTH +: ADDRESS_WIDTH] !==
                         expected_address[full_tag_index]) ||
                        (hbm_request_write_data_o[
                             lane_index*DATA_WIDTH +: DATA_WIDTH] !==
                         expected_write_data[full_tag_index]) ||
                        (hbm_request_byte_enable_o[
                             lane_index*DATA_BYTES +: DATA_BYTES] !==
                         expected_byte_enable[full_tag_index])) begin
                        $fatal(1, "boundary request payload mismatch tag=%0h",
                               hbm_tag);
                    end

                    issued_tag[full_tag_index] = 1'b1;
                    response_data = hbm_request_write_o[lane_index] ?
                        '0 : hbm_request_write_data_o[
                            lane_index*DATA_WIDTH +: DATA_WIDTH];
                    response_status = (hbm_tag[5:0] == 6'h15) ? 2'd1 : 2'd0;
                    expected_response_data[full_tag_index] = response_data;
                    expected_response_status[full_tag_index] = response_status;
                    response_tag_queue[tail_next] = hbm_tag;
                    response_write_queue[tail_next] =
                        hbm_request_write_o[lane_index];
                    response_data_queue[tail_next] = response_data;
                    response_status_queue[tail_next] = response_status;
                    tail_next = tail_next + 1;
                    hbm_issued_count = hbm_issued_count + 1;
                    issued_this_cycle = issued_this_cycle + 1;
                end
            end
            response_tail = tail_next;
            if (issued_this_cycle == HBM_LANES) begin
                five_lane_issue_cycles = five_lane_issue_cycles + 1;
            end

            if (hbm_response_valid_i[0] && hbm_response_ready_o[0]) begin
                response_head = response_head + 1;
            end

            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (channel_response_valid_o[channel_index] &&
                    channel_response_ready_i[channel_index]) begin
                    local_tag = channel_response_local_tag_o[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH];
                    full_tag_index = channel_index*TAGS_PER_CHANNEL +
                                     int'(local_tag);
                    if (!reserved_tag[full_tag_index] ||
                        !issued_tag[full_tag_index] ||
                        (channel_response_write_o[channel_index] !==
                         expected_write[full_tag_index]) ||
                        (channel_response_read_data_o[
                             channel_index*DATA_WIDTH +: DATA_WIDTH] !==
                         expected_response_data[full_tag_index]) ||
                        (channel_response_status_o[
                             channel_index*2 +: 2] !==
                         expected_response_status[full_tag_index])) begin
                        $fatal(1, "boundary response mismatch tag=%0h",
                               full_tag_index);
                    end
                    reserved_tag[full_tag_index] = 1'b0;
                    issued_tag[full_tag_index] = 1'b0;
                    delivered_count = delivered_count + 1;
                    channel_response_count[channel_index] =
                        channel_response_count[channel_index] + 1;
                end
            end
        end
    end

    always @(negedge clk_i) begin
        integer channel_index;
        logic [31:0] payload_word;

        if (rst_i) begin
            channel_request_valid_i = '0;
            hbm_request_ready_i = '0;
            channel_response_ready_i = '0;
        end else begin
            lfsr_q = {lfsr_q[30:0],
                      lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            hbm_request_ready_i = drain_mode ? '1 :
                {lfsr_q[19], lfsr_q[7], lfsr_q[25], lfsr_q[3],
                 lfsr_q[14]} | 5'b00101;
            channel_response_ready_i = drain_mode ? '1 :
                (lfsr_q[15:0] ^ {lfsr_q[7:0], lfsr_q[31:24]});

            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (!channel_request_valid_i[channel_index] ||
                    request_accepted_q[channel_index]) begin
                    if (drive_enable &&
                        (next_sequence[channel_index] <
                         REQUESTS_PER_CHANNEL)) begin
                        payload_word = {
                            8'(channel_index),
                            8'(next_sequence[channel_index]),
                            16'(channel_index*REQUESTS_PER_CHANNEL +
                                next_sequence[channel_index])
                        };
                        channel_request_valid_i[channel_index] = 1'b1;
                        channel_request_write_i[channel_index] =
                            next_sequence[channel_index][0];
                        channel_request_address_i[
                            channel_index*ADDRESS_WIDTH +: ADDRESS_WIDTH] =
                            (ADDRESS_WIDTH'(channel_index*
                                REQUESTS_PER_CHANNEL) +
                             ADDRESS_WIDTH'(next_sequence[channel_index])) *
                            ADDRESS_WIDTH'(DATA_BYTES);
                        channel_request_write_data_i[
                            channel_index*DATA_WIDTH +: DATA_WIDTH] =
                            {DATA_WIDTH/32{payload_word}};
                        channel_request_byte_enable_i[
                            channel_index*DATA_BYTES +: DATA_BYTES] = '1;
                        channel_request_qos_i[channel_index*2 +: 2] =
                            2'(channel_index % 4);
                        next_sequence[channel_index] =
                            next_sequence[channel_index] + 1;
                    end else begin
                        channel_request_valid_i[channel_index] = 1'b0;
                    end
                end
            end
        end
    end
    /* verilator lint_on BLKSEQ */

    initial begin
        integer channel_index;

        clk_i = 1'b0;
        rst_i = 1'b1;
        channel_request_valid_i = '0;
        channel_request_write_i = '0;
        channel_request_address_i = '0;
        channel_request_byte_enable_i = '0;
        channel_request_qos_i = '0;
        hbm_request_ready_i = '0;
        channel_response_ready_i = '0;
        reserved_tag = '0;
        issued_tag = '0;
        expected_write = '0;
        request_accepted_q = '0;
        drive_enable = 1'b0;
        drain_mode = 1'b0;
        lfsr_q = 32'h8d31_6a5b;
        source_accepted_count = 0;
        hbm_issued_count = 0;
        response_head = 0;
        response_tail = 0;
        delivered_count = 0;
        five_lane_issue_cycles = 0;
        for (channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin
            next_sequence[channel_index] = 0;
            channel_source_count[channel_index] = 0;
            channel_response_count[channel_index] = 0;
            channel_request_write_data_i[
                channel_index*DATA_WIDTH +: DATA_WIDTH] = '0;
        end

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        drive_enable = 1'b1;

        wait (source_accepted_count == TOTAL_REQUESTS);
        @(negedge clk_i);
        drive_enable = 1'b0;
        channel_request_valid_i = '0;
        drain_mode = 1'b1;

        wait ((delivered_count == TOTAL_REQUESTS) && !busy_o);
        repeat (8) @(posedge clk_i);
        #0.01;

        if ((hbm_issued_count != TOTAL_REQUESTS) ||
            (response_head != TOTAL_REQUESTS) ||
            (response_tail != TOTAL_REQUESTS) ||
            (five_lane_issue_cycles == 0) ||
            (reserved_tag != '0) || (issued_tag != '0) ||
            protocol_error_o || outstanding_full_o ||
            (outstanding_count_o != 13'd0) ||
            (accepted_beats_o != 64'(TOTAL_REQUESTS)) ||
            (issued_beats_o != 64'(TOTAL_REQUESTS)) ||
            (accepted_responses_o != 64'(TOTAL_REQUESTS)) ||
            (delivered_responses_o != 64'(TOTAL_REQUESTS)) ||
            (dropped_responses_o != 64'd0) ||
            (request_backpressure_cycles_o == 64'd0) ||
            (response_backpressure_cycles_o == 64'd0)) begin
            $fatal(1, "boundary drain or telemetry mismatch");
        end

        for (channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin
            if ((channel_source_count[channel_index] !=
                 REQUESTS_PER_CHANNEL) ||
                (channel_response_count[channel_index] !=
                 REQUESTS_PER_CHANNEL)) begin
                $fatal(1, "boundary channel count mismatch channel=%0d",
                       channel_index);
            end
        end

        $display("[RTL_SIM PASS] npu_dma_hbm_boundary accepted=%0d issued=%0d delivered=%0d five_lane_cycles=%0d request_bp=%0d response_bp=%0d",
                 source_accepted_count, hbm_issued_count, delivered_count,
                 five_lane_issue_cycles,
                 request_backpressure_cycles_o,
                 response_backpressure_cycles_o);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "npu_dma_hbm_boundary timeout");
    end
endmodule

`default_nettype wire
