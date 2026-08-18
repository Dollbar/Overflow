`timescale 1ns/1ps
`default_nettype none

// Banked Tile-K-major input storage. For either tensor, vector byte offset V
// addresses BANKS parallel 128-bit vectors at {buffer_id, bank, V/16}.
module npu_local_tensor_buffer #(
    parameter int unsigned BUFFER_COUNT = 4,
    parameter int unsigned BANKS = 16,
    parameter int unsigned VECTOR_DEPTH = 512,
    parameter int unsigned ADDRESS_WIDTH =
        (VECTOR_DEPTH <= 1) ? 1 : $clog2(VECTOR_DEPTH)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic dma_write_valid_i,
    output logic dma_write_ready_o,
    input  logic dma_write_weight_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 dma_write_buffer_id_i,
    input  logic [$clog2(BANKS)-1:0] dma_write_bank_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 dma_write_offset_i,
    input  logic [127:0] dma_write_data_i,

    input  logic [BANKS-1:0] feedback_write_valid_i,
    output logic [BANKS-1:0] feedback_write_ready_o,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 feedback_write_buffer_id_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 feedback_write_offset_i,
    input  logic [BANKS*128-1:0] feedback_write_data_i,

    input  logic activation_read_enable_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 activation_read_buffer_id_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 activation_read_offset_i,
    output logic activation_read_valid_o,
    output logic [BANKS*128-1:0] activation_read_data_o,

    input  logic weight_read_enable_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 weight_read_buffer_id_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 weight_read_offset_i,
    output logic weight_read_valid_o,
    output logic [BANKS*128-1:0] weight_read_data_o,
    output logic protocol_error_o
);

    (* ram_style = "block" *) logic [127:0]
        activation_mem [0:BUFFER_COUNT-1][0:BANKS-1][0:VECTOR_DEPTH-1];
    (* ram_style = "block" *) logic [127:0]
        weight_mem [0:BUFFER_COUNT-1][0:BANKS-1][0:VECTOR_DEPTH-1];

    logic write_buffer_valid;
    logic write_address_valid;
    logic activation_buffer_valid;
    logic activation_address_valid;
    logic weight_buffer_valid;
    logic weight_address_valid;
    logic [ADDRESS_WIDTH-1:0] write_address;
    logic [ADDRESS_WIDTH-1:0] activation_address;
    logic [ADDRESS_WIDTH-1:0] weight_address;
    logic dma_feedback_collision;
    logic [BANKS-1:0] feedback_buffer_valid;
    logic [BANKS-1:0] feedback_address_valid;
    logic [BANKS*ADDRESS_WIDTH-1:0] feedback_address;
    localparam int unsigned BUFFER_INDEX_WIDTH =
        (BUFFER_COUNT <= 1) ? 1 : $clog2(BUFFER_COUNT);
    localparam int unsigned BUFFER_COMPARE_WIDTH =
        npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH + 1;
    localparam logic [BUFFER_COMPARE_WIDTH-1:0] BUFFER_COUNT_LIMIT =
        BUFFER_COMPARE_WIDTH'(BUFFER_COUNT);

    always_comb begin
        dma_feedback_collision = !dma_write_weight_i &&
            feedback_write_valid_i[dma_write_bank_i];
        dma_write_ready_o = !rst_i && !clear_i && !dma_feedback_collision;
        feedback_write_ready_o = {BANKS{!rst_i && !clear_i}};
        write_buffer_valid = {1'b0, dma_write_buffer_id_i} <
            BUFFER_COUNT_LIMIT;
        write_address_valid = (dma_write_offset_i[3:0] == 4'd0) &&
            ((dma_write_offset_i >> 4) < VECTOR_DEPTH);
        activation_buffer_valid = {1'b0, activation_read_buffer_id_i} <
            BUFFER_COUNT_LIMIT;
        activation_address_valid = (activation_read_offset_i[3:0] == 4'd0) &&
            ((activation_read_offset_i >> 4) < VECTOR_DEPTH);
        weight_buffer_valid = {1'b0, weight_read_buffer_id_i} <
            BUFFER_COUNT_LIMIT;
        weight_address_valid = (weight_read_offset_i[3:0] == 4'd0) &&
            ((weight_read_offset_i >> 4) < VECTOR_DEPTH);
        write_address = ADDRESS_WIDTH'(dma_write_offset_i >> 4);
        activation_address = ADDRESS_WIDTH'(activation_read_offset_i >> 4);
        weight_address = ADDRESS_WIDTH'(weight_read_offset_i >> 4);
        feedback_buffer_valid = '0;
        feedback_address_valid = '0;
        feedback_address = '0;
        for (integer bank = 0; bank < BANKS; bank++) begin
            feedback_buffer_valid[bank] = {1'b0,
                feedback_write_buffer_id_i[
                    bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                    npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH
                ]} < BUFFER_COUNT_LIMIT;
            feedback_address_valid[bank] =
                (feedback_write_offset_i[
                    bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                    npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH
                 ][3:0] == 4'd0) &&
                ((feedback_write_offset_i[
                    bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                    npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH
                  ] >> 4) < VECTOR_DEPTH);
            feedback_address[bank*ADDRESS_WIDTH +: ADDRESS_WIDTH] =
                ADDRESS_WIDTH'(feedback_write_offset_i[
                    bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                    npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH
                ] >> 4);
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            activation_read_valid_o <= 1'b0;
            weight_read_valid_o <= 1'b0;
            activation_read_data_o <= '0;
            weight_read_data_o <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            activation_read_valid_o <= activation_read_enable_i;
            weight_read_valid_o <= weight_read_enable_i;

            if (dma_write_valid_i && dma_write_ready_o) begin
                if (write_buffer_valid && write_address_valid) begin
                    if (dma_write_weight_i) begin
                        weight_mem[BUFFER_INDEX_WIDTH'(dma_write_buffer_id_i)]
                                  [dma_write_bank_i]
                                  [write_address] <= dma_write_data_i;
                    end else begin
                        activation_mem[BUFFER_INDEX_WIDTH'(dma_write_buffer_id_i)]
                                      [dma_write_bank_i]
                                      [write_address] <= dma_write_data_i;
                    end
                end else begin
                    protocol_error_o <= 1'b1;
                end
            end

            for (integer bank = 0; bank < BANKS; bank++) begin
                if (feedback_write_valid_i[bank] &&
                    feedback_write_ready_o[bank]) begin
                    if (feedback_buffer_valid[bank] &&
                        feedback_address_valid[bank]) begin
                        activation_mem[
                            BUFFER_INDEX_WIDTH'(
                                feedback_write_buffer_id_i[
                                    bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                                    npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH
                                ])
                        ][bank][feedback_address[
                            bank*ADDRESS_WIDTH +: ADDRESS_WIDTH
                        ]] <= feedback_write_data_i[bank*128 +: 128];
                    end else begin
                        protocol_error_o <= 1'b1;
                    end
                end
            end

            if (activation_read_enable_i) begin
                if (activation_buffer_valid && activation_address_valid) begin
                    for (integer bank = 0; bank < BANKS; bank++) begin
                        activation_read_data_o[bank*128 +: 128] <=
                            activation_mem[
                                BUFFER_INDEX_WIDTH'(activation_read_buffer_id_i)
                            ][bank]
                                          [activation_address];
                    end
                end else begin
                    activation_read_data_o <= '0;
                    protocol_error_o <= 1'b1;
                end
            end

            if (weight_read_enable_i) begin
                if (weight_buffer_valid && weight_address_valid) begin
                    for (integer bank = 0; bank < BANKS; bank++) begin
                        weight_read_data_o[bank*128 +: 128] <=
                            weight_mem[
                                BUFFER_INDEX_WIDTH'(weight_read_buffer_id_i)
                            ][bank]
                                      [weight_address];
                    end
                end else begin
                    weight_read_data_o <= '0;
                    protocol_error_o <= 1'b1;
                end
            end
        end
    end

    initial begin
        assert (BUFFER_COUNT > 0)
            else $error("npu_local_tensor_buffer BUFFER_COUNT must be positive");
        assert (BUFFER_COUNT <= (1 << npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH))
            else $error("npu_local_tensor_buffer BUFFER_COUNT exceeds Buffer ID space");
    end

endmodule

`default_nettype wire
