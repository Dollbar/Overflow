`timescale 1ns/1ps
`default_nettype none

// Verification-only model for the SRAM macro contract. Read data and valid
// are registered. Memory contents are not cleared by reset. Same-address
// accesses involving a write on both ports are outside the contract.
/* verilator lint_off DECLFILENAME */
module sram_tdp_sync_model #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ADDR_WIDTH = 5,
    parameter int unsigned DEPTH = 32
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic a_req_i,
    input  logic a_we_i,
    input  logic [ADDR_WIDTH-1:0] a_addr_i,
    input  logic [DATA_WIDTH-1:0] a_wdata_i,
    output logic [DATA_WIDTH-1:0] a_rdata_o,
    output logic a_rvalid_o,
    input  logic b_req_i,
    input  logic b_we_i,
    input  logic [ADDR_WIDTH-1:0] b_addr_i,
    input  logic [DATA_WIDTH-1:0] b_wdata_i,
    output logic [DATA_WIDTH-1:0] b_rdata_o,
    output logic b_rvalid_o
);

    logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            a_rdata_o <= '0;
            a_rvalid_o <= 1'b0;
            b_rdata_o <= '0;
            b_rvalid_o <= 1'b0;
        end else begin
            a_rvalid_o <= a_req_i && !a_we_i;
            b_rvalid_o <= b_req_i && !b_we_i;
            if (a_req_i && a_we_i) begin
                memory[a_addr_i] <= a_wdata_i;
            end
            if (b_req_i && b_we_i) begin
                memory[b_addr_i] <= b_wdata_i;
            end
            if (a_req_i && !a_we_i) begin
                a_rdata_o <= memory[a_addr_i];
            end
            if (b_req_i && !b_we_i) begin
                b_rdata_o <= memory[b_addr_i];
            end
            if (a_req_i && b_req_i && (a_addr_i == b_addr_i) &&
                (a_we_i || b_we_i)) begin
                $fatal(1, "SRAM model same-address write collision");
            end
        end
    end

endmodule

module SRAM_32_32 (
    input logic clk_i, input logic rst_i,
    input logic a_req_i, input logic a_we_i,
    input logic [4:0] a_addr_i, input logic [31:0] a_wdata_i,
    output logic [31:0] a_rdata_o, output logic a_rvalid_o,
    input logic b_req_i, input logic b_we_i,
    input logic [4:0] b_addr_i, input logic [31:0] b_wdata_i,
    output logic [31:0] b_rdata_o, output logic b_rvalid_o
);
    sram_tdp_sync_model #(.DATA_WIDTH(32)) u_model (.*);
endmodule

module SRAM_32_64 (
    input logic clk_i, input logic rst_i,
    input logic a_req_i, input logic a_we_i,
    input logic [4:0] a_addr_i, input logic [63:0] a_wdata_i,
    output logic [63:0] a_rdata_o, output logic a_rvalid_o,
    input logic b_req_i, input logic b_we_i,
    input logic [4:0] b_addr_i, input logic [63:0] b_wdata_i,
    output logic [63:0] b_rdata_o, output logic b_rvalid_o
);
    sram_tdp_sync_model #(.DATA_WIDTH(64)) u_model (.*);
endmodule

module SRAM_32_128 (
    input logic clk_i, input logic rst_i,
    input logic a_req_i, input logic a_we_i,
    input logic [4:0] a_addr_i, input logic [127:0] a_wdata_i,
    output logic [127:0] a_rdata_o, output logic a_rvalid_o,
    input logic b_req_i, input logic b_we_i,
    input logic [4:0] b_addr_i, input logic [127:0] b_wdata_i,
    output logic [127:0] b_rdata_o, output logic b_rvalid_o
);
    sram_tdp_sync_model #(.DATA_WIDTH(128)) u_model (.*);
endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
