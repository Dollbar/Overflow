`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_hbm_tag_tracker;
    localparam int unsigned CHANNELS = 16;
    localparam int unsigned LOCAL_TAG_WIDTH = 8;
    localparam int unsigned TAGS_PER_CHANNEL = 256;
    localparam int unsigned TOTAL_TAGS = CHANNELS * TAGS_PER_CHANNEL;
    localparam int unsigned COUNT_WIDTH = 13;

    logic clk_i;
    logic rst_i;
    logic [CHANNELS-1:0] allocation_commit_i;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] allocation_local_tag_i;
    logic [CHANNELS-1:0] allocation_permitted_o;
    logic [CHANNELS-1:0] retirement_commit_i;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] retirement_local_tag_i;
    logic [CHANNELS-1:0] retirement_known_o;
    logic [CHANNELS-1:0] duplicate_allocation_o;
    logic [CHANNELS-1:0] unknown_retirement_o;
    logic protocol_error_o;
    logic empty_o;
    logic full_o;
    logic [COUNT_WIDTH-1:0] outstanding_count_o;

    logic [TOTAL_TAGS-1:0] expected_outstanding;
    logic [CHANNELS-1:0] expected_allocation_accepted;
    logic [CHANNELS-1:0] expected_retirement_accepted;
    integer expected_count;
    integer expected_telemetry_count;
    integer pending_telemetry_delta_q;
    integer pending_telemetry_delta_qq;
    integer duplicate_count;
    integer unknown_count;
    logic expected_protocol_error;
    logic current_protocol_error_event;
    logic pending_protocol_error_event;
    logic [31:0] lfsr_q;

    npu_dma_hbm_tag_tracker dut (
        .clk_i,
        .rst_i,
        .allocation_commit_i,
        .allocation_local_tag_i,
        .allocation_permitted_o,
        .retirement_commit_i,
        .retirement_local_tag_i,
        .retirement_known_o,
        .duplicate_allocation_o,
        .unknown_retirement_o,
        .protocol_error_o,
        .empty_o,
        .full_o,
        .outstanding_count_o
    );

    always #0.5 clk_i = ~clk_i;

    task automatic run_cycle;
        integer channel_index;
        integer allocation_index;
        integer retirement_index;
        logic expected_permitted;
        logic expected_known;
        begin
            #0.01;
            expected_allocation_accepted = '0;
            expected_retirement_accepted = '0;
            current_protocol_error_event = 1'b0;
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                allocation_index = channel_index*TAGS_PER_CHANNEL +
                    int'(allocation_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]);
                retirement_index = channel_index*TAGS_PER_CHANNEL +
                    int'(retirement_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]);
                expected_known = expected_outstanding[retirement_index];
                expected_retirement_accepted[channel_index] =
                    retirement_commit_i[channel_index] && expected_known;
                expected_permitted = !expected_outstanding[allocation_index] ||
                    (expected_retirement_accepted[channel_index] &&
                     (allocation_index == retirement_index));
                expected_allocation_accepted[channel_index] =
                    allocation_commit_i[channel_index] && expected_permitted;

                if (retirement_known_o[channel_index] !== expected_known ||
                    allocation_permitted_o[channel_index] !== expected_permitted ||
                    duplicate_allocation_o[channel_index] !==
                        (allocation_commit_i[channel_index] && !expected_permitted) ||
                    unknown_retirement_o[channel_index] !==
                        (retirement_commit_i[channel_index] && !expected_known)) begin
                    $fatal(1, "tracker combinational mismatch channel=%0d", channel_index);
                end
                if (duplicate_allocation_o[channel_index]) begin
                    duplicate_count = duplicate_count + 1;
                    current_protocol_error_event = 1'b1;
                end
                if (unknown_retirement_o[channel_index]) begin
                    unknown_count = unknown_count + 1;
                    current_protocol_error_event = 1'b1;
                end
            end

            @(posedge clk_i);
            expected_protocol_error = expected_protocol_error |
                pending_protocol_error_event;
            pending_protocol_error_event = current_protocol_error_event;
            expected_telemetry_count = expected_telemetry_count +
                pending_telemetry_delta_qq;
            pending_telemetry_delta_qq = pending_telemetry_delta_q;
            pending_telemetry_delta_q = 0;
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                allocation_index = channel_index*TAGS_PER_CHANNEL +
                    int'(allocation_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]);
                retirement_index = channel_index*TAGS_PER_CHANNEL +
                    int'(retirement_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]);
                if (expected_retirement_accepted[channel_index]) begin
                    expected_outstanding[retirement_index] = 1'b0;
                    expected_count = expected_count - 1;
                    pending_telemetry_delta_q = pending_telemetry_delta_q - 1;
                end
                if (expected_allocation_accepted[channel_index]) begin
                    expected_outstanding[allocation_index] = 1'b1;
                    expected_count = expected_count + 1;
                    pending_telemetry_delta_q = pending_telemetry_delta_q + 1;
                end
            end
            #0.01;
            if (outstanding_count_o !== COUNT_WIDTH'(expected_telemetry_count) ||
                empty_o !== (expected_count == 0) ||
                full_o !== (expected_count == TOTAL_TAGS) ||
                protocol_error_o !== expected_protocol_error) begin
                $fatal(1, "tracker state mismatch state=%0d telemetry=%0d observed=%0d",
                       expected_count, expected_telemetry_count,
                       outstanding_count_o);
            end
            @(negedge clk_i);
        end
    endtask

    initial begin
        integer channel_index;
        integer tag_index;
        integer cycle_index;

        clk_i = 1'b0;
        rst_i = 1'b1;
        allocation_commit_i = '0;
        allocation_local_tag_i = '0;
        retirement_commit_i = '0;
        retirement_local_tag_i = '0;
        expected_outstanding = '0;
        expected_count = 0;
        expected_telemetry_count = 0;
        pending_telemetry_delta_q = 0;
        pending_telemetry_delta_qq = 0;
        duplicate_count = 0;
        unknown_count = 0;
        expected_protocol_error = 1'b0;
        current_protocol_error_event = 1'b0;
        pending_protocol_error_event = 1'b0;
        lfsr_q = 32'hc001_cafe;

        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        allocation_commit_i = '1;
        allocation_local_tag_i = '0;
        run_cycle();

        allocation_commit_i = '1;
        run_cycle();

        allocation_commit_i = '0;
        retirement_commit_i = '1;
        for (channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin
            retirement_local_tag_i[
                channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] = 8'd1;
        end
        run_cycle();

        allocation_commit_i = '1;
        retirement_commit_i = '1;
        allocation_local_tag_i = '0;
        retirement_local_tag_i = '0;
        run_cycle();

        allocation_commit_i = '0;
        retirement_commit_i = '1;
        run_cycle();

        retirement_commit_i = '0;
        allocation_commit_i = '1;
        for (tag_index = 0; tag_index < TAGS_PER_CHANNEL;
             tag_index = tag_index + 1) begin
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                allocation_local_tag_i[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                    LOCAL_TAG_WIDTH'(tag_index);
            end
            run_cycle();
        end
        if (!full_o || (expected_count != TOTAL_TAGS)) begin
            $fatal(1, "tracker failed the 4096-tag fill test");
        end

        allocation_commit_i = '0;
        retirement_commit_i = '1;
        for (tag_index = 0; tag_index < TAGS_PER_CHANNEL;
             tag_index = tag_index + 1) begin
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                retirement_local_tag_i[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                    LOCAL_TAG_WIDTH'(tag_index);
            end
            run_cycle();
        end
        if (!empty_o || (expected_count != 0)) begin
            $fatal(1, "tracker failed the 4096-tag drain test");
        end

        for (cycle_index = 0; cycle_index < 1000;
             cycle_index = cycle_index + 1) begin
            lfsr_q = {lfsr_q[30:0],
                      lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                allocation_commit_i[channel_index] =
                    lfsr_q[channel_index] ^ lfsr_q[(channel_index+7) % 32];
                retirement_commit_i[channel_index] =
                    lfsr_q[(channel_index+3) % 32] ^
                    lfsr_q[(channel_index+19) % 32];
                allocation_local_tag_i[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                    lfsr_q[(channel_index*3) % 24 +: LOCAL_TAG_WIDTH] ^
                    LOCAL_TAG_WIDTH'(cycle_index);
                retirement_local_tag_i[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                    lfsr_q[(channel_index*5) % 24 +: LOCAL_TAG_WIDTH] ^
                    LOCAL_TAG_WIDTH'(cycle_index >> 1);
            end
            run_cycle();
        end

        allocation_commit_i = '0;
        for (tag_index = 0; tag_index < TAGS_PER_CHANNEL;
             tag_index = tag_index + 1) begin
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                retirement_commit_i[channel_index] = expected_outstanding[
                    channel_index*TAGS_PER_CHANNEL + tag_index];
                retirement_local_tag_i[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                    LOCAL_TAG_WIDTH'(tag_index);
            end
            run_cycle();
        end
        retirement_commit_i = '0;
        run_cycle();
        run_cycle();
        if (duplicate_count == 0 || unknown_count == 0) begin
            $fatal(1, "tracker error injection coverage is incomplete");
        end
        if (!empty_o || (outstanding_count_o != '0)) begin
            $fatal(1, "tracker random-state drain failed");
        end

        $display("[RTL_SIM PASS] npu_dma_hbm_tag_tracker outstanding=%0d duplicate=%0d unknown=%0d",
                 outstanding_count_o, duplicate_count, unknown_count);
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "npu_dma_hbm_tag_tracker timeout");
    end
endmodule

`default_nettype wire
