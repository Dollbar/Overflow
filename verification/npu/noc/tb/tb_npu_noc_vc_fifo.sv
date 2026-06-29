`timescale 1ns/1ps
`default_nettype none

module tb_npu_noc_vc_fifo;

    localparam int unsigned WIDTH = 16;
    localparam int unsigned DEPTH = 3;

    logic clk;
    logic rst;
    logic clear;
    logic push_valid;
    logic push_ready;
    logic [WIDTH-1:0] push_data;
    logic pop_valid;
    logic pop_ready;
    logic [WIDTH-1:0] pop_data;
    logic [$clog2(DEPTH+1)-1:0] level;
    integer checked_words;

    npu_noc_vc_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(clear),
        .push_valid_i(push_valid),
        .push_ready_o(push_ready),
        .push_data_i(push_data),
        .pop_valid_o(pop_valid),
        .pop_ready_i(pop_ready),
        .pop_data_o(pop_data),
        .level_o(level)
    );

    always #0.5 clk = ~clk;

    task automatic push(input logic [WIDTH-1:0] data);
        @(negedge clk);
        push_data = data;
        push_valid = 1'b1;
        do @(posedge clk); while (!push_ready);
        @(negedge clk);
        push_valid = 1'b0;
    endtask

    task automatic pop_and_check(input logic [WIDTH-1:0] expected);
        @(negedge clk);
        pop_ready = 1'b1;
        do @(posedge clk); while (!pop_valid);
        if (pop_data !== expected) begin
            $fatal(1, "FIFO order mismatch expected=%h actual=%h",
                   expected, pop_data);
        end
        checked_words = checked_words + 1;
        @(negedge clk);
        pop_ready = 1'b0;
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        clear = 1'b0;
        push_valid = 1'b0;
        push_data = '0;
        pop_ready = 1'b0;
        checked_words = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        push(16'h1010);
        push(16'h2020);
        push(16'h3030);
        if (level != $bits(level)'(DEPTH) || push_ready) begin
            $fatal(1, "FIFO full state mismatch");
        end

        // A full FIFO accepts a push when a pop occurs in the same cycle.
        @(negedge clk);
        push_data = 16'h4040;
        push_valid = 1'b1;
        pop_ready = 1'b1;
        @(posedge clk);
        if (!push_ready || !pop_valid || pop_data !== 16'h1010) begin
            $fatal(1, "FIFO full-turnover mismatch");
        end
        checked_words = checked_words + 1;
        @(negedge clk);
        push_valid = 1'b0;
        pop_ready = 1'b0;

        pop_and_check(16'h2020);
        pop_and_check(16'h3030);
        pop_and_check(16'h4040);
        if (level != 0 || pop_valid) begin
            $fatal(1, "FIFO empty state mismatch");
        end

        push(16'habcd);
        @(negedge clk);
        clear = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear = 1'b0;
        @(posedge clk);
        if (level != 0 || pop_valid || !push_ready) begin
            $fatal(1, "FIFO clear state mismatch");
        end

        $display("PASS tb_npu_noc_vc_fifo checked_words=%0d", checked_words);
        $finish;
    end

endmodule

`default_nettype wire
