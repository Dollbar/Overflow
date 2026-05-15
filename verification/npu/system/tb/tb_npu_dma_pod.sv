`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_pod;

    localparam int unsigned CHANNELS = 16;
    localparam int unsigned HBM_LANES = 5;
    localparam int unsigned COMMAND_WIDTH = npu_dma_pkg::NPU_DMA_COMMAND_WIDTH;
    localparam int unsigned COMPLETION_WIDTH =
        npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH;
    localparam int unsigned RESPONSE_DEPTH = 1024;
    localparam logic [17:0] BEATS_PER_COMMAND = 18'd8;

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
    logic [63:0] sram_accepted_reads_o;
    logic [63:0] sram_accepted_writes_o;
    logic [63:0] sram_read_conflict_cycles_o;
    logic [63:0] sram_write_conflict_cycles_o;

    logic response_valid_q;
    integer response_head_q;
    integer response_tail_q;
    integer response_count_q;
    logic response_write_queue [0:RESPONSE_DEPTH-1];
    logic [11:0] response_tag_queue [0:RESPONSE_DEPTH-1];
    logic [34:0] response_address_queue [0:RESPONSE_DEPTH-1];
    logic [34:0] channel_read_base [0:CHANNELS-1];
    logic [34:0] channel_write_base [0:CHANNELS-1];
    logic [23:0] channel_sram_base [0:CHANNELS-1];
    integer completion_count [0:CHANNELS-1];
    integer accepted_hbm_requests;
    integer checked_hbm_writes;
    integer max_request_lanes;

    function automatic logic [1023:0] hbm_pattern(
        input logic [34:0] address
    );
        logic [31:0] word;
        word = address[31:0] ^ {29'd0, address[34:32]} ^ 32'h7c15_a39d;
        return {32{word}};
    endfunction

    always #0.5 clk_i = ~clk_i;
    assign hbm_request_ready_i = '1;

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
            hbm_response_tag_i[0 +: 12] =
                response_tag_queue[response_head_q];
            hbm_response_read_data_i[0 +: 1024] = hbm_pattern(
                response_address_queue[response_head_q]);
        end
    end

    npu_dma_pod u_dut (
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
        .data_error_seen_o,
        .sram_accepted_reads_o,
        .sram_accepted_writes_o,
        .sram_read_conflict_cycles_o,
        .sram_write_conflict_cycles_o
    );

    always_ff @(posedge clk_i) begin : hbm_and_completion_scoreboard
        integer push_count;
        integer active_lanes;
        integer write_count;
        integer channel;
        logic response_fire;
        logic [11:0] request_tag;
        logic [34:0] request_address;
        logic [34:0] source_address;
        npu_dma_pkg::npu_dma_completion_t observed_completion;

        response_fire = hbm_response_valid_i[0] && hbm_response_ready_o[0];
        if (rst_i || clear_i) begin
            response_valid_q <= 1'b0;
            response_head_q <= 0;
            response_tail_q <= 0;
            response_count_q <= 0;
            accepted_hbm_requests <= 0;
            checked_hbm_writes <= 0;
            max_request_lanes <= 0;
            for (integer index = 0; index < CHANNELS; index++) begin
                completion_count[index] <= 0;
            end
        end else begin
            push_count = 0;
            active_lanes = 0;
            write_count = 0;
            if ((^hbm_response_ready_o) === 1'bx)
                $fatal(1, "HBM response ready contains unknown state");
            for (integer lane = 0; lane < HBM_LANES; lane++) begin
                if (hbm_request_valid_o[lane] &&
                    hbm_request_ready_i[lane]) begin
                    active_lanes = active_lanes + 1;
                    request_tag = hbm_request_tag_o[lane*12 +: 12];
                    request_address = hbm_request_address_o[
                        lane*35 +: 35];
                    channel = int'(request_tag[11:8]);
                    if ((channel >= CHANNELS) ||
                        (hbm_request_partition_o[lane*3 +: 3] != 3'd0) ||
                        (hbm_request_byte_enable_o[lane*128 +: 128] != '1))
                        $fatal(1, "pod emitted malformed HBM request");
                    if (hbm_request_write_o[lane]) begin
                        source_address = channel_read_base[channel] +
                            (request_address - channel_write_base[channel]);
                        if (hbm_request_write_data_o[
                            lane*1024 +: 1024] !==
                            hbm_pattern(source_address))
                            $fatal(1, "pod round-trip mismatch channel=%0d address=%h",
                                   channel, request_address);
                        write_count = write_count + 1;
                    end
                    if ((response_tail_q + push_count) >= RESPONSE_DEPTH)
                        $fatal(1, "HBM response queue overflow");
                    response_write_queue[response_tail_q+push_count] <=
                        hbm_request_write_o[lane];
                    response_tag_queue[response_tail_q+push_count] <=
                        request_tag;
                    response_address_queue[response_tail_q+push_count] <=
                        request_address;
                    push_count = push_count + 1;
                end
            end
            if (active_lanes > max_request_lanes)
                max_request_lanes <= active_lanes;
            if (push_count != 0) begin
                response_tail_q <= response_tail_q + push_count;
                accepted_hbm_requests <= accepted_hbm_requests + push_count;
            end
            if (write_count != 0)
                checked_hbm_writes <= checked_hbm_writes + write_count;
            if (response_fire) begin
                response_valid_q <= 1'b0;
                response_head_q <= response_head_q + 1;
            end else if (!response_valid_q && (response_count_q != 0)) begin
                response_valid_q <= 1'b1;
            end
            case ({(push_count != 0), response_fire})
                2'b10: response_count_q <= response_count_q + push_count;
                2'b01: response_count_q <= response_count_q - 1;
                2'b11: response_count_q <= response_count_q + push_count - 1;
                default: response_count_q <= response_count_q;
            endcase

            for (integer index = 0; index < CHANNELS; index++) begin
                if (completion_valid_o[index] && completion_ready_i[index]) begin
                    observed_completion = completion_o[
                        index*COMPLETION_WIDTH +: COMPLETION_WIDTH];
                    if (!observed_completion.success ||
                        (observed_completion.error_code !=
                         npu_dma_pkg::NPU_DMA_ERROR_OK) ||
                        observed_completion.corrected_ecc_seen ||
                        (observed_completion.beats_completed !=
                         BEATS_PER_COMMAND) ||
                        (observed_completion.command_id !=
                         ((completion_count[index] == 0) ?
                          (16'h8000 + 16'(index)) :
                          (16'h9000 + 16'(index)))))
                        $fatal(1, "pod completion mismatch channel=%0d phase=%0d",
                               index, completion_count[index]);
                    completion_count[index] <= completion_count[index] + 1;
                end
            end
        end
    end

    task automatic submit_phase(input logic write_phase);
        npu_dma_pkg::npu_dma_command_t descriptor;
        logic [CHANNELS-1:0] pending;
        logic [CHANNELS-1:0] accepted;
        @(negedge clk_i);
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            descriptor = '0;
            descriptor.version = npu_dma_pkg::NPU_DMA_COMMAND_VERSION;
            descriptor.operation = write_phase ?
                npu_dma_pkg::NPU_DMA_SRAM_TO_HBM :
                npu_dma_pkg::NPU_DMA_HBM_TO_SRAM;
            descriptor.command_id = (write_phase ? 16'h9000 : 16'h8000) +
                                    16'(channel);
            descriptor.hbm_base_address = write_phase ?
                channel_write_base[channel] : channel_read_base[channel];
            descriptor.sram_base_address = channel_sram_base[channel];
            descriptor.x_beat_count = BEATS_PER_COMMAND;
            descriptor.y_count = 16'd1;
            descriptor.z_count = 16'd1;
            descriptor.qos = 2'(channel);
            command_i[channel*COMMAND_WIDTH +: COMMAND_WIDTH] = descriptor;
        end
        pending = '1;
        command_valid_i = pending;
        while (pending != '0) begin
            @(posedge clk_i);
            accepted = pending & command_ready_o;
            @(negedge clk_i);
            pending &= ~accepted;
            command_valid_i = pending;
        end
    endtask

    initial begin : test_sequence
        integer wait_cycles;
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        quiesce_i = 1'b0;
        command_valid_i = '0;
        command_i = '0;
        completion_ready_i = '1;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            channel_read_base[channel] = 35'h0100_0000 +
                                         channel*35'h0001_0000;
            channel_write_base[channel] = 35'h0200_0000 +
                                          channel*35'h0001_0000;
            channel_sram_base[channel] = 24'(channel << 16);
        end
        repeat (6) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        submit_phase(1'b0);
        wait_cycles = 0;
        while (1) begin
            integer completed;
            completed = 0;
            for (integer channel = 0; channel < CHANNELS; channel++)
                completed += completion_count[channel];
            if (completed == CHANNELS) break;
            @(negedge clk_i);
            wait_cycles = wait_cycles + 1;
            if (wait_cycles > 2000)
                $fatal(1, "HBM-to-SRAM phase timeout");
        end

        submit_phase(1'b1);
        @(negedge clk_i);
        quiesce_i = 1'b1;
        wait_cycles = 0;
        while (!quiesced_o) begin
            @(negedge clk_i);
            wait_cycles = wait_cycles + 1;
            if (command_ready_o != '0)
                $fatal(1, "pod admitted command while quiescing");
            if (wait_cycles > 3000)
                $fatal(1, "pod quiesce timeout");
        end
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            if (completion_count[channel] != 2)
                $fatal(1, "pod omitted completion channel=%0d", channel);
        end
        #1;
        if (busy_o || protocol_error_o || outstanding_full_o ||
            (outstanding_count_o != '0) || (command_level_o != '0) ||
            (channel_outstanding_o != '0) || (response_count_q != 0) ||
            (accepted_hbm_requests != 256) ||
            (checked_hbm_writes != 128) || (max_request_lanes != 5) ||
            (accepted_beats_o != 64'd256) ||
            (issued_beats_o != 64'd256) ||
            (accepted_responses_o != 64'd256) ||
            (delivered_responses_o != 64'd256) ||
            (dropped_responses_o != 64'd0) ||
            (ok_responses_o != 64'd256) ||
            (corrected_responses_o != '0) ||
            (uncorrectable_responses_o != '0) ||
            (data_error_responses_o != '0) || corrected_seen_o ||
            uncorrectable_seen_o || data_error_seen_o ||
            (outstanding_high_watermark_o == '0) ||
            ((^request_backpressure_cycles_o) === 1'bx) ||
            ((^response_backpressure_cycles_o) === 1'bx) ||
            (sram_accepted_reads_o != 64'd128) ||
            (sram_accepted_writes_o != 64'd128) ||
            (sram_read_conflict_cycles_o == 64'd0))
            $fatal(1, "pod final accounting mismatch");

        $display("[RTL_SIM PASS] npu_dma_pod roundtrip_beats=128 max_lanes=%0d sram_read_conflicts=%0d sram_write_conflicts=%0d request_bp=%0d response_bp=%0d quiesce_cycles=%0d",
                 max_request_lanes, sram_read_conflict_cycles_o,
                 sram_write_conflict_cycles_o,
                 request_backpressure_cycles_o,
                 response_backpressure_cycles_o, wait_cycles);
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "npu_dma_pod timeout");
    end

endmodule

`default_nettype wire
