`timescale 1ns/1ps
`default_nettype none

module tb_gemm_array16_peak;

    localparam int unsigned ARRAY_DIM = 16;
    localparam int unsigned NODE_COUNT = ARRAY_DIM * ARRAY_DIM;
    localparam int unsigned TILE_SIZE = 16;
    localparam int unsigned K_ELEMENTS = 256;
    localparam int unsigned WAVE_CYCLES = K_ELEMENTS;
    localparam int unsigned EXPECTED_RESULT_BEATS = NODE_COUNT * TILE_SIZE;
    localparam logic [31:0] EXPECTED_FP32 = 32'h43800000;
    localparam logic [7:0] TASK_TAG = 8'h5a;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic [ARRAY_DIM*16-1:0] direct_a_valid;
    logic [ARRAY_DIM*128-1:0] direct_a_data;
    logic [ARRAY_DIM*32-1:0] direct_a_format;
    logic [ARRAY_DIM*128-1:0] direct_a_scale;
    logic [ARRAY_DIM*16-1:0] direct_a_block_first;
    logic [ARRAY_DIM*16-1:0] direct_a_block_last;
    logic [ARRAY_DIM*16-1:0] direct_a_matrix_first;
    logic [ARRAY_DIM*16-1:0] direct_a_matrix_last;
    logic [ARRAY_DIM*128-1:0] direct_a_tag;
    logic [ARRAY_DIM*16-1:0] direct_b_valid;
    logic [ARRAY_DIM*128-1:0] direct_b_data;
    logic [ARRAY_DIM*32-1:0] direct_b_format;
    logic [ARRAY_DIM*128-1:0] direct_b_scale;
    logic [NODE_COUNT-1:0] result_valid;
    logic [NODE_COUNT*512-1:0] result_data;
    logic [NODE_COUNT*16-1:0] result_invalid;
    logic [NODE_COUNT*8-1:0] result_tag;
    logic [NODE_COUNT*4-1:0] result_row;
    logic [NODE_COUNT*6-1:0] result_level;
    logic [NODE_COUNT-1:0] input_pair_issue;
    logic [NODE_COUNT-1:0] output_overflow;
    logic [3:0] scenario_id;
    logic [3:0] expected_row_q [0:NODE_COUNT-1];
    integer input_wave_beats;
    integer full_input_cycles;
    integer observed_result_beats;
    integer checked_values;
    integer issue_events;
    integer peak_result_beats;

    /* verilator lint_off PINCONNECTEMPTY */
    GEMM_65536 #(
        .ARRAY_X(ARRAY_DIM),
        .ARRAY_Y(ARRAY_DIM),
        .CONTROL_TREE_FANOUT(16)
    ) u_dut (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .direct_a_valid_i(direct_a_valid),
        .direct_a_data_i(direct_a_data),
        .direct_a_format_i(direct_a_format),
        .direct_a_scale_i(direct_a_scale),
        .direct_a_block_first_i(direct_a_block_first),
        .direct_a_block_last_i(direct_a_block_last),
        .direct_a_matrix_first_i(direct_a_matrix_first),
        .direct_a_matrix_last_i(direct_a_matrix_last),
        .direct_a_tag_i(direct_a_tag),
        .direct_b_valid_i(direct_b_valid),
        .direct_b_data_i(direct_b_data),
        .direct_b_format_i(direct_b_format),
        .direct_b_scale_i(direct_b_scale),
        .result_ready_i('1),
        .result_valid_o(result_valid),
        .result_data_o(result_data),
        .result_invalid_o(result_invalid),
        .result_tag_o(result_tag),
        .result_row_o(result_row),
        .result_level_o(result_level),
        .input_pair_issue_o(input_pair_issue),
        .output_overflow_o(output_overflow)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #2 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/gemm_array16_peak.vcd");
        $dumpvars(0, tb_gemm_array16_peak);
    end
`endif

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    task automatic drive_dense_cycle(input integer k_index);
        begin
            direct_a_valid = '1;
            direct_b_valid = '1;
            direct_a_data = {ARRAY_DIM*TILE_SIZE{8'h38}};
            direct_b_data = {ARRAY_DIM*TILE_SIZE{8'h38}};
            direct_a_block_first = '0;
            direct_a_block_last = '0;
            direct_a_matrix_first = '0;
            direct_a_matrix_last = '0;
            for (integer physical = 0; physical < ARRAY_DIM; physical++) begin
                for (integer lane = 0; lane < TILE_SIZE; lane++) begin
                    direct_a_block_first[physical*TILE_SIZE + lane] =
                        !k_index[4];
                    direct_a_block_last[physical*TILE_SIZE + lane] =
                        k_index[4];
                    direct_a_matrix_first[physical*TILE_SIZE + lane] =
                        (k_index < TILE_SIZE);
                    direct_a_matrix_last[physical*TILE_SIZE + lane] =
                        (k_index >= K_ELEMENTS-TILE_SIZE);
                end
            end
        end
    endtask

    always @(posedge clk_i) begin
        integer cycle_issues;
        if (rst_i || clear_i) begin
            input_wave_beats <= 0;
            full_input_cycles <= 0;
            issue_events <= 0;
        end else begin
            if ((|direct_a_valid) || (|direct_b_valid)) begin
                if (!(|direct_a_valid) || !(|direct_b_valid)) begin
                    fail("A/B array boundary wavefronts diverged");
                end
                input_wave_beats <= input_wave_beats + 1;
                if ((&direct_a_valid) && (&direct_b_valid)) begin
                    full_input_cycles <= full_input_cycles + 1;
                end
            end
            cycle_issues = 0;
            for (integer node = 0; node < NODE_COUNT; node++) begin
                if (input_pair_issue[node]) begin
                    cycle_issues = cycle_issues + 1;
                end
            end
            issue_events <= issue_events + cycle_issues;
        end
    end

    always @(negedge clk_i) begin
        integer cycle_results;
        if (rst_i || clear_i) begin
            observed_result_beats <= 0;
            checked_values <= 0;
            peak_result_beats <= 0;
            for (integer node = 0; node < NODE_COUNT; node++) begin
                expected_row_q[node] <= 4'd0;
            end
        end else begin
            cycle_results = 0;
            for (integer node = 0; node < NODE_COUNT; node++) begin
                if (result_valid[node]) begin
                    cycle_results = cycle_results + 1;
                    if (result_tag[node*8 +: 8] !== TASK_TAG ||
                        result_row[node*4 +: 4] !== expected_row_q[node]) begin
                        $display("node=%0d got_tag=%02x got_row=%0d expected_row=%0d",
                            node, result_tag[node*8 +: 8],
                            result_row[node*4 +: 4], expected_row_q[node]);
                        fail("full-array result metadata mismatch");
                    end
                    if (result_invalid[node*16 +: 16] != 16'd0) begin
                        fail("full-array result invalid flag asserted");
                    end
                    for (integer lane = 0; lane < TILE_SIZE; lane++) begin
                        if (result_data[node*512 + lane*32 +: 32] !==
                            EXPECTED_FP32) begin
                            $display("node=%0d row=%0d lane=%0d got=%08x expected=%08x",
                                node, result_row[node*4 +: 4], lane,
                                result_data[node*512 + lane*32 +: 32],
                                EXPECTED_FP32);
                            fail("full-array numeric mismatch");
                        end
                    end
                    expected_row_q[node] <= expected_row_q[node] + 4'd1;
                end
            end
            observed_result_beats <= observed_result_beats + cycle_results;
            checked_values <= checked_values + cycle_results*TILE_SIZE;
            if (cycle_results > peak_result_beats) begin
                peak_result_beats <= cycle_results;
            end
        end
    end

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        direct_a_valid = '0;
        direct_a_data = '0;
        direct_a_format = {ARRAY_DIM*TILE_SIZE{mxfp_pkg::MXFP8_E4M3}};
        direct_a_scale = {ARRAY_DIM*TILE_SIZE{8'd127}};
        direct_a_block_first = '0;
        direct_a_block_last = '0;
        direct_a_matrix_first = '0;
        direct_a_matrix_last = '0;
        direct_a_tag = {ARRAY_DIM*TILE_SIZE{TASK_TAG}};
        direct_b_valid = '0;
        direct_b_data = '0;
        direct_b_format = {ARRAY_DIM*TILE_SIZE{mxfp_pkg::MXFP8_E4M3}};
        direct_b_scale = {ARRAY_DIM*TILE_SIZE{8'd127}};
        scenario_id = 4'd0;

        repeat (12) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        repeat (12) @(posedge clk_i);

        scenario_id = 4'd1;
        for (integer wave_cycle = 0; wave_cycle < WAVE_CYCLES; wave_cycle++) begin
            drive_dense_cycle(wave_cycle);
            @(negedge clk_i);
        end
        direct_a_valid = '0;
        direct_b_valid = '0;

        scenario_id = 4'd2;
        while (observed_result_beats < EXPECTED_RESULT_BEATS) @(posedge clk_i);
        repeat (12) @(posedge clk_i);

        if (input_wave_beats != WAVE_CYCLES) begin
            fail("full-array input wavefront count mismatch");
        end
        if (full_input_cycles != K_ELEMENTS) begin
            fail("full-array 256-lane peak input cycle count mismatch");
        end
        if (observed_result_beats != EXPECTED_RESULT_BEATS ||
            checked_values != EXPECTED_RESULT_BEATS*TILE_SIZE) begin
            fail("full-array result count mismatch");
        end
        if (peak_result_beats < ARRAY_DIM) begin
            $display("peak_result_beats=%0d", peak_result_beats);
            fail("full-array output did not reach sixteen 512-bit beats per cycle");
        end
        if (issue_events != NODE_COUNT*K_ELEMENTS) begin
            $display("issue_events=%0d expected=%0d", issue_events,
                     NODE_COUNT*K_ELEMENTS);
            fail("full-array Tile issue count contains a compute bubble");
        end
        if (|output_overflow) begin
            fail("full-array protocol error asserted");
        end
        $display("PASS: full 16x16 Tile array dense_cycles=%0d results=%0d values=%0d peak_results=%0d issue_events=%0d peak_tops_1ghz=131.072",
            input_wave_beats, observed_result_beats, checked_values,
            peak_result_beats, issue_events);
        $finish;
    end

    initial begin
        repeat (4000) @(posedge clk_i);
        fail("timeout");
    end

    wire _unused_status = &{1'b0, result_level};

endmodule

`default_nettype wire
