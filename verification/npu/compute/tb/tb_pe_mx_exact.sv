`timescale 1ns/1ps
`default_nettype none

module tb_pe_mx_exact;

    localparam int unsigned BURST_PRODUCTS = 4096;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic a_valid_i;
    logic [7:0] a_i;
    mxfp_pkg::mxfp_format_e a_format_i;
    logic [7:0] a_scale_i;
    logic a_block_first_i;
    logic a_block_last_i;
    logic a_matrix_first_i;
    logic a_matrix_last_i;
    logic [7:0] a_tag_i;
    logic b_valid_i;
    logic [7:0] b_i;
    mxfp_pkg::mxfp_format_e b_format_i;
    logic [7:0] b_scale_i;
    logic a_valid_o;
    logic [7:0] a_o;
    logic b_valid_o;
    logic [7:0] b_o;
    logic product_valid_o;
    mxfp_pkg::mxfp_product_t product_o;
    logic product_invalid_o;
    logic [3:0] scenario_id;
    integer observed_products;

    /* verilator lint_off PINCONNECTEMPTY */
    PE_FP8 u_dut (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .a_valid_i(a_valid_i), .a_i(a_i), .a_format_i(a_format_i),
        .a_scale_i(a_scale_i), .a_block_first_i(a_block_first_i),
        .a_block_last_i(a_block_last_i),
        .a_matrix_first_i(a_matrix_first_i),
        .a_matrix_last_i(a_matrix_last_i), .a_tag_i(a_tag_i),
        .b_valid_i(b_valid_i), .b_i(b_i), .b_format_i(b_format_i),
        .b_scale_i(b_scale_i), .a_valid_o(a_valid_o), .a_o(a_o),
        .a_format_o(), .a_scale_o(), .a_block_first_o(),
        .a_block_last_o(), .a_matrix_first_o(), .a_matrix_last_o(),
        .a_tag_o(), .b_valid_o(b_valid_o), .b_o(b_o),
        .b_format_o(), .b_scale_o(), .product_valid_o(product_valid_o),
        .product_o(product_o), .product_invalid_o(product_invalid_o)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #0.5 clk_i = ~clk_i;

    task automatic fail(input string message);
        begin
            $display("FAIL: scenario=%0d %s", scenario_id, message);
            $fatal(1);
        end
    endtask

    task automatic drive_pair(
        input mxfp_pkg::mxfp_format_e format,
        input logic [7:0] a_value,
        input logic [7:0] b_value
    );
        begin
            a_valid_i = 1'b1;
            b_valid_i = 1'b1;
            a_format_i = format;
            b_format_i = format;
            a_i = a_value;
            b_i = b_value;
            a_scale_i = 8'd127;
            b_scale_i = 8'd127;
            @(negedge clk_i);
        end
    endtask

    task automatic stop_input;
        begin
            a_valid_i = 1'b0;
            b_valid_i = 1'b0;
        end
    endtask

    task automatic check_one_product(input logic expected_sign);
        begin
            if (!product_valid_o) fail("exact product valid missing");
            if (product_invalid_o || product_o.is_nan || product_o.is_inf ||
                product_o.is_zero) fail("unexpected exact-product status");
            if (product_o.sign !== expected_sign ||
                product_o.element_exponent !== 9'sd0 ||
                product_o.scale_exponent !== 10'sd0 ||
                product_o.significand !== 8'd64) begin
                $display("sign=%0b element_exp=%0d scale_exp=%0d sig=%0d",
                         product_o.sign, product_o.element_exponent,
                         product_o.scale_exponent, product_o.significand);
                fail("exact product payload mismatch");
            end
        end
    endtask

    always @(negedge clk_i) begin
        if (!rst_i && !clear_i && product_valid_o) begin
            observed_products <= observed_products + 1;
        end
    end

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        a_valid_i = 1'b0;
        a_i = 8'd0;
        a_format_i = mxfp_pkg::MXFP8_E4M3;
        a_scale_i = 8'd127;
        a_block_first_i = 1'b0;
        a_block_last_i = 1'b0;
        a_matrix_first_i = 1'b0;
        a_matrix_last_i = 1'b0;
        a_tag_i = 8'd0;
        b_valid_i = 1'b0;
        b_i = 8'd0;
        b_format_i = mxfp_pkg::MXFP8_E4M3;
        b_scale_i = 8'd127;
        scenario_id = 4'd0;
        observed_products = 0;
        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        scenario_id = 4'd1;
        drive_pair(mxfp_pkg::MXFP8_E4M3, 8'h38, 8'h38);
        stop_input();
        check_one_product(1'b0);
        if (!a_valid_o || !b_valid_o || a_o != 8'h38 || b_o != 8'h38)
            fail("registered A/B forwarding mismatch");
        @(negedge clk_i);

        scenario_id = 4'd2;
        drive_pair(mxfp_pkg::MXFP4_E2M1, 8'h0a, 8'h02);
        stop_input();
        check_one_product(1'b1);
        @(negedge clk_i);

        scenario_id = 4'd3;
        for (integer index = 0; index < BURST_PRODUCTS; index++) begin
            drive_pair(mxfp_pkg::MXFP8_E4M3, 8'h38, 8'h38);
        end
        stop_input();
        @(negedge clk_i);
        if (observed_products != BURST_PRODUCTS + 2)
            fail("one-product-per-cycle burst count mismatch");

        scenario_id = 4'd4;
        a_valid_i = 1'b1;
        b_valid_i = 1'b1;
        clear_i = 1'b1;
        @(negedge clk_i);
        clear_i = 1'b0;
        stop_input();
        if (product_valid_o || a_valid_o || b_valid_o)
            fail("clear did not flush PE valid state");

        $display("PASS: PE exact-only products=%0d one_product_per_cycle=1 no_accumulator=1",
                 observed_products);
        $finish;
    end

    initial begin
        repeat (BURST_PRODUCTS + 100) @(posedge clk_i);
        fail("timeout");
    end

endmodule

`default_nettype wire
