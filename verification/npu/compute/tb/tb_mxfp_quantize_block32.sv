`timescale 1ns/1ps
`default_nettype none

module tb_mxfp_quantize_block32;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic input_valid_i;
    logic input_ready_o;
    logic [511:0] input_data_i;
    logic [15:0] input_invalid_i;
    logic input_last_i;
    mxfp_pkg::mxfp_format_e format_i;
    logic output_valid_o;
    logic output_ready_i;
    logic [255:0] output_data_o;
    mxfp_pkg::mxfp_scale_t output_scale_o;
    logic [31:0] output_invalid_o;
    logic [31:0] output_overflow_o;
    logic [31:0] output_inexact_o;
    logic output_last_o;
    logic [3:0] scenario_id;
    integer checks;

    mxfp_quantize_block32 u_dut (.*);

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/mxfp_quantize_block32.vcd");
        $dumpvars(0, tb_mxfp_quantize_block32);
    end
`endif

    task automatic fail(input string message);
        begin
            $display("FAIL: %s", message);
            $fatal(1);
        end
    endtask

    task automatic send_beat(
        input logic [31:0] value,
        input logic [15:0] invalid,
        input logic last
    );
        begin
            while (!input_ready_o) @(posedge clk_i);
            @(negedge clk_i);
            for (integer lane = 0; lane < 16; lane++) begin
                input_data_i[lane*32 +: 32] = value;
            end
            input_invalid_i = invalid;
            input_last_i = last;
            input_valid_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            input_valid_i = 1'b0;
        end
    endtask

    task automatic check_block(
        input logic [7:0] expected_scale,
        input logic [7:0] expected_element,
        input logic expected_fp4,
        input logic [31:0] expected_invalid,
        input logic expected_last
    );
        begin
            while (!output_valid_o) @(posedge clk_i);
            #1;
            if (output_scale_o !== expected_scale) begin
                $display("scale got=%02x expected=%02x",
                         output_scale_o, expected_scale);
                fail("shared scale mismatch");
            end
            for (integer lane = 0; lane < 32; lane++) begin
                if (expected_fp4) begin
                    if (output_data_o[lane*4 +: 4] !==
                        expected_element[3:0]) begin
                        fail("MXFP4 packed element mismatch");
                    end
                end else if (output_data_o[lane*8 +: 8] !==
                             expected_element) begin
                    fail("MXFP8 element mismatch");
                end
            end
            if (expected_fp4 && (output_data_o[255:128] != 128'd0)) begin
                fail("MXFP4 unused output bits are not zero");
            end
            if ((output_invalid_o !== expected_invalid) ||
                (output_last_o !== expected_last)) begin
                fail("block metadata mismatch");
            end
            checks = checks + 35;

            repeat (2) begin
                @(posedge clk_i);
                #1;
                if (!output_valid_o ||
                    (output_scale_o !== expected_scale)) begin
                    fail("quantized block changed under backpressure");
                end
                checks = checks + 1;
            end
            @(negedge clk_i);
            output_ready_i = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            output_ready_i = 1'b0;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        input_valid_i = 1'b0;
        input_data_i = '0;
        input_invalid_i = '0;
        input_last_i = 1'b0;
        format_i = mxfp_pkg::MXFP8_E4M3;
        output_ready_i = 1'b0;
        scenario_id = 4'd0;
        checks = 0;

        repeat (3) @(posedge clk_i);
        rst_i = 1'b0;

        scenario_id = 4'd1;
        format_i = mxfp_pkg::MXFP8_E4M3;
        send_beat(32'h3f800000, 16'h0001, 1'b0);
        send_beat(32'h3f800000, 16'h8000, 1'b1);
        check_block(8'd119, 8'h78, 1'b0, 32'h80000001, 1'b1);

        scenario_id = 4'd2;
        format_i = mxfp_pkg::MXFP8_E4M3;
        send_beat(32'h3f800000, 16'd0, 1'b0);
        send_beat(32'h3f800000, 16'd0, 1'b0);
        check_block(8'd119, 8'h78, 1'b0, 32'd0, 1'b0);

        scenario_id = 4'd3;
        format_i = mxfp_pkg::MXFP4_E2M1;
        send_beat(32'h3f800000, 16'd0, 1'b0);
        send_beat(32'h3f800000, 16'd0, 1'b1);
        check_block(8'd125, 8'h06, 1'b1, 32'd0, 1'b1);

        scenario_id = 4'd4;
        format_i = mxfp_pkg::MXFP8_E4M3;
        send_beat(32'h7fc00000, 16'd0, 1'b0);
        send_beat(32'h3f800000, 16'd0, 1'b1);
        while (!output_valid_o) @(posedge clk_i);
        #1;
        if (output_scale_o !== mxfp_pkg::MX_E8M0_NAN) begin
            fail("NaN block did not select E8M0 NaN scale");
        end
        checks = checks + 1;
        @(negedge clk_i);
        output_ready_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        output_ready_i = 1'b0;

        scenario_id = 4'd5;
        send_beat(32'h3f800000, 16'd0, 1'b0);
        @(negedge clk_i);
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        clear_i = 1'b0;
        if (output_valid_o) begin
            fail("clear did not discard the partial MX block");
        end
        send_beat(32'h3f800000, 16'd0, 1'b0);
        send_beat(32'h3f800000, 16'd0, 1'b1);
        check_block(8'd119, 8'h78, 1'b0, 32'd0, 1'b1);

        $display("PASS: MX block quantizer checks=%0d", checks);
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clk_i);
        fail("timeout");
    end

    wire _unused_status = &{1'b0, output_overflow_o,
        output_inexact_o, scenario_id};

endmodule

`default_nettype wire
