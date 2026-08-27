`timescale 1ns/1ps
`default_nettype none

// KD28 implementation adapters for the technology-neutral NPU SRAM boundary.
// Compile this file with either the functional KD28 cells or their black boxes,
// never with rtl/npu/sram/sram_macro_blackbox.sv.
/* verilator lint_off DECLFILENAME */
module SRAM_32_32 (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        a_req_i,
    input  logic        a_we_i,
    input  logic [4:0]  a_addr_i,
    input  logic [31:0] a_wdata_i,
    output logic [31:0] a_rdata_o,
    output logic        a_rvalid_o,
    input  logic        b_req_i,
    input  logic        b_we_i,
    input  logic [4:0]  b_addr_i,
    input  logic [31:0] b_wdata_i,
    output logic [31:0] b_rdata_o,
    output logic        b_rvalid_o
);
    KD28_SRAM_TDP_32X32 u_sram (
        .CLK(clk_i),
        .ACS(a_req_i), .AWE(a_we_i), .AA(a_addr_i),
        .AD(a_wdata_i), .AWM(4'hf), .AQ(a_rdata_o),
        .BCS(b_req_i), .BWE(b_we_i), .BA(b_addr_i),
        .BD(b_wdata_i), .BWM(4'hf), .BQ(b_rdata_o)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            a_rvalid_o <= 1'b0;
            b_rvalid_o <= 1'b0;
        end else begin
            a_rvalid_o <= a_req_i && !a_we_i;
            b_rvalid_o <= b_req_i && !b_we_i;
        end
    end
endmodule

module SRAM_32_64 (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        a_req_i,
    input  logic        a_we_i,
    input  logic [4:0]  a_addr_i,
    input  logic [63:0] a_wdata_i,
    output logic [63:0] a_rdata_o,
    output logic        a_rvalid_o,
    input  logic        b_req_i,
    input  logic        b_we_i,
    input  logic [4:0]  b_addr_i,
    input  logic [63:0] b_wdata_i,
    output logic [63:0] b_rdata_o,
    output logic        b_rvalid_o
);
    KD28_SRAM_TDP_32X64 u_sram (
        .CLK(clk_i),
        .ACS(a_req_i), .AWE(a_we_i), .AA(a_addr_i),
        .AD(a_wdata_i), .AWM(8'hff), .AQ(a_rdata_o),
        .BCS(b_req_i), .BWE(b_we_i), .BA(b_addr_i),
        .BD(b_wdata_i), .BWM(8'hff), .BQ(b_rdata_o)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            a_rvalid_o <= 1'b0;
            b_rvalid_o <= 1'b0;
        end else begin
            a_rvalid_o <= a_req_i && !a_we_i;
            b_rvalid_o <= b_req_i && !b_we_i;
        end
    end
endmodule

module SRAM_32_128 (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         a_req_i,
    input  logic         a_we_i,
    input  logic [4:0]   a_addr_i,
    input  logic [127:0] a_wdata_i,
    output logic [127:0] a_rdata_o,
    output logic         a_rvalid_o,
    input  logic         b_req_i,
    input  logic         b_we_i,
    input  logic [4:0]   b_addr_i,
    input  logic [127:0] b_wdata_i,
    output logic [127:0] b_rdata_o,
    output logic         b_rvalid_o
);
    KD28_SRAM_TDP_32X128 u_sram (
        .CLK(clk_i),
        .ACS(a_req_i), .AWE(a_we_i), .AA(a_addr_i),
        .AD(a_wdata_i), .AWM(16'hffff), .AQ(a_rdata_o),
        .BCS(b_req_i), .BWE(b_we_i), .BA(b_addr_i),
        .BD(b_wdata_i), .BWM(16'hffff), .BQ(b_rdata_o)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            a_rvalid_o <= 1'b0;
            b_rvalid_o <= 1'b0;
        end else begin
            a_rvalid_o <= a_req_i && !a_we_i;
            b_rvalid_o <= b_req_i && !b_we_i;
        end
    end
endmodule

module npu_local_sram_1w1r_macro #(
    parameter int unsigned ADDRESS_WIDTH = 11,
    parameter int unsigned DATA_WIDTH = 128
) (
    input  logic                     clk_i,
    input  logic                     rst_i,
    input  logic                     write_enable_i,
    input  logic [ADDRESS_WIDTH-1:0] write_address_i,
    input  logic [DATA_WIDTH-1:0]    write_data_i,
    input  logic                     read_enable_i,
    input  logic [ADDRESS_WIDTH-1:0] read_address_i,
    output logic                     read_valid_o,
    output logic [DATA_WIDTH-1:0]    read_data_o
);
    localparam int unsigned DEPTH = 1 << ADDRESS_WIDTH;

    kd28_fifo_sdp_storage_map #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDRESS_WIDTH)
    ) u_storage (
        .write_clk_i(clk_i),
        .write_cs_i(write_enable_i),
        .write_addr_i(write_address_i),
        .write_data_i(write_data_i),
        .read_clk_i(clk_i),
        .read_cs_i(read_enable_i),
        .read_addr_i(read_address_i),
        .read_data_o(read_data_o)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            read_valid_o <= 1'b0;
        end else begin
            read_valid_o <= read_enable_i;
        end
    end

    initial begin
        if (!((ADDRESS_WIDTH > 0) && (ADDRESS_WIDTH <= 16) &&
              (DATA_WIDTH > 0) && ((DATA_WIDTH % 8) == 0))) begin
            $error("KD28 NPU local SRAM parameters are outside the mapper contract");
        end
    end
endmodule

module npu_feedback_block_store_macro #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned ADDRESS_WIDTH = 8,
    parameter int unsigned DATA_WIDTH = 264
) (
    input  logic                              clk_i,
    input  logic                              rst_i,
    input  logic [CHANNELS-1:0]               write_valid_i,
    input  logic [CHANNELS*ADDRESS_WIDTH-1:0] write_address_i,
    input  logic [CHANNELS*DATA_WIDTH-1:0]    write_data_i,
    input  logic [CHANNELS-1:0]               read_enable_i,
    input  logic [CHANNELS*ADDRESS_WIDTH-1:0] read_address_i,
    output logic [CHANNELS-1:0]               read_valid_o,
    output logic [CHANNELS*DATA_WIDTH-1:0]    read_data_o
);
    generate
        for (genvar channel = 0; channel < CHANNELS; channel++) begin : g_channel
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(ADDRESS_WIDTH),
                .DATA_WIDTH(DATA_WIDTH)
            ) u_channel_store (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .write_enable_i(write_valid_i[channel]),
                .write_address_i(write_address_i[
                    channel*ADDRESS_WIDTH +: ADDRESS_WIDTH]),
                .write_data_i(write_data_i[
                    channel*DATA_WIDTH +: DATA_WIDTH]),
                .read_enable_i(read_enable_i[channel]),
                .read_address_i(read_address_i[
                    channel*ADDRESS_WIDTH +: ADDRESS_WIDTH]),
                .read_valid_o(read_valid_o[channel]),
                .read_data_o(read_data_o[channel*DATA_WIDTH +: DATA_WIDTH])
            );
        end
    endgenerate

    initial begin
        if (CHANNELS == 0) begin
            $error("KD28 NPU feedback store requires at least one channel");
        end
    end
endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
