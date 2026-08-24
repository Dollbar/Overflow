`timescale 1ns/1ps
`default_nettype none

module tb_gemm_buffer_stream_peak #(
    parameter int unsigned K_ELEMENTS = 256,
    parameter logic [31:0] EXPECTED_FP32 =
        (K_ELEMENTS == 4096) ? 32'h45800000 : 32'h43800000
);

    localparam int unsigned ARRAY_DIM = 16;
    localparam int unsigned NODE_COUNT = ARRAY_DIM * ARRAY_DIM;
    localparam int unsigned BUFFER_COUNT = 4;
    localparam int unsigned VECTOR_DEPTH = 8192;
    localparam int unsigned INPUT_STORE_BYTES =
        BUFFER_COUNT * ARRAY_DIM * VECTOR_DEPTH * 16;
    localparam int unsigned EXPECTED_VECTOR_BEATS = 4096;
    localparam logic [15:0] JOB_ID = 16'h1310;
    localparam logic [7:0] TASK_TAG = 8'h8a;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic tensor_write_valid;
    logic tensor_write_ready;
    logic tensor_write_weight;
    logic [3:0] tensor_write_buffer_id;
    logic [3:0] tensor_write_bank;
    logic [31:0] tensor_write_offset;
    logic [127:0] tensor_write_data;
    logic [127:0] tensor_write_scale;
    logic activation_read_enable;
    logic [3:0] activation_read_buffer_id;
    logic [31:0] activation_read_offset;
    logic activation_read_valid;
    logic [ARRAY_DIM*128-1:0] activation_read_data;
    logic [ARRAY_DIM*128-1:0] activation_read_scale;
    logic weight_read_enable;
    logic [3:0] weight_read_buffer_id;
    logic [31:0] weight_read_offset;
    logic weight_read_valid;
    logic [ARRAY_DIM*128-1:0] weight_read_data;
    logic [ARRAY_DIM*128-1:0] weight_read_scale;
    logic tensor_protocol_error;
    logic [ARRAY_DIM-1:0] feedback_write_ready;

    npu_scheduler_pkg::npu_gemm_command_t gemm_command;
    npu_scheduler_pkg::npu_buffer_read_command_t activation_command;
    npu_scheduler_pkg::npu_buffer_read_command_t weight_command;
    npu_scheduler_pkg::npu_result_command_t result_command;
    logic gemm_command_valid;
    logic gemm_command_ready;
    logic activation_command_valid;
    logic activation_command_ready;
    logic weight_command_valid;
    logic weight_command_ready;
    logic result_command_valid;
    logic result_command_ready;

    logic [ARRAY_DIM*16-1:0] wave_a_valid;
    logic [ARRAY_DIM*128-1:0] wave_a_data;
    logic [ARRAY_DIM*32-1:0] wave_a_format;
    logic [ARRAY_DIM*128-1:0] wave_a_scale;
    logic [ARRAY_DIM*16-1:0] wave_a_block_first;
    logic [ARRAY_DIM*16-1:0] wave_a_block_last;
    logic [ARRAY_DIM*16-1:0] wave_a_matrix_first;
    logic [ARRAY_DIM*16-1:0] wave_a_matrix_last;
    logic [ARRAY_DIM*128-1:0] wave_a_tag;
    logic [ARRAY_DIM*16-1:0] wave_b_valid;
    logic [ARRAY_DIM*128-1:0] wave_b_data;
    logic [ARRAY_DIM*32-1:0] wave_b_format;
    logic [ARRAY_DIM*128-1:0] wave_b_scale;

    logic [NODE_COUNT-1:0] executor_result_ready;
    logic [NODE_COUNT*512-1:0] executor_result_data_tieoff;
    logic [NODE_COUNT*16-1:0] executor_result_invalid_tieoff;
    logic [NODE_COUNT*8-1:0] executor_result_tag_tieoff;
    logic [NODE_COUNT*4-1:0] executor_result_row_tieoff;
    logic [NODE_COUNT-1:0] gemm_result_valid;
    logic [NODE_COUNT*512-1:0] gemm_result_data;
    logic [NODE_COUNT*16-1:0] gemm_result_invalid;
    logic [NODE_COUNT*8-1:0] gemm_result_tag;
    logic [NODE_COUNT*4-1:0] gemm_result_row;
    logic [NODE_COUNT*6-1:0] gemm_result_level;
    logic [NODE_COUNT-1:0] input_pair_issue;
    logic [NODE_COUNT-1:0] output_overflow;

    logic [ARRAY_DIM-1:0] vector_result_valid;
    logic [ARRAY_DIM*512-1:0] vector_result_data;
    logic [ARRAY_DIM*16-1:0] vector_result_invalid;
    logic [ARRAY_DIM*16-1:0] vector_result_job_id;
    logic [ARRAY_DIM*8-1:0] vector_result_tag;
    logic [ARRAY_DIM*16-1:0] vector_result_row;
    logic [ARRAY_DIM*5-1:0] vector_result_segment;
    logic [ARRAY_DIM-1:0] vector_result_last;
    logic completion_valid;
    logic [7:0] completion_tag;
    logic completion_success;
    logic executor_busy;
    logic executor_protocol_error;

    logic [3:0] scenario_id;
    integer dense_input_cycles;
    integer dense_input_values;
    integer observed_result_beats;
    integer checked_values;
    integer peak_result_beats;
    logic [3:0] expected_row_q [0:NODE_COUNT-1];

    assign executor_result_data_tieoff = {NODE_COUNT{512'd0}};
    assign executor_result_invalid_tieoff = {NODE_COUNT{16'd0}};
    assign executor_result_tag_tieoff = {NODE_COUNT{8'd0}};
    assign executor_result_row_tieoff = {NODE_COUNT{4'd0}};

    // Initialize only the verification SRAM model so the throughput test does
    // not spend thousands of cycles evaluating an idle 65,536-PE array while
    // serializing the preload through the scalar maintenance write port.
    generate
        for (genvar init_bank = 0; init_bank < ARRAY_DIM;
             init_bank++) begin : g_model_preload
            initial begin
                for (integer k_index = 0; k_index < K_ELEMENTS; k_index++) begin
                    u_buffer.g_bank[init_bank].u_activation_data.memory[k_index] =
                        {16{8'h38}};
                    u_buffer.g_bank[init_bank].u_activation_scale.memory[k_index] =
                        {16{8'd127}};
                    u_buffer.g_bank[init_bank].u_weight_data.memory[k_index] =
                        {16{8'h38}};
                    u_buffer.g_bank[init_bank].u_weight_scale.memory[k_index] =
                        {16{8'd127}};
                end
            end
        end
    endgenerate

    npu_local_tensor_buffer #(
        .BUFFER_COUNT(BUFFER_COUNT),
        .BANKS(ARRAY_DIM),
        .VECTOR_DEPTH(VECTOR_DEPTH)
    ) u_buffer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .tensor_write_valid_i(tensor_write_valid),
        .tensor_write_ready_o(tensor_write_ready),
        .tensor_write_weight_i(tensor_write_weight),
        .tensor_write_buffer_id_i(tensor_write_buffer_id),
        .tensor_write_bank_i(tensor_write_bank),
        .tensor_write_offset_i(tensor_write_offset),
        .tensor_write_data_i(tensor_write_data),
        .tensor_write_scale_i(tensor_write_scale),
        .feedback_write_valid_i('0),
        .feedback_write_ready_o(feedback_write_ready),
        .feedback_write_buffer_id_i('0),
        .feedback_write_offset_i('0),
        .feedback_write_data_i('0),
        .feedback_write_scale_i('0),
        .activation_read_enable_i(activation_read_enable),
        .activation_read_buffer_id_i(activation_read_buffer_id),
        .activation_read_offset_i(activation_read_offset),
        .activation_read_valid_o(activation_read_valid),
        .activation_read_data_o(activation_read_data),
        .activation_read_scale_o(activation_read_scale),
        .weight_read_enable_i(weight_read_enable),
        .weight_read_buffer_id_i(weight_read_buffer_id),
        .weight_read_offset_i(weight_read_offset),
        .weight_read_valid_o(weight_read_valid),
        .weight_read_data_o(weight_read_data),
        .weight_read_scale_o(weight_read_scale),
        .protocol_error_o(tensor_protocol_error)
    );

    npu_square_gemm_executor #(
        .ARRAY_DIM(ARRAY_DIM)
    ) u_executor (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .gemm_command_valid_i(gemm_command_valid),
        .gemm_command_ready_o(gemm_command_ready),
        .gemm_command_i(gemm_command),
        .activation_command_valid_i(activation_command_valid),
        .activation_command_ready_o(activation_command_ready),
        .activation_command_i(activation_command),
        .weight_command_valid_i(weight_command_valid),
        .weight_command_ready_o(weight_command_ready),
        .weight_command_i(weight_command),
        .result_command_valid_i(result_command_valid),
        .result_command_ready_o(result_command_ready),
        .result_command_i(result_command),
        .activation_read_enable_o(activation_read_enable),
        .activation_read_buffer_id_o(activation_read_buffer_id),
        .activation_read_offset_o(activation_read_offset),
        .activation_read_valid_i(activation_read_valid),
        .activation_read_data_i(activation_read_data),
        .activation_read_scale_i(activation_read_scale),
        .weight_read_enable_o(weight_read_enable),
        .weight_read_buffer_id_o(weight_read_buffer_id),
        .weight_read_offset_o(weight_read_offset),
        .weight_read_valid_i(weight_read_valid),
        .weight_read_data_i(weight_read_data),
        .weight_read_scale_i(weight_read_scale),
        .wave_a_valid_o(wave_a_valid),
        .wave_a_data_o(wave_a_data),
        .wave_a_format_o(wave_a_format),
        .wave_a_scale_o(wave_a_scale),
        .wave_a_block_first_o(wave_a_block_first),
        .wave_a_block_last_o(wave_a_block_last),
        .wave_a_matrix_first_o(wave_a_matrix_first),
        .wave_a_matrix_last_o(wave_a_matrix_last),
        .wave_a_tag_o(wave_a_tag),
        .wave_b_valid_o(wave_b_valid),
        .wave_b_data_o(wave_b_data),
        .wave_b_format_o(wave_b_format),
        .wave_b_scale_o(wave_b_scale),
        .result_ready_o(executor_result_ready),
        .result_valid_i('0),
        .result_data_i(executor_result_data_tieoff),
        .result_invalid_i(executor_result_invalid_tieoff),
        .result_tag_i(executor_result_tag_tieoff),
        .result_row_i(executor_result_row_tieoff),
        .vector_result_valid_o(vector_result_valid),
        .vector_result_ready_i('1),
        .vector_result_data_o(vector_result_data),
        .vector_result_invalid_o(vector_result_invalid),
        .vector_result_job_id_o(vector_result_job_id),
        .vector_result_tag_o(vector_result_tag),
        .vector_result_row_o(vector_result_row),
        .vector_result_segment_o(vector_result_segment),
        .vector_result_last_o(vector_result_last),
        .completion_valid_o(completion_valid),
        .completion_ready_i(1'b1),
        .completion_tag_o(completion_tag),
        .completion_success_o(completion_success),
        .busy_o(executor_busy),
        .protocol_error_o(executor_protocol_error)
    );

    GEMM_65536 #(
        .ARRAY_X(ARRAY_DIM),
        .ARRAY_Y(ARRAY_DIM),
        .CONTROL_TREE_FANOUT(16)
    ) u_gemm (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .direct_a_valid_i(wave_a_valid),
        .direct_a_data_i(wave_a_data),
        .direct_a_format_i(wave_a_format),
        .direct_a_scale_i(wave_a_scale),
        .direct_a_block_first_i(wave_a_block_first),
        .direct_a_block_last_i(wave_a_block_last),
        .direct_a_matrix_first_i(wave_a_matrix_first),
        .direct_a_matrix_last_i(wave_a_matrix_last),
        .direct_a_tag_i(wave_a_tag),
        .direct_b_valid_i(wave_b_valid),
        .direct_b_data_i(wave_b_data),
        .direct_b_format_i(wave_b_format),
        .direct_b_scale_i(wave_b_scale),
        .result_ready_i('1),
        .result_valid_o(gemm_result_valid),
        .result_data_o(gemm_result_data),
        .result_invalid_o(gemm_result_invalid),
        .result_tag_o(gemm_result_tag),
        .result_row_o(gemm_result_row),
        .result_level_o(gemm_result_level),
        .input_pair_issue_o(input_pair_issue),
        .output_overflow_o(output_overflow)
    );

    always #2 clk_i = ~clk_i;

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    always @(negedge clk_i) begin
        if (rst_i || clear_i) begin
            dense_input_cycles <= 0;
            dense_input_values <= 0;
        end else if ((|wave_a_valid) || (|wave_b_valid)) begin
            if (!(&wave_a_valid) || !(&wave_b_valid)) begin
                fail("GEMM boundary input contains a lane bubble");
            end
            for (integer lane = 0; lane < ARRAY_DIM*16; lane++) begin
                if ((wave_a_data[lane*8 +: 8] !== 8'h38) ||
                    (wave_b_data[lane*8 +: 8] !== 8'h38) ||
                    (wave_a_scale[lane*8 +: 8] !== 8'd127) ||
                    (wave_b_scale[lane*8 +: 8] !== 8'd127)) begin
                    fail("buffer-to-GEMM input payload mismatch");
                end
            end
            dense_input_cycles <= dense_input_cycles + 1;
            dense_input_values <= dense_input_values + ARRAY_DIM*16;
        end
    end

    always @(negedge clk_i) begin
        integer cycle_beats;
        if (rst_i || clear_i) begin
            observed_result_beats <= 0;
            checked_values <= 0;
            peak_result_beats <= 0;
            for (integer node = 0; node < NODE_COUNT; node++) begin
                expected_row_q[node] <= '0;
            end
        end else begin
            cycle_beats = 0;
            for (integer node = 0; node < NODE_COUNT; node++) begin
                if (gemm_result_valid[node]) begin
                    cycle_beats = cycle_beats + 1;
                    if (gemm_result_tag[node*8 +: 8] !== TASK_TAG ||
                        gemm_result_row[node*4 +: 4] !== expected_row_q[node] ||
                        gemm_result_invalid[node*16 +: 16] != 16'd0) begin
                        fail("GEMM result metadata mismatch");
                    end
                    for (integer lane = 0; lane < 16; lane++) begin
                        if (gemm_result_data[
                            node*512 + lane*32 +: 32] !== EXPECTED_FP32) begin
                            fail("buffer-to-GEMM numeric mismatch");
                        end
                    end
                    expected_row_q[node] <= expected_row_q[node] + 4'd1;
                end
            end
            observed_result_beats <= observed_result_beats + cycle_beats;
            checked_values <= checked_values + cycle_beats*16;
            if (cycle_beats > peak_result_beats) begin
                peak_result_beats <= cycle_beats;
            end
        end
    end

    initial begin
        assert (INPUT_STORE_BYTES == 8*1024*1024)
            else $error("configured input store is not 8 MiB");
        assert ((K_ELEMENTS == 256) || (K_ELEMENTS == 4096))
            else $error("buffer-stream regression supports K=256 or K=4096");
        assert ((K_ELEMENTS % 32) == 0)
            else $error("K_ELEMENTS must contain complete 32-element MX blocks");

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        tensor_write_valid = 1'b0;
        tensor_write_weight = 1'b0;
        tensor_write_buffer_id = '0;
        tensor_write_bank = '0;
        tensor_write_offset = '0;
        tensor_write_data = {16{8'h38}};
        tensor_write_scale = {16{8'd127}};
        gemm_command_valid = 1'b0;
        activation_command_valid = 1'b0;
        weight_command_valid = 1'b0;
        result_command_valid = 1'b0;
        gemm_command = '0;
        activation_command = '0;
        weight_command = '0;
        result_command = '0;
        scenario_id = 4'd0;

        repeat (12) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        repeat (12) @(posedge clk_i);

        scenario_id = 4'd1;
        gemm_command.job_id = JOB_ID;
        gemm_command.tag = TASK_TAG;
        gemm_command.k_blocks = 16'(K_ELEMENTS / 32);
        gemm_command.matrix_size = 16'd256;
        gemm_command.activation_format = mxfp_pkg::MXFP8_E4M3;
        gemm_command.weight_format = mxfp_pkg::MXFP8_E4M3;
        activation_command.job_id = JOB_ID;
        activation_command.tag = TASK_TAG;
        activation_command.buffer_id = 4'd0;
        activation_command.base_offset = 32'd0;
        activation_command.matrix_size = 16'd256;
        activation_command.format = mxfp_pkg::MXFP8_E4M3;
        weight_command = activation_command;
        result_command.job_id = JOB_ID;
        result_command.tag = TASK_TAG;
        result_command.matrix_size = 16'd256;
        result_command.vectors_per_row = 5'd16;

        @(negedge clk_i);
        gemm_command_valid = 1'b1;
        activation_command_valid = 1'b1;
        weight_command_valid = 1'b1;
        result_command_valid = 1'b1;
        do begin
            @(posedge clk_i);
        end while (!(gemm_command_ready && activation_command_ready &&
                     weight_command_ready && result_command_ready));
        @(negedge clk_i);
        gemm_command_valid = 1'b0;
        activation_command_valid = 1'b0;
        weight_command_valid = 1'b0;
        result_command_valid = 1'b0;

        scenario_id = 4'd2;
        while (observed_result_beats < EXPECTED_VECTOR_BEATS) @(posedge clk_i);
        repeat (8) @(posedge clk_i);

        if (dense_input_cycles != K_ELEMENTS ||
            dense_input_values != K_ELEMENTS*ARRAY_DIM*16) begin
            $display("dense_input_cycles=%0d dense_input_values=%0d",
                dense_input_cycles, dense_input_values);
            fail("GEMM did not receive K dense cycles of 256 values");
        end
        if (observed_result_beats != EXPECTED_VECTOR_BEATS ||
            checked_values != 65536) begin
            fail("buffer-to-GEMM result count mismatch");
        end
        if (peak_result_beats < ARRAY_DIM) begin
            fail("GEMM result plane did not reach sixteen beats per cycle");
        end
        if (tensor_protocol_error || executor_protocol_error ||
            (|output_overflow)) begin
            fail("protocol error or output overflow asserted");
        end
        $display("PASS: 8MiB A/B buffers K=%0d dense_cycles=%0d values_per_cycle=256 input_pairs=%0d results=%0d peak_results=%0d peak_tops_1ghz=131.072",
            K_ELEMENTS, dense_input_cycles, dense_input_values,
            checked_values, peak_result_beats);
        $finish;
    end

    initial begin
        repeat (30000) @(posedge clk_i);
        fail("timeout");
    end

    wire _unused_status = &{
        1'b0, gemm_result_level, input_pair_issue, executor_result_ready,
        feedback_write_ready, tensor_write_ready, vector_result_valid,
        vector_result_data,
        vector_result_invalid, vector_result_job_id, vector_result_tag,
        vector_result_row, vector_result_segment, vector_result_last,
        completion_valid, completion_tag, completion_success, executor_busy
    };

endmodule

`default_nettype wire
