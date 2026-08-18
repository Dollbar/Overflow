`timescale 1ns/1ps
`default_nettype none

// Banked FP32 operand storage for the sixteen row-level Vector engines.  Each
// bank supplies one 16-lane vector per cycle from independent B and C arrays.
// Contents survive clear_i; clear only cancels in-flight read responses.
module npu_local_vector_operand_buffer #(
    parameter int unsigned BUFFER_COUNT = 4,
    parameter int unsigned BANKS = 16,
    parameter int unsigned VECTOR_DEPTH = 512,
    parameter int unsigned BANK_INDEX_WIDTH =
        (BANKS <= 1) ? 1 : $clog2(BANKS),
    parameter int unsigned ADDRESS_WIDTH =
        (VECTOR_DEPTH <= 1) ? 1 : $clog2(VECTOR_DEPTH)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic write_valid_i,
    output logic write_ready_o,
    input  logic write_operand_c_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 write_buffer_id_i,
    input  logic [BANK_INDEX_WIDTH-1:0] write_bank_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 write_offset_i,
    input  logic [511:0] write_data_i,

    input  logic [BANKS-1:0] read_b_enable_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 read_b_buffer_id_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 read_b_offset_i,
    output logic [BANKS-1:0] read_b_valid_o,
    output logic [BANKS*512-1:0] read_b_data_o,

    input  logic [BANKS-1:0] read_c_enable_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 read_c_buffer_id_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 read_c_offset_i,
    output logic [BANKS-1:0] read_c_valid_o,
    output logic [BANKS*512-1:0] read_c_data_o,
    output logic protocol_error_o
);

    localparam int unsigned BUFFER_INDEX_WIDTH =
        (BUFFER_COUNT <= 1) ? 1 : $clog2(BUFFER_COUNT);
    localparam int unsigned BUFFER_COMPARE_WIDTH =
        npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH + 1;
    localparam logic [BUFFER_COMPARE_WIDTH-1:0] BUFFER_COUNT_LIMIT =
        BUFFER_COMPARE_WIDTH'(BUFFER_COUNT);

    // Logical banked storage is intentionally left technology-neutral here.
    // Integrations may replace these arrays with banked SRAM macros without
    // changing the scheduler-facing protocol.
    logic [511:0] operand_b_mem
        [0:BUFFER_COUNT-1][0:BANKS-1][0:VECTOR_DEPTH-1];
    logic [511:0] operand_c_mem
        [0:BUFFER_COUNT-1][0:BANKS-1][0:VECTOR_DEPTH-1];

    logic write_buffer_valid;
    logic write_bank_valid;
    logic write_address_valid;
    logic [ADDRESS_WIDTH-1:0] write_address;

    always_comb begin
        write_ready_o = !rst_i && !clear_i;
        write_buffer_valid = {1'b0, write_buffer_id_i} <
            BUFFER_COUNT_LIMIT;
        write_bank_valid = {1'b0, write_bank_i} <
            (BANK_INDEX_WIDTH + 1)'(BANKS);
        write_address_valid = (write_offset_i[5:0] == 6'd0) &&
            ((write_offset_i >> 6) < VECTOR_DEPTH);
        write_address = ADDRESS_WIDTH'(write_offset_i >> 6);
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            read_b_valid_o <= '0;
            read_c_valid_o <= '0;
            read_b_data_o <= '0;
            read_c_data_o <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            read_b_valid_o <= read_b_enable_i;
            read_c_valid_o <= read_c_enable_i;

            if (write_valid_i && write_ready_o) begin
                if (write_buffer_valid && write_bank_valid &&
                    write_address_valid) begin
                    if (write_operand_c_i) begin
                        operand_c_mem[
                            BUFFER_INDEX_WIDTH'(write_buffer_id_i)
                        ][write_bank_i][write_address] <= write_data_i;
                    end else begin
                        operand_b_mem[
                            BUFFER_INDEX_WIDTH'(write_buffer_id_i)
                        ][write_bank_i][write_address] <= write_data_i;
                    end
                end else begin
                    protocol_error_o <= 1'b1;
                end
            end

            for (integer bank = 0; bank < BANKS; bank++) begin
                logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                    b_buffer_id;
                logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                    c_buffer_id;
                logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                    b_offset;
                logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                    c_offset;
                logic b_request_valid;
                logic c_request_valid;

                b_buffer_id = read_b_buffer_id_i[
                    bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                    npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH
                ];
                c_buffer_id = read_c_buffer_id_i[
                    bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                    npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH
                ];
                b_offset = read_b_offset_i[
                    bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                    npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH
                ];
                c_offset = read_c_offset_i[
                    bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                    npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH
                ];
                b_request_valid = ({1'b0, b_buffer_id} <
                    BUFFER_COUNT_LIMIT) &&
                    (b_offset[5:0] == 6'd0) &&
                    ((b_offset >> 6) < VECTOR_DEPTH);
                c_request_valid = ({1'b0, c_buffer_id} <
                    BUFFER_COUNT_LIMIT) &&
                    (c_offset[5:0] == 6'd0) &&
                    ((c_offset >> 6) < VECTOR_DEPTH);

                if (read_b_enable_i[bank]) begin
                    if (b_request_valid) begin
                        read_b_data_o[bank*512 +: 512] <= operand_b_mem[
                            BUFFER_INDEX_WIDTH'(b_buffer_id)
                        ][bank][ADDRESS_WIDTH'(b_offset >> 6)];
                    end else begin
                        read_b_data_o[bank*512 +: 512] <= '0;
                        protocol_error_o <= 1'b1;
                    end
                end
                if (read_c_enable_i[bank]) begin
                    if (c_request_valid) begin
                        read_c_data_o[bank*512 +: 512] <= operand_c_mem[
                            BUFFER_INDEX_WIDTH'(c_buffer_id)
                        ][bank][ADDRESS_WIDTH'(c_offset >> 6)];
                    end else begin
                        read_c_data_o[bank*512 +: 512] <= '0;
                        protocol_error_o <= 1'b1;
                    end
                end
            end
        end
    end

    initial begin
        assert (BUFFER_COUNT > 0)
            else $error("npu_local_vector_operand_buffer BUFFER_COUNT must be positive");
        assert (BUFFER_COUNT <= (1 << npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH))
            else $error("npu_local_vector_operand_buffer BUFFER_COUNT exceeds Buffer ID space");
        assert (BANKS > 0)
            else $error("npu_local_vector_operand_buffer BANKS must be positive");
        assert (VECTOR_DEPTH > 0)
            else $error("npu_local_vector_operand_buffer VECTOR_DEPTH must be positive");
    end

endmodule

`default_nettype wire
