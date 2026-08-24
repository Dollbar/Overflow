`timescale 1ns/1ps
`default_nettype none

module tb_tile_mx_gemm_k4096;

    localparam int unsigned TILE_SIZE = 16;
    localparam int unsigned K_SIZE = 4096;
    localparam int unsigned TASK_COUNT = 3;
    localparam int unsigned EXPECTED_ROWS = TASK_COUNT*TILE_SIZE;
    localparam logic [31:0] EXPECTED_FP32 = 32'h45800000;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic [15:0] a_valid_i;
    logic [127:0] a_data_i;
    logic [31:0] a_format_i;
    logic [127:0] a_scale_i;
    logic [15:0] a_block_first_i;
    logic [15:0] a_block_last_i;
    logic [15:0] a_matrix_first_i;
    logic [15:0] a_matrix_last_i;
    logic [127:0] a_tag_i;
    logic [15:0] b_valid_i;
    logic [127:0] b_data_i;
    logic [31:0] b_format_i;
    logic [127:0] b_scale_i;
    logic result_valid_o;
    logic [511:0] result_data_o;
    logic [15:0] result_invalid_o;
    logic [7:0] result_tag_o;
    logic [3:0] result_row_o;
    logic output_overflow_o;
    logic [3:0] scenario_id;
    integer accepted_cycles;
    integer observed_rows;
    integer checked_values;

    /* verilator lint_off PINCONNECTEMPTY */
    TILE_FP8_16_FIFO u_dut (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .a_valid_i(a_valid_i), .a_data_i(a_data_i),
        .a_format_i(a_format_i), .a_scale_i(a_scale_i),
        .a_block_first_i(a_block_first_i),
        .a_block_last_i(a_block_last_i),
        .a_matrix_first_i(a_matrix_first_i),
        .a_matrix_last_i(a_matrix_last_i),
        .a_tag_i(a_tag_i),
        .b_valid_i(b_valid_i), .b_data_i(b_data_i),
        .b_format_i(b_format_i), .b_scale_i(b_scale_i),
        .a_east_valid_o(), .a_east_data_o(), .a_east_format_o(),
        .a_east_scale_o(), .a_east_block_first_o(),
        .a_east_block_last_o(), .a_east_matrix_first_o(),
        .a_east_matrix_last_o(), .a_east_tag_o(),
        .b_south_valid_o(), .b_south_data_o(), .b_south_format_o(),
        .b_south_scale_o(), .result_ready_i(1'b1),
        .result_valid_o(result_valid_o), .result_data_o(result_data_o),
        .result_invalid_o(result_invalid_o), .result_tag_o(result_tag_o),
        .result_row_o(result_row_o), .result_level_o(),
        .input_issue_o(), .output_overflow_o(output_overflow_o)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk_i = ~clk_i;

    function automatic logic [7:0] one_encoding(input integer task_index);
        case (task_index)
            0: one_encoding = 8'h02;
            1: one_encoding = 8'h38;
            default: one_encoding = 8'h38;
        endcase
    endfunction

    function automatic logic [1:0] task_format(input integer task_index);
        case (task_index)
            0: task_format = mxfp_pkg::MXFP4_E2M1;
            default: task_format = mxfp_pkg::MXFP8_E4M3;
        endcase
    endfunction

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    task automatic drive_block_major_cycle(
        input integer task_index,
        input integer local_cycle
    );
        begin
            a_valid_i = '1;
            b_valid_i = '1;
            a_data_i = {TILE_SIZE{one_encoding(task_index)}};
            b_data_i = {TILE_SIZE{one_encoding(task_index)}};
            a_format_i = {16{task_format(task_index)}};
            b_format_i = {16{task_format(task_index)}};
            a_scale_i = {16{8'd127}};
            b_scale_i = {16{8'd127}};
            a_tag_i = {16{8'(8'h70 + task_index)}};
            a_block_first_i = {TILE_SIZE{!local_cycle[4]}};
            a_block_last_i = {TILE_SIZE{local_cycle[4]}};
            a_matrix_first_i = {TILE_SIZE{local_cycle < TILE_SIZE}};
            a_matrix_last_i =
                {TILE_SIZE{local_cycle >= K_SIZE-TILE_SIZE}};
        end
    endtask

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            accepted_cycles <= 0;
        end else if ((|a_valid_i) && (|b_valid_i)) begin
            accepted_cycles <= accepted_cycles + 1;
        end
    end

    always @(negedge clk_i) begin
        integer expected_task;
        if (!rst_i && !clear_i && result_valid_o) begin
            expected_task = observed_rows / TILE_SIZE;
            if ((result_tag_o !== 8'(8'h70 + expected_task)) ||
                (result_row_o !== 4'(observed_rows % TILE_SIZE))) begin
                $display("observed=%0d expected_task=%0d got_tag=%02x expected_tag=%02x got_row=%0d expected_row=%0d",
                    observed_rows, expected_task, result_tag_o,
                    8'(8'h70 + expected_task), result_row_o,
                    observed_rows % TILE_SIZE);
                fail("K=4096 metadata mismatch");
            end
            if (result_invalid_o != 16'd0) fail("K=4096 invalid result");
            for (integer lane = 0; lane < TILE_SIZE; lane++) begin
                if (result_data_o[lane*32 +: 32] !== EXPECTED_FP32) begin
                    $display("task=%0d row=%0d lane=%0d got=%08x expected=%08x",
                        expected_task, result_row_o, lane,
                        result_data_o[lane*32 +: 32], EXPECTED_FP32);
                    fail("K=4096 numeric mismatch");
                end
            end
            observed_rows <= observed_rows + 1;
            checked_values <= checked_values + TILE_SIZE;
        end
    end

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        a_valid_i = 16'd0;
        a_data_i = 128'd0;
        a_format_i = 32'd0;
        a_scale_i = 128'd0;
        a_block_first_i = 16'd0;
        a_block_last_i = 16'd0;
        a_matrix_first_i = 16'd0;
        a_matrix_last_i = 16'd0;
        a_tag_i = 128'd0;
        b_valid_i = 16'd0;
        b_data_i = 128'd0;
        b_format_i = 32'd0;
        b_scale_i = 128'd0;
        scenario_id = 4'd0;
        observed_rows = 0;
        checked_values = 0;
        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        for (integer task_index = 0; task_index < TASK_COUNT; task_index++) begin
            scenario_id = 4'(task_index + 1);
            for (integer local_cycle = 0;
                 local_cycle < K_SIZE; local_cycle++) begin
                drive_block_major_cycle(task_index, local_cycle);
                @(negedge clk_i);
            end
        end
        a_valid_i = 16'd0;
        b_valid_i = 16'd0;
        while (observed_rows < EXPECTED_ROWS) @(posedge clk_i);
        repeat (4) @(posedge clk_i);
        if (accepted_cycles != TASK_COUNT*K_SIZE) begin
            fail("K=4096 accepted cycle count mismatch");
        end
        if (checked_values != EXPECTED_ROWS*TILE_SIZE) begin
            fail("K=4096 checked value count mismatch");
        end
        if (output_overflow_o) fail("K=4096 result FIFO overflowed");
        $display("PASS: Tile K=4096 tasks=%0d cycles=%0d values=%0d compute_no_bubble=1",
            TASK_COUNT, accepted_cycles, checked_values);
        $finish;
    end

    initial begin
        repeat (20000) @(posedge clk_i);
        fail("timeout");
    end

endmodule

`default_nettype wire
