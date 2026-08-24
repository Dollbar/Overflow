`timescale 1ns/1ps
`default_nettype none

// Banked packed-MX Vector operand controller. B/C data and E8M0 scale storage
// are explicit npu_local_sram_1w1r_macro replacement points.
module npu_local_vector_operand_buffer #(
    parameter int unsigned BUFFER_COUNT = 4,
    parameter int unsigned BANKS = 16,
    // Default data capacity per Vector-B or Vector-C store:
    // 4 buffer IDs x 16 banks x 8192 words x 16 bytes = 8 MiB.
    parameter int unsigned VECTOR_DEPTH = 8192,
    parameter int unsigned BANK_INDEX_WIDTH =
        (BANKS <= 1) ? 1 : $clog2(BANKS),
    parameter int unsigned ADDRESS_WIDTH =
        (VECTOR_DEPTH <= 1) ? 1 : $clog2(VECTOR_DEPTH),
    parameter int unsigned BUFFER_INDEX_WIDTH =
        (BUFFER_COUNT <= 1) ? 1 : $clog2(BUFFER_COUNT),
    parameter int unsigned MACRO_ADDRESS_WIDTH =
        BUFFER_INDEX_WIDTH + ADDRESS_WIDTH
) (
    input  logic clk_i, input logic rst_i, input logic clear_i,
    input  logic write_valid_i, output logic write_ready_o,
    input  logic write_operand_c_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 write_buffer_id_i,
    input  logic [BANK_INDEX_WIDTH-1:0] write_bank_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 write_offset_i,
    input  logic [127:0] write_data_i, input logic [7:0] write_scale_i,
    input  logic [BANKS-1:0] read_b_enable_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 read_b_buffer_id_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 read_b_offset_i,
    output logic [BANKS-1:0] read_b_valid_o,
    output logic [BANKS*128-1:0] read_b_data_o,
    output logic [BANKS*8-1:0] read_b_scale_o,
    input  logic [BANKS-1:0] read_c_enable_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 read_c_buffer_id_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 read_c_offset_i,
    output logic [BANKS-1:0] read_c_valid_o,
    output logic [BANKS*128-1:0] read_c_data_o,
    output logic [BANKS*8-1:0] read_c_scale_o,
    output logic protocol_error_o
);

    localparam int unsigned BUFFER_COMPARE_WIDTH =
        npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH + 1;
    localparam logic [BUFFER_COMPARE_WIDTH-1:0] BUFFER_COUNT_LIMIT =
        BUFFER_COMPARE_WIDTH'(BUFFER_COUNT);

    logic write_request_valid;
    logic [MACRO_ADDRESS_WIDTH-1:0] write_address;
    logic [BANKS-1:0] b_write_enable;
    logic [BANKS-1:0] c_write_enable;
    logic [BANKS*MACRO_ADDRESS_WIDTH-1:0] b_read_address;
    logic [BANKS*MACRO_ADDRESS_WIDTH-1:0] c_read_address;
    logic [BANKS-1:0] b_read_request_valid;
    logic [BANKS-1:0] c_read_request_valid;
    logic [BANKS-1:0] b_data_read_valid;
    logic [BANKS-1:0] b_scale_read_valid;
    logic [BANKS-1:0] c_data_read_valid;
    logic [BANKS-1:0] c_scale_read_valid;

    always_comb begin
        write_ready_o = !rst_i && !clear_i;
        write_request_valid = ({1'b0, write_buffer_id_i} <
            BUFFER_COUNT_LIMIT) &&
            ({1'b0, write_bank_i} < (BANK_INDEX_WIDTH+1)'(BANKS)) &&
            (write_offset_i[3:0] == 4'd0) &&
            ((write_offset_i >> 4) < VECTOR_DEPTH);
        write_address = {BUFFER_INDEX_WIDTH'(write_buffer_id_i),
            ADDRESS_WIDTH'(write_offset_i >> 4)};
        b_write_enable = '0;
        c_write_enable = '0;
        if (write_valid_i && write_ready_o && write_request_valid) begin
            if (write_operand_c_i) begin
                c_write_enable[write_bank_i] = 1'b1;
            end else begin
                b_write_enable[write_bank_i] = 1'b1;
            end
        end

        b_read_address = '0;
        c_read_address = '0;
        b_read_request_valid = '0;
        c_read_request_valid = '0;
        for (integer bank = 0; bank < BANKS; bank++) begin
            logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0] b_buffer;
            logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0] c_buffer;
            logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0] b_offset;
            logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0] c_offset;
            b_buffer = read_b_buffer_id_i[
                bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH];
            c_buffer = read_c_buffer_id_i[
                bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH];
            b_offset = read_b_offset_i[
                bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH];
            c_offset = read_c_offset_i[
                bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH];
            b_read_request_valid[bank] = read_b_enable_i[bank] &&
                ({1'b0, b_buffer} < BUFFER_COUNT_LIMIT) &&
                (b_offset[3:0] == 4'd0) &&
                ((b_offset >> 4) < VECTOR_DEPTH);
            c_read_request_valid[bank] = read_c_enable_i[bank] &&
                ({1'b0, c_buffer} < BUFFER_COUNT_LIMIT) &&
                (c_offset[3:0] == 4'd0) &&
                ((c_offset >> 4) < VECTOR_DEPTH);
            b_read_address[bank*MACRO_ADDRESS_WIDTH +:
                MACRO_ADDRESS_WIDTH] = {
                BUFFER_INDEX_WIDTH'(b_buffer),
                ADDRESS_WIDTH'(b_offset >> 4)};
            c_read_address[bank*MACRO_ADDRESS_WIDTH +:
                MACRO_ADDRESS_WIDTH] = {
                BUFFER_INDEX_WIDTH'(c_buffer),
                ADDRESS_WIDTH'(c_offset >> 4)};
        end
    end

    generate
        for (genvar bank = 0; bank < BANKS; bank++) begin : g_bank
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(MACRO_ADDRESS_WIDTH), .DATA_WIDTH(128)
            ) u_b_data (
                .clk_i(clk_i), .rst_i(rst_i || clear_i),
                .write_enable_i(b_write_enable[bank]),
                .write_address_i(write_address), .write_data_i(write_data_i),
                .read_enable_i(b_read_request_valid[bank]),
                .read_address_i(b_read_address[
                    bank*MACRO_ADDRESS_WIDTH +: MACRO_ADDRESS_WIDTH]),
                .read_valid_o(b_data_read_valid[bank]),
                .read_data_o(read_b_data_o[bank*128 +: 128]));
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(MACRO_ADDRESS_WIDTH), .DATA_WIDTH(8)
            ) u_b_scale (
                .clk_i(clk_i), .rst_i(rst_i || clear_i),
                .write_enable_i(b_write_enable[bank]),
                .write_address_i(write_address), .write_data_i(write_scale_i),
                .read_enable_i(b_read_request_valid[bank]),
                .read_address_i(b_read_address[
                    bank*MACRO_ADDRESS_WIDTH +: MACRO_ADDRESS_WIDTH]),
                .read_valid_o(b_scale_read_valid[bank]),
                .read_data_o(read_b_scale_o[bank*8 +: 8]));
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(MACRO_ADDRESS_WIDTH), .DATA_WIDTH(128)
            ) u_c_data (
                .clk_i(clk_i), .rst_i(rst_i || clear_i),
                .write_enable_i(c_write_enable[bank]),
                .write_address_i(write_address), .write_data_i(write_data_i),
                .read_enable_i(c_read_request_valid[bank]),
                .read_address_i(c_read_address[
                    bank*MACRO_ADDRESS_WIDTH +: MACRO_ADDRESS_WIDTH]),
                .read_valid_o(c_data_read_valid[bank]),
                .read_data_o(read_c_data_o[bank*128 +: 128]));
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(MACRO_ADDRESS_WIDTH), .DATA_WIDTH(8)
            ) u_c_scale (
                .clk_i(clk_i), .rst_i(rst_i || clear_i),
                .write_enable_i(c_write_enable[bank]),
                .write_address_i(write_address), .write_data_i(write_scale_i),
                .read_enable_i(c_read_request_valid[bank]),
                .read_address_i(c_read_address[
                    bank*MACRO_ADDRESS_WIDTH +: MACRO_ADDRESS_WIDTH]),
                .read_valid_o(c_scale_read_valid[bank]),
                .read_data_o(read_c_scale_o[bank*8 +: 8]));
        end
    endgenerate

    assign read_b_valid_o = b_data_read_valid & b_scale_read_valid;
    assign read_c_valid_o = c_data_read_valid & c_scale_read_valid;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            protocol_error_o <= 1'b0;
        end else begin
            if (write_valid_i && write_ready_o && !write_request_valid) begin
                protocol_error_o <= 1'b1;
            end
            for (integer bank = 0; bank < BANKS; bank++) begin
                if ((read_b_enable_i[bank] &&
                     !b_read_request_valid[bank]) ||
                    (read_c_enable_i[bank] &&
                     !c_read_request_valid[bank])) begin
                    protocol_error_o <= 1'b1;
                end
            end
        end
    end

    initial begin
        assert ((BUFFER_COUNT > 0) && (BANKS > 0) && (VECTOR_DEPTH > 0))
            else $error("npu_local_vector_operand_buffer parameters must be positive");
    end

endmodule

`default_nettype wire
