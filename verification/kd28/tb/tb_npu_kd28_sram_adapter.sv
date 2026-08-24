`timescale 1ns/1ps
`default_nettype none

module tb_npu_kd28_sram_adapter;
    logic clk_i;
    logic rst_i;
    logic local_write_enable;
    logic [11:0] local_write_address;
    logic [127:0] local_write_data;
    logic local_read_enable;
    logic [11:0] local_read_address;
    logic local_read_valid;
    logic [127:0] local_read_data;
    logic [1:0] feedback_write_valid;
    logic [15:0] feedback_write_address;
    logic [527:0] feedback_write_data;
    logic [1:0] feedback_read_enable;
    logic [15:0] feedback_read_address;
    logic [1:0] feedback_read_valid;
    logic [527:0] feedback_read_data;
    integer check_count;

    localparam logic [127:0] LOCAL_DATA_0 =
        128'h00112233_44556677_8899aabb_ccddeeff;
    localparam logic [127:0] LOCAL_DATA_2047 =
        128'h10213243_54657687_98a9bacb_dcedfe0f;
    localparam logic [127:0] LOCAL_DATA_2048 =
        128'hffeeddcc_bbaa9988_77665544_33221100;
    localparam logic [127:0] LOCAL_DATA_4095 =
        128'hf0e0d0c0_b0a09080_70605040_30201000;
    localparam logic [263:0] FEEDBACK_DATA_0 = {
        8'ha1,
        128'h00112233_44556677_8899aabb_ccddeeff,
        128'h10213243_54657687_98a9bacb_dcedfe0f
    };
    localparam logic [263:0] FEEDBACK_DATA_1 = {
        8'hb2,
        128'hffeeddcc_bbaa9988_77665544_33221100,
        128'hf0e0d0c0_b0a09080_70605040_30201000
    };

    npu_local_sram_1w1r_macro #(
        .ADDRESS_WIDTH(12),
        .DATA_WIDTH(128)
    ) u_local_store (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .write_enable_i(local_write_enable),
        .write_address_i(local_write_address),
        .write_data_i(local_write_data),
        .read_enable_i(local_read_enable),
        .read_address_i(local_read_address),
        .read_valid_o(local_read_valid),
        .read_data_o(local_read_data)
    );

    npu_feedback_block_store_macro #(
        .CHANNELS(2),
        .ADDRESS_WIDTH(8),
        .DATA_WIDTH(264)
    ) u_feedback_store (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .write_valid_i(feedback_write_valid),
        .write_address_i(feedback_write_address),
        .write_data_i(feedback_write_data),
        .read_enable_i(feedback_read_enable),
        .read_address_i(feedback_read_address),
        .read_valid_o(feedback_read_valid),
        .read_data_o(feedback_read_data)
    );

    always #5 clk_i = ~clk_i;

    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        local_write_enable = 1'b0;
        local_write_address = '0;
        local_write_data = '0;
        local_read_enable = 1'b0;
        local_read_address = '0;
        feedback_write_valid = '0;
        feedback_write_address = '0;
        feedback_write_data = '0;
        feedback_read_enable = '0;
        feedback_read_address = '0;
        check_count = 0;

        repeat (3) @(negedge clk_i);
        rst_i = 1'b0;

        local_write_enable = 1'b1;
        local_write_address = 12'd0;
        local_write_data = LOCAL_DATA_0;
        @(negedge clk_i);
        local_write_address = 12'd2047;
        local_write_data = LOCAL_DATA_2047;
        @(negedge clk_i);
        local_write_address = 12'd2048;
        local_write_data = LOCAL_DATA_2048;
        @(negedge clk_i);
        local_write_address = 12'd4095;
        local_write_data = LOCAL_DATA_4095;
        @(negedge clk_i);
        local_write_enable = 1'b0;

        local_read_enable = 1'b1;
        local_read_address = 12'd0;
        @(negedge clk_i);
        if (!local_read_valid || (local_read_data !== LOCAL_DATA_0)) begin
            $fatal(1, "FAIL: KD28 local SRAM address zero");
        end
        check_count = check_count + 1;
        local_read_address = 12'd2047;
        @(negedge clk_i);
        if (!local_read_valid || (local_read_data !== LOCAL_DATA_2047)) begin
            $fatal(1, "FAIL: KD28 local SRAM lower depth-bank boundary");
        end
        check_count = check_count + 1;
        local_read_address = 12'd2048;
        @(negedge clk_i);
        if (!local_read_valid || (local_read_data !== LOCAL_DATA_2048)) begin
            $fatal(1, "FAIL: KD28 local SRAM upper depth-bank boundary");
        end
        check_count = check_count + 1;
        local_read_address = 12'd4095;
        @(negedge clk_i);
        if (!local_read_valid || (local_read_data !== LOCAL_DATA_4095)) begin
            $fatal(1, "FAIL: KD28 local SRAM final logical address");
        end
        check_count = check_count + 1;
        local_read_enable = 1'b0;
        @(negedge clk_i);
        if (local_read_valid) begin
            $fatal(1, "FAIL: KD28 local SRAM read-valid request gap");
        end
        check_count = check_count + 1;

        feedback_write_valid = 2'b11;
        feedback_write_address = {8'd255, 8'd3};
        feedback_write_data = {FEEDBACK_DATA_1, FEEDBACK_DATA_0};
        @(negedge clk_i);
        feedback_write_valid = '0;
        feedback_read_enable = 2'b11;
        feedback_read_address = {8'd255, 8'd3};
        @(negedge clk_i);
        if ((feedback_read_valid !== 2'b11) ||
            (feedback_read_data[263:0] !== FEEDBACK_DATA_0) ||
            (feedback_read_data[527:264] !== FEEDBACK_DATA_1)) begin
            $fatal(1, "FAIL: KD28 channelized feedback store");
        end
        check_count = check_count + 1;

        rst_i = 1'b1;
        @(negedge clk_i);
        if (local_read_valid || (feedback_read_valid != 2'b00)) begin
            $fatal(1, "FAIL: KD28 NPU SRAM reset did not suppress read-valid");
        end
        check_count = check_count + 1;
        rst_i = 1'b0;
        feedback_read_enable = '0;

        $display("[RTL_SIM PASS] npu_kd28_sram_adapter checks=%0d",
                 check_count);
        $finish;
    end

    initial begin
        repeat (300) @(posedge clk_i);
        $fatal(1, "FAIL: KD28 NPU SRAM adapter timeout");
    end
endmodule

`default_nettype wire
