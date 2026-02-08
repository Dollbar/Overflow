`timescale 1ns/1ps
`default_nettype none

module tb_local_mx_buffers;
    localparam int unsigned BANKS = 2;

    logic clk_i;
    logic rst_i;
    logic clear_i;
    logic tensor_write_valid;
    logic tensor_write_ready;
    logic tensor_write_weight;
    logic [3:0] tensor_write_buffer;
    logic tensor_write_bank;
    logic [31:0] tensor_write_offset;
    logic [127:0] tensor_write_data;
    logic [127:0] tensor_write_scale;
    logic [BANKS-1:0] feedback_write_valid;
    logic [BANKS-1:0] feedback_write_ready;
    logic [BANKS*4-1:0] feedback_write_buffer;
    logic [BANKS*32-1:0] feedback_write_offset;
    logic [BANKS*128-1:0] feedback_write_data;
    logic [BANKS*8-1:0] feedback_write_scale;
    logic activation_read_enable;
    logic [3:0] activation_read_buffer;
    logic [31:0] activation_read_offset;
    logic activation_read_valid;
    logic [BANKS*128-1:0] activation_read_data;
    logic [BANKS*128-1:0] activation_read_scale;
    logic weight_read_enable;
    logic [3:0] weight_read_buffer;
    logic [31:0] weight_read_offset;
    logic weight_read_valid;
    logic [BANKS*128-1:0] weight_read_data;
    logic [BANKS*128-1:0] weight_read_scale;
    logic tensor_error;

    logic vector_write_valid;
    logic vector_write_ready;
    logic vector_write_c;
    logic [3:0] vector_write_buffer;
    logic vector_write_bank;
    logic [31:0] vector_write_offset;
    logic [127:0] vector_write_data;
    logic [7:0] vector_write_scale;
    logic [BANKS-1:0] read_b_enable;
    logic [BANKS*4-1:0] read_b_buffer;
    logic [BANKS*32-1:0] read_b_offset;
    logic [BANKS-1:0] read_b_valid;
    logic [BANKS*128-1:0] read_b_data;
    logic [BANKS*8-1:0] read_b_scale;
    logic [BANKS-1:0] read_c_enable;
    logic [BANKS*4-1:0] read_c_buffer;
    logic [BANKS*32-1:0] read_c_offset;
    logic [BANKS-1:0] read_c_valid;
    logic [BANKS*128-1:0] read_c_data;
    logic [BANKS*8-1:0] read_c_scale;
    logic vector_error;
    logic [3:0] scenario_id;
    integer checks;

    npu_local_tensor_buffer #(
        .BUFFER_COUNT(2), .BANKS(BANKS), .VECTOR_DEPTH(8)
    ) u_tensor (
        .clk_i, .rst_i, .clear_i,
        .tensor_write_valid_i(tensor_write_valid),
        .tensor_write_ready_o(tensor_write_ready),
        .tensor_write_weight_i(tensor_write_weight),
        .tensor_write_buffer_id_i(tensor_write_buffer),
        .tensor_write_bank_i(tensor_write_bank),
        .tensor_write_offset_i(tensor_write_offset),
        .tensor_write_data_i(tensor_write_data),
        .tensor_write_scale_i(tensor_write_scale),
        .feedback_write_valid_i(feedback_write_valid),
        .feedback_write_ready_o(feedback_write_ready),
        .feedback_write_buffer_id_i(feedback_write_buffer),
        .feedback_write_offset_i(feedback_write_offset),
        .feedback_write_data_i(feedback_write_data),
        .feedback_write_scale_i(feedback_write_scale),
        .activation_read_enable_i(activation_read_enable),
        .activation_read_buffer_id_i(activation_read_buffer),
        .activation_read_offset_i(activation_read_offset),
        .activation_read_valid_o(activation_read_valid),
        .activation_read_data_o(activation_read_data),
        .activation_read_scale_o(activation_read_scale),
        .weight_read_enable_i(weight_read_enable),
        .weight_read_buffer_id_i(weight_read_buffer),
        .weight_read_offset_i(weight_read_offset),
        .weight_read_valid_o(weight_read_valid),
        .weight_read_data_o(weight_read_data),
        .weight_read_scale_o(weight_read_scale),
        .protocol_error_o(tensor_error));

    npu_local_vector_operand_buffer #(
        .BUFFER_COUNT(2), .BANKS(BANKS), .VECTOR_DEPTH(8)
    ) u_vector (
        .clk_i, .rst_i, .clear_i,
        .write_valid_i(vector_write_valid),
        .write_ready_o(vector_write_ready),
        .write_operand_c_i(vector_write_c),
        .write_buffer_id_i(vector_write_buffer),
        .write_bank_i(vector_write_bank),
        .write_offset_i(vector_write_offset),
        .write_data_i(vector_write_data),
        .write_scale_i(vector_write_scale),
        .read_b_enable_i(read_b_enable),
        .read_b_buffer_id_i(read_b_buffer),
        .read_b_offset_i(read_b_offset),
        .read_b_valid_o(read_b_valid),
        .read_b_data_o(read_b_data),
        .read_b_scale_o(read_b_scale),
        .read_c_enable_i(read_c_enable),
        .read_c_buffer_id_i(read_c_buffer),
        .read_c_offset_i(read_c_offset),
        .read_c_valid_o(read_c_valid),
        .read_c_data_o(read_c_data),
        .read_c_scale_o(read_c_scale),
        .protocol_error_o(vector_error));

    always #5 clk_i = ~clk_i;

`ifdef TRACE
    initial begin
        $dumpfile("build/waves/local_mx_buffers.vcd");
        $dumpvars(0, tb_local_mx_buffers);
    end
`endif

    task automatic fail(input string message);
        begin
            $display("FAIL: %s", message);
            $fatal(1);
        end
    endtask

    task automatic tensor_buffer_write(
        input logic weight, input logic bank, input logic [127:0] data,
        input logic [7:0] scale
    );
        begin
            @(negedge clk_i);
            tensor_write_weight = weight;
            tensor_write_bank = bank;
            tensor_write_data = data;
            tensor_write_scale = {16{scale}};
            tensor_write_valid = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            tensor_write_valid = 1'b0;
        end
    endtask

    task automatic vector_write(
        input logic operand_c, input logic bank, input logic [127:0] data,
        input logic [7:0] scale
    );
        begin
            @(negedge clk_i);
            vector_write_c = operand_c;
            vector_write_bank = bank;
            vector_write_data = data;
            vector_write_scale = scale;
            vector_write_valid = 1'b1;
            @(posedge clk_i);
            @(negedge clk_i);
            vector_write_valid = 1'b0;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_i = 1'b0;
        tensor_write_valid = 1'b0;
        tensor_write_weight = 1'b0;
        tensor_write_buffer = 4'd1;
        tensor_write_bank = 1'b0;
        tensor_write_offset = 32'd16;
        tensor_write_data = '0;
        tensor_write_scale = '0;
        feedback_write_valid = '0;
        feedback_write_buffer = {2{4'd1}};
        feedback_write_offset = {2{32'd16}};
        feedback_write_data = '0;
        feedback_write_scale = '0;
        activation_read_enable = 1'b0;
        activation_read_buffer = 4'd1;
        activation_read_offset = 32'd16;
        weight_read_enable = 1'b0;
        weight_read_buffer = 4'd1;
        weight_read_offset = 32'd16;
        vector_write_valid = 1'b0;
        vector_write_c = 1'b0;
        vector_write_buffer = 4'd1;
        vector_write_bank = 1'b0;
        vector_write_offset = 32'd16;
        vector_write_data = '0;
        vector_write_scale = '0;
        read_b_enable = '0;
        read_b_buffer = {2{4'd1}};
        read_b_offset = {2{32'd16}};
        read_c_enable = '0;
        read_c_buffer = {2{4'd1}};
        read_c_offset = {2{32'd16}};
        scenario_id = 4'd0;
        checks = 0;

        repeat (3) @(posedge clk_i);
        rst_i = 1'b0;

        scenario_id = 4'd1;
        tensor_buffer_write(1'b0, 1'b0, 128'h1111, 8'h71);
        tensor_buffer_write(1'b0, 1'b1, 128'h2222, 8'h72);
        tensor_buffer_write(1'b1, 1'b0, 128'h3333, 8'h73);
        tensor_buffer_write(1'b1, 1'b1, 128'h4444, 8'h74);
        @(negedge clk_i);
        activation_read_enable = 1'b1;
        weight_read_enable = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        activation_read_enable = 1'b0;
        weight_read_enable = 1'b0;
        if (!activation_read_valid || !weight_read_valid ||
            (activation_read_data[127:0] != 128'h1111) ||
            (activation_read_data[255:128] != 128'h2222) ||
            (activation_read_scale != {{16{8'h72}}, {16{8'h71}}}) ||
            (weight_read_data[127:0] != 128'h3333) ||
            (weight_read_data[255:128] != 128'h4444) ||
            (weight_read_scale != {{16{8'h74}}, {16{8'h73}}})) begin
            fail("tensor macro-controller read mismatch");
        end
        checks = checks + 8;

        scenario_id = 4'd2;
        @(negedge clk_i);
        feedback_write_data = {128'hbbbb, 128'haaaa};
        feedback_write_scale = 16'h7b7a;
        feedback_write_valid = 2'b11;
        @(posedge clk_i);
        @(negedge clk_i);
        feedback_write_valid = '0;
        activation_read_enable = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        activation_read_enable = 1'b0;
        if (!activation_read_valid ||
            (activation_read_data != {128'hbbbb, 128'haaaa}) ||
            (activation_read_scale != {{16{8'h7b}}, {16{8'h7a}}})) begin
            fail("feedback data/scale write mismatch");
        end
        checks = checks + 3;

        scenario_id = 4'd3;
        vector_write(1'b0, 1'b0, 128'h5555, 8'h75);
        vector_write(1'b0, 1'b1, 128'h6666, 8'h76);
        vector_write(1'b1, 1'b0, 128'h7777, 8'h77);
        vector_write(1'b1, 1'b1, 128'h8888, 8'h78);
        @(negedge clk_i);
        read_b_enable = 2'b11;
        read_c_enable = 2'b11;
        @(posedge clk_i);
        @(negedge clk_i);
        read_b_enable = '0;
        read_c_enable = '0;
        if ((read_b_valid != 2'b11) || (read_c_valid != 2'b11) ||
            (read_b_data != {128'h6666, 128'h5555}) ||
            (read_b_scale != 16'h7675) ||
            (read_c_data != {128'h8888, 128'h7777}) ||
            (read_c_scale != 16'h7877)) begin
            fail("Vector B/C macro-controller read mismatch");
        end
        checks = checks + 6;

        scenario_id = 4'd4;
        @(negedge clk_i);
        read_b_enable = 2'b11;
        activation_read_enable = 1'b1;
        clear_i = 1'b1;
        @(posedge clk_i);
        @(negedge clk_i);
        read_b_enable = '0;
        activation_read_enable = 1'b0;
        clear_i = 1'b0;
        if ((read_b_valid != 2'b00) || activation_read_valid ||
            tensor_error || vector_error) begin
            fail("local buffer clear recovery failed");
        end
        checks = checks + 3;

        $display("PASS: local MX buffer checks=%0d", checks);
        $finish;
    end

    initial begin
        repeat (1000) @(posedge clk_i);
        fail("timeout");
    end

    wire _unused = &{1'b0, tensor_write_ready, feedback_write_ready,
        vector_write_ready, scenario_id};
endmodule

`default_nettype wire
