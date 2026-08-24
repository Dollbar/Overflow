`timescale 1ns/1ps
`default_nettype none

module tb_npu_heterogeneous_k8192 #(
    parameter int unsigned TASK_PAIRS = 1,
    parameter int unsigned MIN_OPERAND_BYTES = 0
);
    import npu_scheduler_pkg::*;
    import npu_gemm_vector_tb_pkg::*;

    localparam int unsigned ARRAY_DIM = 16;
    localparam int unsigned VECTOR_DEPTH = 8192;
    localparam int unsigned K_ELEMENTS = 8192;
    localparam logic [15:0] MATRIX_SIZE = 16'd256;
    localparam int unsigned RESULT_BEATS = MATRIX_SIZE*MATRIX_SIZE/16;
    localparam logic [3:0] FEEDBACK_BUFFER_ID = 4'd2;
    localparam int unsigned FEEDBACK_BASE_ADDRESS =
        FEEDBACK_BUFFER_ID*VECTOR_DEPTH;
    localparam logic [31:0] EXPECTED_FP32 = 32'h46000000;
    localparam logic [7:0] EXPECTED_MX_DATA = 8'h78;
    localparam logic [7:0] EXPECTED_MX_SCALE = 8'd132;
    localparam logic [15:0] JOB_ID_BASE = 16'h9000;
    localparam int unsigned TOTAL_TASKS = 2*TASK_PAIRS;
    localparam int unsigned TIMEOUT_CYCLES =
        TOTAL_TASKS*(K_ELEMENTS + 4096) + 10000;
    localparam longint unsigned TOTAL_INPUT_PAIRS =
        longint'(TOTAL_TASKS)*K_ELEMENTS*ARRAY_DIM*16;
    localparam longint unsigned TOTAL_OPERAND_BYTES = 2*TOTAL_INPUT_PAIRS;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic descriptor_write_valid;
    logic descriptor_write_ready;
    logic [3:0] descriptor_write_index;
    logic [NPU_TASK_DESCRIPTOR_WIDTH-1:0] descriptor_write_data;
    logic descriptor_submit_valid;
    logic descriptor_submit_ready;
    logic [3:0] descriptor_submit_index;
    logic tensor_write_ready;
    logic vector_operand_write_ready;
    logic [ARRAY_DIM-1:0] gemm_output_valid;
    logic [ARRAY_DIM*NPU_POST_RESULT_WIDTH-1:0] gemm_output_result;
    logic [ARRAY_DIM*NPU_POST_COMMAND_WIDTH-1:0] gemm_output_command;
    logic [ARRAY_DIM-1:0] gemm_vector_valid;
    logic [ARRAY_DIM*NPU_POST_RESULT_WIDTH-1:0] gemm_vector_result;
    logic [ARRAY_DIM*NPU_POST_COMMAND_WIDTH-1:0] gemm_vector_command;
    logic [ARRAY_DIM-1:0] gemm_feedback_valid;
    logic [ARRAY_DIM*NPU_POST_RESULT_WIDTH-1:0] gemm_feedback_result;
    logic [ARRAY_DIM*NPU_POST_COMMAND_WIDTH-1:0] gemm_feedback_command;
    logic status_valid;
    logic [NPU_TASK_STATUS_WIDTH-1:0] status;
    logic busy;
    logic protocol_error;
    logic [3:0] scenario_id;
    logic [RESULT_BEATS-1:0] external_seen;
    logic [RESULT_BEATS-1:0] feedback_seen;
    logic check_feedback_memory;
    logic [15:0] expected_job_id;
    logic dense_burst_active;
    logic external_result_active;
    logic feedback_result_active;
    integer dense_burst_cycles;
    integer external_dense_cycles;
    integer feedback_dense_cycles;
    integer external_result_beats;
    integer feedback_result_beats;
    integer status_count;
    longint unsigned total_dense_cycles;
    longint unsigned total_external_result_beats;
    longint unsigned total_feedback_result_beats;
    npu_task_status_t status_decoded;

    assign status_decoded = npu_task_status_t'(status);

    generate
        for (genvar init_bank = 0; init_bank < ARRAY_DIM;
             init_bank++) begin : g_model_preload
            initial begin
                for (integer k_index = 0; k_index < K_ELEMENTS;
                     k_index++) begin
                    u_dut.u_tensor_buffer.g_bank[init_bank].
                        u_activation_data.memory[k_index] = {16{8'h38}};
                    u_dut.u_tensor_buffer.g_bank[init_bank].
                        u_activation_scale.memory[k_index] = {16{8'd127}};
                    u_dut.u_tensor_buffer.g_bank[init_bank].
                        u_weight_data.memory[k_index] = {16{8'h38}};
                    u_dut.u_tensor_buffer.g_bank[init_bank].
                        u_weight_scale.memory[k_index] = {16{8'd127}};
                end
            end

            always @(posedge check_feedback_memory) begin
                for (integer physical_word = 0; physical_word < 256;
                     physical_word++) begin
                    if (u_dut.u_tensor_buffer.g_bank[init_bank].
                            u_activation_data.memory[
                                FEEDBACK_BASE_ADDRESS + physical_word] !==
                        {16{EXPECTED_MX_DATA}}) begin
                        fail("feedback Activation-buffer data mismatch");
                    end
                    if (u_dut.u_tensor_buffer.g_bank[init_bank].
                            u_activation_scale.memory[
                                FEEDBACK_BASE_ADDRESS + physical_word] !==
                        {16{EXPECTED_MX_SCALE}}) begin
                        fail("feedback Activation-buffer scale mismatch");
                    end
                end
            end
        end
    endgenerate

    npu_square_gemm_system #(
        .ARRAY_DIM(ARRAY_DIM),
        .TENSOR_VECTOR_DEPTH(VECTOR_DEPTH)
    ) u_dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .descriptor_write_valid_i(descriptor_write_valid),
        .descriptor_write_ready_o(descriptor_write_ready),
        .descriptor_write_index_i(descriptor_write_index),
        .descriptor_write_data_i(descriptor_write_data),
        .descriptor_submit_valid_i(descriptor_submit_valid),
        .descriptor_submit_ready_o(descriptor_submit_ready),
        .descriptor_submit_index_i(descriptor_submit_index),
        .tensor_write_valid_i(1'b0),
        .tensor_write_ready_o(tensor_write_ready),
        .tensor_write_weight_i(1'b0),
        .tensor_write_buffer_id_i('0),
        .tensor_write_bank_i('0),
        .tensor_write_offset_i('0),
        .tensor_write_data_i('0),
        .tensor_write_scale_i('0),
        .vector_operand_write_valid_i(1'b0),
        .vector_operand_write_ready_o(vector_operand_write_ready),
        .vector_operand_write_c_i(1'b0),
        .vector_operand_write_buffer_id_i('0),
        .vector_operand_write_bank_i('0),
        .vector_operand_write_offset_i('0),
        .vector_operand_write_data_i('0),
        .vector_operand_write_scale_i('0),
        .gemm_output_valid_o(gemm_output_valid),
        .gemm_output_ready_i('1),
        .gemm_output_result_o(gemm_output_result),
        .gemm_output_command_o(gemm_output_command),
        .gemm_vector_valid_o(gemm_vector_valid),
        .gemm_vector_ready_i('1),
        .gemm_vector_result_o(gemm_vector_result),
        .gemm_vector_command_o(gemm_vector_command),
        .gemm_feedback_valid_o(gemm_feedback_valid),
        .gemm_feedback_ready_i('1),
        .gemm_feedback_result_o(gemm_feedback_result),
        .gemm_feedback_command_o(gemm_feedback_command),
        .event_set_valid_i(1'b0),
        .event_set_id_i('0),
        .event_clear_valid_i(1'b0),
        .event_clear_id_i('0),
        .status_valid_o(status_valid),
        .status_ready_i(1'b1),
        .status_o(status),
        .busy_o(busy),
        .protocol_error_o(protocol_error)
    );

    always #2 clk_i = ~clk_i;

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    task automatic send_descriptor(
        input logic [3:0] slot,
        input npu_task_descriptor_t descriptor
    );
        begin
            @(negedge clk_i);
            descriptor_write_index = slot;
            descriptor_write_data = descriptor;
            descriptor_write_valid = 1'b1;
            while (!descriptor_write_ready) @(negedge clk_i);
            @(negedge clk_i);
            descriptor_write_valid = 1'b0;
            descriptor_submit_index = slot;
            descriptor_submit_valid = 1'b1;
            while (!descriptor_submit_ready) @(negedge clk_i);
            @(negedge clk_i);
            descriptor_submit_valid = 1'b0;
        end
    endtask

    always @(negedge clk_i) begin
        if (!rst_i && !clear_i && (scenario_id != 4'd0)) begin
            if (dense_burst_active &&
                !((|u_dut.wave_a_valid) || (|u_dut.wave_b_valid))) begin
                fail("dense Tensor-to-GEMM boundary contains a cycle bubble");
            end
            if ((|u_dut.wave_a_valid) || (|u_dut.wave_b_valid)) begin
            if (!(&u_dut.wave_a_valid) || !(&u_dut.wave_b_valid)) begin
                fail("dense Tensor-to-GEMM boundary contains a lane bubble");
            end
            if (dense_burst_cycles >= K_ELEMENTS) begin
                fail("dense Tensor-to-GEMM boundary exceeded K length");
            end
            for (integer lane = 0; lane < ARRAY_DIM*16; lane++) begin
                if ((u_dut.wave_a_data[lane*8 +: 8] !== 8'h38) ||
                    (u_dut.wave_b_data[lane*8 +: 8] !== 8'h38) ||
                    (u_dut.wave_a_scale[lane*8 +: 8] !== 8'd127) ||
                    (u_dut.wave_b_scale[lane*8 +: 8] !== 8'd127)) begin
                    fail("Tensor-to-GEMM payload or scale mismatch");
                end
            end
            dense_burst_cycles <= dense_burst_cycles + 1;
            dense_burst_active <=
                (dense_burst_cycles + 1) < K_ELEMENTS;
            if (scenario_id == 4'd1) begin
                external_dense_cycles <= external_dense_cycles + 1;
            end else if (scenario_id == 4'd2) begin
                feedback_dense_cycles <= feedback_dense_cycles + 1;
            end
            end
        end
    end

    always @(negedge clk_i) begin
        integer cycle_beats;
        integer beat_index;
        npu_post_result_beat_t beat;
        npu_post_command_t command;
        if (!rst_i && !clear_i && (scenario_id == 4'd1)) begin
            if (external_result_active && !(|gemm_vector_valid)) begin
                fail("GEMM-to-Vector external plane contains a cycle bubble");
            end
            if (|gemm_vector_valid) begin
            if (scenario_id != 4'd1) begin
                fail("unexpected external Vector result route");
            end
            if (!(&gemm_vector_valid)) begin
                fail("GEMM-to-Vector external plane contains a bubble");
            end
            cycle_beats = 0;
            for (integer channel = 0; channel < ARRAY_DIM; channel++) begin
                if (gemm_vector_valid[channel]) begin
                    cycle_beats = cycle_beats + 1;
                    beat = npu_post_result_beat_t'(
                        gemm_vector_result[
                            channel*NPU_POST_RESULT_WIDTH +:
                            NPU_POST_RESULT_WIDTH]);
                    command = npu_post_command_t'(
                        gemm_vector_command[
                            channel*NPU_POST_COMMAND_WIDTH +:
                            NPU_POST_COMMAND_WIDTH]);
                    if ((^beat === 1'bx) || (^command === 1'bx)) begin
                        fail("external Vector beat contains X");
                    end
                    if ((beat.job_id != expected_job_id) ||
                        (beat.payload_kind != NPU_PAYLOAD_MX_VECTOR) ||
                        (beat.mx_format != mxfp_pkg::MXFP8_E4M3) ||
                        (beat.mx_scale != EXPECTED_MX_SCALE) ||
                        (beat.invalid != '0) ||
                        (beat.row >= MATRIX_SIZE) ||
                        (beat.segment >= 5'd16) ||
                        (command.route != NPU_POST_VECTOR) ||
                        (command.vector_result_route !=
                         NPU_VECTOR_TO_EXTERNAL)) begin
                        $display("external metadata: job=%h kind=%0d format=%0d scale=%0d invalid=%h row=%0d segment=%0d route=%0d vector_route=%0d",
                            beat.job_id, beat.payload_kind, beat.mx_format,
                            beat.mx_scale, beat.invalid, beat.row,
                            beat.segment, command.route,
                            command.vector_result_route);
                        fail("external Vector metadata mismatch");
                    end
                    for (integer lane = 0; lane < 16; lane++) begin
                        if (beat.data[lane*8 +: 8] !== EXPECTED_MX_DATA) begin
                            fail("external Vector MX payload mismatch");
                        end
                    end
                    if (beat.data[511:128] != '0) begin
                        fail("external Vector MX upper payload is not zero");
                    end
                    beat_index = integer'(beat.row)*16 +
                        integer'(beat.segment);
                    if ((beat_index < 0) ||
                        (beat_index >= RESULT_BEATS)) begin
                        fail("external Vector coordinate out of range");
                    end
                    if (external_seen[beat_index]) begin
                        fail("duplicate external Vector coordinate");
                    end
                    external_seen[beat_index] <= 1'b1;
                end
            end
            external_result_beats <= external_result_beats + cycle_beats;
            external_result_active <=
                (external_result_beats + cycle_beats) < RESULT_BEATS;
            end
        end
    end

    always @(negedge clk_i) begin
        integer cycle_beats;
        integer beat_index;
        npu_post_result_beat_t beat;
        npu_post_command_t command;
        if (!rst_i && !clear_i && (scenario_id == 4'd2)) begin
            if (feedback_result_active && !(|gemm_feedback_valid)) begin
                fail("Vector-to-feedback plane contains a cycle bubble");
            end
            if (|gemm_feedback_valid) begin
            if (scenario_id != 4'd2) begin
                fail("unexpected Vector feedback route");
            end
            if (!(&gemm_feedback_valid) ||
                !(&u_dut.feedback_writer_ready)) begin
                fail("Vector-to-feedback plane contains a bubble");
            end
            cycle_beats = 0;
            for (integer channel = 0; channel < ARRAY_DIM; channel++) begin
                if (gemm_feedback_valid[channel] &&
                    u_dut.feedback_writer_ready[channel]) begin
                    cycle_beats = cycle_beats + 1;
                    beat = npu_post_result_beat_t'(
                        gemm_feedback_result[
                            channel*NPU_POST_RESULT_WIDTH +:
                            NPU_POST_RESULT_WIDTH]);
                    command = npu_post_command_t'(
                        gemm_feedback_command[
                            channel*NPU_POST_COMMAND_WIDTH +:
                            NPU_POST_COMMAND_WIDTH]);
                    if ((^beat === 1'bx) || (^command === 1'bx)) begin
                        fail("Vector feedback beat contains X");
                    end
                    if ((beat.job_id != expected_job_id) ||
                        (beat.payload_kind != NPU_PAYLOAD_FP32_VECTOR) ||
                        (beat.invalid != '0) ||
                        (beat.row >= MATRIX_SIZE) ||
                        (beat.segment >= 5'd16) ||
                        (command.route != NPU_POST_VECTOR) ||
                        (command.vector_result_route !=
                         NPU_VECTOR_TO_FEEDBACK) ||
                        (command.destination_buffer_id !=
                         FEEDBACK_BUFFER_ID) ||
                        (command.destination_format !=
                         mxfp_pkg::MXFP8_E4M3)) begin
                        fail("Vector feedback metadata mismatch");
                    end
                    for (integer lane = 0; lane < 16; lane++) begin
                        if (beat.data[lane*32 +: 32] !== EXPECTED_FP32) begin
                            fail("Vector feedback FP32 payload mismatch");
                        end
                    end
                    beat_index = integer'(beat.row)*16 +
                        integer'(beat.segment);
                    if ((beat_index < 0) ||
                        (beat_index >= RESULT_BEATS)) begin
                        fail("Vector feedback coordinate out of range");
                    end
                    if (feedback_seen[beat_index]) begin
                        fail("duplicate Vector feedback coordinate");
                    end
                    feedback_seen[beat_index] <= 1'b1;
                end
            end
            feedback_result_beats <= feedback_result_beats + cycle_beats;
            feedback_result_active <=
                (feedback_result_beats + cycle_beats) < RESULT_BEATS;
            end
        end
    end

    always @(negedge clk_i) begin
        if (!rst_i && !clear_i && status_valid) begin
            if (^status_decoded === 1'bx) begin
                fail("task completion status contains X");
            end
            if (!status_decoded.success ||
                (status_decoded.code != NPU_TASK_STATUS_OK)) begin
                fail("task completion status reported failure");
            end
            if (status_decoded.job_id != expected_job_id) begin
                fail("task completion job ID mismatch");
            end
            status_count <= status_count + 1;
        end
    end

    initial begin
        npu_task_descriptor_t descriptor;
        integer completed_tasks;

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        descriptor_write_valid = 1'b0;
        descriptor_write_index = '0;
        descriptor_write_data = '0;
        descriptor_submit_valid = 1'b0;
        descriptor_submit_index = '0;
        scenario_id = 4'd0;
        external_seen = '0;
        feedback_seen = '0;
        check_feedback_memory = 1'b0;
        expected_job_id = '0;
        dense_burst_active = 1'b0;
        external_result_active = 1'b0;
        feedback_result_active = 1'b0;
        dense_burst_cycles = 0;
        external_dense_cycles = 0;
        feedback_dense_cycles = 0;
        external_result_beats = 0;
        feedback_result_beats = 0;
        status_count = 0;
        total_dense_cycles = 0;
        total_external_result_beats = 0;
        total_feedback_result_beats = 0;
        completed_tasks = 0;

        repeat (12) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        repeat (12) @(posedge clk_i);

        for (integer task_pair = 0; task_pair < TASK_PAIRS;
             task_pair++) begin
            @(negedge clk_i);
            scenario_id = 4'd0;
            external_seen = '0;
            external_dense_cycles = 0;
            external_result_beats = 0;
            dense_burst_cycles = 0;
            dense_burst_active = 1'b0;
            external_result_active = 1'b0;
            expected_job_id = JOB_ID_BASE + 16'(2*task_pair);
            descriptor = make_square_gemm_descriptor(
                expected_job_id, MATRIX_SIZE);
            descriptor.k_blocks = 16'(K_ELEMENTS/32);
            descriptor.activation_buffer_id = 4'd0;
            descriptor.weight_buffer_id = 4'd0;
            descriptor.activation_format = mxfp_pkg::MXFP8_E4M3;
            descriptor.weight_format = mxfp_pkg::MXFP8_E4M3;
            descriptor.post_route = NPU_POST_VECTOR;
            descriptor.vector_control.operation =
                vector_pkg::VECTOR_ENGINE_OP_EPILOGUE;
            descriptor.vector_control.lane_mask = 16'hffff;
            descriptor.vector_result_route = NPU_VECTOR_TO_EXTERNAL;
            descriptor.output_format = NPU_OUTPUT_MX;
            descriptor.output_mx_format = mxfp_pkg::MXFP8_E4M3;
            scenario_id = 4'd1;
            send_descriptor(4'(2*task_pair), descriptor);
            completed_tasks = completed_tasks + 1;
            while (status_count < completed_tasks) @(posedge clk_i);
            while (busy) @(posedge clk_i);
            repeat (8) @(posedge clk_i);

            if ((dense_burst_cycles != K_ELEMENTS) ||
                dense_burst_active ||
                (external_dense_cycles != K_ELEMENTS) ||
                (external_result_beats != RESULT_BEATS) ||
                external_result_active || !(&external_seen)) begin
                fail("K=8192 external heterogeneous count mismatch");
            end
            total_dense_cycles = total_dense_cycles +
                longint'(external_dense_cycles);
            total_external_result_beats = total_external_result_beats +
                longint'(external_result_beats);

            @(negedge clk_i);
            scenario_id = 4'd0;
            feedback_seen = '0;
            feedback_dense_cycles = 0;
            feedback_result_beats = 0;
            dense_burst_cycles = 0;
            dense_burst_active = 1'b0;
            feedback_result_active = 1'b0;
            expected_job_id = JOB_ID_BASE + 16'(2*task_pair + 1);
            descriptor = make_square_gemm_descriptor(
                expected_job_id, MATRIX_SIZE);
            descriptor.k_blocks = 16'(K_ELEMENTS/32);
            descriptor.activation_buffer_id = 4'd0;
            descriptor.weight_buffer_id = 4'd0;
            descriptor.output_buffer_id = FEEDBACK_BUFFER_ID;
            descriptor.activation_format = mxfp_pkg::MXFP8_E4M3;
            descriptor.weight_format = mxfp_pkg::MXFP8_E4M3;
            descriptor.post_route = NPU_POST_VECTOR;
            descriptor.vector_control.operation =
                vector_pkg::VECTOR_ENGINE_OP_EPILOGUE;
            descriptor.vector_control.lane_mask = 16'hffff;
            descriptor.vector_result_route = NPU_VECTOR_TO_FEEDBACK;
            descriptor.output_format = NPU_OUTPUT_MX;
            descriptor.output_mx_format = mxfp_pkg::MXFP8_E4M3;
            descriptor.feedback_operand = 1'b0;
            descriptor.feedback_transpose = 1'b0;
            scenario_id = 4'd2;
            send_descriptor(4'(2*task_pair + 1), descriptor);
            completed_tasks = completed_tasks + 1;
            while (status_count < completed_tasks) @(posedge clk_i);
            while (busy) @(posedge clk_i);
            repeat (8) @(posedge clk_i);

            if ((dense_burst_cycles != K_ELEMENTS) ||
                dense_burst_active ||
                (feedback_dense_cycles != K_ELEMENTS) ||
                (feedback_result_beats != RESULT_BEATS) ||
                feedback_result_active || !(&feedback_seen)) begin
                fail("K=8192 Vector feedback count mismatch");
            end
            total_dense_cycles = total_dense_cycles +
                longint'(feedback_dense_cycles);
            total_feedback_result_beats = total_feedback_result_beats +
                longint'(feedback_result_beats);
        end
        check_feedback_memory = 1'b1;
        #1;
        check_feedback_memory = 1'b0;
        if ((|gemm_output_valid) || protocol_error) begin
            fail("unexpected direct output or sticky protocol error");
        end

        if ((total_dense_cycles != longint'(TOTAL_TASKS)*K_ELEMENTS) ||
            (TOTAL_OPERAND_BYTES < longint'(MIN_OPERAND_BYTES))) begin
            fail("aggregate traffic threshold mismatch");
        end
        $display("PASS: heterogeneous stream K=8192 tasks=%0d dense_cycles=%0d input_pairs=%0d operand_bytes=%0d external_beats=%0d feedback_beats=%0d no_bubble=1",
            TOTAL_TASKS, total_dense_cycles, TOTAL_INPUT_PAIRS,
            TOTAL_OPERAND_BYTES, total_external_result_beats,
            total_feedback_result_beats);
        $finish;
    end

    initial begin
        repeat (TIMEOUT_CYCLES) @(posedge clk_i);
        fail("timeout");
    end

    wire _unused_outputs = &{1'b0, tensor_write_ready,
        vector_operand_write_ready, gemm_output_result,
        gemm_output_command};

endmodule

`default_nettype wire
