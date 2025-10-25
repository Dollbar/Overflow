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

/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on DECLFILENAME */

`default_nettype wire
