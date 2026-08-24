`timescale 1ns/1ps
`default_nettype none

module tb_tile_mx_gemm_path;
    localparam int unsigned TILE_SIZE = 16;
    localparam int unsigned INPUT_CYCLES_PER_TASK = 32;
    localparam int unsigned EXPECTED_TASKS = 7;
    localparam logic [31:0] EXPECTED_FP32 = 32'h42000000; // 32.0

    logic clk_i, rst_i, clear_i;
    logic [15:0] a_valid_i, b_valid_i;
    logic [127:0] a_data_i, a_scale_i, a_tag_i;
    logic [127:0] b_data_i, b_scale_i;
    logic [31:0] a_format_i, b_format_i;
    logic [15:0] a_block_first_i, a_block_last_i;
    logic [15:0] a_matrix_first_i, a_matrix_last_i;
    logic result_ready_i, result_valid_o;
    logic [511:0] result_data_o;
    logic [15:0] result_invalid_o;
    logic [7:0] result_tag_o;
    logic [3:0] result_row_o;
    logic [5:0] result_level_o;
    logic input_issue_o, output_overflow_o;
    logic [3:0] scenario_id;
    logic [7:0] expected_tag [0:EXPECTED_TASKS-1];
    integer input_cycles, observed_rows, expected_tasks_queued;

    /* verilator lint_off PINCONNECTEMPTY */
    TILE_FP8_16_FIFO u_dut (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .a_valid_i(a_valid_i), .a_data_i(a_data_i),
        .a_format_i(a_format_i), .a_scale_i(a_scale_i),
        .a_block_first_i(a_block_first_i),
        .a_block_last_i(a_block_last_i),
        .a_matrix_first_i(a_matrix_first_i),
        .a_matrix_last_i(a_matrix_last_i), .a_tag_i(a_tag_i),
        .b_valid_i(b_valid_i), .b_data_i(b_data_i),
        .b_format_i(b_format_i), .b_scale_i(b_scale_i),
        .a_east_valid_o(), .a_east_data_o(), .a_east_format_o(),
        .a_east_scale_o(), .a_east_block_first_o(),
        .a_east_block_last_o(), .a_east_matrix_first_o(),
        .a_east_matrix_last_o(), .a_east_tag_o(),
        .b_south_valid_o(), .b_south_data_o(), .b_south_format_o(),
        .b_south_scale_o(), .result_ready_i(result_ready_i),
        .result_valid_o(result_valid_o), .result_data_o(result_data_o),
        .result_invalid_o(result_invalid_o), .result_tag_o(result_tag_o),
        .result_row_o(result_row_o), .result_level_o(result_level_o),
        .input_issue_o(input_issue_o), .output_overflow_o(output_overflow_o)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    wire _unused_status = &{1'b0, result_level_o, input_issue_o};
    always #0.5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/tile_mx_gemm_path.vcd");
        $dumpvars(0, tb_tile_mx_gemm_path);
    end
`endif

    function automatic logic [7:0] one_encoding(input logic [1:0] format);
        one_encoding = (format == mxfp_pkg::MXFP4_E2M1) ? 8'h02 : 8'h38;
    endfunction

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    task automatic drive_idle_cycle;
        begin
            a_valid_i = '0;
            b_valid_i = '0;
            @(negedge clk_i);
        end
    endtask

    task automatic drive_matrix_cycle(
        input logic [7:0] tag,
        input logic [1:0] format,
        input integer local_cycle
    );
        begin
            a_valid_i = '1;
            b_valid_i = '1;
            a_data_i = {TILE_SIZE{one_encoding(format)}};
            b_data_i = {TILE_SIZE{one_encoding(format)}};
            a_format_i = {TILE_SIZE{format}};
            b_format_i = {TILE_SIZE{format}};
            a_scale_i = {TILE_SIZE{8'd127}};
            b_scale_i = {TILE_SIZE{8'd127}};
            a_block_first_i = {TILE_SIZE{local_cycle < 16}};
            a_block_last_i = {TILE_SIZE{local_cycle >= 16}};
            a_matrix_first_i = {TILE_SIZE{local_cycle < 16}};
            a_matrix_last_i = {TILE_SIZE{local_cycle >= 16}};
            a_tag_i = {TILE_SIZE{tag}};
            input_cycles = input_cycles + 1;
            @(negedge clk_i);
        end
    endtask

    task automatic queue_matrix(input logic [7:0] tag);
        begin
            if (expected_tasks_queued >= EXPECTED_TASKS)
                fail("expected task queue overflow");
            expected_tag[expected_tasks_queued] = tag;
            expected_tasks_queued = expected_tasks_queued + 1;
        end
    endtask

    task automatic drive_matrix(
        input logic [7:0] tag,
        input logic [1:0] format,
        input bit gap_each_beat
    );
        begin
            queue_matrix(tag);
            for (integer local_cycle = 0;
                 local_cycle < INPUT_CYCLES_PER_TASK; local_cycle++) begin
                drive_matrix_cycle(tag, format, local_cycle);
                if (gap_each_beat) drive_idle_cycle();
            end
            a_valid_i = '0;
            b_valid_i = '0;
        end
    endtask

    task automatic wait_for_tasks(input integer count);
        begin
            while (observed_rows < count*TILE_SIZE) @(posedge clk_i);
            repeat (3) @(posedge clk_i);
        end
    endtask

    always @(negedge clk_i) begin
        integer expected_task;
        if (!rst_i && !clear_i && result_valid_o && result_ready_i) begin
            expected_task = observed_rows / TILE_SIZE;
            if (expected_task >= expected_tasks_queued)
                fail("unexpected result after clear/reset");
            if (result_tag_o !== expected_tag[expected_task])
                fail("result tag mismatch");
            if (result_row_o !== 4'(observed_rows % TILE_SIZE))
                fail("result row mismatch");
            if (result_invalid_o != 16'd0) fail("unexpected invalid result");
            for (integer lane = 0; lane < TILE_SIZE; lane++) begin
                if (result_data_o[lane*32 +: 32] !== EXPECTED_FP32) begin
                    $display("task=%0d row=%0d lane=%0d got=%08x expected=%08x",
                             expected_task, result_row_o, lane,
                             result_data_o[lane*32 +: 32], EXPECTED_FP32);
                    fail("numeric mismatch");
                end
            end
            observed_rows <= observed_rows + 1;
        end
    end

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        a_valid_i = '0;
        a_data_i = '0;
        a_format_i = '0;
        a_scale_i = '0;
        a_block_first_i = '0;
        a_block_last_i = '0;
        a_matrix_first_i = '0;
        a_matrix_last_i = '0;
        a_tag_i = '0;
        b_valid_i = '0;
        b_data_i = '0;
        b_format_i = '0;
        b_scale_i = '0;
        result_ready_i = 1'b1;
        scenario_id = 4'd0;
        input_cycles = 0;
        observed_rows = 0;
        expected_tasks_queued = 0;
        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        // Two matrices are contiguous across MXFP4/MXFP8 and bank seams.
        scenario_id = 4'd1;
        drive_matrix(8'h40, mxfp_pkg::MXFP4_E2M1, 1'b0);
        drive_matrix(8'h41, mxfp_pkg::MXFP8_E4M3, 1'b0);
        wait_for_tasks(2);

        // Gaps must only pause accepted-beat bank addressing.
        scenario_id = 4'd2;
        drive_matrix(8'h42, mxfp_pkg::MXFP4_E2M1, 1'b1);
        wait_for_tasks(3);

        // One standalone matrix.
        scenario_id = 4'd3;
        drive_matrix(8'h43, mxfp_pkg::MXFP8_E4M3, 1'b0);
        wait_for_tasks(4);

        // Clear a partial matrix, then verify no stale result and recovery.
        scenario_id = 4'd4;
        for (integer cycle = 0; cycle < 20; cycle++)
            drive_matrix_cycle(8'he0, mxfp_pkg::MXFP4_E2M1, cycle);
        a_valid_i = '0;
        b_valid_i = '0;
        clear_i = 1'b1;
        repeat (2) @(negedge clk_i);
        clear_i = 1'b0;
        repeat (3) @(negedge clk_i);
        scenario_id = 4'd5;
        drive_matrix(8'h44, mxfp_pkg::MXFP4_E2M1, 1'b0);
        wait_for_tasks(5);

        // Reset a partial matrix, then verify no stale result and recovery.
        scenario_id = 4'd6;
        for (integer cycle = 0; cycle < 20; cycle++)
            drive_matrix_cycle(8'he1, mxfp_pkg::MXFP8_E4M3, cycle);
        a_valid_i = '0;
        b_valid_i = '0;
        rst_i = 1'b1;
        repeat (3) @(negedge clk_i);
        rst_i = 1'b0;
        repeat (3) @(negedge clk_i);
        scenario_id = 4'd7;
        drive_matrix(8'h45, mxfp_pkg::MXFP8_E4M3, 1'b0);
        wait_for_tasks(6);

        // Gapped output traffic exercises the result FIFO backpressure path.
        scenario_id = 4'd8;
        drive_matrix(8'h46, mxfp_pkg::MXFP4_E2M1, 1'b0);
        while (observed_rows < EXPECTED_TASKS*TILE_SIZE) begin
            result_ready_i = ~result_ready_i;
            @(negedge clk_i);
        end
        result_ready_i = 1'b1;
        repeat (4) @(posedge clk_i);

        if (input_cycles != EXPECTED_TASKS*INPUT_CYCLES_PER_TASK + 40)
            fail("input cycle count mismatch");
        if (observed_rows != EXPECTED_TASKS*TILE_SIZE)
            fail("result row count mismatch");
        if (output_overflow_o) fail("result FIFO overflowed");
        $display("PASS: Tile reduction/bank waveform tasks=%0d input_cycles=%0d rows=%0d clear_reset_recovery=1",
                 EXPECTED_TASKS, input_cycles, observed_rows);
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk_i);
        fail("timeout");
    end
endmodule

`default_nettype wire
