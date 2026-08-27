`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_engine;

    localparam int unsigned CHANNELS = 16;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned COMMAND_WIDTH = npu_dma_pkg::NPU_DMA_COMMAND_WIDTH;
    localparam int unsigned COMPLETION_WIDTH =
        npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH;
    localparam int unsigned SRAM_WORDS = 1024;
    localparam int unsigned RESPONSE_DEPTH = 2048;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic quiesce_i;
    logic [CHANNELS-1:0] command_valid_i;
    logic [CHANNELS-1:0] command_ready_o;
    logic [CHANNELS*COMMAND_WIDTH-1:0] command_i;
    logic [CHANNELS*3-1:0] command_level_o;
    logic [CHANNELS*9-1:0] channel_outstanding_o;
    logic [CHANNELS-1:0] completion_valid_o;
    logic [CHANNELS-1:0] completion_ready_i;
    logic [CHANNELS*COMPLETION_WIDTH-1:0] completion_o;
    logic [CHANNELS-1:0] sram_read_request_valid_o;
    logic [CHANNELS-1:0] sram_read_request_ready_i;
    logic [CHANNELS*24-1:0] sram_read_request_address_o;
    logic [CHANNELS-1:0] sram_read_response_valid_i;
    logic [CHANNELS-1:0] sram_read_response_ready_o;
    logic [CHANNELS*1024-1:0] sram_read_response_data_i;
    logic [CHANNELS-1:0] sram_write_valid_o;
    logic [CHANNELS-1:0] sram_write_ready_i;
    logic [CHANNELS*24-1:0] sram_write_address_o;
    logic [CHANNELS*1024-1:0] sram_write_data_o;
    logic [CHANNELS*128-1:0] sram_write_byte_enable_o;
    logic [HBM_LANES-1:0] hbm_request_valid_o;
    logic [HBM_LANES-1:0] hbm_request_ready_i;
    logic [HBM_LANES-1:0] hbm_request_write_o;
    logic [HBM_LANES*3-1:0] hbm_request_partition_o;
    logic [HBM_LANES*35-1:0] hbm_request_address_o;
    logic [HBM_LANES*12-1:0] hbm_request_tag_o;
    logic [HBM_LANES*1024-1:0] hbm_request_write_data_o;
    logic [HBM_LANES*128-1:0] hbm_request_byte_enable_o;
    logic [HBM_LANES-1:0] hbm_response_valid_i;
    logic [HBM_LANES-1:0] hbm_response_ready_o;
    logic [HBM_LANES-1:0] hbm_response_write_i;
    logic [HBM_LANES*3-1:0] hbm_response_partition_i;
    logic [HBM_LANES*12-1:0] hbm_response_tag_i;
    logic [HBM_LANES*1024-1:0] hbm_response_read_data_i;
    logic [HBM_LANES*2-1:0] hbm_response_status_i;
    logic busy_o;
    logic quiesced_o;
    logic protocol_error_o;
    logic outstanding_full_o;
    logic [12:0] outstanding_count_o;
    logic [12:0] outstanding_high_watermark_o;
    logic [63:0] accepted_beats_o;
    logic [63:0] issued_beats_o;
    logic [63:0] request_backpressure_cycles_o;
    logic [63:0] accepted_responses_o;
    logic [63:0] delivered_responses_o;
    logic [63:0] dropped_responses_o;
    logic [63:0] response_backpressure_cycles_o;
    logic [63:0] ok_responses_o;
    logic [63:0] corrected_responses_o;
    logic [63:0] uncorrectable_responses_o;
    logic [63:0] data_error_responses_o;
    logic corrected_seen_o;
    logic uncorrectable_seen_o;
    logic data_error_seen_o;

    logic [1023:0] sram_memory [0:SRAM_WORDS-1];
    logic [1023:0] expected_sram_write_data [0:SRAM_WORDS-1];
    logic expected_sram_write_valid [0:SRAM_WORDS-1];
    logic [CHANNELS-1:0] sram_response_valid_q;
    logic [CHANNELS*1024-1:0] sram_response_data_q;
    logic response_valid_q;
    integer response_head_q;
    integer response_tail_q;
    integer response_count_q;
    logic response_write_queue [0:RESPONSE_DEPTH-1];
    logic [11:0] response_tag_queue [0:RESPONSE_DEPTH-1];
    logic [34:0] response_address_queue [0:RESPONSE_DEPTH-1];
    integer completion_head [0:CHANNELS-1];
    integer completion_tail [0:CHANNELS-1];
    logic [15:0] expected_completion_id [0:CHANNELS-1][0:15];
    logic [17:0] expected_completion_beats [0:CHANNELS-1][0:15];
    logic [34:0] channel_hbm_base [0:CHANNELS-1];
    logic [23:0] channel_sram_base [0:CHANNELS-1];
    integer max_request_lanes;
    integer accepted_hbm_requests;
    integer retired_hbm_responses;
    integer committed_sram_reads;
    integer committed_sram_writes;

    assign sram_read_request_ready_i =
        ~sram_response_valid_q | sram_read_response_ready_o;
    assign sram_read_response_valid_i = sram_response_valid_q;
    assign sram_read_response_data_i = sram_response_data_q;
    assign sram_write_ready_i = {CHANNELS{1'b1}};
    assign hbm_request_ready_i = {HBM_LANES{1'b1}};

    always_comb begin
        hbm_response_valid_i = '0;
        hbm_response_write_i = '0;
        hbm_response_partition_i = '0;
        hbm_response_tag_i = '0;
        hbm_response_read_data_i = '0;
        hbm_response_status_i = '0;
        if (response_valid_q) begin
            hbm_response_valid_i[0] = 1'b1;
            hbm_response_write_i[0] =
                response_write_queue[response_head_q];
            hbm_response_partition_i[0 +: 3] = 3'd0;
            hbm_response_tag_i[0 +: 12] =
                response_tag_queue[response_head_q];
            hbm_response_read_data_i[0 +: 1024] = {32{
                response_address_queue[response_head_q][31:0] ^
                32'h2d84_b6f1}};
            hbm_response_status_i[0 +: 2] = 2'd0;
        end
    end

    npu_dma_engine dut (
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
        .sram_read_request_valid_o,
        .sram_read_request_ready_i,
        .sram_read_request_address_o,
        .sram_read_response_valid_i,
        .sram_read_response_ready_o,
        .sram_read_response_data_i,
        .sram_write_valid_o,
        .sram_write_ready_i,
        .sram_write_address_o,
        .sram_write_data_o,
        .sram_write_byte_enable_o,
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
        .busy_o,
        .quiesced_o,
        .protocol_error_o,
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

    always #0.5 clk_i = ~clk_i;

    always_ff @(posedge clk_i) begin
        integer lane;
        integer channel;
        integer push_count;
        integer active_lanes;
        integer word_index;
        integer sram_read_fire_count;
        integer sram_write_fire_count;
        logic response_fire;
        logic [11:0] request_tag;
        logic [34:0] request_address;
        npu_dma_pkg::npu_dma_completion_t observed_completion;
        response_fire = hbm_response_valid_i[0] && hbm_response_ready_o[0];
        if (rst_i || clear_i) begin
            sram_response_valid_q <= '0;
            for (channel = 0; channel < CHANNELS; channel++) begin
                sram_response_data_q[channel*1024 +: 1024] <= '0;
            end
            response_valid_q <= 1'b0;
            response_head_q <= 0;
            response_tail_q <= 0;
            response_count_q <= 0;
            max_request_lanes <= 0;
            accepted_hbm_requests <= 0;
            retired_hbm_responses <= 0;
            committed_sram_reads <= 0;
            committed_sram_writes <= 0;
        end else begin
            if ((^hbm_response_ready_o) === 1'bx) begin
                $fatal(1, "HBM response ready contains unknown state");
            end
            push_count = 0;
            active_lanes = 0;
            sram_read_fire_count = 0;
            sram_write_fire_count = 0;
            for (lane = 0; lane < HBM_LANES; lane++) begin
                if (hbm_request_valid_o[lane] &&
                    hbm_request_ready_i[lane]) begin
                    active_lanes = active_lanes + 1;
                    request_tag = hbm_request_tag_o[lane*12 +: 12];
                    request_address = hbm_request_address_o[
                        lane*35 +: 35];
                    if ((hbm_request_partition_o[lane*3 +: 3] != 3'd0) ||
                        (hbm_request_byte_enable_o[lane*128 +: 128] !=
                         {128{1'b1}})) begin
                        $fatal(1, "HBM request geometry mismatch");
                    end
                    channel = int'(request_tag[11:8]);
                    if (hbm_request_write_o[lane]) begin
                        word_index = (int'(channel_sram_base[channel]) +
                            int'(24'(request_address-
                                     channel_hbm_base[channel]))) >> 7;
                        if ((word_index < 0) ||
                            (word_index >= SRAM_WORDS)) begin
                            $fatal(1, "HBM write source exceeds test SRAM");
                        end
                        if (hbm_request_write_data_o[
                            lane*1024 +: 1024] != sram_memory[word_index]) begin
                            $fatal(1, "engine HBM write payload mismatch channel=%0d",
                                   channel);
                        end
                    end
                    response_write_queue[response_tail_q+push_count] <=
                        hbm_request_write_o[lane];
                    response_tag_queue[response_tail_q+push_count] <=
                        request_tag;
                    response_address_queue[response_tail_q+push_count] <=
                        request_address;
                    push_count = push_count + 1;
                end
            end
            if (active_lanes > max_request_lanes) begin
                max_request_lanes <= active_lanes;
            end
            if (push_count != 0) begin
                response_tail_q <= response_tail_q + push_count;
                accepted_hbm_requests <= accepted_hbm_requests + push_count;
            end

            if (response_fire) begin
                response_valid_q <= 1'b0;
                response_head_q <= response_head_q + 1;
                retired_hbm_responses <= retired_hbm_responses + 1;
            end else if (!response_valid_q && (response_count_q != 0)) begin
                response_valid_q <= 1'b1;
            end
            case ({(push_count != 0), response_fire})
                2'b10: response_count_q <= response_count_q + push_count;
                2'b01: response_count_q <= response_count_q - 1;
                2'b11: response_count_q <= response_count_q + push_count - 1;
                default: response_count_q <= response_count_q;
            endcase

            for (channel = 0; channel < CHANNELS; channel++) begin
                if (sram_response_valid_q[channel] &&
                    sram_read_response_ready_o[channel]) begin
                    sram_response_valid_q[channel] <= 1'b0;
                end
                if (sram_read_request_valid_o[channel] &&
                    sram_read_request_ready_i[channel]) begin
                    word_index = int'(sram_read_request_address_o[
                        channel*24 +: 24]) >> 7;
                    if ((word_index < 0) ||
                        (word_index >= SRAM_WORDS)) begin
                        $fatal(1, "SRAM read exceeds test SRAM");
                    end
                    sram_response_valid_q[channel] <= 1'b1;
                    sram_response_data_q[channel*1024 +: 1024] <=
                        sram_memory[word_index];
                    sram_read_fire_count = sram_read_fire_count + 1;
                end
                if (sram_write_valid_o[channel] &&
                    sram_write_ready_i[channel]) begin
                    if (sram_write_byte_enable_o[
                        channel*128 +: 128] != {128{1'b1}}) begin
                        $fatal(1, "engine SRAM write enable mismatch");
                    end
                    word_index = int'(sram_write_address_o[
                        channel*24 +: 24]) >> 7;
                    if ((word_index < 0) ||
                        (word_index >= SRAM_WORDS)) begin
                        $fatal(1, "SRAM write exceeds test SRAM");
                    end
                    if (!expected_sram_write_valid[word_index] ||
                        (sram_write_data_o[channel*1024 +: 1024] !=
                         expected_sram_write_data[word_index])) begin
                        $fatal(1, "engine SRAM write payload mismatch channel=%0d",
                               channel);
                    end
                    sram_memory[word_index] <=
                        sram_write_data_o[channel*1024 +: 1024];
                    sram_write_fire_count = sram_write_fire_count + 1;
                end
                if (completion_valid_o[channel] &&
                    completion_ready_i[channel]) begin
                    observed_completion = completion_o[
                        channel*COMPLETION_WIDTH +: COMPLETION_WIDTH];
                    if ((completion_head[channel] >=
                         completion_tail[channel]) ||
                        (observed_completion.command_id !=
                         expected_completion_id[channel][
                             completion_head[channel]]) ||
                        !observed_completion.success ||
                        (observed_completion.error_code !=
                         npu_dma_pkg::NPU_DMA_ERROR_OK) ||
                        observed_completion.corrected_ecc_seen ||
                        (observed_completion.beats_completed !=
                         expected_completion_beats[channel][
                             completion_head[channel]])) begin
                        $fatal(1, "engine completion mismatch channel=%0d",
                               channel);
                    end
                    completion_head[channel] <=
                        completion_head[channel] + 1;
                end
            end
            if (sram_read_fire_count != 0) begin
                committed_sram_reads <= committed_sram_reads +
                                        sram_read_fire_count;
            end
            if (sram_write_fire_count != 0) begin
                committed_sram_writes <= committed_sram_writes +
                                         sram_write_fire_count;
            end
        end
    end

    task automatic submit_command;
        input integer channel;
        input logic [1:0] operation;
        input logic [15:0] command_id;
        input logic [17:0] beats;
        input logic [34:0] hbm_base;
        input logic [23:0] sram_base;
        npu_dma_pkg::npu_dma_command_t descriptor;
        integer beat_index;
        integer word_index;
        logic [31:0] expected_pattern;
        begin
            descriptor = '0;
            descriptor.version = npu_dma_pkg::NPU_DMA_COMMAND_VERSION;
            descriptor.operation =
                npu_dma_pkg::npu_dma_operation_e'(operation);
            descriptor.command_id = command_id;
            descriptor.hbm_base_address = hbm_base;
            descriptor.sram_base_address = sram_base;
            descriptor.x_beat_count = beats;
            descriptor.y_count = 16'd1;
            descriptor.z_count = 16'd1;
            descriptor.qos = 2'(channel);
            if (operation == npu_dma_pkg::NPU_DMA_HBM_TO_SRAM) begin
                for (beat_index = 0; beat_index < int'(beats);
                     beat_index = beat_index + 1) begin
                    word_index = (int'(sram_base) >> 7) + beat_index;
                    if ((word_index < 0) ||
                        (word_index >= SRAM_WORDS)) begin
                        $fatal(1, "submitted destination exceeds test SRAM");
                    end
                    expected_pattern = 32'(hbm_base + beat_index*35'd128) ^
                                       32'h2d84_b6f1;
                    expected_sram_write_data[word_index] =
                        {32{expected_pattern}};
                    expected_sram_write_valid[word_index] = 1'b1;
                end
            end
            @(negedge clk_i);
            command_i[channel*COMMAND_WIDTH +: COMMAND_WIDTH] = descriptor;
            command_valid_i[channel] = 1'b1;
            while (!command_ready_o[channel]) begin
                @(negedge clk_i);
            end
            expected_completion_id[channel][completion_tail[channel]] =
                command_id;
            expected_completion_beats[channel][completion_tail[channel]] =
                beats;
            completion_tail[channel] = completion_tail[channel] + 1;
            @(posedge clk_i);
            @(negedge clk_i);
            command_valid_i[channel] = 1'b0;
        end
    endtask

    initial begin
        integer channel;
        integer index;
        integer initial_completion_target;
        integer quiesce_wait_cycles;
        integer final_completion_target;
        integer resume_completion_target;
        logic [31:0] source_pattern;
        npu_dma_pkg::npu_dma_command_t initial_descriptor;
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        quiesce_i = 1'b0;
        command_valid_i = '0;
        command_i = '0;
        completion_ready_i = {CHANNELS{1'b1}};
        for (channel = 0; channel < CHANNELS; channel++) begin
            completion_head[channel] = 0;
            completion_tail[channel] = 0;
            channel_hbm_base[channel] = 35'h0010_0000 + channel*35'h10000;
            channel_sram_base[channel] = 24'(channel*4096);
        end
        for (index = 0; index < SRAM_WORDS; index++) begin
            sram_memory[index] = '0;
            expected_sram_write_data[index] = '0;
            expected_sram_write_valid[index] = 1'b0;
        end
        for (channel = 8; channel < CHANNELS; channel++) begin
            for (index = 0; index < 8; index++) begin
                source_pattern = 32'h8100_0000 + channel*32'h100 + index;
                sram_memory[(int'(channel_sram_base[channel]) >> 7)+index] =
                    {32{source_pattern}};
            end
        end

        repeat (6) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        @(negedge clk_i);
        for (channel = 0; channel < CHANNELS; channel++) begin
            initial_descriptor = '0;
            initial_descriptor.version =
                npu_dma_pkg::NPU_DMA_COMMAND_VERSION;
            initial_descriptor.operation = (channel < 8) ?
                npu_dma_pkg::NPU_DMA_HBM_TO_SRAM :
                npu_dma_pkg::NPU_DMA_SRAM_TO_HBM;
            initial_descriptor.command_id = 16'h5000 + 16'(channel);
            initial_descriptor.hbm_base_address =
                channel_hbm_base[channel];
            initial_descriptor.sram_base_address =
                channel_sram_base[channel];
            initial_descriptor.x_beat_count = 18'd8;
            initial_descriptor.y_count = 16'd1;
            initial_descriptor.z_count = 16'd1;
            initial_descriptor.qos = 2'(channel);
            command_i[channel*COMMAND_WIDTH +: COMMAND_WIDTH] =
                initial_descriptor;
            expected_completion_id[channel][0] =
                initial_descriptor.command_id;
            expected_completion_beats[channel][0] = 18'd8;
            completion_tail[channel] = 1;
            if (channel < 8) begin
                for (index = 0; index < 8; index++) begin
                    source_pattern = 32'(
                        channel_hbm_base[channel] + index*35'd128) ^
                        32'h2d84_b6f1;
                    expected_sram_write_data[
                        (int'(channel_sram_base[channel]) >> 7)+index] =
                        {32{source_pattern}};
                    expected_sram_write_valid[
                        (int'(channel_sram_base[channel]) >> 7)+index] =
                        1'b1;
                end
            end
        end
        command_valid_i = {CHANNELS{1'b1}};
        if (command_ready_o != {CHANNELS{1'b1}}) begin
            $fatal(1, "initial sixteen-channel command set was not admitted");
        end
        @(posedge clk_i);
        @(negedge clk_i);
        command_valid_i = '0;
        initial_completion_target = 16;
        while (1) begin
            integer completion_sum;
            completion_sum = 0;
            for (channel = 0; channel < CHANNELS; channel++) begin
                completion_sum = completion_sum + completion_head[channel];
            end
            if (completion_sum == initial_completion_target) break;
            @(negedge clk_i);
        end
        if ((max_request_lanes != 5) || (accepted_hbm_requests != 128) ||
            (retired_hbm_responses != 128) ||
            (committed_sram_reads != 64) ||
            (committed_sram_writes != 64)) begin
            $fatal(1, "sixteen-channel phase accounting mismatch lanes=%0d req=%0d resp=%0d reads=%0d writes=%0d",
                   max_request_lanes, accepted_hbm_requests,
                   retired_hbm_responses, committed_sram_reads,
                   committed_sram_writes);
        end

        completion_ready_i[0] = 1'b0;
        for (index = 0; index < 4; index++) begin
            channel_hbm_base[0] = 35'h0040_0000 + index*35'h1000;
            channel_sram_base[0] = 24'(24'h08000 + index*256);
            submit_command(0, npu_dma_pkg::NPU_DMA_HBM_TO_SRAM,
                16'h6000 + 16'(index), 18'd2,
                channel_hbm_base[0], channel_sram_base[0]);
        end
        repeat (2) @(negedge clk_i);
        if (command_level_o[0 +: 3] != 3'd4) begin
            $fatal(1, "channel context limit did not reach four");
        end
        command_valid_i[0] = 1'b1;
        repeat (4) begin
            @(negedge clk_i);
            if (command_ready_o[0]) begin
                $fatal(1, "fifth channel context was admitted");
            end
        end
        command_valid_i[0] = 1'b0;

        completion_ready_i[0] = 1'b1;
        quiesce_i = 1'b1;
        quiesce_wait_cycles = 0;
        while (!quiesced_o) begin
            @(negedge clk_i);
            quiesce_wait_cycles = quiesce_wait_cycles + 1;
            if (command_ready_o != '0) begin
                $fatal(1, "engine admitted a command while quiescing");
            end
            if (quiesce_wait_cycles > 2000) begin
                $fatal(1, "engine quiesce timeout");
            end
        end
        final_completion_target = 5;
        if ((completion_head[0] != final_completion_target) || busy_o ||
            (command_level_o != '0) || (channel_outstanding_o != '0) ||
            (outstanding_count_o != 13'd0) || (response_count_q != 0)) begin
            $fatal(1, "engine quiesce state is not fully drained");
        end

        @(negedge clk_i);
        quiesce_i = 1'b0;
        @(posedge clk_i);
        @(negedge clk_i);
        if (quiesced_o) begin
            $fatal(1, "engine quiesced state did not clear");
        end
        channel_hbm_base[1] = 35'h0050_0000;
        channel_sram_base[1] = 24'h0c000;
        submit_command(1, npu_dma_pkg::NPU_DMA_HBM_TO_SRAM,
            16'h7001, 18'd1, channel_hbm_base[1], channel_sram_base[1]);
        resume_completion_target = 2;
        while (completion_head[1] != resume_completion_target) begin
            @(negedge clk_i);
        end

        repeat (5) @(posedge clk_i);
        #0.01;
        if (busy_o || protocol_error_o || outstanding_full_o ||
            (outstanding_count_o != 13'd0) ||
            (accepted_beats_o != 64'd137) ||
            (issued_beats_o != 64'd137) ||
            (accepted_responses_o != 64'd137) ||
            (delivered_responses_o != 64'd137) ||
            (dropped_responses_o != 64'd0) ||
            (ok_responses_o != 64'd137) ||
            (corrected_responses_o != 64'd0) ||
            (uncorrectable_responses_o != 64'd0) ||
            (data_error_responses_o != 64'd0) || corrected_seen_o ||
            uncorrectable_seen_o || data_error_seen_o ||
            (outstanding_high_watermark_o == 13'd0)) begin
            $fatal(1, "engine final telemetry mismatch");
        end
        $display("[RTL_SIM PASS] npu_dma_engine beats=%0d max_request_lanes=%0d high_watermark=%0d quiesce_cycles=%0d request_bp=%0d response_bp=%0d",
                 accepted_beats_o, max_request_lanes,
                 outstanding_high_watermark_o, quiesce_wait_cycles,
                 request_backpressure_cycles_o,
                 response_backpressure_cycles_o);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "npu_dma_engine timeout");
    end

endmodule

`default_nettype wire
