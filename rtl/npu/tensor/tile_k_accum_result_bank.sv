`timescale 1ns/1ps
`default_nettype none

// One FP32 result lane backed by a synchronous 32x32 SRAM and a two-entry
// response queue.  The queue absorbs the SRAM's one-cycle read latency while
// keeping the result stream at one beat per cycle after warm-up.
(* keep_hierarchy = "yes" *)
module tile_k_accum_result_bank (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        mem_write_i,
    input  logic [4:0]  mem_write_addr_i,
    input  logic [31:0] mem_write_data_i,
    input  logic        mem_read_i,
    input  logic [4:0]  mem_read_addr_i,
    input  logic        queue_write_slot_i,
    input  logic        queue_read_slot_i,
    output logic [31:0] queue_data_o,
    output logic        mem_read_valid_o
);

    logic [31:0] queue_mem [0:1];
    logic [31:0] mem_read_data;
    logic mem_read_valid;

    /* verilator lint_off PINCONNECTEMPTY */
    SRAM_32_32 u_result_sram (
        .clk_i      (clk_i),
        .rst_i      (rst_i),
        .a_req_i    (mem_write_i),
        .a_we_i     (mem_write_i),
        .a_addr_i   (mem_write_addr_i),
        .a_wdata_i  (mem_write_data_i),
        .a_rdata_o  (),
        .a_rvalid_o (),
        .b_req_i    (mem_read_i),
        .b_we_i     (1'b0),
        .b_addr_i   (mem_read_addr_i),
        .b_wdata_i  (32'd0),
        .b_rdata_o  (mem_read_data),
        .b_rvalid_o (mem_read_valid)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    assign mem_read_valid_o = mem_read_valid;
    assign queue_data_o = queue_mem[queue_read_slot_i];

    always_ff @(posedge clk_i) begin
        if (!rst_i && mem_read_valid) begin
            queue_mem[queue_write_slot_i] <= mem_read_data;
        end
    end

endmodule

`default_nettype wire
