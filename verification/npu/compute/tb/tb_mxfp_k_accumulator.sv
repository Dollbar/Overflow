`timescale 1ns/1ps
`default_nettype none

module tb_mxfp_k_accumulator;

    localparam int unsigned MAX_BLOCKS = (256*4096)/32;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic start_i;
    logic start_ready_o;
    logic [4:0] rows_i;
    logic [15:0] k_blocks_i;
    logic stream_first_i;
    logic stream_last_i;
    logic [3:0] stream_row_i;
    logic [7:0] stream_tag_i;
    logic partial_valid_i;
    logic partial_ready_o;
    logic [1119:0] partial_exact_i;
    logic [31:0] partial_special_i;
    logic [31:0] partial_zero_sign_i;
    logic [15:0] partial_invalid_i;
    logic [159:0] partial_scale_exponent_i;
    logic result_ready_i;
    logic result_valid_o;
    logic [511:0] result_data_o;
    logic [15:0] result_invalid_o;
    logic [7:0] result_tag_o;
    logic [3:0] result_row_o;
    logic busy_o;
    logic block_done_o;
    logic done_o;
    logic protocol_error_o;
    integer checks;
    logic [3:0] scenario_id;
    wire _unused_status = &{1'b0, busy_o, block_done_o, done_o,
                            result_tag_o, result_row_o, scenario_id};

    tile_fp32_k_accumulator u_dut (.*);

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/mxfp_k_accumulator.vcd");
        $dumpvars(0, tb_mxfp_k_accumulator);
    end
`endif

`ifdef DEBUG_ACCUM
    always @(negedge clk_i) begin
        $display("t=%0t partial=%0b merge=%0b final=%0b convert=%0b/%08x push=%0b level=%0d read=%0b resp=%0b qlevel=%0d out=%0b/%08x",
                 $time, u_dut.partial_fire, u_dut.merge_valid_q,
                 u_dut.final_valid_q, &u_dut.convert_valid,
                 u_dut.convert_data[31:0], u_dut.result_push,
                 u_dut.result_level_q, u_dut.result_mem_read,
                 u_dut.result_mem_response, u_dut.result_queue_level_q,
                 result_valid_o, result_data_o[31:0]);
    end
`endif

    task automatic fail(input string message);
        begin
            $display("FAIL: %s", message);
            $fatal(1);
        end
    endtask

    task automatic issue_partial(
        input logic signed [69:0] value,
        input logic signed [9:0] scale
    );
        begin
            while (!partial_ready_o) @(posedge clk_i);
            @(negedge clk_i);
            partial_valid_i = 1'b1;
            for (integer lane = 0; lane < 16; lane++) begin
                partial_exact_i[lane*70 +: 70] = value;
                partial_scale_exponent_i[lane*10 +: 10] = scale;
            end
            @(posedge clk_i);
            @(negedge clk_i);
            partial_valid_i = 1'b0;
        end
    endtask

    task automatic issue_command(input logic [15:0] block_count);
        begin
            while (!start_ready_o) @(posedge clk_i);
            @(negedge clk_i);
            rows_i = 5'd1;
            k_blocks_i = block_count;
            start_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            start_i = 1'b0;
        end
    endtask

    task automatic accept_result;
        begin
            @(negedge clk_i);
            result_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            result_ready_i = 1'b0;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        start_i = 1'b0;
        rows_i = 5'd1;
        k_blocks_i = 16'd1;
        stream_first_i = 1'b0;
        stream_last_i = 1'b0;
        stream_row_i = 4'd0;
        stream_tag_i = 8'd0;
        partial_valid_i = 1'b0;
        partial_exact_i = '0;
        partial_special_i = '0;
        partial_zero_sign_i = '0;
        partial_invalid_i = '0;
        partial_scale_exponent_i = '0;
        result_ready_i = 1'b0;
        checks = 0;
        scenario_id = 4'd0;

        repeat (3) @(posedge clk_i);
        rst_i = 1'b0;
        issue_command(16'd1);

        // One 32-element block sum is 2.0 in Q32. Scale exponent +1 produces
        // 4.0 exactly in every lane.
        scenario_id = 4'd1;
        issue_partial(70'sd8589934592, 10'sd1);
        while (!result_valid_o) @(posedge clk_i);
        #1;
        for (integer lane = 0; lane < 16; lane++) begin
            if (result_data_o[lane*32 +: 32] !== 32'h40800000) begin
                $display("lane=%0d got=%08x", lane,
                         result_data_o[lane*32 +: 32]);
                fail("scaled MX block accumulation mismatch");
            end
        end
        if (result_invalid_o != 16'd0 || protocol_error_o) begin
            fail("unexpected invalid or protocol error");
        end
        checks = checks + 16;

        repeat (2) begin
            @(posedge clk_i);
            #1;
            if (!result_valid_o ||
                (result_data_o[31:0] !== 32'h40800000)) begin
                fail("result did not remain stable under backpressure");
            end
            checks = checks + 1;
        end
        accept_result();

        // Rounding each block to FP32 would discard every +32 block. Exact
        // accumulation produces 2^30+96, which rounds to the next FP32 value.
        scenario_id = 4'd2;
        issue_command(16'd4);
        issue_partial(70'sd4611686018427387904, 10'sd0);
        repeat (3) issue_partial(70'sd137438953472, 10'sd0);
        while (!result_valid_o) @(posedge clk_i);
        #1;
        for (integer lane = 0; lane < 16; lane++) begin
            if (result_data_o[lane*32 +: 32] !== 32'h4e800001) begin
                $display("lane=%0d got=%08x", lane,
                         result_data_o[lane*32 +: 32]);
                fail("intermediate-rounding regression mismatch");
            end
        end
        if (result_invalid_o != 16'd0 || protocol_error_o) begin
            fail("unexpected invalid or protocol error after exact accumulation");
        end
        checks = checks + 16;
        accept_result();

`ifndef TRACE
        // 32768 exact 32-product blocks exercise the complete 2^20-product
        // contract. Each block is 32*2^30, so the final exact value is 2^50.
        scenario_id = 4'd3;
        issue_command(16'(MAX_BLOCKS));
        repeat (MAX_BLOCKS)
            issue_partial(70'sd147573952589676412928, 10'sd0);
        while (!result_valid_o) @(posedge clk_i);
        #1;
        for (integer lane = 0; lane < 16; lane++) begin
            if (result_data_o[lane*32 +: 32] !== 32'h58800000) begin
                $display("lane=%0d got=%08x", lane,
                         result_data_o[lane*32 +: 32]);
                fail("85-bit maximum accumulation mismatch");
            end
        end
        if (result_invalid_o != 16'd0 || protocol_error_o) begin
            fail("unexpected invalid or protocol error at maximum length");
        end
        checks = checks + 16;
        accept_result();
`endif

        @(negedge clk_i);
        scenario_id = 4'd4;
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;
        repeat (2) @(posedge clk_i);
        if (result_valid_o || protocol_error_o) begin
            fail("clear recovery failed");
        end
        checks = checks + 1;

`ifdef TRACE
        $display("PASS: directed MX K accumulator checks=%0d", checks);
`else
        $display("PASS: MX K accumulator checks=%0d max_products=%0d",
                 checks, MAX_BLOCKS*32);
`endif
        $finish;
    end

    initial begin
        repeat (2*MAX_BLOCKS + 2000) @(posedge clk_i);
        fail("timeout");
    end

endmodule

`default_nettype wire
