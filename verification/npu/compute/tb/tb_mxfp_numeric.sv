`timescale 1ns/1ps
`default_nettype none

module tb_mxfp_numeric;

    localparam int unsigned CASE_COUNT = 90;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic valid_i;
    logic [7:0] a_data_i;
    logic [7:0] b_data_i;
    logic [7:0] a_scale_i;
    logic [7:0] b_scale_i;
    mxfp_pkg::mxfp_format_e a_format_i;
    mxfp_pkg::mxfp_format_e b_format_i;
    logic valid_o;
    mxfp_pkg::mxfp_product_t product_o;
    logic invalid_o;
    logic [31:0] decoded_fp32;
    logic decoded_invalid;
    logic [55:0] reference_mem [0:CASE_COUNT-1];
    integer checks;
    integer case_index;

    mxfp_to_fp32 u_decode (
        .data_i    (a_data_i),
        .format_i  (a_format_i),
        .scale_i   (a_scale_i),
        .data_o    (decoded_fp32),
        .invalid_o (decoded_invalid)
    );

    mxfp_decoded_mul_pair u_pair (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i), .valid_i(valid_i),
        .a_data_i(a_data_i), .a_format_i(a_format_i), .a_scale_i(a_scale_i),
        .b_data_i(b_data_i), .b_format_i(b_format_i), .b_scale_i(b_scale_i),
        .valid_o(valid_o), .product_o(product_o), .invalid_o(invalid_o)
    );

    always #5 clk_i = ~clk_i;

    task automatic fail(input string message);
        begin
            $display("FAIL: %s", message);
            $fatal(1);
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        valid_i = 1'b0;
        a_data_i = 8'd0;
        b_data_i = 8'd0;
        a_scale_i = 8'd127;
        b_scale_i = 8'd127;
        a_format_i = mxfp_pkg::MXFP4_E2M1;
        b_format_i = mxfp_pkg::MXFP4_E2M1;
        checks = 0;
        $readmemh("build/reference/mxfp_decode.hex", reference_mem);

        repeat (2) @(posedge clk_i);
        rst_i <= 1'b0;
        @(posedge clk_i);

        for (case_index = 0; case_index < CASE_COUNT; case_index++) begin
            a_format_i = mxfp_pkg::mxfp_format_e'(reference_mem[case_index][55:52]);
            a_data_i = reference_mem[case_index][51:44];
            a_scale_i = reference_mem[case_index][43:36];
            #1;
            if (decoded_fp32 !== reference_mem[case_index][35:4]) begin
                $display("case=%0d fmt=%0d raw=%02x scale=%02x got=%08x expected=%08x",
                         case_index, a_format_i, a_data_i, a_scale_i,
                         decoded_fp32, reference_mem[case_index][35:4]);
                fail("MX decode mismatch");
            end
            if (decoded_invalid !== reference_mem[case_index][0]) begin
                fail("MX invalid mismatch");
            end
            checks = checks + 1;
        end

        a_format_i = mxfp_pkg::MXFP4_E2M1;
        b_format_i = mxfp_pkg::MXFP8_E4M3;
        a_data_i = 8'h07;
        b_data_i = 8'h40;
        a_scale_i = 8'd130;
        b_scale_i = 8'd125;
        @(negedge clk_i);
        valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        if (!valid_o || invalid_o || product_o.sign || product_o.is_zero ||
            product_o.is_inf || product_o.is_nan ||
            (product_o.significand != 8'd96) ||
            (product_o.element_exponent != 9'sd3) ||
            (product_o.scale_exponent != 10'sd1)) begin
            $display("product valid=%0b invalid=%0b sig=%0d elem_exp=%0d scale_exp=%0d",
                     valid_o, invalid_o, product_o.significand,
                     product_o.element_exponent, product_o.scale_exponent);
            fail("MX exact product metadata mismatch");
        end
        valid_i = 1'b0;
        @(posedge clk_i);
        checks = checks + 1;

        clear_i = 1'b1;
        @(posedge clk_i);
        clear_i = 1'b0;
        #1;
        if (valid_o) begin
            fail("clear did not cancel MX product valid");
        end
        checks = checks + 1;

        $display("PASS: MX numeric checks=%0d", checks);
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clk_i);
        fail("timeout");
    end

endmodule

/* verilator lint_off DECLFILENAME */
module mxfp_decoded_mul_pair (
    input logic clk_i,
    input logic rst_i,
    input logic clear_i,
    input logic valid_i,
    input logic [7:0] a_data_i,
    input mxfp_pkg::mxfp_format_e a_format_i,
    input logic [7:0] a_scale_i,
    input logic [7:0] b_data_i,
    input mxfp_pkg::mxfp_format_e b_format_i,
    input logic [7:0] b_scale_i,
    output logic valid_o,
    output mxfp_pkg::mxfp_product_t product_o,
    output logic invalid_o
);

    mxfp_pkg::mxfp_decoded_t a_decoded;
    mxfp_pkg::mxfp_decoded_t b_decoded;

    mxfp_unpack u_a (
        .data_i(a_data_i), .format_i(a_format_i), .scale_i(a_scale_i),
        .decoded_o(a_decoded)
    );
    mxfp_unpack u_b (
        .data_i(b_data_i), .format_i(b_format_i), .scale_i(b_scale_i),
        .decoded_o(b_decoded)
    );
    mxfp_mul_exact u_mul (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i), .valid_i(valid_i),
        .a_i(a_decoded), .b_i(b_decoded), .valid_o(valid_o),
        .product_o(product_o), .invalid_o(invalid_o)
    );

endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
