`timescale 1ns/1ps
`default_nettype none

// Technology-neutral declaration boundary for a synchronous true-dual-port
// SRAM.  This file intentionally contains no storage array and no simulation
// behavior.  Replace these declarations with the selected foundry/compiler
// macro adapter in the integration build.
/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
(* black_box *)
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
endmodule

(* black_box *)
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
endmodule

(* black_box *)
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
endmodule

// Banked feedback-block store replacement boundary. Each channel is one
// independent 1W/1R SRAM bank with registered read data and read-valid.
(* black_box *)
module npu_feedback_block_store_macro #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned ADDRESS_WIDTH = 8,
    parameter int unsigned DATA_WIDTH = 264
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic [CHANNELS-1:0] write_valid_i,
    input  logic [CHANNELS*ADDRESS_WIDTH-1:0] write_address_i,
    input  logic [CHANNELS*DATA_WIDTH-1:0] write_data_i,
    input  logic [CHANNELS-1:0] read_enable_i,
    input  logic [CHANNELS*ADDRESS_WIDTH-1:0] read_address_i,
    output logic [CHANNELS-1:0] read_valid_o,
    output logic [CHANNELS*DATA_WIDTH-1:0] read_data_o
);
endmodule

// Generic local-buffer bank replacement boundary. Integrations bind this
// logical 1W/1R contract to the selected depth/width compiler macro.
(* black_box *)
module npu_local_sram_1w1r_macro #(
    parameter int unsigned ADDRESS_WIDTH = 11,
    parameter int unsigned DATA_WIDTH = 128
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic write_enable_i,
    input  logic [ADDRESS_WIDTH-1:0] write_address_i,
    input  logic [DATA_WIDTH-1:0] write_data_i,
    input  logic read_enable_i,
    input  logic [ADDRESS_WIDTH-1:0] read_address_i,
    output logic read_valid_o,
    output logic [DATA_WIDTH-1:0] read_data_o
);
endmodule

/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on DECLFILENAME */

`default_nettype wire
