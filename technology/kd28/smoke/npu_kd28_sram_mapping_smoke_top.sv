`default_nettype none

module npu_kd28_sram_mapping_smoke_top (
    input  logic          clk_i,
    input  logic          rst_i,
    input  logic          valid_i,
    input  logic [14:0]   address_i,
    input  logic [527:0]  data_i,
    output logic [1103:0] data_o,
    output logic [4:0]    read_valid_o
);
    logic [127:0] local_read_data;
    logic local_read_valid;
    logic [527:0] feedback_read_data;
    logic [1:0] feedback_read_valid;
    logic [31:0] tdp32_a_data;
    logic [31:0] tdp32_b_data;
    logic [63:0] tdp64_a_data;
    logic [63:0] tdp64_b_data;
    logic [127:0] tdp128_a_data;
    logic [127:0] tdp128_b_data;
    logic tdp32_a_valid;
    logic tdp32_b_valid;
    logic tdp64_a_valid;
    logic tdp64_b_valid;
    logic tdp128_a_valid;
    logic tdp128_b_valid;

    npu_local_sram_1w1r_macro #(
        .ADDRESS_WIDTH(15), .DATA_WIDTH(128)
    ) u_local_store (
        .clk_i(clk_i), .rst_i(rst_i),
        .write_enable_i(valid_i), .write_address_i(address_i),
        .write_data_i(data_i[127:0]),
        .read_enable_i(valid_i), .read_address_i(address_i),
        .read_valid_o(local_read_valid), .read_data_o(local_read_data)
    );

    npu_feedback_block_store_macro #(
        .CHANNELS(2), .ADDRESS_WIDTH(8), .DATA_WIDTH(264)
    ) u_feedback_store (
        .clk_i(clk_i), .rst_i(rst_i),
        .write_valid_i({2{valid_i}}),
        .write_address_i({2{address_i[7:0]}}),
        .write_data_i(data_i),
        .read_enable_i({2{valid_i}}),
        .read_address_i({2{address_i[7:0]}}),
        .read_valid_o(feedback_read_valid),
        .read_data_o(feedback_read_data)
    );

    SRAM_32_32 u_tdp32 (
        .clk_i(clk_i), .rst_i(rst_i),
        .a_req_i(valid_i), .a_we_i(valid_i), .a_addr_i(address_i[4:0]),
        .a_wdata_i(data_i[31:0]), .a_rdata_o(tdp32_a_data),
        .a_rvalid_o(tdp32_a_valid),
        .b_req_i(valid_i), .b_we_i(1'b0), .b_addr_i(address_i[4:0]),
        .b_wdata_i(data_i[31:0]), .b_rdata_o(tdp32_b_data),
        .b_rvalid_o(tdp32_b_valid)
    );

    SRAM_32_64 u_tdp64 (
        .clk_i(clk_i), .rst_i(rst_i),
        .a_req_i(valid_i), .a_we_i(valid_i), .a_addr_i(address_i[4:0]),
        .a_wdata_i(data_i[63:0]), .a_rdata_o(tdp64_a_data),
        .a_rvalid_o(tdp64_a_valid),
        .b_req_i(valid_i), .b_we_i(1'b0), .b_addr_i(address_i[4:0]),
        .b_wdata_i(data_i[63:0]), .b_rdata_o(tdp64_b_data),
        .b_rvalid_o(tdp64_b_valid)
    );

    SRAM_32_128 u_tdp128 (
        .clk_i(clk_i), .rst_i(rst_i),
        .a_req_i(valid_i), .a_we_i(valid_i), .a_addr_i(address_i[4:0]),
        .a_wdata_i(data_i[127:0]), .a_rdata_o(tdp128_a_data),
        .a_rvalid_o(tdp128_a_valid),
        .b_req_i(valid_i), .b_we_i(1'b0), .b_addr_i(address_i[4:0]),
        .b_wdata_i(data_i[127:0]), .b_rdata_o(tdp128_b_data),
        .b_rvalid_o(tdp128_b_valid)
    );

    assign data_o = {
        feedback_read_data, local_read_data,
        tdp128_b_data, tdp128_a_data,
        tdp64_b_data, tdp64_a_data,
        tdp32_b_data, tdp32_a_data
    };
    assign read_valid_o = {
        local_read_valid,
        &feedback_read_valid,
        tdp128_b_valid,
        tdp64_b_valid,
        tdp32_b_valid
    };
endmodule

`default_nettype wire
