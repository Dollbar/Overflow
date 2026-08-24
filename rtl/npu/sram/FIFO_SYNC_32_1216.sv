`timescale 1ns/1ps
`default_nettype none

module FIFO_SYNC_32_1216 (
    input  logic           clk_i,
    input  logic           rst_i,
    input  logic           clear_i,
    input  logic           wr_valid_i,
    output logic           wr_ready_o,
    input  logic [1215:0]  wr_data_i,
    input  logic           rd_ready_i,
    output logic           rd_valid_o,
    output logic [1215:0]  rd_data_o,
    output logic           full_o,
    output logic           empty_o,
    output logic [5:0]     level_o
);

    localparam logic [5:0] FIFO_DEPTH = 6'd32;
    logic [4:0] wr_ptr_q;
    logic [4:0] rd_ptr_q;
    logic [5:0] count_q;
    logic rd_valid_q;
    logic flush_active;
    logic write_fire;
    logic read_fire;
    logic read_issue;
    logic [1279:0] ram_write_data;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [1279:0] ram_read_data;
    /* verilator lint_on UNUSEDSIGNAL */

    assign flush_active = rst_i || clear_i;
    assign full_o = count_q == FIFO_DEPTH;
    assign empty_o = count_q == 6'd0;
    assign level_o = count_q;
    assign rd_valid_o = rd_valid_q;
    assign rd_data_o = rd_valid_q ? ram_read_data[1215:0] : 1216'd0;
    assign read_fire = rd_valid_q && rd_ready_i;
    assign wr_ready_o = !flush_active && (!full_o || read_fire);
    assign write_fire = wr_valid_i && wr_ready_o;
    assign read_issue = !flush_active && (!rd_valid_q || read_fire) &&
                        (rd_valid_q ? (count_q > 6'd1) : (count_q != 6'd0));
    assign ram_write_data = {64'd0, wr_data_i};

    always_ff @(posedge clk_i) begin
        if (flush_active) begin
            wr_ptr_q <= 5'd0;
            rd_ptr_q <= 5'd0;
            count_q <= 6'd0;
            rd_valid_q <= 1'b0;
        end else begin
            if (write_fire) begin
                wr_ptr_q <= wr_ptr_q + 5'd1;
            end
            if (read_issue) begin
                rd_ptr_q <= rd_ptr_q + 5'd1;
            end
            unique case ({write_fire, read_fire})
                2'b10: count_q <= count_q + 6'd1;
                2'b01: count_q <= count_q - 6'd1;
                default: count_q <= count_q;
            endcase
            unique case ({read_issue, read_fire})
                2'b10: rd_valid_q <= 1'b1;
                2'b01: rd_valid_q <= 1'b0;
                2'b11: rd_valid_q <= 1'b1;
                default: rd_valid_q <= rd_valid_q;
            endcase
        end
    end

    generate
        for (genvar slice = 0; slice < 10; slice = slice + 1) begin : gen_sram_slices
            /* verilator lint_off PINCONNECTEMPTY */
            SRAM_32_128 u_storage (
                .clk_i      (clk_i),
                .rst_i      (flush_active),
                .a_req_i    (write_fire),
                .a_we_i     (1'b1),
                .a_addr_i   (wr_ptr_q),
                .a_wdata_i  (ram_write_data[slice*128 +: 128]),
                .a_rdata_o  (),
                .a_rvalid_o (),
                .b_req_i    (read_issue),
                .b_we_i     (1'b0),
                .b_addr_i   (rd_ptr_q),
                .b_wdata_i  (128'd0),
                .b_rdata_o  (ram_read_data[slice*128 +: 128]),
                .b_rvalid_o ()
            );
            /* verilator lint_on PINCONNECTEMPTY */
        end
    endgenerate

endmodule

`default_nettype wire
