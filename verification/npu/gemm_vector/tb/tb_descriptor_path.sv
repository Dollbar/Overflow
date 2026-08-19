`timescale 1ns/1ps
`default_nettype none

module tb_descriptor_path;
    import npu_scheduler_pkg::*;
    import npu_gemm_vector_tb_pkg::*;

    localparam int unsigned ENTRY_COUNT = 4;
    localparam int unsigned INDEX_WIDTH = 2;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic command_valid_i;
    logic command_ready_o;
    logic command_submit_i;
    logic [INDEX_WIDTH-1:0] command_index_i;
    logic [NPU_TASK_DESCRIPTOR_WIDTH-1:0] command_descriptor_i;
    logic write_valid;
    logic write_ready;
    logic [INDEX_WIDTH-1:0] write_index;
    logic [NPU_TASK_DESCRIPTOR_WIDTH-1:0] write_descriptor;
    logic submit_valid;
    logic submit_ready;
    logic [INDEX_WIDTH-1:0] submit_index;
    logic task_valid;
    logic task_ready;
    logic [NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_payload;
    logic accept_enable_i;
    logic monitor_valid;
    logic [NPU_TASK_DESCRIPTOR_WIDTH-1:0] monitor_payload;
    logic descriptor_protocol_error;
    logic [31:0] source_transaction_count;
    logic [31:0] sink_transaction_count;
    logic [7:0] scenario_id;
    integer check_count;

    npu_descriptor_source_vip #(
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_source (
        .clk_i,
        .rst_i,
        .clear_i,
        .command_valid_i,
        .command_ready_o,
        .command_submit_i,
        .command_index_i,
        .command_descriptor_i,
        .write_valid_o(write_valid),
        .write_ready_i(write_ready),
        .write_index_o(write_index),
        .write_descriptor_o(write_descriptor),
        .submit_valid_o(submit_valid),
        .submit_ready_i(submit_ready),
        .submit_index_o(submit_index),
        .transaction_count_o(source_transaction_count)
    );

    npu_descriptor_buffer #(
        .ENTRY_COUNT(ENTRY_COUNT),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_dut (
        .clk_i,
        .rst_i,
        .clear_i,
        .write_valid_i(write_valid),
        .write_ready_o(write_ready),
        .write_index_i(write_index),
        .write_descriptor_i(write_descriptor),
        .submit_valid_i(submit_valid),
        .submit_ready_o(submit_ready),
        .submit_index_i(submit_index),
        .task_valid_o(task_valid),
        .task_ready_i(task_ready),
        .task_o(task_payload),
        .protocol_error_o(descriptor_protocol_error)
    );

    npu_post_result_sink_vip #(
        .PAYLOAD_WIDTH(NPU_TASK_DESCRIPTOR_WIDTH)
    ) u_sink (
        .clk_i,
        .rst_i,
        .clear_i,
        .accept_enable_i,
        .source_valid_i(task_valid),
        .source_ready_o(task_ready),
        .source_payload_i(task_payload),
        .monitor_valid_o(monitor_valid),
        .monitor_payload_o(monitor_payload),
        .transaction_count_o(sink_transaction_count)
    );

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/descriptor_path.vcd");
        $dumpvars(1, tb_descriptor_path);
    end
`endif

    task automatic send_command(
        input logic submit,
        input logic [INDEX_WIDTH-1:0] index,
        input npu_task_descriptor_t descriptor
    );
        begin
            @(negedge clk_i);
            command_submit_i = submit;
            command_index_i = index;
            command_descriptor_i = descriptor;
            command_valid_i = 1'b1;
            while (!command_ready_o) @(negedge clk_i);
            @(negedge clk_i);
            command_valid_i = 1'b0;
            command_submit_i = 1'b0;
            command_index_i = '0;
            command_descriptor_i = '0;
        end
    endtask

    task automatic expect_descriptor(
        input npu_task_descriptor_t expected
    );
        begin
            while (!monitor_valid) @(negedge clk_i);
            if (monitor_payload !== expected) begin
                $fatal(1, "FAIL: descriptor mismatch scenario=%0d", scenario_id);
            end
            check_count = check_count + 1;
            @(negedge clk_i);
        end
    endtask

    initial begin
        npu_task_descriptor_t descriptor0;
        npu_task_descriptor_t descriptor1;
        npu_task_descriptor_t held_task;

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        command_valid_i = 1'b0;
        command_submit_i = 1'b0;
        command_index_i = '0;
        command_descriptor_i = '0;
        accept_enable_i = 1'b1;
        scenario_id = 8'd0;
        check_count = 0;

        if ((NPU_TASK_DESCRIPTOR_WIDTH != 349) ||
            (NPU_POST_RESULT_WIDTH != 574)) begin
            $fatal(1, "FAIL: package ABI width changed without spec update");
        end

        repeat (3) @(negedge clk_i);
        rst_i = 1'b0;
        repeat (2) @(negedge clk_i);

        // A write alone must not expose a partially committed descriptor.
        scenario_id = 8'd1;
        descriptor0 = make_square_gemm_descriptor(16'h1001, 16'd256,
                                                   4'd0, 4'd0);
        descriptor0.activation_base_offset = 32'h0000_1000;
        descriptor0.weight_base_offset = 32'h0000_2000;
        descriptor0.output_base_offset = 32'h0000_3000;
        send_command(TB_DESCRIPTOR_WRITE, 2'd0, descriptor0);
        repeat (3) @(negedge clk_i);
        if (task_valid || monitor_valid || descriptor_protocol_error) begin
            $fatal(1, "FAIL: descriptor became visible before submit");
        end
        check_count = check_count + 1;
        send_command(TB_DESCRIPTOR_SUBMIT, 2'd0, '0);
        expect_descriptor(descriptor0);

        // Backpressure must hold a submitted descriptor and block a second
        // submit while writes to other slots remain accepted.
        scenario_id = 8'd2;
        descriptor1 = make_square_gemm_descriptor(16'h1002, 16'd16,
                                                   4'd15, 4'd15);
        descriptor1.post_route = NPU_POST_VECTOR;
        send_command(TB_DESCRIPTOR_WRITE, 2'd1, descriptor1);
        accept_enable_i = 1'b0;
        send_command(TB_DESCRIPTOR_SUBMIT, 2'd1, '0);
        repeat (2) @(negedge clk_i);
        held_task = task_payload;
        if (!task_valid || submit_ready || (task_payload !== descriptor1)) begin
            $fatal(1, "FAIL: descriptor did not hold under sink backpressure");
        end
        repeat (3) begin
            @(negedge clk_i);
            if (!task_valid || (task_payload !== held_task)) begin
                $fatal(1, "FAIL: descriptor changed under backpressure");
            end
        end
        accept_enable_i = 1'b1;
        expect_descriptor(descriptor1);

        // Reuse one slot for a continuous write/submit sequence.
        scenario_id = 8'd3;
        for (integer burst_index = 0; burst_index < 4; burst_index++) begin
            descriptor0 = make_square_gemm_descriptor(
                16'(16'h2000 + burst_index), 16'd16,
                4'(burst_index), 4'(burst_index));
            send_command(TB_DESCRIPTOR_WRITE, 2'd2, descriptor0);
            send_command(TB_DESCRIPTOR_SUBMIT, 2'd2, '0);
            expect_descriptor(descriptor0);
        end

        // Submit of an unwritten slot raises the sticky protocol error.
        scenario_id = 8'd4;
        send_command(TB_DESCRIPTOR_SUBMIT, 2'd3, '0);
        repeat (2) @(negedge clk_i);
        if (!descriptor_protocol_error) begin
            $fatal(1, "FAIL: unwritten descriptor submit was not rejected");
        end
        check_count = check_count + 1;

        // Clear flushes an in-flight descriptor and recovers the path.
        scenario_id = 8'd5;
        clear_i = 1'b1;
        @(negedge clk_i);
        clear_i = 1'b0;
        repeat (2) @(negedge clk_i);
        if (task_valid || descriptor_protocol_error ||
            (source_transaction_count != 0) || (sink_transaction_count != 0)) begin
            $fatal(1, "FAIL: clear did not reset descriptor verification path");
        end
        descriptor0 = make_square_gemm_descriptor(16'h3001, 16'd16,
                                                   4'd1, 4'd2);
        send_command(TB_DESCRIPTOR_WRITE, 2'd0, descriptor0);
        send_command(TB_DESCRIPTOR_SUBMIT, 2'd0, '0);
        expect_descriptor(descriptor0);

        // Reset while a descriptor is held flushes it, then traffic recovers.
        scenario_id = 8'd6;
        descriptor1 = make_square_gemm_descriptor(16'h3002, 16'd16,
                                                   4'd3, 4'd4);
        send_command(TB_DESCRIPTOR_WRITE, 2'd1, descriptor1);
        accept_enable_i = 1'b0;
        send_command(TB_DESCRIPTOR_SUBMIT, 2'd1, '0);
        rst_i = 1'b1;
        @(negedge clk_i);
        rst_i = 1'b0;
        accept_enable_i = 1'b1;
        repeat (2) @(negedge clk_i);
        if (task_valid || monitor_valid) begin
            $fatal(1, "FAIL: reset did not flush held descriptor");
        end
        descriptor1 = make_square_gemm_descriptor(16'h3003, 16'd16,
                                                   4'd5, 4'd6);
        send_command(TB_DESCRIPTOR_WRITE, 2'd1, descriptor1);
        send_command(TB_DESCRIPTOR_SUBMIT, 2'd1, '0);
        expect_descriptor(descriptor1);

        $display("PASS: descriptor path atomic write/submit, hold, slot reuse, error, clear/reset checks=%0d",
                 check_count);
        $finish;
    end

    initial begin
        repeat (2000) @(posedge clk_i);
        $fatal(1, "FAIL: descriptor path timeout scenario=%0d", scenario_id);
    end

endmodule

`default_nettype wire
