`timescale 1ns/1ps
`default_nettype none

module tb_npu_post_output_formatter16;
    import fp8_pkg::*;
    import mxfp_pkg::*;
    import npu_scheduler_pkg::*;

    localparam int unsigned CHANNELS = 16;
    localparam int unsigned BEATS_PER_TASK = 8;
    localparam int unsigned RESULT_WIDTH = NPU_POST_RESULT_WIDTH;
    localparam int unsigned COMMAND_WIDTH = NPU_POST_COMMAND_WIDTH;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic [CHANNELS-1:0] input_valid_i;
    logic [CHANNELS-1:0] input_ready_o;
    logic [CHANNELS*RESULT_WIDTH-1:0] input_result_i;
    logic [CHANNELS*COMMAND_WIDTH-1:0] input_command_i;
    logic [CHANNELS-1:0] output_valid_o;
    logic [CHANNELS-1:0] output_ready_i;
    logic [CHANNELS*RESULT_WIDTH-1:0] output_result_o;
    logic [CHANNELS*COMMAND_WIDTH-1:0] output_command_o;
    logic completion_valid_o;
    logic completion_ready_i;
    logic [NPU_TAG_WIDTH-1:0] completion_tag_o;
    logic completion_success_o;
    logic busy_o;
    logic protocol_error_o;
    logic [7:0] scenario_id;
    integer checks;

    npu_post_result_beat_t input_beat [0:CHANNELS-1];
    npu_post_command_t input_command [0:CHANNELS-1];
    npu_post_result_beat_t output_beat [0:CHANNELS-1];
    npu_post_command_t output_command [0:CHANNELS-1];

    npu_post_output_formatter16 #(.CHANNELS(CHANNELS)) u_dut (.*);

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/npu_post_output_formatter16.vcd");
        $dumpvars(0, tb_npu_post_output_formatter16);
    end
`endif

    always_comb begin
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            input_result_i[channel*RESULT_WIDTH +: RESULT_WIDTH] =
                input_beat[channel];
            input_command_i[channel*COMMAND_WIDTH +: COMMAND_WIDTH] =
                input_command[channel];
            output_beat[channel] = npu_post_result_beat_t'(
                output_result_o[channel*RESULT_WIDTH +: RESULT_WIDTH]);
            output_command[channel] = npu_post_command_t'(
                output_command_o[channel*COMMAND_WIDTH +: COMMAND_WIDTH]);
        end
    end

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    task automatic clear_formatter;
        begin
            @(negedge clk_i);
            clear_i = 1'b1;
            input_valid_i = '0;
            output_ready_i = '1;
            @(posedge clk_i);
            @(negedge clk_i);
            clear_i = 1'b0;
        end
    endtask

    task automatic prepare_beat(
        input integer beat_index,
        input mxfp_format_e format,
        input logic [7:0] tag
    );
        begin
            for (integer channel = 0; channel < CHANNELS; channel++) begin
                input_beat[channel] = '0;
                input_beat[channel].payload_kind = NPU_PAYLOAD_FP32_VECTOR;
                input_beat[channel].job_id = 16'h4200 + 16'(tag);
                input_beat[channel].tag = tag;
                input_beat[channel].row = 16'(channel);
                input_beat[channel].segment = 5'(beat_index);
                input_beat[channel].last =
                    (beat_index == (BEATS_PER_TASK-1)) &&
                    (channel == (CHANNELS-1));
                for (integer lane = 0; lane < 16; lane++) begin
                    input_beat[channel].data[lane*32 +: 32] = 32'h3f800000;
                end
                input_command[channel] = '0;
                input_command[channel].job_id = 16'h4200 + 16'(tag);
                input_command[channel].tag = tag;
                input_command[channel].matrix_size = 16'd16;
                input_command[channel].vectors_per_row =
                    5'(BEATS_PER_TASK);
                input_command[channel].route = NPU_POST_EXTERNAL;
                input_command[channel].output_format = NPU_OUTPUT_MX;
                input_command[channel].output_mx_format = format;
            end
        end
    endtask

    task automatic check_output_cycle(
        input integer beat_index,
        input mxfp_format_e format,
        input logic [7:0] tag
    );
        logic [7:0] expected_scale;
        logic [7:0] expected_byte;
        logic [3:0] expected_nibble;
        begin
            unique case (format)
                MXFP4_E2M1: begin
                    expected_scale = 8'd125;
                    expected_byte = 8'd0;
                    expected_nibble = 4'h6;
                end
                MXFP8_E4M3: begin
                    expected_scale = 8'd119;
                    expected_byte = 8'h78;
                    expected_nibble = 4'd0;
                end
                default: begin
                    expected_scale = 8'd112;
                    expected_byte = 8'h78;
                    expected_nibble = 4'd0;
                end
            endcase
            if (output_valid_o != {CHANNELS{1'b1}}) begin
                fail("peak output lane bubble");
            end
            for (integer channel = 0; channel < CHANNELS; channel++) begin
                if ((output_beat[channel].payload_kind !=
                     NPU_PAYLOAD_MX_VECTOR) ||
                    (output_beat[channel].mx_format != format) ||
                    (output_beat[channel].mx_scale != expected_scale) ||
                    (output_beat[channel].job_id !=
                     (16'h4200 + 16'(tag))) ||
                    (output_beat[channel].tag != tag) ||
                    (output_beat[channel].row != 16'(channel)) ||
                    (output_beat[channel].segment != 5'(beat_index)) ||
                    (output_beat[channel].last !=
                     ((beat_index == (BEATS_PER_TASK-1)) &&
                      (channel == (CHANNELS-1)))) ||
                    (output_command[channel].output_mx_format != format)) begin
                    fail("MX result metadata or shared scale mismatch");
                end
                for (integer lane = 0; lane < 16; lane++) begin
                    if (format == MXFP4_E2M1) begin
                        if (output_beat[channel].data[lane*4 +: 4] !=
                            expected_nibble) begin
                            fail("MXFP4 payload mismatch");
                        end
                    end else if (output_beat[channel].data[lane*8 +: 8] !=
                                 expected_byte) begin
                        fail("MXFP8 payload mismatch");
                    end
                end
                if ((format == MXFP4_E2M1) &&
                    (output_beat[channel].data[127:64] != 64'd0)) begin
                    fail("MXFP4 upper payload half was not zero");
                end
            end
            checks = checks + CHANNELS*20;
        end
    endtask

    task automatic run_peak_format(
        input mxfp_format_e format,
        input logic [7:0] tag
    );
        integer output_index;
        begin
            clear_formatter();
            output_index = 0;
            fork
                begin : sender
                    for (integer beat_index = 0;
                         beat_index < BEATS_PER_TASK; beat_index++) begin
                        @(negedge clk_i);
                        while (input_ready_o != {CHANNELS{1'b1}}) begin
                            @(negedge clk_i);
                        end
                        prepare_beat(beat_index, format, tag);
                        input_valid_i = {CHANNELS{1'b1}};
                        @(posedge clk_i);
                    end
                    @(negedge clk_i);
                    input_valid_i = '0;
                end
                begin : receiver
                    while (output_valid_o == '0) @(negedge clk_i);
                    while (output_index < BEATS_PER_TASK) begin
                        check_output_cycle(output_index, format, tag);
                        output_index = output_index + 1;
                        @(negedge clk_i);
                    end
                end
            join
            while (!completion_valid_o) @(negedge clk_i);
            if ((completion_tag_o != tag) || !completion_success_o ||
                protocol_error_o) begin
                fail("formatter completion or protocol status mismatch");
            end
            checks = checks + 3;
            @(posedge clk_i);
            @(negedge clk_i);
            if (busy_o || completion_valid_o) begin
                fail("formatter did not drain after completion");
            end
        end
    endtask

    task automatic abort_inflight_pair(input logic use_reset);
        begin
            clear_formatter();
            prepare_beat(0, MXFP8_E4M3, 8'h61);
            @(negedge clk_i);
            input_valid_i = {CHANNELS{1'b1}};
            @(posedge clk_i);
            @(negedge clk_i);
            input_valid_i = '0;
            if (use_reset) begin
                rst_i = 1'b1;
            end else begin
                clear_i = 1'b1;
            end
            @(posedge clk_i);
            @(negedge clk_i);
            rst_i = 1'b0;
            clear_i = 1'b0;
            if (busy_o || (output_valid_o != '0) || completion_valid_o ||
                protocol_error_o) begin
                fail("in-flight reset/clear did not flush partial MX block");
            end
            checks = checks + 4;
        end
    endtask

    task automatic run_stalled_fp32_single;
        npu_post_result_beat_t held_result;
        begin
            clear_formatter();
            output_ready_i = '0;
            input_beat[0] = '0;
            input_beat[0].data = {16{32'h3f800000}};
            input_beat[0].payload_kind = NPU_PAYLOAD_FP32_VECTOR;
            input_beat[0].job_id = 16'h4262;
            input_beat[0].tag = 8'h62;
            input_beat[0].row = 16'd7;
            input_beat[0].segment = 5'd0;
            input_beat[0].last = 1'b1;
            input_command[0] = '0;
            input_command[0].job_id = 16'h4262;
            input_command[0].tag = 8'h62;
            input_command[0].matrix_size = 16'd1;
            input_command[0].vectors_per_row = 5'd1;
            input_command[0].route = NPU_POST_EXTERNAL;
            input_command[0].output_format = NPU_OUTPUT_FP32;
            @(negedge clk_i);
            input_valid_i[0] = 1'b1;
            while (!input_ready_o[0]) @(negedge clk_i);
            @(posedge clk_i);
            @(negedge clk_i);
            input_valid_i = '0;
            while (!output_valid_o[0]) @(negedge clk_i);
            held_result = output_beat[0];
            repeat (3) begin
                @(posedge clk_i);
                @(negedge clk_i);
                if (!output_valid_o[0] ||
                    (output_beat[0] !== held_result)) begin
                    fail("FP32 output changed under backpressure");
                end
            end
            output_ready_i[0] = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            if ((held_result.payload_kind != NPU_PAYLOAD_FP32_VECTOR) ||
                (held_result.data != {16{32'h3f800000}}) ||
                (held_result.tag != 8'h62) || !held_result.last) begin
                fail("single FP32 pass-through result mismatch");
            end
            while (!completion_valid_o) @(negedge clk_i);
            if ((completion_tag_o != 8'h62) || !completion_success_o) begin
                fail("single FP32 completion mismatch");
            end
            checks = checks + 8;
            output_ready_i = '1;
            @(posedge clk_i);
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        input_valid_i = '0;
        output_ready_i = '1;
        completion_ready_i = 1'b1;
        scenario_id = 8'd0;
        checks = 0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            input_beat[channel] = '0;
            input_command[channel] = '0;
        end

        repeat (3) @(posedge clk_i);
        rst_i = 1'b0;

        scenario_id = 8'd1;
        run_peak_format(MXFP8_E4M3, 8'h31);
        scenario_id = 8'd2;
        run_peak_format(MXFP4_E2M1, 8'h33);
        scenario_id = 8'd3;
        abort_inflight_pair(1'b0);
        scenario_id = 8'd4;
        abort_inflight_pair(1'b1);
        scenario_id = 8'd6;
        run_stalled_fp32_single();

        $display("PASS: 16-lane MX output formatter checks=%0d peak=256-elements/cycle no-bubble",
                 checks);
        $finish;
    end

    initial begin
        repeat (10000) @(posedge clk_i);
        fail("timeout");
    end

endmodule

`default_nettype wire
