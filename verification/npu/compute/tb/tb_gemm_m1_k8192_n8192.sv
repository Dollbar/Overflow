`timescale 1ns/1ps
`default_nettype none

// Narrow-M, K=8192, N=8192 is mapped onto the fixed 256-column GEMM array as
// thirty-two consecutive N waves.  Unused rows in the active Tile row are
// explicitly zero padded.  ARRAY_Y=2 instantiates the production
// active Tile row plus an idle row that checks row masking, while avoiding the
// cost of repeatedly evaluating all fourteen additional idle rows.
module tb_gemm_m1_k8192_n8192 #(
    parameter int unsigned M_ELEMENTS = 1
);

    localparam int unsigned ARRAY_X = 16;
    localparam int unsigned ARRAY_Y = 2;
    localparam int unsigned NODE_COUNT = ARRAY_X * ARRAY_Y;
    localparam int unsigned TILE_SIZE = 16;
    localparam int unsigned K_ELEMENTS = 8192;
    localparam int unsigned N_ELEMENTS = 8192;
    localparam int unsigned N_WAVE_WIDTH = ARRAY_X * TILE_SIZE;
    localparam int unsigned N_WAVES = N_ELEMENTS / N_WAVE_WIDTH;
    localparam int unsigned INPUT_CYCLES = N_WAVES * K_ELEMENTS;
    localparam int unsigned ACTIVE_NODES = ARRAY_X;
    localparam int unsigned EXPECTED_RESULT_BEATS =
        N_WAVES * ACTIVE_NODES * TILE_SIZE;
    localparam int unsigned EXPECTED_PHYSICAL_VALUES =
        EXPECTED_RESULT_BEATS * TILE_SIZE;
    localparam int unsigned EXPECTED_USEFUL_VALUES = M_ELEMENTS * N_ELEMENTS;
    localparam int unsigned EXPECTED_ISSUE_EVENTS =
        N_WAVES * K_ELEMENTS * ACTIVE_NODES;
    localparam int unsigned USEFUL_GOPS_1GHZ =
        M_ELEMENTS * N_WAVE_WIDTH * 2;
    localparam int unsigned PHYSICAL_GOPS_1GHZ =
        ACTIVE_NODES * TILE_SIZE * TILE_SIZE * 2;
    localparam logic [7:0] TAG_BASE = 8'h40;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic [ARRAY_Y*16-1:0] direct_a_valid;
    logic [ARRAY_Y*128-1:0] direct_a_data;
    logic [ARRAY_Y*32-1:0] direct_a_format;
    logic [ARRAY_Y*128-1:0] direct_a_scale;
    logic [ARRAY_Y*16-1:0] direct_a_block_first;
    logic [ARRAY_Y*16-1:0] direct_a_block_last;
    logic [ARRAY_Y*16-1:0] direct_a_matrix_first;
    logic [ARRAY_Y*16-1:0] direct_a_matrix_last;
    logic [ARRAY_Y*128-1:0] direct_a_tag;
    logic [ARRAY_X*16-1:0] direct_b_valid;
    logic [ARRAY_X*128-1:0] direct_b_data;
    logic [ARRAY_X*32-1:0] direct_b_format;
    logic [ARRAY_X*128-1:0] direct_b_scale;
    logic [NODE_COUNT-1:0] result_valid;
    logic [NODE_COUNT*512-1:0] result_data;
    logic [NODE_COUNT*16-1:0] result_invalid;
    logic [NODE_COUNT*8-1:0] result_tag;
    logic [NODE_COUNT*4-1:0] result_row;
    logic [NODE_COUNT*6-1:0] result_level;
    logic [NODE_COUNT-1:0] input_pair_issue;
    logic [NODE_COUNT-1:0] output_overflow;
    logic [3:0] scenario_id;
    logic [3:0] expected_row_q [0:ACTIVE_NODES-1];
    logic [7:0] expected_tag_q [0:ACTIVE_NODES-1];
    integer dense_input_cycles;
    integer observed_result_beats;
    integer checked_physical_values;
    integer checked_useful_values;
    integer checked_padding_values;
    integer issue_events;
    integer peak_result_beats;

    GEMM_65536 #(
        .ARRAY_X(ARRAY_X),
        .ARRAY_Y(ARRAY_Y),
        .CONTROL_TREE_FANOUT(16)
    ) u_dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
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

    always #2 clk_i = ~clk_i;

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    task automatic drive_dense_cycle(
        input logic [5:0] n_wave,
        input integer k_index
    );
        logic [7:0] weight_value;
        begin
            case (n_wave[1:0])
                2'd0: weight_value = 8'h38; // 1.0
                2'd1: weight_value = 8'h30; // 0.5
                2'd2: weight_value = 8'h40; // 2.0
                default: weight_value = 8'h28; // 0.25
            endcase

            direct_a_valid = '0;
            direct_a_valid[0 +: TILE_SIZE] = '1;
            direct_b_valid = '1;
            direct_a_data = '0;
            // Each group of sixteen input cycles loads a 16x16 A block:
            // cycle 0 is logical output row 0, cycles 1..15 are padded rows.
            if (integer'(k_index[3:0]) < M_ELEMENTS) begin
                direct_a_data[0 +: 128] = {TILE_SIZE{8'h38}};
            end
            direct_b_data = {ARRAY_X*TILE_SIZE{weight_value}};
            direct_a_block_first = '0;
            direct_a_block_last = '0;
            direct_a_matrix_first = '0;
            direct_a_matrix_last = '0;
            direct_a_tag = {ARRAY_Y*TILE_SIZE{TAG_BASE + 8'(n_wave)}};

            for (integer lane = 0; lane < TILE_SIZE; lane++) begin
                direct_a_block_first[lane] = !k_index[4];
                direct_a_block_last[lane] = k_index[4];
                direct_a_matrix_first[lane] = (k_index < TILE_SIZE);
                direct_a_matrix_last[lane] =
                    (k_index >= K_ELEMENTS-TILE_SIZE);
            end
        end
    endtask

    always @(posedge clk_i) begin
        integer cycle_issues;
        logic [ARRAY_Y*16-1:0] expected_a_valid;
        if (rst_i || clear_i) begin
            dense_input_cycles <= 0;
            issue_events <= 0;
        end else begin
            expected_a_valid = '0;
            expected_a_valid[0 +: TILE_SIZE] = '1;
            if ((|direct_a_valid) || (|direct_b_valid)) begin
                if ((direct_a_valid !== expected_a_valid) ||
                    (direct_b_valid !== '1)) begin
                    fail("narrow-M mapped boundary contains an input bubble");
                end
                dense_input_cycles <= dense_input_cycles + 1;
            end

            cycle_issues = 0;
            for (integer node = 0; node < NODE_COUNT; node++) begin
                if (input_pair_issue[node]) begin
                    if (node >= ACTIVE_NODES) begin
                        fail("idle Tile row issued a padded computation");
                    end
                    cycle_issues = cycle_issues + 1;
                end
            end
            issue_events <= issue_events + cycle_issues;
        end
    end

    always @(negedge clk_i) begin
        integer cycle_results;
        integer cycle_useful_values;
        integer cycle_padding_values;
        logic [31:0] expected_value;
        if (rst_i || clear_i) begin
            observed_result_beats <= 0;
            checked_physical_values <= 0;
            checked_useful_values <= 0;
            checked_padding_values <= 0;
            peak_result_beats <= 0;
            for (integer node = 0; node < ACTIVE_NODES; node++) begin
                expected_row_q[node] <= 4'd0;
                expected_tag_q[node] <= TAG_BASE;
            end
        end else begin
            cycle_results = 0;
            cycle_useful_values = 0;
            cycle_padding_values = 0;
            for (integer node = 0; node < NODE_COUNT; node++) begin
                if (result_valid[node]) begin
                    if (node >= ACTIVE_NODES) begin
                        fail("idle Tile row produced a padded result");
                    end
                    cycle_results = cycle_results + 1;
                    if ((result_tag[node*8 +: 8] !== expected_tag_q[node]) ||
                        (result_row[node*4 +: 4] !== expected_row_q[node]) ||
                        (result_invalid[node*16 +: 16] != 16'd0)) begin
                        $display("node=%0d tag=%02x expected_tag=%02x row=%0d expected_row=%0d",
                            node, result_tag[node*8 +: 8], expected_tag_q[node],
                            result_row[node*4 +: 4], expected_row_q[node]);
                        fail("narrow-M result metadata mismatch");
                    end

                    case (expected_tag_q[node][1:0])
                        2'd0: expected_value = 32'h46000000; // 8192.0
                        2'd1: expected_value = 32'h45800000; // 4096.0
                        2'd2: expected_value = 32'h46800000; // 16384.0
                        default: expected_value = 32'h45000000; // 2048.0
                    endcase
                    if (integer'(expected_row_q[node]) >= M_ELEMENTS) begin
                        expected_value = 32'h00000000;
                    end

                    for (integer lane = 0; lane < TILE_SIZE; lane++) begin
                        if (result_data[node*512 + lane*32 +: 32] !==
                            expected_value) begin
                            $display("node=%0d tag=%02x row=%0d lane=%0d got=%08x expected=%08x",
                                node, result_tag[node*8 +: 8],
                                result_row[node*4 +: 4], lane,
                                result_data[node*512 + lane*32 +: 32],
                                expected_value);
                            fail("narrow-M K=8192 N=8192 numeric mismatch");
                        end
                    end

                    if (integer'(expected_row_q[node]) < M_ELEMENTS) begin
                        cycle_useful_values =
                            cycle_useful_values + TILE_SIZE;
                    end else begin
                        cycle_padding_values =
                            cycle_padding_values + TILE_SIZE;
                    end
                    if (expected_row_q[node] == 4'd15) begin
                        expected_row_q[node] <= 4'd0;
                        expected_tag_q[node] <= expected_tag_q[node] + 8'd1;
                    end else begin
                        expected_row_q[node] <= expected_row_q[node] + 4'd1;
                    end
                end
            end
            observed_result_beats <= observed_result_beats + cycle_results;
            checked_physical_values <=
                checked_physical_values + cycle_results*TILE_SIZE;
            checked_useful_values <=
                checked_useful_values + cycle_useful_values;
            checked_padding_values <=
                checked_padding_values + cycle_padding_values;
            if (cycle_results > peak_result_beats) begin
                peak_result_beats <= cycle_results;
            end
        end
    end

    initial begin
        assert ((N_ELEMENTS % N_WAVE_WIDTH) == 0)
            else $error("N must contain complete 256-column waves");
        assert ((K_ELEMENTS % 32) == 0)
            else $error("K must contain complete 32-element MX blocks");
        assert ((M_ELEMENTS > 0) && (M_ELEMENTS <= TILE_SIZE))
            else $error("M must be in 1..16 for one active Tile row");

        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        direct_a_valid = '0;
        direct_a_data = '0;
        direct_a_format = {ARRAY_Y*TILE_SIZE{mxfp_pkg::MXFP8_E4M3}};
        direct_a_scale = {ARRAY_Y*TILE_SIZE{8'd127}};
        direct_a_block_first = '0;
        direct_a_block_last = '0;
        direct_a_matrix_first = '0;
        direct_a_matrix_last = '0;
        direct_a_tag = '0;
        direct_b_valid = '0;
        direct_b_data = '0;
        direct_b_format = {ARRAY_X*TILE_SIZE{mxfp_pkg::MXFP8_E4M3}};
        direct_b_scale = {ARRAY_X*TILE_SIZE{8'd127}};
        scenario_id = 4'd0;

        repeat (12) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;
        repeat (12) @(posedge clk_i);

        scenario_id = 4'd1;
        for (integer n_wave = 0; n_wave < N_WAVES; n_wave++) begin
            for (integer k_index = 0; k_index < K_ELEMENTS; k_index++) begin
                drive_dense_cycle(6'(n_wave), k_index);
                @(negedge clk_i);
            end
        end
        direct_a_valid = '0;
        direct_b_valid = '0;

        scenario_id = 4'd2;
        while (observed_result_beats < EXPECTED_RESULT_BEATS)
            @(posedge clk_i);
        repeat (16) @(posedge clk_i);

        if (dense_input_cycles != INPUT_CYCLES) begin
            fail("narrow-M input cycle count mismatch");
        end
        if ((observed_result_beats != EXPECTED_RESULT_BEATS) ||
            (checked_physical_values != EXPECTED_PHYSICAL_VALUES) ||
            (checked_useful_values != EXPECTED_USEFUL_VALUES) ||
            (checked_padding_values !=
             EXPECTED_PHYSICAL_VALUES-EXPECTED_USEFUL_VALUES)) begin
            fail("narrow-M result count mismatch");
        end
        if (issue_events != EXPECTED_ISSUE_EVENTS) begin
            $display("issue_events=%0d expected=%0d",
                issue_events, EXPECTED_ISSUE_EVENTS);
            fail("narrow-M mapped Tile issue count contains a compute bubble");
        end
        if (peak_result_beats < ACTIVE_NODES) begin
            fail("narrow-M output plane did not reach sixteen beats per cycle");
        end
        if (|output_overflow) begin
            fail("narrow-M output overflow asserted");
        end

        $display("PASS: GEMM M=%0d K=8192 N=8192 n_waves=%0d dense_cycles=%0d useful_results=%0d padded_results=%0d issue_events=%0d useful_tops_1ghz=%0d.%03d physical_tops_1ghz=%0d.%03d no_bubble=1",
            M_ELEMENTS, N_WAVES, dense_input_cycles, checked_useful_values,
            checked_padding_values, issue_events,
            USEFUL_GOPS_1GHZ/1000, USEFUL_GOPS_1GHZ%1000,
            PHYSICAL_GOPS_1GHZ/1000, PHYSICAL_GOPS_1GHZ%1000);
        $finish;
    end

    initial begin
        repeat (INPUT_CYCLES + 20000) @(posedge clk_i);
        fail("timeout");
    end

    wire _unused_status = &{1'b0, result_level};

endmodule

`default_nettype wire
