`timescale 1ns/1ps
`default_nettype none

// Banked Tile-K-major input storage controller. Storage is provided only by
// npu_local_sram_1w1r_macro replacement instances; this module has no array.
module npu_local_tensor_buffer #(
    parameter int unsigned BUFFER_COUNT = 4,
    parameter int unsigned BANKS = 16,
    // Default data capacity per A or B store:
    // 4 buffer IDs x 16 banks x 8192 words x 16 bytes = 8 MiB.
    parameter int unsigned VECTOR_DEPTH = 8192,
    parameter int unsigned ADDRESS_WIDTH =
        (VECTOR_DEPTH <= 1) ? 1 : $clog2(VECTOR_DEPTH),
    parameter int unsigned BUFFER_INDEX_WIDTH =
        (BUFFER_COUNT <= 1) ? 1 : $clog2(BUFFER_COUNT),
    parameter int unsigned MACRO_ADDRESS_WIDTH =
        BUFFER_INDEX_WIDTH + ADDRESS_WIDTH
) (
    input  logic clk_i, input logic rst_i, input logic clear_i,
    input  logic tensor_write_valid_i, output logic tensor_write_ready_o,
    input  logic tensor_write_weight_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 tensor_write_buffer_id_i,
    input  logic [$clog2(BANKS)-1:0] tensor_write_bank_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 tensor_write_offset_i,
    input  logic [127:0] tensor_write_data_i,
    input  logic [127:0] tensor_write_scale_i,
    input  logic [BANKS-1:0] feedback_write_valid_i,
    output logic [BANKS-1:0] feedback_write_ready_o,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 feedback_write_buffer_id_i,
    input  logic [BANKS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 feedback_write_offset_i,
    input  logic [BANKS*128-1:0] feedback_write_data_i,
    input  logic [BANKS*8-1:0] feedback_write_scale_i,
    input  logic activation_read_enable_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 activation_read_buffer_id_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 activation_read_offset_i,
    output logic activation_read_valid_o,
    output logic [BANKS*128-1:0] activation_read_data_o,
    output logic [BANKS*128-1:0] activation_read_scale_o,
    input  logic weight_read_enable_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 weight_read_buffer_id_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 weight_read_offset_i,
    output logic weight_read_valid_o,
    output logic [BANKS*128-1:0] weight_read_data_o,
    output logic [BANKS*128-1:0] weight_read_scale_o,
    output logic protocol_error_o
);

    localparam int unsigned BUFFER_COMPARE_WIDTH =
        npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH + 1;
    localparam logic [BUFFER_COMPARE_WIDTH-1:0] BUFFER_COUNT_LIMIT =
        BUFFER_COMPARE_WIDTH'(BUFFER_COUNT);

    logic write_buffer_valid;
    logic write_address_valid;
    logic activation_read_address_valid;
    logic weight_read_address_valid;
    logic tensor_feedback_collision;
    logic [BANKS-1:0] activation_write_enable;
    logic [BANKS*MACRO_ADDRESS_WIDTH-1:0] activation_write_address;
    logic [BANKS*128-1:0] activation_write_data;
    logic [BANKS*128-1:0] activation_write_scale;
    logic [BANKS-1:0] weight_write_enable;
    logic [BANKS*MACRO_ADDRESS_WIDTH-1:0] weight_write_address;
    logic [BANKS-1:0] activation_data_read_valid;
    logic [BANKS-1:0] activation_scale_read_valid;
    logic [BANKS-1:0] weight_data_read_valid;
    logic [BANKS-1:0] weight_scale_read_valid;
    logic [MACRO_ADDRESS_WIDTH-1:0] activation_read_address;
    logic [MACRO_ADDRESS_WIDTH-1:0] weight_read_address;

    assign feedback_write_ready_o = {BANKS{!rst_i && !clear_i}};

    always_comb begin
        write_buffer_valid = {1'b0, tensor_write_buffer_id_i} <
            BUFFER_COUNT_LIMIT;
        write_address_valid = (tensor_write_offset_i[3:0] == 4'd0) &&
            ((tensor_write_offset_i >> 4) < VECTOR_DEPTH);
        activation_read_address_valid =
            ({1'b0, activation_read_buffer_id_i} < BUFFER_COUNT_LIMIT) &&
            (activation_read_offset_i[3:0] == 4'd0) &&
            ((activation_read_offset_i >> 4) < VECTOR_DEPTH);
        weight_read_address_valid =
            ({1'b0, weight_read_buffer_id_i} < BUFFER_COUNT_LIMIT) &&
            (weight_read_offset_i[3:0] == 4'd0) &&
            ((weight_read_offset_i >> 4) < VECTOR_DEPTH);
        tensor_feedback_collision = !tensor_write_weight_i &&
            feedback_write_valid_i[tensor_write_bank_i];
        tensor_write_ready_o = !rst_i && !clear_i &&
            !tensor_feedback_collision;
        activation_write_enable = '0;
        activation_write_address = '0;
        activation_write_data = '0;
        activation_write_scale = '0;
        weight_write_enable = '0;
        weight_write_address = '0;
        for (integer bank = 0; bank < BANKS; bank++) begin
            if (feedback_write_valid_i[bank] &&
                feedback_write_ready_o[bank]) begin
                activation_write_enable[bank] = 1'b1;
                activation_write_address[bank*MACRO_ADDRESS_WIDTH +:
                    MACRO_ADDRESS_WIDTH] = {
                    BUFFER_INDEX_WIDTH'(feedback_write_buffer_id_i[
                        bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                        npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH]),
                    ADDRESS_WIDTH'(feedback_write_offset_i[
                        bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                        npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH] >> 4)};
                activation_write_data[bank*128 +: 128] =
                    feedback_write_data_i[bank*128 +: 128];
                activation_write_scale[bank*128 +: 128] =
                    {16{feedback_write_scale_i[bank*8 +: 8]}};
            end
        end
        if (tensor_write_valid_i && tensor_write_ready_o && write_buffer_valid &&
            write_address_valid) begin
            if (tensor_write_weight_i) begin
                weight_write_enable[tensor_write_bank_i] = 1'b1;
                weight_write_address[tensor_write_bank_i*MACRO_ADDRESS_WIDTH +:
                    MACRO_ADDRESS_WIDTH] = {
                    BUFFER_INDEX_WIDTH'(tensor_write_buffer_id_i),
                    ADDRESS_WIDTH'(tensor_write_offset_i >> 4)};
            end else begin
                activation_write_enable[tensor_write_bank_i] = 1'b1;
                activation_write_address[
                    tensor_write_bank_i*MACRO_ADDRESS_WIDTH +:
                    MACRO_ADDRESS_WIDTH] = {
                    BUFFER_INDEX_WIDTH'(tensor_write_buffer_id_i),
                    ADDRESS_WIDTH'(tensor_write_offset_i >> 4)};
                activation_write_data[tensor_write_bank_i*128 +: 128] =
                    tensor_write_data_i;
                activation_write_scale[tensor_write_bank_i*128 +: 128] =
                    tensor_write_scale_i;
            end
        end
        activation_read_address = {
            BUFFER_INDEX_WIDTH'(activation_read_buffer_id_i),
            ADDRESS_WIDTH'(activation_read_offset_i >> 4)};
        weight_read_address = {
            BUFFER_INDEX_WIDTH'(weight_read_buffer_id_i),
            ADDRESS_WIDTH'(weight_read_offset_i >> 4)};
    end

    generate
        for (genvar bank = 0; bank < BANKS; bank++) begin : g_bank
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(MACRO_ADDRESS_WIDTH), .DATA_WIDTH(128)
            ) u_activation_data (
                .clk_i(clk_i), .rst_i(rst_i || clear_i),
                .write_enable_i(activation_write_enable[bank]),
                .write_address_i(activation_write_address[
                    bank*MACRO_ADDRESS_WIDTH +: MACRO_ADDRESS_WIDTH]),
                .write_data_i(activation_write_data[bank*128 +: 128]),
                .read_enable_i(activation_read_enable_i &&
                    activation_read_address_valid),
                .read_address_i(activation_read_address),
                .read_valid_o(activation_data_read_valid[bank]),
                .read_data_o(activation_read_data_o[bank*128 +: 128]));
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(MACRO_ADDRESS_WIDTH), .DATA_WIDTH(128)
            ) u_activation_scale (
                .clk_i(clk_i), .rst_i(rst_i || clear_i),
                .write_enable_i(activation_write_enable[bank]),
                .write_address_i(activation_write_address[
                    bank*MACRO_ADDRESS_WIDTH +: MACRO_ADDRESS_WIDTH]),
                .write_data_i(activation_write_scale[bank*128 +: 128]),
                .read_enable_i(activation_read_enable_i &&
                    activation_read_address_valid),
                .read_address_i(activation_read_address),
                .read_valid_o(activation_scale_read_valid[bank]),
                .read_data_o(activation_read_scale_o[bank*128 +: 128]));
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(MACRO_ADDRESS_WIDTH), .DATA_WIDTH(128)
            ) u_weight_data (
                .clk_i(clk_i), .rst_i(rst_i || clear_i),
                .write_enable_i(weight_write_enable[bank]),
                .write_address_i(weight_write_address[
                    bank*MACRO_ADDRESS_WIDTH +: MACRO_ADDRESS_WIDTH]),
                .write_data_i(tensor_write_data_i),
                .read_enable_i(weight_read_enable_i &&
                    weight_read_address_valid),
                .read_address_i(weight_read_address),
                .read_valid_o(weight_data_read_valid[bank]),
                .read_data_o(weight_read_data_o[bank*128 +: 128]));
            npu_local_sram_1w1r_macro #(
                .ADDRESS_WIDTH(MACRO_ADDRESS_WIDTH), .DATA_WIDTH(128)
            ) u_weight_scale (
                .clk_i(clk_i), .rst_i(rst_i || clear_i),
                .write_enable_i(weight_write_enable[bank]),
                .write_address_i(weight_write_address[
                    bank*MACRO_ADDRESS_WIDTH +: MACRO_ADDRESS_WIDTH]),
                .write_data_i(tensor_write_scale_i),
                .read_enable_i(weight_read_enable_i &&
                    weight_read_address_valid),
                .read_address_i(weight_read_address),
                .read_valid_o(weight_scale_read_valid[bank]),
                .read_data_o(weight_read_scale_o[bank*128 +: 128]));
        end
    endgenerate

    assign activation_read_valid_o = &activation_data_read_valid &&
        &activation_scale_read_valid;
    assign weight_read_valid_o = &weight_data_read_valid &&
        &weight_scale_read_valid;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            protocol_error_o <= 1'b0;
        end else begin
            if (tensor_write_valid_i && tensor_write_ready_o &&
                (!write_buffer_valid || !write_address_valid)) begin
                protocol_error_o <= 1'b1;
            end
            if (activation_read_enable_i &&
                !activation_read_address_valid) begin
                protocol_error_o <= 1'b1;
            end
            if (weight_read_enable_i && !weight_read_address_valid) begin
                protocol_error_o <= 1'b1;
            end
        end
    end

    initial begin
        assert ((BUFFER_COUNT > 0) && (BANKS > 0) && (VECTOR_DEPTH > 0))
            else $error("npu_local_tensor_buffer parameters must be positive");
    end

endmodule

`default_nettype wire
