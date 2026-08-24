`timescale 1ns/1ps
`default_nettype none

module tb_npu_gemm_vector_coupler16_peak;
    import mxfp_pkg::*;
    import vector_pkg::*;
    import npu_scheduler_pkg::*;

    localparam int unsigned CHANNELS = 16;
    localparam int unsigned BEATS = 8;
    localparam int unsigned RESULT_WIDTH = NPU_POST_RESULT_WIDTH;
    localparam int unsigned COMMAND_WIDTH = NPU_POST_COMMAND_WIDTH;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic vector_command_valid_i;
    logic vector_command_ready_o;
    logic [NPU_VECTOR_COMMAND_WIDTH-1:0] vector_command_i;
    logic [CHANNELS-1:0] gemm_valid_i;
    logic [CHANNELS-1:0] gemm_ready_o;
    logic [CHANNELS*RESULT_WIDTH-1:0] gemm_result_i;
    logic [CHANNELS*COMMAND_WIDTH-1:0] gemm_command_i;
    logic [CHANNELS-1:0] operand_b_read_enable_o;
    logic [CHANNELS*NPU_BUFFER_ID_WIDTH-1:0] operand_b_read_buffer_id_o;
    logic [CHANNELS*NPU_BUFFER_OFFSET_WIDTH-1:0] operand_b_read_offset_o;
    logic [CHANNELS-1:0] operand_b_read_valid_i;
    logic [CHANNELS*128-1:0] operand_b_read_data_i;
    logic [CHANNELS*8-1:0] operand_b_read_scale_i;
    logic [CHANNELS-1:0] operand_c_read_enable_o;
    logic [CHANNELS*NPU_BUFFER_ID_WIDTH-1:0] operand_c_read_buffer_id_o;
    logic [CHANNELS*NPU_BUFFER_OFFSET_WIDTH-1:0] operand_c_read_offset_o;
    logic [CHANNELS-1:0] operand_c_read_valid_i;
    logic [CHANNELS*128-1:0] operand_c_read_data_i;
    logic [CHANNELS*8-1:0] operand_c_read_scale_i;
    logic [CHANNELS-1:0] result_valid_o;
    logic [CHANNELS-1:0] result_ready_i;
    logic [CHANNELS*RESULT_WIDTH-1:0] result_o;
    logic [CHANNELS*COMMAND_WIDTH-1:0] result_command_o;
    logic completion_valid_o;
    logic completion_ready_i;
    logic [NPU_TAG_WIDTH-1:0] completion_tag_o;
    logic completion_success_o;
    logic completion_feedback_o;
    logic busy_o;
    logic protocol_error_o;
    logic [7:0] scenario_id;
    integer checks;

    npu_vector_command_t vector_command;
    npu_post_result_beat_t gemm_beat [0:CHANNELS-1];
    npu_post_command_t gemm_command [0:CHANNELS-1];
    npu_post_result_beat_t result_beat [0:CHANNELS-1];

    npu_gemm_vector_coupler16 #(
        .CHANNELS(CHANNELS), .CONTEXTS(16), .FIFO_DEPTH(4)
    ) u_dut (.*);

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/npu_gemm_vector_coupler16_peak.vcd");
        $dumpvars(0, tb_npu_gemm_vector_coupler16_peak);
    end
`endif

    always_comb begin
        vector_command_i = vector_command;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            gemm_result_i[channel*RESULT_WIDTH +: RESULT_WIDTH] =
                gemm_beat[channel];
            gemm_command_i[channel*COMMAND_WIDTH +: COMMAND_WIDTH] =
                gemm_command[channel];
            result_beat[channel] = npu_post_result_beat_t'(
                result_o[channel*RESULT_WIDTH +: RESULT_WIDTH]);
        end
    end

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    initial begin
        integer received_cycles;
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        vector_command_valid_i = 1'b0;
        vector_command = '0;
        gemm_valid_i = '0;
        operand_b_read_valid_i = '0;
        operand_b_read_data_i = '0;
        operand_b_read_scale_i = '0;
        operand_c_read_valid_i = '0;
        operand_c_read_data_i = '0;
        operand_c_read_scale_i = '0;
        result_ready_i = '1;
        completion_ready_i = 1'b1;
        scenario_id = 8'd0;
        checks = 0;
        received_cycles = 0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            gemm_beat[channel] = '0;
            gemm_command[channel] = '0;
        end

        repeat (3) @(posedge clk_i);
        rst_i = 1'b0;
        scenario_id = 8'd1;

        vector_command.job_id = 16'h6601;
        vector_command.tag = 8'h41;
        vector_command.matrix_size = 16'd16;
        vector_command.vectors_per_row = 5'(BEATS);
        vector_command.control.lane_mask = 16'hffff;
        vector_command.control.tag = 8'h41;
        vector_command.control.operation = VECTOR_ENGINE_OP_PASS;
        vector_command.control.output_format = EPILOGUE_OUT_MX;
        vector_command.control.mx_format = MXFP8_E4M3;
        @(negedge clk_i);
        vector_command_valid_i = 1'b1;
        while (!vector_command_ready_o) @(negedge clk_i);
        @(posedge clk_i);
        @(negedge clk_i);
        vector_command_valid_i = 1'b0;

        fork
            begin : sender
                for (integer beat_index = 0; beat_index < BEATS;
                     beat_index++) begin
                    while (gemm_ready_o != {CHANNELS{1'b1}})
                        @(negedge clk_i);
                    for (integer channel = 0; channel < CHANNELS; channel++) begin
                        gemm_beat[channel] = '0;
                        gemm_beat[channel].data =
                            {16{32'h3f800000}};
                        gemm_beat[channel].payload_kind =
                            NPU_PAYLOAD_FP32_VECTOR;
                        gemm_beat[channel].job_id = 16'h6601;
                        gemm_beat[channel].tag = 8'h41;
                        gemm_beat[channel].row = 16'(channel);
                        gemm_beat[channel].segment = 5'(beat_index);
                        gemm_beat[channel].last =
                            (beat_index == (BEATS-1)) &&
                            (channel == (CHANNELS-1));
                        gemm_command[channel] = '0;
                        gemm_command[channel].job_id = 16'h6601;
                        gemm_command[channel].tag = 8'h41;
                        gemm_command[channel].matrix_size = 16'd16;
                        gemm_command[channel].vectors_per_row = 5'(BEATS);
                        gemm_command[channel].route = NPU_POST_VECTOR;
                        gemm_command[channel].vector_control =
                            vector_command.control;
                        gemm_command[channel].output_format = NPU_OUTPUT_MX;
                        gemm_command[channel].output_mx_format = MXFP8_E4M3;
                    end
                    gemm_valid_i = {CHANNELS{1'b1}};
                    @(posedge clk_i);
                    @(negedge clk_i);
                end
                gemm_valid_i = '0;
            end
            begin : receiver
                while (result_valid_o == '0) @(negedge clk_i);
                while (received_cycles < BEATS) begin
                    if (result_valid_o != {CHANNELS{1'b1}}) begin
                        fail("Vector coupler result bubble at peak load");
                    end
                    for (integer channel = 0; channel < CHANNELS; channel++) begin
                        if ((result_beat[channel].payload_kind !=
                             NPU_PAYLOAD_MX_VECTOR) ||
                            (result_beat[channel].mx_format != MXFP8_E4M3) ||
                            (result_beat[channel].mx_scale != 8'd119) ||
                            (result_beat[channel].data[127:0] !=
                             {16{8'h78}}) ||
                            (result_beat[channel].job_id != 16'h6601) ||
                            (result_beat[channel].tag != 8'h41) ||
                            (result_beat[channel].row != 16'(channel)) ||
                            (result_beat[channel].segment !=
                             5'(received_cycles))) begin
                            fail("Vector coupler MX payload/scale/metadata mismatch");
                        end
                    end
                    checks = checks + CHANNELS*8;
                    received_cycles = received_cycles + 1;
                    @(negedge clk_i);
                end
            end
        join

        while (!completion_valid_o) @(negedge clk_i);
        if ((completion_tag_o != 8'h41) || !completion_success_o ||
            completion_feedback_o || protocol_error_o ||
            (|operand_b_read_enable_o) ||
            (|operand_c_read_enable_o)) begin
            fail("Vector coupler completion or protocol status mismatch");
        end
        checks = checks + 5;
        @(posedge clk_i);
        @(negedge clk_i);
        if (busy_o || completion_valid_o) begin
            fail("Vector coupler did not drain");
        end

        $display("PASS: Vector coupler checks=%0d peak=16-beats/256-elements-per-cycle no-bubble",
                 checks);
        $finish;
    end

    initial begin
        repeat (10000) @(posedge clk_i);
        fail("timeout");
    end

    wire _unused_operand_ports = &{1'b0,
        operand_b_read_buffer_id_o, operand_b_read_offset_o,
        operand_c_read_buffer_id_o, operand_c_read_offset_o,
        result_command_o};

endmodule

`default_nettype wire
