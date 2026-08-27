`timescale 1ns/1ps
`default_nettype none

module tb_npu_dma_local_tag_allocator;
    localparam int unsigned CHANNELS = 16;
    localparam int unsigned LOCAL_TAG_WIDTH = 8;
    localparam int unsigned TAGS_PER_CHANNEL = 256;
    localparam int unsigned TOTAL_TAGS = CHANNELS * TAGS_PER_CHANNEL;

    logic clk_i;
    logic rst_i;
    logic [CHANNELS-1:0] allocation_request_i;
    logic [CHANNELS-1:0] allocation_available_o;
    logic [CHANNELS-1:0] allocation_grant_o;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] allocation_local_tag_o;
    logic [CHANNELS-1:0] release_commit_i;
    logic [CHANNELS*LOCAL_TAG_WIDTH-1:0] release_local_tag_i;
    logic [CHANNELS-1:0] release_known_o;
    logic [CHANNELS-1:0] allocation_failure_o;
    logic [CHANNELS-1:0] unknown_release_o;
    logic protocol_error_o;

    logic [TOTAL_TAGS-1:0] expected_free;
    logic current_protocol_error_event;
    logic pending_protocol_error_event;
    logic expected_protocol_error;
    logic [31:0] lfsr_q;
    integer allocation_count;
    integer release_count;
    integer allocation_failure_count;
    integer unknown_release_count;

    npu_dma_local_tag_allocator dut (
        .clk_i,
        .rst_i,
        .allocation_request_i,
        .allocation_available_o,
        .allocation_grant_o,
        .allocation_local_tag_o,
        .release_commit_i,
        .release_local_tag_i,
        .release_known_o,
        .allocation_failure_o,
        .unknown_release_o,
        .protocol_error_o
    );

    always #0.5 clk_i = ~clk_i;

    task automatic run_cycle;
        integer channel_index;
        integer tag_index;
        logic [$clog2(TOTAL_TAGS)-1:0] release_index;
        logic [LOCAL_TAG_WIDTH-1:0] selected_tag;
        logic expected_release_known;
        logic expected_available;
        logic expected_grant;
        logic [TAGS_PER_CHANNEL-1:0] candidate_tags;
        begin
            #0.01;
            current_protocol_error_event = 1'b0;
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                release_index = $clog2(TOTAL_TAGS)'(
                    channel_index*TAGS_PER_CHANNEL +
                    int'(release_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]));
                expected_release_known = !expected_free[release_index];
                candidate_tags = expected_free[
                    channel_index*TAGS_PER_CHANNEL +: TAGS_PER_CHANNEL];

                expected_available = |candidate_tags;
                expected_grant = allocation_request_i[channel_index] &&
                    expected_available;
                selected_tag = 0;
                for (tag_index = TAGS_PER_CHANNEL - 1; tag_index >= 0;
                     tag_index = tag_index - 1) begin
                    if (candidate_tags[tag_index]) begin
                        selected_tag = LOCAL_TAG_WIDTH'(tag_index);
                    end
                end

                if (release_known_o[channel_index] !== expected_release_known ||
                    allocation_available_o[channel_index] !==
                        expected_available ||
                    allocation_grant_o[channel_index] !== expected_grant ||
                    allocation_failure_o[channel_index] !==
                        (allocation_request_i[channel_index] &&
                         !expected_available) ||
                    unknown_release_o[channel_index] !==
                        (release_commit_i[channel_index] &&
                         !expected_release_known) ||
                    (expected_available &&
                     (allocation_local_tag_o[
                         channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] !==
                      selected_tag))) begin
                    $fatal(1, "local-tag allocator mismatch channel=%0d", channel_index);
                end

                if (allocation_failure_o[channel_index]) begin
                    allocation_failure_count = allocation_failure_count + 1;
                    current_protocol_error_event = 1'b1;
                end
                if (unknown_release_o[channel_index]) begin
                    unknown_release_count = unknown_release_count + 1;
                    current_protocol_error_event = 1'b1;
                end
            end

            @(posedge clk_i);
            expected_protocol_error = expected_protocol_error |
                pending_protocol_error_event;
            pending_protocol_error_event = current_protocol_error_event;
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                release_index = $clog2(TOTAL_TAGS)'(
                    channel_index*TAGS_PER_CHANNEL +
                    int'(release_local_tag_i[
                        channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]));
                if (release_commit_i[channel_index] &&
                    !expected_free[release_index]) begin
                    expected_free[release_index] = 1'b1;
                    release_count = release_count + 1;
                end
                if (allocation_grant_o[channel_index]) begin
                    tag_index = channel_index*TAGS_PER_CHANNEL +
                        int'(allocation_local_tag_o[
                            channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH]);
                    expected_free[tag_index] = 1'b0;
                    allocation_count = allocation_count + 1;
                end
            end
            #0.01;
            if (protocol_error_o !== expected_protocol_error) begin
                $fatal(1, "local-tag allocator sticky error mismatch");
            end
            @(negedge clk_i);
        end
    endtask

    task automatic apply_reset;
        begin
            rst_i = 1'b1;
            allocation_request_i = '0;
            release_commit_i = '0;
            release_local_tag_i = '0;
            expected_free = '1;
            current_protocol_error_event = 1'b0;
            pending_protocol_error_event = 1'b0;
            expected_protocol_error = 1'b0;
            repeat (3) @(posedge clk_i);
            @(negedge clk_i);
            rst_i = 1'b0;
        end
    endtask

    initial begin
        integer channel_index;
        integer tag_index;
        integer cycle_index;

        clk_i = 1'b0;
        rst_i = 1'b1;
        allocation_request_i = '0;
        release_commit_i = '0;
        release_local_tag_i = '0;
        expected_free = '1;
        current_protocol_error_event = 1'b0;
        pending_protocol_error_event = 1'b0;
        expected_protocol_error = 1'b0;
        lfsr_q = 32'h41c6_ce57;
        allocation_count = 0;
        release_count = 0;
        allocation_failure_count = 0;
        unknown_release_count = 0;

        apply_reset();

        allocation_request_i = '1;
        for (tag_index = 0; tag_index < TAGS_PER_CHANNEL;
             tag_index = tag_index + 1) begin
            run_cycle();
        end
        if (|allocation_available_o) begin
            $fatal(1, "local-tag allocator failed the 4096-tag fill test");
        end

        run_cycle();

        release_commit_i = '1;
        for (channel_index = 0; channel_index < CHANNELS;
             channel_index = channel_index + 1) begin
            release_local_tag_i[
                channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] = 8'd100;
        end
        run_cycle();
        release_commit_i = '0;
        run_cycle();
        allocation_request_i = '0;
        #0.01;
        if (|allocation_available_o) begin
            $fatal(1, "released tag was not reclaimed on the following cycle");
        end

        release_commit_i = '1;
        run_cycle();
        run_cycle();
        if (!protocol_error_o || allocation_failure_count == 0 ||
            unknown_release_count == 0) begin
            $fatal(1, "local-tag allocator directed error coverage is incomplete");
        end

        apply_reset();

        for (cycle_index = 0; cycle_index < 1000;
             cycle_index = cycle_index + 1) begin
            lfsr_q = {lfsr_q[30:0],
                      lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                allocation_request_i[channel_index] =
                    lfsr_q[channel_index] ^ lfsr_q[(channel_index+11) % 32];
                release_commit_i[channel_index] =
                    lfsr_q[(channel_index+5) % 32] ^
                    lfsr_q[(channel_index+23) % 32];
                release_local_tag_i[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                    lfsr_q[(channel_index*7) % 24 +: LOCAL_TAG_WIDTH] ^
                    LOCAL_TAG_WIDTH'(cycle_index);
            end
            run_cycle();
        end

        allocation_request_i = '0;
        for (tag_index = 0; tag_index < TAGS_PER_CHANNEL;
             tag_index = tag_index + 1) begin
            for (channel_index = 0; channel_index < CHANNELS;
                 channel_index = channel_index + 1) begin
                release_commit_i[channel_index] = !expected_free[
                    channel_index*TAGS_PER_CHANNEL + tag_index];
                release_local_tag_i[
                    channel_index*LOCAL_TAG_WIDTH +: LOCAL_TAG_WIDTH] =
                    LOCAL_TAG_WIDTH'(tag_index);
            end
            run_cycle();
        end
        release_commit_i = '0;
        run_cycle();
        if (expected_free !== '1 || allocation_available_o !== '1) begin
            $fatal(1, "local-tag allocator random-state drain failed");
        end

        $display("[RTL_SIM PASS] npu_dma_local_tag_allocator allocations=%0d releases=%0d allocation_failures=%0d unknown_releases=%0d",
                 allocation_count, release_count, allocation_failure_count,
                 unknown_release_count);
        $finish;
    end

    initial begin
        #3000;
        $fatal(1, "npu_dma_local_tag_allocator timeout");
    end
endmodule

`default_nettype wire
