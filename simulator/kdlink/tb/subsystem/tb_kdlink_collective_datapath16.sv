`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_collective_datapath16;
    localparam integer CONTEXTS = 16;
    localparam integer FLITS_PER_CONTEXT = 32;
    localparam integer TOTAL_FLITS = CONTEXTS*FLITS_PER_CONTEXT;
    logic clk;
    logic rst_n;
    logic descriptor_valid;
    wire descriptor_ready;
    logic [511:0] descriptor;
    wire allocate_valid;
    wire [3:0] allocate_context;
    logic [15:0] context_block;
    logic local_valid;
    wire local_ready;
    logic [3:0] local_context;
    logic [511:0] local_payload;
    logic [63:0] local_byte_valid;
    logic local_last;
    logic remote_valid;
    wire remote_ready;
    logic [3:0] remote_context;
    logic [511:0] remote_payload;
    logic [63:0] remote_byte_valid;
    logic remote_last;
    wire result_valid;
    logic result_ready;
    wire [3:0] result_context;
    wire [1:0] result_dtype;
    wire [11:0] result_collective_id;
    wire [31:0] result_user_tag;
    wire [511:0] result_payload;
    wire [63:0] result_byte_valid;
    wire result_last;
    wire completion_valid;
    logic completion_ready;
    wire [3:0] completion_context;
    wire [11:0] completion_collective_id;
    wire [31:0] completion_user_tag;
    wire completion_error;
    wire [15:0] active_context;
    wire descriptor_error;
    wire duplicate_error;
    wire stream_error;
    wire internal_error;

    integer sent_count [0:CONTEXTS-1];
    integer result_count [0:CONTEXTS-1];
    integer issue_count [0:CONTEXTS-1];
    integer completion_count [0:CONTEXTS-1];
    integer total_sent;
    integer total_results;
    integer total_completions;
    integer cycle_count;
    integer last_steady_result_cycle;
    integer rr_context;
    integer scan_index;
    integer candidate_context;
    integer selected_context;
    integer context_index;
    integer preload_round;
    integer fault_context_before;
    integer fault_other_before;
    integer timeout_count;
    logic fault_phase;
    integer fault_completion_seen;
    integer fault_descriptor_seen;
    integer fault_duplicate_seen;

    function automatic [11:0] context_id(input [3:0] ctx);
        context_id = {ctx, ~ctx, ctx};
    endfunction

    function automatic [31:0] context_tag(input [3:0] ctx);
        context_tag = {ctx, ~ctx, ctx, ~ctx, ctx, ~ctx, ctx, ~ctx};
    endfunction

    function automatic [63:0] byte_mask(input [3:0] ctx, input [5:0] flit);
        byte_mask = {8{{ctx, flit[3:0]}}} ^ {64{flit[0]}} ^
            (flit[5] ? 64'ha55a_c33c_f00f_6996 : 64'h6996_0ff0_3cc3_5aa5);
    endfunction

    function automatic [511:0] expected_payload(input [1:0] dtype,
                                                 input [63:0] mask);
        reg [511:0] reduced_value;
        reg [511:0] local_value;
        integer byte_index;
        integer lane_index;
        begin
            case (dtype)
                2'd0: begin reduced_value = {16{32'd3}}; local_value = {16{32'd1}}; end
                2'd1: begin reduced_value = {16{32'h4040_0000}}; local_value = {16{32'h3f80_0000}}; end
                2'd2: begin reduced_value = {32{16'h4200}}; local_value = {32{16'h3c00}}; end
                default: begin reduced_value = {32{16'h4040}}; local_value = {32{16'h3f80}}; end
            endcase
            if (dtype == 2'd0) begin
                for (lane_index = 0; lane_index < 16; lane_index = lane_index + 1)
                    if (!(&mask[lane_index*4 +: 4]))
                        reduced_value[lane_index*32 +: 32] =
                            local_value[lane_index*32 +: 32];
            end
            for (byte_index = 0; byte_index < 64; byte_index = byte_index + 1)
                if (!mask[byte_index])
                    reduced_value[byte_index*8 +: 8] = local_value[byte_index*8 +: 8];
            expected_payload = reduced_value;
        end
    endfunction

    kdlink_collective_datapath16 u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .descriptor_valid_i(descriptor_valid),
        .descriptor_ready_o(descriptor_ready), .descriptor_i(descriptor),
        .allocate_valid_o(allocate_valid),
        .allocate_context_o(allocate_context), .context_block_i(context_block),
        .local_valid_i(local_valid), .local_ready_o(local_ready),
        .local_context_i(local_context), .local_payload_i(local_payload),
        .local_byte_valid_i(local_byte_valid), .local_last_i(local_last),
        .remote_valid_i(remote_valid), .remote_ready_o(remote_ready),
        .remote_context_i(remote_context), .remote_payload_i(remote_payload),
        .remote_byte_valid_i(remote_byte_valid), .remote_last_i(remote_last),
        .result_valid_o(result_valid), .result_ready_i(result_ready),
        .result_context_o(result_context), .result_dtype_o(result_dtype),
        .result_collective_id_o(result_collective_id),
        .result_user_tag_o(result_user_tag), .result_payload_o(result_payload),
        .result_byte_valid_o(result_byte_valid), .result_last_o(result_last),
        .completion_valid_o(completion_valid),
        .completion_ready_i(completion_ready),
        .completion_context_o(completion_context),
        .completion_collective_id_o(completion_collective_id),
        .completion_user_tag_o(completion_user_tag),
        .completion_error_o(completion_error), .active_context_o(active_context),
        .descriptor_error_o(descriptor_error),
        .duplicate_error_o(duplicate_error), .stream_error_o(stream_error),
        .internal_error_o(internal_error)
    );

    always #0.5 clk = ~clk;

    task automatic drive_pair(input integer selected);
        begin
            local_context = selected[3:0];
            remote_context = selected[3:0];
            local_byte_valid = byte_mask(selected[3:0], sent_count[selected][5:0]);
            remote_byte_valid = local_byte_valid;
            local_last = (sent_count[selected] == FLITS_PER_CONTEXT-1);
            remote_last = local_last;
            case (selected[1:0])
                0: begin
                    local_payload = {16{32'd1}};
                    remote_payload = {16{32'd2}};
                end
                1: begin
                    local_payload = {16{32'h3f80_0000}};
                    remote_payload = {16{32'h4000_0000}};
                end
                2: begin
                    local_payload = {32{16'h3c00}};
                    remote_payload = {32{16'h4000}};
                end
                default: begin
                    local_payload = {32{16'h3f80}};
                    remote_payload = {32{16'h4000}};
                end
            endcase
            local_valid = 1'b1;
            remote_valid = 1'b1;
        end
    endtask

    task automatic submit_context(input integer selected);
        begin
            @(negedge clk);
            descriptor = 512'd0;
            descriptor[2:0] = `KDL_OPCODE_ALL_REDUCE;
            descriptor[4:3] = selected[1:0];
            descriptor[9:5] = 5'd0;
            descriptor[15:10] = 6'd32;
            descriptor[24:21] = 4'd2;
            descriptor[36:25] = context_id(selected[3:0]);
            descriptor[48:37] = 12'd64;
            descriptor[56:49] = 8'hff;
            descriptor[58:57] = 2'b11;
            descriptor[223:192] = FLITS_PER_CONTEXT*64;
            descriptor[415:384] = context_tag(selected[3:0]);
            descriptor_valid = 1'b1;
            #0.01;
            if (!descriptor_ready)
                $fatal(1, "descriptor was not ready expected=%0d", selected);
            @(posedge clk); #0.01;
            if (!allocate_valid || allocate_context != selected[3:0])
                $fatal(1, "descriptor allocation failed expected=%0d got=%0d valid=%b",
                    selected, allocate_context, allocate_valid);
            @(negedge clk); descriptor_valid = 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            total_results <= 0;
            total_completions <= 0;
            last_steady_result_cycle <= -1;
            for (context_index = 0; context_index < CONTEXTS;
                 context_index = context_index + 1) begin
                result_count[context_index] <= 0;
                issue_count[context_index] <= 0;
                completion_count[context_index] <= 0;
            end
        end else begin
            cycle_count <= cycle_count + 1;
            if (u_dut.issue_fire)
                issue_count[u_dut.scheduler_issue_index] <=
                    issue_count[u_dut.scheduler_issue_index] + 1;
            if (result_valid && result_ready && !fault_phase) begin
                if (result_dtype != result_context[1:0] ||
                    result_collective_id != context_id(result_context) ||
                    result_user_tag != context_tag(result_context) ||
                    result_byte_valid != byte_mask(result_context,
                        result_count[result_context][5:0]))
                    $fatal(1, "result metadata mismatch context=%0d", result_context);
                if (result_payload != expected_payload(result_context[1:0],
                    byte_mask(result_context, result_count[result_context][5:0])))
                    $fatal(1, "masked reduction result mismatch context=%0d flit=%0d",
                        result_context, result_count[result_context]);
                if (result_last !=
                    (result_count[result_context] == FLITS_PER_CONTEXT-1))
                    $fatal(1, "result last mismatch context=%0d count=%0d",
                        result_context, result_count[result_context]);
                if (total_results < 80 && last_steady_result_cycle >= 0 &&
                    cycle_count != last_steady_result_cycle + 1)
                    $fatal(1, "integrated reduction stream contains a bubble result=%0d",
                        total_results);
                if (total_results < 80) last_steady_result_cycle <= cycle_count;
                result_count[result_context] <= result_count[result_context] + 1;
                total_results <= total_results + 1;
            end
            if (completion_valid && completion_ready && fault_phase) begin
                if (!completion_error || completion_context != 4'd0 ||
                    completion_collective_id != context_id(4'd0) ||
                    completion_user_tag != context_tag(4'd0))
                    $fatal(1, "fault completion mismatch context=%0d error=%b",
                        completion_context, completion_error);
                fault_completion_seen <= fault_completion_seen + 1;
            end else if (completion_valid && completion_ready) begin
                if (completion_error ||
                    completion_collective_id != context_id(completion_context) ||
                    completion_user_tag != context_tag(completion_context))
                    $fatal(1, "completion metadata mismatch context=%0d error=%b",
                        completion_context, completion_error);
                if (completion_count[completion_context] != 0)
                    $fatal(1, "duplicate completion context=%0d", completion_context);
                completion_count[completion_context] <= 1;
                total_completions <= total_completions + 1;
            end
            if (fault_phase && descriptor_error)
                fault_descriptor_seen <= fault_descriptor_seen + 1;
            if (fault_phase && duplicate_error)
                fault_duplicate_seen <= fault_duplicate_seen + 1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        descriptor_valid = 1'b0;
        descriptor = 512'd0;
        context_block = 16'hffff;
        local_valid = 1'b0;
        local_context = 4'd0;
        local_payload = 512'd0;
        local_byte_valid = 64'd0;
        local_last = 1'b0;
        remote_valid = 1'b0;
        remote_context = 4'd0;
        remote_payload = 512'd0;
        remote_byte_valid = 64'd0;
        remote_last = 1'b0;
        result_ready = 1'b1;
        completion_ready = 1'b0;
        fault_phase = 1'b0;
        fault_completion_seen = 0;
        fault_descriptor_seen = 0;
        fault_duplicate_seen = 0;
        total_sent = 0;
        rr_context = 0;
        for (context_index = 0; context_index < CONTEXTS;
             context_index = context_index + 1)
            sent_count[context_index] = 0;
        repeat (6) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        for (context_index = 0; context_index < CONTEXTS;
             context_index = context_index + 1)
            submit_context(context_index);

        for (preload_round = 0; preload_round < 4;
             preload_round = preload_round + 1) begin
            for (context_index = 0; context_index < CONTEXTS;
                 context_index = context_index + 1) begin
                @(negedge clk);
                drive_pair(context_index);
                #0.01;
                if (!local_ready || !remote_ready)
                    $fatal(1, "context preload backpressured context=%0d round=%0d counts=%0d/%0d active=%h final=%h",
                        context_index, preload_round,
                        u_dut.local_count_q[context_index],
                        u_dut.remote_count_q[context_index], active_context,
                        u_dut.final_issued_q);
                @(posedge clk);
                sent_count[context_index] = sent_count[context_index] + 1;
                total_sent = total_sent + 1;
                @(negedge clk); local_valid = 1'b0; remote_valid = 1'b0;
            end
        end
        result_ready = 1'b0;
        context_block = 16'd0;
        timeout_count = 0;
        while (u_dut.result_occupancy < 7'd60 && timeout_count < 500) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (u_dut.result_occupancy < 7'd60)
            $fatal(1, "result FIFO did not reach high-water mark occupancy=%0d",
                u_dut.result_occupancy);
        @(negedge clk); result_ready = 1'b1;

        fork
            begin
                while (total_sent < TOTAL_FLITS) begin
                    @(negedge clk);
                    selected_context = -1;
                    for (scan_index = 0; scan_index < CONTEXTS;
                         scan_index = scan_index + 1) begin
                        candidate_context = (rr_context + scan_index) % CONTEXTS;
                        if (selected_context < 0 &&
                            sent_count[candidate_context] < FLITS_PER_CONTEXT &&
                            !context_block[candidate_context] &&
                            u_dut.local_count_q[candidate_context] < 4 &&
                            u_dut.remote_count_q[candidate_context] < 4)
                            selected_context = candidate_context;
                    end
                    if (selected_context >= 0) begin
                        drive_pair(selected_context);
                        #0.01;
                        if (!local_ready || !remote_ready)
                            $fatal(1, "selected context was not ready context=%0d",
                                selected_context);
                        @(posedge clk);
                        sent_count[selected_context] = sent_count[selected_context] + 1;
                        total_sent = total_sent + 1;
                        rr_context = (selected_context + 1) % CONTEXTS;
                    end else begin
                        local_valid = 1'b0;
                        remote_valid = 1'b0;
                    end
                end
                @(negedge clk); local_valid = 1'b0; remote_valid = 1'b0;
            end
            begin
                wait (total_results >= 80);
                @(negedge clk); context_block[1] = 1'b1;
                repeat (3) @(posedge clk);
                fault_context_before = issue_count[1];
                fault_other_before = issue_count[0] + issue_count[2] + issue_count[3];
                repeat (20) @(posedge clk);
                if (issue_count[1] != fault_context_before ||
                    issue_count[0] + issue_count[2] + issue_count[3] <= fault_other_before)
                    $fatal(1, "recoverable context block did not isolate progress");
                @(negedge clk); context_block[1] = 1'b0;
            end
            begin
                wait (total_results >= 140);
                repeat (80) begin
                    @(negedge clk);
                    result_ready = (cycle_count[1:0] != 2'd0);
                end
                @(negedge clk); result_ready = 1'b1;
            end
            begin
                wait (total_results == TOTAL_FLITS);
                repeat (8) @(posedge clk);
                @(negedge clk); completion_ready = 1'b1;
            end
        join_none

        timeout_count = 0;
        while ((total_results < TOTAL_FLITS || total_completions < CONTEXTS) &&
               timeout_count < 5000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (total_results != TOTAL_FLITS || total_completions != CONTEXTS ||
            active_context != 16'd0 || descriptor_error || duplicate_error ||
            stream_error || internal_error)
            $fatal(1, "collective datapath final failure results=%0d completions=%0d active=%h errors=%b%b%b%b",
                total_results, total_completions, active_context, descriptor_error,
                duplicate_error, stream_error, internal_error);
        for (context_index = 0; context_index < CONTEXTS;
             context_index = context_index + 1)
            if (result_count[context_index] != FLITS_PER_CONTEXT ||
                issue_count[context_index] != FLITS_PER_CONTEXT ||
                completion_count[context_index] != 1)
                $fatal(1, "context accounting mismatch context=%0d results=%0d issues=%0d completions=%0d",
                    context_index, result_count[context_index],
                    issue_count[context_index], completion_count[context_index]);
        fault_phase = 1'b1;
        submit_context(0);
        @(negedge clk);
        descriptor_valid = 1'b1;
        #0.01;
        if (descriptor_ready)
            $fatal(1, "duplicate descriptor was unexpectedly accepted");
        @(negedge clk); descriptor_valid = 1'b0;
        @(negedge clk);
        descriptor = 512'd0;
        descriptor_valid = 1'b1;
        #0.01;
        if (descriptor_ready)
            $fatal(1, "invalid descriptor was unexpectedly accepted");
        @(negedge clk); descriptor_valid = 1'b0;
        local_context = 4'd0;
        remote_context = 4'd0;
        local_payload = {16{32'h1111_1111}};
        remote_payload = {16{32'h2222_2222}};
        local_byte_valid = 64'ha55a_c33c_f00f_6996;
        remote_byte_valid = ~local_byte_valid;
        local_last = 1'b0;
        remote_last = 1'b1;
        local_valid = 1'b1;
        remote_valid = 1'b1;
        #0.01;
        if (!local_ready || !remote_ready)
            $fatal(1, "fault pair was unexpectedly backpressured");
        @(negedge clk); local_valid = 1'b0; remote_valid = 1'b0;
        timeout_count = 0;
        while ((fault_completion_seen == 0 || fault_descriptor_seen == 0 ||
                fault_duplicate_seen == 0) && timeout_count < 500) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (fault_completion_seen != 1 || fault_descriptor_seen == 0 ||
            fault_duplicate_seen == 0 || !stream_error || internal_error)
            $fatal(1, "fault-path verification failed completion=%0d descriptor=%0d duplicate=%0d errors=%b%b",
                fault_completion_seen, fault_descriptor_seen, fault_duplicate_seen,
                stream_error, internal_error);
        @(negedge clk); rst_n = 1'b0;
        repeat (3) @(posedge clk);
        #0.01;
        if (descriptor_error || duplicate_error || stream_error || internal_error)
            $fatal(1, "fault status did not clear on reset");
        @(negedge clk); rst_n = 1'b1;
        for (context_index = 0; context_index < 32; context_index = context_index + 1) begin
            @(negedge clk);
            local_context = context_index[3:0];
            remote_context = ~context_index[3:0];
            local_byte_valid = 64'ha55a_c33c_f00f_6996 ^ {8{context_index[7:0]}};
            remote_byte_valid = ~local_byte_valid;
            local_payload = {16{32'h9e37_79b9 ^ context_index}};
            remote_payload = ~local_payload;
            descriptor = {16{32'h7f4a_7c15 ^ context_index}};
        end
        $display("TB_KDLINK_COLLECTIVE_DATAPATH16_PASS contexts=16 flits=%0d dtypes=INT32,FP32,FP16,BF16 ii1_window=80 backpressure=1 recoverable_context_block=1 exact_completion=1",
            TOTAL_FLITS);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "KDLink collective datapath timeout");
    end
endmodule
