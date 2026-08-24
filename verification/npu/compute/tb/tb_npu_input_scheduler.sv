`timescale 1ns/1ps
`default_nettype none

module tb_npu_input_scheduler;
    import fp8_pkg::*;
    import mxfp_pkg::*;
    import vector_pkg::*;
    import npu_scheduler_pkg::*;

    localparam int unsigned TASK_SLOTS = 8;
    localparam int unsigned ACTIVE_CONTEXTS = 8;
    localparam int unsigned COMMAND_FIFO_DEPTH = 2;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic task_valid_i;
    logic task_ready_o;
    logic [NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_i;
    logic completion_valid_i;
    logic completion_ready_o;
    logic [NPU_TAG_WIDTH-1:0] completion_tag_i;
    logic completion_success_i;
    logic event_set_valid_i;
    logic [NPU_EVENT_ID_WIDTH-1:0] event_set_id_i;
    logic event_clear_valid_i;
    logic [NPU_EVENT_ID_WIDTH-1:0] event_clear_id_i;
    logic gemm_command_valid_o;
    logic gemm_command_ready_i;
    logic [NPU_GEMM_COMMAND_WIDTH-1:0] gemm_command_o;
    logic activation_command_valid_o;
    logic activation_command_ready_i;
    logic [NPU_BUFFER_READ_COMMAND_WIDTH-1:0] activation_command_o;
    logic weight_command_valid_o;
    logic weight_command_ready_i;
    logic [NPU_BUFFER_READ_COMMAND_WIDTH-1:0] weight_command_o;
    logic vector_command_valid_o;
    logic vector_command_ready_i;
    logic [NPU_VECTOR_COMMAND_WIDTH-1:0] vector_command_o;
    logic result_command_valid_o;
    logic result_command_ready_i;
    logic [NPU_RESULT_COMMAND_WIDTH-1:0] result_command_o;
    logic post_command_valid_o;
    logic post_command_ready_i;
    logic [NPU_POST_COMMAND_WIDTH-1:0] post_command_o;
    logic status_valid_o;
    logic status_ready_i;
    logic [NPU_TASK_STATUS_WIDTH-1:0] status_o;
    logic [$clog2(TASK_SLOTS+1)-1:0] task_level_o;
    logic [$clog2(ACTIVE_CONTEXTS+1)-1:0] active_contexts_o;
    logic protocol_error_o;
    logic [7:0] scenario_id;

    npu_gemm_command_t gemm_log [0:63];
    npu_buffer_read_command_t activation_log [0:63];
    npu_buffer_read_command_t weight_log [0:63];
    npu_vector_command_t vector_log [0:63];
    npu_result_command_t result_log [0:63];
    npu_post_command_t post_log [0:63];
    npu_task_status_t status_log [0:63];
    integer gemm_cycle_log [0:63];
    integer cycle_count;
    integer gemm_count;
    integer activation_count;
    integer weight_count;
    integer vector_count;
    integer result_count;
    integer post_count;
    integer status_count;
    integer check_count;

    npu_input_scheduler #(
        .TASK_SLOTS(TASK_SLOTS),
        .ACTIVE_CONTEXTS(ACTIVE_CONTEXTS),
        .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH)
    ) u_dut (.*);

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/npu_input_scheduler.vcd");
        $dumpvars(1, tb_npu_input_scheduler);
    end
`endif

    function automatic npu_task_descriptor_t make_descriptor(
        input logic [15:0] job_id,
        input logic [15:0] matrix_size
    );
        npu_task_descriptor_t descriptor;
        begin
            descriptor = '0;
            descriptor.version = NPU_TASK_DESCRIPTOR_VERSION;
            descriptor.operation = NPU_TASK_GEMM;
            descriptor.job_id = job_id;
            descriptor.matrix_size = matrix_size;
            descriptor.k_blocks = {12'd0, matrix_size[8:5]};
            descriptor.activation_buffer_id = 4'd1;
            descriptor.activation_base_offset = 32'h0000_1000;
            descriptor.weight_buffer_id = 4'd2;
            descriptor.weight_base_offset = 32'h0000_4000;
            descriptor.output_buffer_id = 4'd3;
            descriptor.output_base_offset = 32'h0000_8000;
            descriptor.activation_format = MXFP8_E4M3;
            descriptor.weight_format = MXFP8_E4M3;
            descriptor.vector_b_format = MXFP8_E4M3;
            descriptor.vector_c_format = MXFP4_E2M1;
            descriptor.vector_control.lane_mask = 16'hffff;
            descriptor.vector_control.operation = VECTOR_ENGINE_OP_PASS;
            descriptor.vector_b_buffer_id = 4'd4;
            descriptor.vector_b_base_offset = 32'h0000_c000;
            descriptor.vector_c_buffer_id = 4'd5;
            descriptor.vector_c_base_offset = 32'h0001_0000;
            descriptor.vector_scalar = 32'h3f80_0000;
            descriptor.vector_result_route = NPU_VECTOR_TO_EXTERNAL;
            descriptor.output_format = NPU_OUTPUT_FP32;
            descriptor.output_mx_format = MXFP8_E4M3;
            make_descriptor = descriptor;
        end
    endfunction

    task automatic send_task(input npu_task_descriptor_t descriptor);
        begin
            @(negedge clk_i);
            task_i = descriptor;
            task_valid_i = 1'b1;
            while (!task_ready_o) @(negedge clk_i);
            @(negedge clk_i);
            task_valid_i = 1'b0;
            task_i = '0;
        end
    endtask

    task automatic complete_task(
        input logic [7:0] tag,
        input logic success
    );
        begin
            @(negedge clk_i);
            completion_tag_i = tag;
            completion_success_i = success;
            completion_valid_i = 1'b1;
            while (!completion_ready_o) @(negedge clk_i);
            @(negedge clk_i);
            completion_valid_i = 1'b0;
            completion_tag_i = '0;
            completion_success_i = 1'b0;
        end
    endtask

    task automatic wait_for_gemm_count(input integer expected_count);
        begin
            while (gemm_count < expected_count) @(negedge clk_i);
        end
    endtask

    task automatic wait_for_status_count(input integer expected_count);
        begin
            while (status_count < expected_count) @(negedge clk_i);
        end
    endtask

    always @(posedge clk_i) begin
        cycle_count <= cycle_count + 1;
        if (gemm_command_valid_o && gemm_command_ready_i) begin
            gemm_log[gemm_count] <= npu_gemm_command_t'(gemm_command_o);
            gemm_cycle_log[gemm_count] <= cycle_count;
            gemm_count <= gemm_count + 1;
        end
        if (activation_command_valid_o && activation_command_ready_i) begin
            activation_log[activation_count] <=
                npu_buffer_read_command_t'(activation_command_o);
            activation_count <= activation_count + 1;
        end
        if (weight_command_valid_o && weight_command_ready_i) begin
            weight_log[weight_count] <=
                npu_buffer_read_command_t'(weight_command_o);
            weight_count <= weight_count + 1;
        end
        if (vector_command_valid_o && vector_command_ready_i) begin
            vector_log[vector_count] <= npu_vector_command_t'(vector_command_o);
            vector_count <= vector_count + 1;
        end
        if (result_command_valid_o && result_command_ready_i) begin
            result_log[result_count] <= npu_result_command_t'(result_command_o);
            result_count <= result_count + 1;
        end
        if (post_command_valid_o && post_command_ready_i) begin
            post_log[post_count] <= npu_post_command_t'(post_command_o);
            post_count <= post_count + 1;
        end
        if (status_valid_o && status_ready_i) begin
            status_log[status_count] <= npu_task_status_t'(status_o);
            status_count <= status_count + 1;
        end
    end

    initial begin
        npu_task_descriptor_t descriptor;
        integer base_gemm;
        integer base_activation;
        integer base_weight;
        integer base_vector;
        integer base_result;
        logic [5:0] base_post;
        integer base_status;
        logic [7:0] first_tag;
        logic [7:0] reset_tag;

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        task_valid_i = 1'b0;
        task_i = '0;
        completion_valid_i = 1'b0;
        completion_tag_i = '0;
        completion_success_i = 1'b0;
        event_set_valid_i = 1'b0;
        event_set_id_i = '0;
        event_clear_valid_i = 1'b0;
        event_clear_id_i = '0;
        gemm_command_ready_i = 1'b1;
        activation_command_ready_i = 1'b1;
        weight_command_ready_i = 1'b1;
        vector_command_ready_i = 1'b1;
        result_command_ready_i = 1'b1;
        post_command_ready_i = 1'b1;
        status_ready_i = 1'b1;
        scenario_id = '0;
        cycle_count = 0;
        gemm_count = 0;
        activation_count = 0;
        weight_count = 0;
        vector_count = 0;
        result_count = 0;
        post_count = 0;
        status_count = 0;
        check_count = 0;

        repeat (3) @(negedge clk_i);
        rst_i = 1'b0;

        // A square descriptor derives one origin-anchored vector count.
        scenario_id = 8'd1;
        descriptor = make_descriptor(16'h0101, 16'd48);
        descriptor.output_mx_format = MXFP4_E2M1;
        descriptor.signal_event_valid = 1'b1;
        descriptor.signal_event_id = 8'd5;
        send_task(descriptor);
        wait_for_gemm_count(1);
        @(negedge clk_i);
        if ((gemm_log[0].job_id != 16'h0101) ||
            (gemm_log[0].matrix_size != 16'd48) ||
            (gemm_log[0].activation_format != MXFP8_E4M3) ||
            (gemm_log[0].weight_format != MXFP8_E4M3) ||
            (activation_log[0].buffer_id != 4'd1) ||
            (activation_log[0].matrix_size != 16'd48) ||
            (weight_log[0].buffer_id != 4'd2) ||
            (weight_log[0].matrix_size != 16'd48) ||
            (activation_count != 1) || (weight_count != 1) ||
            (vector_count != 0) || (result_count != 1) ||
            (post_count != 1) ||
            (post_log[0].job_id != 16'h0101) ||
            (post_log[0].tag != gemm_log[0].tag) ||
            (post_log[0].matrix_size != 16'd48) ||
            (post_log[0].vectors_per_row != 5'd3) ||
            (post_log[0].route != NPU_POST_EXTERNAL) ||
            (post_log[0].destination_format != MXFP4_E2M1) ||
            (post_log[0].output_mx_format != MXFP4_E2M1) ||
            (post_log[0].vector_control.mx_format != MXFP4_E2M1) ||
            (result_log[0].output_mx_format != MXFP4_E2M1) ||
            (result_log[0].source != NPU_RESULT_FROM_GEMM)) begin
            $fatal(1, "FAIL: single GEMM command split or derived geometry");
        end
        first_tag = gemm_log[0].tag;
        complete_task(first_tag, 1'b1);
        wait_for_status_count(1);
        @(negedge clk_i);
        if (!status_log[0].success ||
            (status_log[0].code != NPU_TASK_STATUS_OK) ||
            (active_contexts_o != 0)) begin
            $fatal(1, "FAIL: successful completion/status release");
        end
        check_count = check_count + 1;

        // A dependency-blocked task does not head-of-line block independent work.
        scenario_id = 8'd2;
        descriptor = make_descriptor(16'h0201, 16'd16);
        descriptor.wait_event_valid = 1'b1;
        descriptor.wait_event_id = 8'd9;
        send_task(descriptor);
        descriptor = make_descriptor(16'h0202, 16'd16);
        send_task(descriptor);
        wait_for_gemm_count(2);
        @(negedge clk_i);
        if (gemm_log[1].job_id != 16'h0202) begin
            $fatal(1, "FAIL: ready task did not bypass dependency stall");
        end
        event_set_id_i = 8'd9;
        event_set_valid_i = 1'b1;
        @(negedge clk_i);
        event_set_valid_i = 1'b0;
        wait_for_gemm_count(3);
        @(negedge clk_i);
        if (gemm_log[2].job_id != 16'h0201) begin
            $fatal(1, "FAIL: dependency release did not issue waiting task");
        end
        complete_task(gemm_log[1].tag, 1'b1);
        complete_task(gemm_log[2].tag, 1'b1);
        wait_for_status_count(3);
        check_count = check_count + 1;

        // The compiler owns Tile isolation. Two full-array descriptors issue on
        // consecutive cycles without a hardware region-busy interlock.
        scenario_id = 8'd3;
        base_gemm = gemm_count;
        base_status = status_count;
        @(negedge clk_i);
        for (integer task_number = 0; task_number < 2; task_number++) begin
            if (!task_ready_o) begin
                $fatal(1, "FAIL: full-array descriptor burst was backpressured");
            end
            descriptor = make_descriptor(16'h0301 + 16'(task_number),
                                         16'd256);
            task_i = descriptor;
            task_valid_i = 1'b1;
            @(negedge clk_i);
        end
        task_valid_i = 1'b0;
        task_i = '0;
        wait_for_gemm_count(base_gemm + 2);
        @(negedge clk_i);
        if ((gemm_log[base_gemm].job_id != 16'h0301) ||
            (gemm_log[base_gemm + 1].job_id != 16'h0302) ||
            (gemm_cycle_log[base_gemm + 1] !=
             (gemm_cycle_log[base_gemm] + 1)) ||
            (active_contexts_o != 2)) begin
            $fatal(1, "FAIL: compiler-scheduled full-array tasks did not issue consecutively");
        end
        complete_task(gemm_log[base_gemm].tag, 1'b1);
        complete_task(gemm_log[base_gemm + 1].tag, 1'b1);
        wait_for_status_count(base_status + 2);
        check_count = check_count + 1;

        // Fill the vector command FIFO while its consumer is stalled.  A third
        // vector task must not leak partial GEMM/A/B/result commands.
        scenario_id = 8'd4;
        vector_command_ready_i = 1'b0;
        base_gemm = gemm_count;
        base_activation = activation_count;
        base_weight = weight_count;
        base_vector = vector_count;
        base_result = result_count;
        base_post = 6'(post_count);
        for (integer task_number = 0; task_number < 3; task_number++) begin
            descriptor = make_descriptor(16'h0400 + 16'(task_number),
                                         16'd16);
            descriptor.post_route = NPU_POST_VECTOR;
            descriptor.vector_control.operation = VECTOR_ENGINE_OP_SILU;
            if (task_number == 0) begin
                descriptor.vector_result_route = NPU_VECTOR_TO_FEEDBACK;
                descriptor.output_format = NPU_OUTPUT_MX;
                descriptor.output_mx_format = MXFP8_E4M3;
            end
            send_task(descriptor);
        end
        while (gemm_count < (base_gemm + 2)) @(negedge clk_i);
        repeat (5) @(negedge clk_i);
        if ((gemm_count != base_gemm + 2) ||
            (activation_count != base_activation + 2) ||
            (weight_count != base_weight + 2) ||
            (result_count != base_result + 2) ||
            (vector_count != base_vector)) begin
            $fatal(1, "FAIL: command split was not atomic under vector backpressure");
        end
        vector_command_ready_i = 1'b1;
        wait_for_gemm_count(base_gemm + 3);
        while (vector_count < (base_vector + 3)) @(negedge clk_i);
        if ((vector_log[base_vector].control.operation != VECTOR_ENGINE_OP_SILU) ||
            (vector_log[base_vector].control.tag !=
             vector_log[base_vector].tag) ||
            (vector_log[base_vector].control.output_format !=
             EPILOGUE_OUT_FP32) ||
            (vector_log[base_vector].control.mx_format != MXFP8_E4M3) ||
            (result_log[base_result].vector_result_route !=
             NPU_VECTOR_TO_FEEDBACK) ||
            (post_log[base_post].vector_result_route !=
             NPU_VECTOR_TO_FEEDBACK) ||
            (result_log[base_result].source != NPU_RESULT_FROM_VECTOR)) begin
            $fatal(1, "FAIL: vector command fields or result source");
        end
        for (integer command_index = base_gemm;
             command_index < base_gemm + 3; command_index++) begin
            complete_task(gemm_log[command_index].tag, 1'b1);
        end
        wait_for_status_count(8);
        check_count = check_count + 1;

        // Dynamic mode always emits one B-read command with every GEMM command.
        scenario_id = 8'd5;
        base_weight = weight_count;
        descriptor = make_descriptor(16'h0501, 16'd16);
        send_task(descriptor);
        wait_for_gemm_count(base_gemm + 4);
        repeat (3) @(negedge clk_i);
        if (weight_count != base_weight + 1) begin
            $fatal(1, "FAIL: dynamic task did not emit a B-read command");
        end
        complete_task(gemm_log[base_gemm + 3].tag, 1'b1);
        wait_for_status_count(9);
        check_count = check_count + 1;

        // Four committed descriptors enter and issue on consecutive cycles.
        scenario_id = 8'd9;
        base_gemm = gemm_count;
        base_status = status_count;
        @(negedge clk_i);
        for (integer task_number = 0; task_number < 4; task_number++) begin
            if (!task_ready_o) begin
                $fatal(1, "FAIL: descriptor input stalled during ready burst");
            end
            descriptor = make_descriptor(16'h0900 + 16'(task_number),
                                         16'd16);
            task_i = descriptor;
            task_valid_i = 1'b1;
            @(negedge clk_i);
        end
        task_valid_i = 1'b0;
        task_i = '0;
        wait_for_gemm_count(base_gemm + 4);
        @(negedge clk_i);
        for (integer command_index = base_gemm + 1;
             command_index < base_gemm + 4; command_index++) begin
            if (gemm_cycle_log[command_index] !=
                (gemm_cycle_log[command_index-1] + 1)) begin
                $fatal(1, "FAIL: internal GEMM command issue contained a bubble");
            end
        end
        for (integer command_index = base_gemm;
             command_index < base_gemm + 4; command_index++) begin
            complete_task(gemm_log[command_index].tag, 1'b1);
        end
        wait_for_status_count(base_status + 4);
        check_count = check_count + 1;

        // Fill every issue slot with dependency-blocked work.  Once released,
        // each issued slot must accept a replacement in the same cycle.
        scenario_id = 8'd10;
        base_gemm = gemm_count;
        base_status = status_count;
        for (integer task_number = 0; task_number < TASK_SLOTS;
             task_number++) begin
            descriptor = make_descriptor(16'h0a00 + 16'(task_number),
                                         16'd16);
            descriptor.wait_event_valid = 1'b1;
            descriptor.wait_event_id = 8'd55;
            send_task(descriptor);
        end
        if (task_level_o != $bits(task_level_o)'(TASK_SLOTS)) begin
            $fatal(1, "FAIL: issue queue did not reach full occupancy");
        end
        event_set_id_i = 8'd55;
        event_set_valid_i = 1'b1;
        @(negedge clk_i);
        event_set_valid_i = 1'b0;
        for (integer task_number = 0; task_number < TASK_SLOTS;
             task_number++) begin
            if (!task_ready_o) begin
                $fatal(1, "FAIL: full issue queue did not reuse issued credit");
            end
            descriptor = make_descriptor(16'h0a80 + 16'(task_number),
                                         16'd16);
            task_i = descriptor;
            task_valid_i = 1'b1;
            @(negedge clk_i);
        end
        task_valid_i = 1'b0;
        task_i = '0;
        wait_for_gemm_count(base_gemm + TASK_SLOTS);
        for (integer command_index = base_gemm + 1;
             command_index < base_gemm + TASK_SLOTS; command_index++) begin
            if (gemm_cycle_log[command_index] !=
                (gemm_cycle_log[command_index-1] + 1)) begin
                $fatal(1, "FAIL: full-queue issue contained a command bubble");
            end
        end
        for (integer command_index = base_gemm;
             command_index < base_gemm + TASK_SLOTS; command_index++) begin
            complete_task(gemm_log[command_index].tag, 1'b1);
        end
        wait_for_gemm_count(base_gemm + (2*TASK_SLOTS));
        for (integer command_index = base_gemm + TASK_SLOTS;
             command_index < base_gemm + (2*TASK_SLOTS); command_index++) begin
            complete_task(gemm_log[command_index].tag, 1'b1);
        end
        wait_for_status_count(base_status + (2*TASK_SLOTS));
        check_count = check_count + 1;

        // v0.1 descriptors and reserved MX format encodings are rejected at
        // the v0.2 ABI boundary without leaking partial commands.
        scenario_id = 8'd6;
        base_gemm = gemm_count;
        base_activation = activation_count;
        base_weight = weight_count;
        base_result = result_count;
        base_status = status_count;
        descriptor = make_descriptor(16'h0601, 16'd20);
        descriptor.version = 4'd0;
        send_task(descriptor);
        wait_for_status_count(base_status + 1);
        @(negedge clk_i);
        if ((status_log[base_status].job_id != 16'h0601) ||
            (status_log[base_status].code != NPU_TASK_ERROR_VERSION) ||
            status_log[base_status].success ||
            (gemm_count != base_gemm) ||
            (activation_count != base_activation) ||
            (weight_count != base_weight) ||
            (result_count != base_result) || protocol_error_o) begin
            $fatal(1, "FAIL: v0.1 descriptor crossed v0.2 ABI boundary");
        end

        descriptor = make_descriptor(16'h0602, 16'd16);
        descriptor.activation_format = MXFP_RESERVED_2;
        send_task(descriptor);
        wait_for_status_count(base_status + 2);
        @(negedge clk_i);
        if ((status_log[base_status + 1].job_id != 16'h0602) ||
            (status_log[base_status + 1].code != NPU_TASK_ERROR_FORMAT) ||
            status_log[base_status + 1].success ||
            (gemm_count != base_gemm) || protocol_error_o) begin
            $fatal(1, "FAIL: reserved MX format crossed v0.2 ABI boundary");
        end
        check_count = check_count + 1;

        // Clear flushes a dependency-waiting task and all sticky state, then recovers.
        scenario_id = 8'd7;
        base_status = status_count;
        descriptor = make_descriptor(16'h0701, 16'd16);
        descriptor.wait_event_valid = 1'b1;
        descriptor.wait_event_id = 8'd77;
        send_task(descriptor);
        while (task_level_o == 0) @(negedge clk_i);
        clear_i = 1'b1;
        @(negedge clk_i);
        clear_i = 1'b0;
        repeat (2) @(negedge clk_i);
        if ((task_level_o != 0) || (active_contexts_o != 0) ||
            protocol_error_o || gemm_command_valid_o || status_valid_o) begin
            $fatal(1, "FAIL: clear did not flush scheduler state");
        end
        descriptor = make_descriptor(16'h0702, 16'd16);
        send_task(descriptor);
        wait_for_gemm_count(base_gemm + 1);
        complete_task(gemm_log[base_gemm].tag, 1'b1);
        wait_for_status_count(base_status + 1);
        check_count = check_count + 1;

        // Reset an active context, verify stale completion detection, and recover.
        scenario_id = 8'd8;
        descriptor = make_descriptor(16'h0801, 16'd16);
        send_task(descriptor);
        wait_for_gemm_count(base_gemm + 2);
        reset_tag = gemm_log[base_gemm + 1].tag;
        rst_i = 1'b1;
        @(negedge clk_i);
        rst_i = 1'b0;
        repeat (2) @(negedge clk_i);
        if ((task_level_o != 0) || (active_contexts_o != 0) ||
            gemm_command_valid_o || status_valid_o) begin
            $fatal(1, "FAIL: reset did not flush active work");
        end
        complete_task(reset_tag, 1'b1);
        wait_for_status_count(base_status + 2);
        if (status_log[base_status + 1].code !=
            NPU_TASK_ERROR_COMPLETION) begin
            $fatal(1, "FAIL: stale completion was not rejected");
        end
        clear_i = 1'b1;
        @(negedge clk_i);
        clear_i = 1'b0;
        descriptor = make_descriptor(16'h0802, 16'd16);
        send_task(descriptor);
        wait_for_gemm_count(base_gemm + 3);
        complete_task(gemm_log[base_gemm + 2].tag, 1'b1);
        wait_for_status_count(base_status + 3);
        check_count = check_count + 1;

        $display("PASS: npu_input_scheduler fixed-origin geometry, dependency bypass, atomic six-way command split, backpressure, completion, clear/reset checks=%0d",
                 check_count);
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk_i);
        $fatal(1, "FAIL: npu_input_scheduler timeout scenario=%0d", scenario_id);
    end

endmodule

`default_nettype wire
