`timescale 1ns/1ps
`default_nettype none

module tb_gemm_boundary_skew;

    localparam int unsigned LANES = 4;
    localparam int unsigned PAYLOAD_WIDTH = 8;
    localparam int unsigned HISTORY_DEPTH = 128;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic [LANES-1:0] valid_i;
    logic [LANES*PAYLOAD_WIDTH-1:0] payload_i;
    logic [LANES-1:0] valid_o;
    logic [LANES*PAYLOAD_WIDTH-1:0] payload_o;
    logic [3:0] scenario_id;
    logic [LANES-1:0] valid_history [0:HISTORY_DEPTH-1];
    logic [LANES*PAYLOAD_WIDTH-1:0] payload_history [0:HISTORY_DEPTH-1];
    integer epoch_cycle;

    gemm_boundary_skew #(
        .LANES(LANES),
        .PAYLOAD_WIDTH(PAYLOAD_WIDTH)
    ) u_dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .valid_i(valid_i),
        .payload_i(payload_i),
        .valid_o(valid_o),
        .payload_o(payload_o)
    );

    always #2 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/gemm_boundary_skew.vcd");
        $dumpvars(0, tb_gemm_boundary_skew);
    end
`endif

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d epoch_cycle=%0d %s",
                scenario_id, epoch_cycle, message);
            $fatal(1);
        end
    endtask

    task automatic stream_step(
        input logic [LANES-1:0] step_valid,
        input logic [LANES*PAYLOAD_WIDTH-1:0] step_payload
    );
        logic expected_valid;
        logic [PAYLOAD_WIDTH-1:0] expected_payload;
        begin
            @(negedge clk_i);
            valid_i = step_valid;
            payload_i = step_payload;
            valid_history[epoch_cycle] = step_valid;
            payload_history[epoch_cycle] = step_payload;
            // Check the boundary values that the array will sample at the
            // following rising edge, before the skew registers advance.
            #1;
            for (integer lane = 0; lane < LANES; lane++) begin
                expected_valid = (epoch_cycle >= lane) ?
                    valid_history[epoch_cycle-lane][lane] : 1'b0;
                if (valid_o[lane] !== expected_valid) begin
                    fail("lane valid delay mismatch");
                end
                if (expected_valid) begin
                    expected_payload = payload_history[epoch_cycle-lane][
                        lane*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
                    if (payload_o[lane*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] !==
                        expected_payload) begin
                        fail("lane payload delay mismatch");
                    end
                end
            end
            @(posedge clk_i);
            epoch_cycle = epoch_cycle + 1;
        end
    endtask

    task automatic flush_with_clear;
        begin
            @(negedge clk_i);
            valid_i = '0;
            clear_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            if (valid_o != '0) fail("clear did not flush in-flight valids");
            clear_i = 1'b0;
            epoch_cycle = 0;
        end
    endtask

    task automatic flush_with_reset;
        begin
            @(negedge clk_i);
            valid_i = '0;
            rst_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            if (valid_o != '0) fail("reset did not flush in-flight valids");
            rst_i = 1'b0;
            epoch_cycle = 0;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        valid_i = '0;
        payload_i = '0;
        scenario_id = 4'd0;
        epoch_cycle = 0;

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        scenario_id = 4'd1;
        for (integer cycle = 0; cycle < 8; cycle++) begin
            stream_step('1, {
                8'(cycle*4+3), 8'(cycle*4+2),
                8'(cycle*4+1), 8'(cycle*4)
            });
        end
        repeat (LANES) stream_step('0, '0);

        scenario_id = 4'd2;
        for (integer cycle = 0; cycle < 8; cycle++) begin
            stream_step((cycle[0] ? 4'b0101 : 4'b1010), {
                8'hd0 + 8'(cycle), 8'hc0 + 8'(cycle),
                8'hb0 + 8'(cycle), 8'ha0 + 8'(cycle)
            });
        end
        repeat (LANES) stream_step('0, '0);

        scenario_id = 4'd3;
        stream_step('1, 32'h44332211);
        repeat (LANES) stream_step('0, '0);

        scenario_id = 4'd4;
        repeat (3) stream_step('1, 32'h88776655);
        flush_with_clear();
        repeat (5) stream_step('1, 32'hccbbaa99);
        repeat (LANES) stream_step('0, '0);

        scenario_id = 4'd5;
        repeat (3) stream_step('1, 32'h10203040);
        flush_with_reset();
        repeat (5) stream_step('1, 32'h50607080);
        repeat (LANES) stream_step('0, '0);

        $display("PASS: boundary skew continuous/gapped/single/clear/reset");
        $finish;
    end

    initial begin
        repeat (300) @(posedge clk_i);
        fail("timeout");
    end

endmodule

`default_nettype wire
