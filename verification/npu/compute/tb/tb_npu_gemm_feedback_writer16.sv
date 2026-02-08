`timescale 1ns/1ps
`default_nettype none

module tb_npu_gemm_feedback_writer16;

    localparam int unsigned CHANNELS = 16;
    localparam int unsigned RESULT_WIDTH =
        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH;
    localparam int unsigned COMMAND_WIDTH =
        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic [CHANNELS-1:0] feedback_valid_i;
    logic [CHANNELS-1:0] feedback_ready_o;
    logic [CHANNELS*RESULT_WIDTH-1:0] feedback_result_i;
    logic [CHANNELS*COMMAND_WIDTH-1:0] feedback_command_i;
    logic [CHANNELS-1:0] activation_write_valid_o;
    logic [CHANNELS-1:0] activation_write_ready_i;
    logic [CHANNELS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        activation_write_buffer_id_o;
    logic [CHANNELS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        activation_write_offset_o;
    logic [CHANNELS*128-1:0] activation_write_data_o;
    logic [CHANNELS*8-1:0] activation_write_scale_o;
    logic completion_valid_o;
    logic completion_ready_i;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_o;
    logic completion_success_o;
    logic busy_o;
    logic protocol_error_o;
    logic [3:0] scenario_id;
    integer checks;

    npu_scheduler_pkg::npu_post_result_beat_t result_beat [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t command [0:CHANNELS-1];

    npu_gemm_feedback_writer16 #(
        .CHANNELS(CHANNELS), .SLOTS(2), .MAX_SEGMENTS(16)
    ) u_dut (.*);

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/npu_gemm_feedback_writer16.vcd");
        $dumpvars(0, tb_npu_gemm_feedback_writer16);
    end
`endif

    always_comb begin
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            feedback_result_i[channel*RESULT_WIDTH +: RESULT_WIDTH] =
                result_beat[channel];
            feedback_command_i[channel*COMMAND_WIDTH +: COMMAND_WIDTH] =
                command[channel];
        end
    end

    task automatic fail(input string message);
        begin
            $display("FAIL: %s", message);
            $fatal(1);
        end
    endtask

    task automatic send_rows(input integer local_row, input integer segment);
        begin
            @(negedge clk_i);
            if (feedback_ready_o != {CHANNELS{1'b1}}) begin
                fail("feedback ingress inserted a peak-load bubble");
            end
            for (integer channel = 0; channel < CHANNELS; channel++) begin
                result_beat[channel] = '0;
                result_beat[channel].job_id = command[channel].job_id;
                result_beat[channel].tag = command[channel].tag;
                result_beat[channel].row = 16'(channel*16 + local_row);
                result_beat[channel].segment = 5'(segment);
                result_beat[channel].last = (segment == 15) &&
                    (local_row == 15) && (channel == CHANNELS-1);
                for (integer lane = 0; lane < 16; lane++) begin
                    result_beat[channel].data[lane*32 +: 32] = 32'h3f800000;
                end
            end
            feedback_valid_i = {CHANNELS{1'b1}};
            @(posedge clk_i);
        end
    endtask

    task automatic run_feedback_format(
        input mxfp_pkg::mxfp_format_e format,
        input logic [7:0] tag,
        input npu_scheduler_pkg::npu_post_route_e source_route
    );
        integer output_cycles;
        logic [7:0] expected_scale;
        begin
            @(negedge clk_i);
            clear_i = 1'b1;
            feedback_valid_i = '0;
            activation_write_ready_i = '0;
            @(posedge clk_i);
            @(negedge clk_i);
            clear_i = 1'b0;
            for (integer channel = 0; channel < CHANNELS; channel++) begin
                command[channel].job_id = 16'h1200 + 16'(tag);
                command[channel].tag = tag;
                command[channel].route = source_route;
                command[channel].vector_result_route =
                    (source_route == npu_scheduler_pkg::NPU_POST_VECTOR) ?
                    npu_scheduler_pkg::NPU_VECTOR_TO_FEEDBACK :
                    npu_scheduler_pkg::NPU_VECTOR_TO_EXTERNAL;
                command[channel].destination_format = format;
                command[channel].output_mx_format = format;
            end

            for (integer local_row = 0; local_row < 16; local_row++) begin
                for (integer segment = 0; segment < 16; segment++) begin
                    send_rows(local_row, segment);
                end
            end
            @(negedge clk_i);
            feedback_valid_i = '0;

            output_cycles = (format == mxfp_pkg::MXFP4_E2M1) ? 128 : 256;
            unique case (format)
                mxfp_pkg::MXFP4_E2M1: expected_scale = 8'd125;
                mxfp_pkg::MXFP8_E4M3: expected_scale = 8'd119;
                default: expected_scale = 8'd112;
            endcase
            while (activation_write_valid_o != {CHANNELS{1'b1}})
                @(negedge clk_i);
            activation_write_ready_i = {CHANNELS{1'b1}};
            for (integer output_cycle = 0; output_cycle < output_cycles;
                 output_cycle++) begin
                integer expected_stream;
                integer expected_half;
                integer expected_pair;
                logic [31:0] expected_offset;
                if (format == mxfp_pkg::MXFP4_E2M1) begin
                    expected_stream = output_cycle / 8;
                    expected_pair = output_cycle % 8;
                    expected_half = 0;
                end else begin
                    expected_stream = output_cycle / 16;
                    expected_pair = (output_cycle % 16) / 2;
                    expected_half = output_cycle % 2;
                end
                if (format == mxfp_pkg::MXFP4_E2M1) begin
                    expected_offset = 32'h00001000 +
                        32'((expected_pair*16 + expected_stream) * 16);
                end else begin
                    expected_offset = 32'h00001000 +
                        32'(((expected_pair*2 + expected_half)*16 +
                             expected_stream) * 16);
                end
                if (activation_write_valid_o != {CHANNELS{1'b1}}) begin
                    fail("feedback drain inserted a throughput bubble");
                end
                for (integer bank = 0; bank < CHANNELS; bank++) begin
                    if (activation_write_buffer_id_o[
                            bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                            npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH] != 4'd2) begin
                        fail("feedback buffer ID mismatch");
                    end
                    if (activation_write_offset_o[
                            bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                            npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH] !==
                        expected_offset) begin
                        fail("feedback physical address mismatch");
                    end
                    if (activation_write_scale_o[bank*8 +: 8] !=
                        expected_scale) begin
                        fail("feedback E8M0 scale mismatch");
                    end
                    if (format == mxfp_pkg::MXFP4_E2M1) begin
                        for (integer lane = 0; lane < 32; lane++) begin
                            if (activation_write_data_o[
                                    bank*128 + lane*4 +: 4] != 4'h6) begin
                                fail("feedback MXFP4 data mismatch");
                            end
                        end
                    end else begin
                        for (integer lane = 0; lane < 16; lane++) begin
                            if (activation_write_data_o[
                                    bank*128 + lane*8 +: 8] != 8'h78) begin
                                fail("feedback MXFP8 data mismatch");
                            end
                        end
                    end
                end
                checks = checks + 36;
                @(posedge clk_i);
                @(negedge clk_i);
            end
            activation_write_ready_i = '0;

            while (!completion_valid_o) @(posedge clk_i);
            #1;
            if ((completion_tag_o != tag) || !completion_success_o ||
                protocol_error_o) begin
                fail("feedback completion or protocol status mismatch");
            end
            checks = checks + 3;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        feedback_valid_i = '0;
        activation_write_ready_i = '0;
        completion_ready_i = 1'b1;
        scenario_id = 4'd0;
        checks = 0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            result_beat[channel] = '0;
            command[channel] = '0;
            command[channel].job_id = 16'h1234;
            command[channel].tag = 8'h5a;
            command[channel].vectors_per_row = 5'd16;
            command[channel].route = npu_scheduler_pkg::NPU_POST_GEMM;
            command[channel].destination_buffer_id = 4'd2;
            command[channel].destination_base_offset = 32'h00001000;
            command[channel].destination_format = mxfp_pkg::MXFP8_E4M3;
            command[channel].output_format = npu_scheduler_pkg::NPU_OUTPUT_MX;
        end

        repeat (3) @(posedge clk_i);
        rst_i = 1'b0;
        scenario_id = 4'd1;
        run_feedback_format(mxfp_pkg::MXFP8_E4M3, 8'h5a,
                            npu_scheduler_pkg::NPU_POST_GEMM);
        scenario_id = 4'd2;
        run_feedback_format(mxfp_pkg::MXFP4_E2M1, 8'h5c,
                            npu_scheduler_pkg::NPU_POST_GEMM);

        scenario_id = 4'd3;
        run_feedback_format(mxfp_pkg::MXFP8_E4M3, 8'h5d,
                            npu_scheduler_pkg::NPU_POST_VECTOR);
        scenario_id = 4'd4;
        run_feedback_format(mxfp_pkg::MXFP4_E2M1, 8'h5f,
                            npu_scheduler_pkg::NPU_POST_VECTOR);

        scenario_id = 4'd7;
        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;
        repeat (2) @(posedge clk_i);
        if (busy_o || completion_valid_o || protocol_error_o) begin
            fail("feedback clear recovery failed");
        end
        checks = checks + 1;

        $display("PASS: MX feedback writer checks=%0d", checks);
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk_i);
        fail("timeout");
    end

    wire _unused_scenario = &{1'b0, scenario_id};

endmodule

`default_nettype wire
