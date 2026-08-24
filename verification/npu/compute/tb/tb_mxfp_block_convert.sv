`timescale 1ns/1ps
`default_nettype none

module tb_mxfp_block_convert;
    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic valid_i;
    logic signed [69:0] exact_i;
    logic signed [9:0] scale_exponent_i;
    fp8_pkg::fp8_reduce_special_e special_i;
    fp8_pkg::fp8_reduce_zero_sign_e zero_sign_i;
    logic invalid_i;
    logic valid_o;
    logic [31:0] result_o;
    logic invalid_o;

    mxfp_block_sum_to_fp32 u_dut (.*);
    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/mxfp_block_convert.vcd");
        $dumpvars(0, tb_mxfp_block_convert);
    end
`endif

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        valid_i = 1'b0;
        exact_i = '0;
        scale_exponent_i = '0;
        special_i = fp8_pkg::FP8_REDUCE_NORMAL;
        zero_sign_i = fp8_pkg::FP8_ZERO_SIGN_ROUNDING;
        invalid_i = 1'b0;
        repeat (2) @(posedge clk_i);
        rst_i = 1'b0;
        @(negedge clk_i);
        exact_i = 70'sd8589934592;
        scale_exponent_i = 10'sd1;
        valid_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        valid_i = 1'b0;
        while (!valid_o) @(posedge clk_i);
        #1;
        if ((result_o !== 32'h40800000) || invalid_o) begin
            $display("FAIL: block converter got=%08x invalid=%0b",
                     result_o, invalid_o);
            $fatal(1);
        end
        $display("PASS: MX block converter");
        $finish;
    end

    initial begin
        repeat (100) @(posedge clk_i);
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
