`timescale 1ns/1ps
`default_nettype none

module tb_npu_independent_vector_path;
    import mxfp_pkg::*;
    import vector_pkg::*;
    import npu_scheduler_pkg::*;
    import npu_gemm_vector_tb_pkg::*;

    localparam int unsigned ARRAY_DIM = 2;
    localparam int unsigned BUFFER_COUNT = 2;
    localparam int unsigned VECTOR_DEPTH = 64;
    localparam int unsigned INDEX_WIDTH = 2;
    localparam logic [15:0] MATRIX_SIZE = 16'd18;
    localparam int unsigned VECTORS_PER_ROW = 2;
    localparam int unsigned EXPECTED_BEATS = MATRIX_SIZE * VECTORS_PER_ROW;
    localparam logic [15:0] JOB_ID = 16'hb101;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic command_valid;
    logic command_ready;
    logic command_submit;
    logic [INDEX_WIDTH-1:0] command_index;
    logic [NPU_TASK_DESCRIPTOR_WIDTH-1:0] command_descriptor;
    logic descriptor_write_valid;
    logic descriptor_write_ready;
    logic [INDEX_WIDTH-1:0] descriptor_write_index;
    logic [NPU_TASK_DESCRIPTOR_WIDTH-1:0] descriptor_write_data;
    logic descriptor_submit_valid;
    logic descriptor_submit_ready;
    logic [INDEX_WIDTH-1:0] descriptor_submit_index;
    logic [31:0] descriptor_transaction_count;

    logic tensor_write_valid;
    logic tensor_write_ready;
    logic tensor_write_weight;
    logic [NPU_BUFFER_ID_WIDTH-1:0] tensor_write_buffer_id;
    logic [$clog2(ARRAY_DIM)-1:0] tensor_write_bank;
    logic [NPU_BUFFER_OFFSET_WIDTH-1:0] tensor_write_offset;
    logic [127:0] tensor_write_data;
    logic [127:0] tensor_write_scale;
    logic vector_operand_write_ready;

    logic [ARRAY_DIM-1:0] gemm_output_valid;
    logic [ARRAY_DIM*NPU_POST_RESULT_WIDTH-1:0] gemm_output_result;
    logic [ARRAY_DIM*NPU_POST_COMMAND_WIDTH-1:0] gemm_output_command;
    logic [ARRAY_DIM-1:0] vector_result_valid;
    logic [ARRAY_DIM-1:0] vector_result_ready;
    logic [ARRAY_DIM*NPU_POST_RESULT_WIDTH-1:0] vector_result;
    logic [ARRAY_DIM*NPU_POST_COMMAND_WIDTH-1:0] vector_result_command;
    logic [ARRAY_DIM-1:0] feedback_valid;
    logic [ARRAY_DIM*NPU_POST_RESULT_WIDTH-1:0] feedback_result;
    logic [ARRAY_DIM*NPU_POST_COMMAND_WIDTH-1:0] feedback_command;
    logic [ARRAY_DIM-1:0] sink_accept_enable;
    logic [ARRAY_DIM-1:0] sink_monitor_valid;
    logic [ARRAY_DIM*NPU_POST_RESULT_WIDTH-1:0] sink_monitor_result;
    logic [ARRAY_DIM*NPU_POST_COMMAND_WIDTH-1:0] sink_monitor_command;
    logic [31:0] sink_transaction_count;
    logic sink_protocol_error;

    logic status_valid;
    logic [NPU_TASK_STATUS_WIDTH-1:0] status;
    logic busy;
    logic protocol_error;
    logic [EXPECTED_BEATS-1:0] seen;
    logic [NPU_TAG_WIDTH-1:0] observed_tag;
    logic observed_tag_valid;
    integer cycle_count;
    integer accepted_beats;
    integer check_count;

    npu_descriptor_source_vip #(
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_descriptor_source (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .command_valid_i(command_valid), .command_ready_o(command_ready),
        .command_submit_i(command_submit), .command_index_i(command_index),
        .command_descriptor_i(command_descriptor),
        .write_valid_o(descriptor_write_valid),
        .write_ready_i(descriptor_write_ready),
        .write_index_o(descriptor_write_index),
        .write_descriptor_o(descriptor_write_data),
        .submit_valid_o(descriptor_submit_valid),
        .submit_ready_i(descriptor_submit_ready),
        .submit_index_o(descriptor_submit_index),
        .transaction_count_o(descriptor_transaction_count)
    );

    npu_vector_result_sink_vip #(
        .CHANNELS(ARRAY_DIM)
    ) u_vector_sink (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .accept_enable_i(sink_accept_enable),
        .source_valid_i(vector_result_valid),
        .source_ready_o(vector_result_ready),
        .source_result_i(vector_result),
        .source_command_i(vector_result_command),
        .monitor_valid_o(sink_monitor_valid),
        .monitor_result_o(sink_monitor_result),
        .monitor_command_o(sink_monitor_command),
        .transaction_count_o(sink_transaction_count),
        .protocol_error_o(sink_protocol_error)
    );

    npu_square_gemm_system #(
        .ARRAY_DIM(ARRAY_DIM),
        .BUFFER_COUNT(BUFFER_COUNT),
        .DESCRIPTOR_ENTRIES(4),
        .TENSOR_VECTOR_DEPTH(VECTOR_DEPTH),
        .TASK_SLOTS(4),
        .ACTIVE_CONTEXTS(4),
        .COMMAND_FIFO_DEPTH(2)
    ) u_dut (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .descriptor_write_valid_i(descriptor_write_valid),
        .descriptor_write_ready_o(descriptor_write_ready),
        .descriptor_write_index_i(descriptor_write_index),
        .descriptor_write_data_i(descriptor_write_data),
        .descriptor_submit_valid_i(descriptor_submit_valid),
        .descriptor_submit_ready_o(descriptor_submit_ready),
        .descriptor_submit_index_i(descriptor_submit_index),
        .tensor_write_valid_i(tensor_write_valid),
        .tensor_write_ready_o(tensor_write_ready),
        .tensor_write_weight_i(tensor_write_weight),
        .tensor_write_buffer_id_i(tensor_write_buffer_id),
        .tensor_write_bank_i(tensor_write_bank),
        .tensor_write_offset_i(tensor_write_offset),
        .tensor_write_data_i(tensor_write_data),
        .tensor_write_scale_i(tensor_write_scale),
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
        .gemm_vector_valid_o(vector_result_valid),
        .gemm_vector_ready_i(vector_result_ready),
        .gemm_vector_result_o(vector_result),
        .gemm_vector_command_o(vector_result_command),
        .gemm_feedback_valid_o(feedback_valid),
        .gemm_feedback_ready_i('1),
        .gemm_feedback_result_o(feedback_result),
        .gemm_feedback_command_o(feedback_command),
        .event_set_valid_i(1'b0), .event_set_id_i('0),
        .event_clear_valid_i(1'b0), .event_clear_id_i('0),
        .status_valid_o(status_valid), .status_ready_i(1'b1),
        .status_o(status), .busy_o(busy),
        .protocol_error_o(protocol_error)
    );

    always #2 clk_i = ~clk_i;

    task automatic send_descriptor_command(
        input logic submit,
        input npu_task_descriptor_t descriptor
    );
        begin
            @(negedge clk_i);
            command_submit = submit;
            command_index = '0;
            command_descriptor = descriptor;
            command_valid = 1'b1;
            while (!command_ready) @(negedge clk_i);
            @(negedge clk_i);
            command_valid = 1'b0;
            command_submit = 1'b0;
            command_descriptor = '0;
        end
    endtask

    task automatic write_activation_word(
        input logic [$clog2(ARRAY_DIM)-1:0] bank,
        input logic [31:0] offset,
        input logic [7:0] element_value
    );
        begin
            @(negedge clk_i);
            tensor_write_bank = bank;
            tensor_write_offset = offset;
            tensor_write_data = {16{element_value}};
            tensor_write_valid = 1'b1;
            while (!tensor_write_ready) @(negedge clk_i);
            @(negedge clk_i);
            tensor_write_valid = 1'b0;
        end
    endtask

    always @(posedge clk_i) begin
        cycle_count <= cycle_count + 1;
        if (!rst_i && !clear_i) begin
            sink_accept_enable[0] <= cycle_count[1:0] != 2'd1;
            // Force the lane-1 backend FIFO to fill so frontend partial-lane
            // retirement and payload stability are exercised.
            sink_accept_enable[1] <= cycle_count[3:0] == 4'd0;
        end
    end

    always @(posedge clk_i) begin
        integer accepted_this_cycle;
        accepted_this_cycle = 0;
        for (integer lane = 0; lane < ARRAY_DIM; lane++) begin
            if (vector_result_valid[lane] && vector_result_ready[lane]) begin
                npu_post_result_beat_t beat;
                /* verilator lint_off UNUSEDSIGNAL */
                npu_post_command_t command;
                /* verilator lint_on UNUSEDSIGNAL */
                integer beat_index;
                beat = npu_post_result_beat_t'(vector_result[
                    lane*NPU_POST_RESULT_WIDTH +: NPU_POST_RESULT_WIDTH]);
                command = npu_post_command_t'(vector_result_command[
                    lane*NPU_POST_COMMAND_WIDTH +: NPU_POST_COMMAND_WIDTH]);
                beat_index = integer'(beat.row) * VECTORS_PER_ROW +
                    integer'(beat.segment);
                if ((beat_index < 0) || (beat_index >= EXPECTED_BEATS) ||
                    seen[beat_index]) begin
                    $fatal(1, "FAIL: standalone Vector duplicate/range row=%0d segment=%0d",
                           beat.row, beat.segment);
                end
                if ((beat.job_id != JOB_ID) || (command.job_id != JOB_ID) ||
                    (beat.tag != command.tag) ||
                    (beat.payload_kind != NPU_PAYLOAD_FP32_VECTOR) ||
                    // FP32 payloads carry canonical zero in the MX-only
                    // metadata fields; input format is not propagated there.
                    (beat.mx_format != mxfp_pkg::mxfp_format_e'(0)) ||
                    (beat.mx_scale != mxfp_pkg::mxfp_scale_t'(0)) ||
                    !command.standalone ||
                    (command.route != NPU_POST_VECTOR) ||
                    (command.vector_control.operation != VECTOR_ENGINE_OP_PASS)) begin
                    $fatal(1, "FAIL: standalone Vector metadata mismatch");
                end
                if (observed_tag_valid && (observed_tag != beat.tag)) begin
                    $fatal(1, "FAIL: standalone Vector tag changed within task");
                end
                observed_tag <= beat.tag;
                observed_tag_valid <= 1'b1;
                for (integer element = 0; element < 16; element++) begin
                    if ((integer'(beat.segment) * 16 + element) < MATRIX_SIZE) begin
                        logic [31:0] expected_value;
                        expected_value = (beat.segment == 5'd0) ?
                            32'h3f80_0000 : 32'h4000_0000;
                        if (beat.data[element*32 +: 32] != expected_value) begin
                            $fatal(1, "FAIL: standalone Vector numeric mismatch row=%0d segment=%0d lane=%0d got=%08x",
                                   beat.row, beat.segment, element,
                                   beat.data[element*32 +: 32]);
                        end
                    end else if (!beat.invalid[element]) begin
                        $fatal(1, "FAIL: standalone Vector tail lane was not masked");
                    end
                end
                if (beat.last != (beat_index == EXPECTED_BEATS-1)) begin
                    $fatal(1, "FAIL: standalone Vector last mismatch");
                end
                seen[beat_index] <= 1'b1;
                accepted_this_cycle = accepted_this_cycle + 1;
            end
        end
        if (accepted_this_cycle != 0) begin
            accepted_beats <= accepted_beats + accepted_this_cycle;
        end
    end

    initial begin
        npu_task_descriptor_t descriptor;
        npu_task_status_t status_fields;

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        command_valid = 1'b0;
        command_submit = 1'b0;
        command_index = '0;
        command_descriptor = '0;
        tensor_write_valid = 1'b0;
        tensor_write_weight = 1'b0;
        tensor_write_buffer_id = '0;
        tensor_write_bank = '0;
        tensor_write_offset = '0;
        tensor_write_data = '0;
        tensor_write_scale = {16{8'd127}};
        sink_accept_enable = '0;
        seen = '0;
        observed_tag = '0;
        observed_tag_valid = 1'b0;
        cycle_count = 0;
        accepted_beats = 0;
        check_count = 0;

        repeat (4) @(negedge clk_i);
        rst_i = 1'b0;
        sink_accept_enable = '1;

        for (integer word_index = 0; word_index < 32; word_index++) begin
            for (integer bank = 0; bank < ARRAY_DIM; bank++) begin
                write_activation_word($clog2(ARRAY_DIM)'(bank),
                                      32'(word_index * 16),
                                      (word_index < 16) ? 8'h38 : 8'h40);
            end
        end
        check_count = check_count + 1;

        descriptor = make_independent_vector_descriptor(
            JOB_ID, MATRIX_SIZE, VECTOR_ENGINE_OP_PASS);
        send_descriptor_command(TB_DESCRIPTOR_WRITE, descriptor);
        send_descriptor_command(TB_DESCRIPTOR_SUBMIT, '0);

        while (!status_valid) @(negedge clk_i);
        status_fields = npu_task_status_t'(status);
        if (!status_fields.success ||
            (status_fields.code != NPU_TASK_STATUS_OK) ||
            (status_fields.job_id != JOB_ID) || !observed_tag_valid ||
            (status_fields.tag != observed_tag)) begin
            $fatal(1, "FAIL: standalone Vector completion status mismatch");
        end
        repeat (4) @(negedge clk_i);
        if ((accepted_beats != EXPECTED_BEATS) || !(&seen) ||
            (sink_transaction_count != EXPECTED_BEATS) ||
            (descriptor_transaction_count != 32'd2) ||
            sink_protocol_error || protocol_error ||
            (|gemm_output_valid) || (|feedback_valid) || busy) begin
            $fatal(1, "FAIL: standalone Vector closure beats=%0d sink=%0d seen=%h busy=%0b protocol=%0b sink_protocol=%0b",
                   accepted_beats, sink_transaction_count, seen, busy,
                   protocol_error, sink_protocol_error);
        end
        check_count = check_count + 1;

        $display("[RTL_SIM PASS] independent_vector matrix=%0d beats=%0d checks=%0d",
                 MATRIX_SIZE, accepted_beats, check_count);
        $finish;
    end

    initial begin
        repeat (20000) @(posedge clk_i);
        $fatal(1, "FAIL: independent Vector path timeout beats=%0d", accepted_beats);
    end

    wire _unused_outputs = &{1'b0, gemm_output_result, gemm_output_command,
        feedback_result, feedback_command, sink_monitor_valid,
        sink_monitor_result, sink_monitor_command, vector_operand_write_ready};

endmodule

`default_nettype wire
