`timescale 1ns/1ps
`default_nettype none

// 16 lane carry-save exact K state packed into independent 64-bit SRAM banks.
// The two ports permit one row read and one different-row write per cycle.
module tile_k_accum_state_mem #(
    parameter int unsigned DATA_WIDTH = 1440,
    parameter int unsigned BANK_COUNT = (DATA_WIDTH + 63) / 64
) (
    input  logic                         clk_i,
    input  logic                         rst_i,
    input  logic                         a_req_i,
    input  logic                         a_we_i,
    input  logic [4:0]                   a_addr_i,
    input  logic [DATA_WIDTH-1:0]        a_wdata_i,
    output logic [DATA_WIDTH-1:0]        a_rdata_o,
    output logic                         a_rvalid_o,
    input  logic                         b_req_i,
    input  logic                         b_we_i,
    input  logic [4:0]                   b_addr_i,
    input  logic [DATA_WIDTH-1:0]        b_wdata_i,
    output logic [DATA_WIDTH-1:0]        b_rdata_o,
    output logic                         b_rvalid_o
);

    localparam int unsigned PAD_WIDTH = BANK_COUNT * 64;
    logic [PAD_WIDTH-1:0] a_wdata_padded;
    logic [PAD_WIDTH-1:0] b_wdata_padded;
    // The upper bits are physical bank padding when DATA_WIDTH is not a multiple of 64.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [PAD_WIDTH-1:0] a_rdata_padded;
    logic [PAD_WIDTH-1:0] b_rdata_padded;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [BANK_COUNT-1:0] a_rvalid_bank;
    logic [BANK_COUNT-1:0] b_rvalid_bank;
    localparam int unsigned RESET_BRANCH_COUNT = (BANK_COUNT + 3) / 4;
    logic [RESET_BRANCH_COUNT-1:0] bank_reset;

    assign a_wdata_padded = {{(PAD_WIDTH-DATA_WIDTH){1'b0}}, a_wdata_i};
    assign b_wdata_padded = {{(PAD_WIDTH-DATA_WIDTH){1'b0}}, b_wdata_i};
    assign a_rdata_o = a_rdata_padded[DATA_WIDTH-1:0];
    assign b_rdata_o = b_rdata_padded[DATA_WIDTH-1:0];
    assign a_rvalid_o = &a_rvalid_bank;
    assign b_rvalid_o = &b_rvalid_bank;

    generate
        for (genvar reset_branch = 0;
             reset_branch < RESET_BRANCH_COUNT;
             reset_branch = reset_branch + 1) begin : g_reset_branch
            (* keep = "true", dont_touch = "true" *)
            tile_flush_buffer #(
                .BUFFER_ID (400 + reset_branch)
            ) u_reset_buffer (
                .rst_i   (rst_i),
                .clear_i (1'b0),
                .flush_o (bank_reset[reset_branch])
            );
        end

        for (genvar bank = 0; bank < BANK_COUNT; bank = bank + 1) begin : g_state_bank
            SRAM_32_64 u_state_bank (
                .clk_i      (clk_i),
                .rst_i      (bank_reset[bank/4]),
                .a_req_i    (a_req_i),
                .a_we_i     (a_we_i),
                .a_addr_i   (a_addr_i),
                .a_wdata_i  (a_wdata_padded[bank*64 +: 64]),
                .a_rdata_o  (a_rdata_padded[bank*64 +: 64]),
                .a_rvalid_o (a_rvalid_bank[bank]),
                .b_req_i    (b_req_i),
                .b_we_i     (b_we_i),
                .b_addr_i   (b_addr_i),
                .b_wdata_i  (b_wdata_padded[bank*64 +: 64]),
                .b_rdata_o  (b_rdata_padded[bank*64 +: 64]),
                .b_rvalid_o (b_rvalid_bank[bank])
            );
        end
    endgenerate

endmodule

`default_nettype wire
