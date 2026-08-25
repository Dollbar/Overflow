`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_hbm_status_monitor;
    localparam int unsigned CHANNELS = 16;
    localparam int unsigned RANDOM_CYCLES = 1024;

    logic clk_i;
    logic rst_i;
    logic [CHANNELS-1:0] response_commit_i;
    logic [CHANNELS*2-1:0] response_status_i;
    logic [63:0] ok_responses_o;
    logic [63:0] corrected_responses_o;
    logic [63:0] uncorrectable_responses_o;
    logic [63:0] data_error_responses_o;
    logic corrected_seen_o;
    logic uncorrectable_seen_o;
    logic data_error_seen_o;
    logic [31:0] lfsr_q;
    longint unsigned expected_count [0:3];

    npu_dma_hbm_status_monitor dut (
        .clk_i,
        .rst_i,
        .response_commit_i,
        .response_status_i,
        .ok_responses_o,
        .corrected_responses_o,
        .uncorrectable_responses_o,
        .data_error_responses_o,
        .corrected_seen_o,
        .uncorrectable_seen_o,
        .data_error_seen_o
    );

    always #0.5 clk_i = ~clk_i;

    task automatic account_cycle;
        integer channel_index;
        logic [1:0] status_value;
        begin
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                if (response_commit_i[channel_index]) begin
                    status_value = response_status_i[
                        channel_index*2 +: 2];
                    expected_count[status_value] =
                        expected_count[status_value] + 1;
                end
            end
            @(posedge clk_i);
        end
    endtask

    task automatic check_counters;
        begin
            if ((ok_responses_o !== expected_count[0]) ||
                (corrected_responses_o !== expected_count[1]) ||
                (uncorrectable_responses_o !== expected_count[2]) ||
                (data_error_responses_o !== expected_count[3])) begin
                $fatal(1,
                       "status counters mismatch got=%0d/%0d/%0d/%0d expected=%0d/%0d/%0d/%0d",
                       ok_responses_o, corrected_responses_o,
                       uncorrectable_responses_o, data_error_responses_o,
                       expected_count[0], expected_count[1],
                       expected_count[2], expected_count[3]);
            end
        end
    endtask

    initial begin
        integer channel_index;
        integer cycle_index;

        clk_i = 1'b0;
        rst_i = 1'b1;
        response_commit_i = '0;
        response_status_i = '0;
        lfsr_q = 32'hb7e1_5163;
        expected_count[0] = 0;
        expected_count[1] = 0;
        expected_count[2] = 0;
        expected_count[3] = 0;

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        response_commit_i = '1;
        for (channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin
            response_status_i[channel_index*2 +: 2] =
                2'(channel_index % 4);
        end
        account_cycle();

        for (cycle_index = 0; cycle_index < RANDOM_CYCLES;
             cycle_index = cycle_index + 1) begin
            @(negedge clk_i);
            lfsr_q = {lfsr_q[30:0],
                      lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            response_commit_i = lfsr_q[15:0];
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                response_status_i[channel_index*2 +: 2] =
                    lfsr_q[(channel_index*2) % 30 +: 2] ^
                    2'(cycle_index);
            end
            account_cycle();
        end

        @(negedge clk_i);
        response_commit_i = '0;
        response_status_i = '0;
        repeat (4) @(posedge clk_i);
        check_counters();
        if (!corrected_seen_o || !uncorrectable_seen_o ||
            !data_error_seen_o) begin
            $fatal(1, "status sticky flags did not record all fault classes");
        end

        @(negedge clk_i);
        rst_i = 1'b1;
        repeat (2) @(posedge clk_i);
        if ((ok_responses_o != 0) || (corrected_responses_o != 0) ||
            (uncorrectable_responses_o != 0) ||
            (data_error_responses_o != 0) || corrected_seen_o ||
            uncorrectable_seen_o || data_error_seen_o) begin
            $fatal(1, "status telemetry did not clear on reset");
        end

        $display("[RTL_SIM PASS] npu_dma_hbm_status_monitor counts=%0d/%0d/%0d/%0d",
                 expected_count[0], expected_count[1],
                 expected_count[2], expected_count[3]);
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "status monitor test timed out");
    end
endmodule

`default_nettype wire
