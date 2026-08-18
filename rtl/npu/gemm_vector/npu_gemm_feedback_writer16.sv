`timescale 1ns/1ps
`default_nettype none

// Full-rate GEMM-to-activation feedback path. GEMM row-major FP32 beats are
// quantized on arrival and transposed into the Tile-K-major activation layout.
// Two matrix slots allow one task to drain while the next task is collected.
module npu_gemm_feedback_writer16 #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned SLOTS = 2,
    parameter int unsigned MAX_SEGMENTS = 16,
    parameter int unsigned SLOT_INDEX_WIDTH =
        (SLOTS <= 1) ? 1 : $clog2(SLOTS)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic [CHANNELS-1:0] feedback_valid_i,
    output logic [CHANNELS-1:0] feedback_ready_o,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 feedback_result_i,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 feedback_command_i,

    output logic [CHANNELS-1:0] activation_write_valid_o,
    input  logic [CHANNELS-1:0] activation_write_ready_i,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 activation_write_buffer_id_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 activation_write_offset_o,
    output logic [CHANNELS*128-1:0] activation_write_data_o,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_o,
    output logic completion_success_o,
    output logic busy_o,
    output logic protocol_error_o
);

    localparam int unsigned SLOT_LEVEL_WIDTH = $clog2(SLOTS + 1);
    localparam int unsigned CHANNEL_INDEX_WIDTH =
        (CHANNELS <= 1) ? 1 : $clog2(CHANNELS);
    localparam int unsigned SEGMENT_INDEX_WIDTH =
        (MAX_SEGMENTS <= 1) ? 1 : $clog2(MAX_SEGMENTS);

    // Each column is a byte-write SRAM bank. One arriving row writes one byte
    // into all 16 column banks; draining reads one complete 128-bit column.
    // Logical transpose storage is technology-neutral. Integrations may
    // replace this banked scratchpad with a macro or register-file instance.
    logic [127:0] transpose_mem
        [0:SLOTS-1][0:CHANNELS-1][0:MAX_SEGMENTS-1][0:15];

    logic [SLOTS-1:0] slot_input_done_q;
    logic [CHANNELS-1:0] slot_bank_done_q [0:SLOTS-1];
    logic [npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        slot_job_id_q [0:SLOTS-1];
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
        slot_tag_q [0:SLOTS-1];
    logic [4:0] slot_segments_q [0:SLOTS-1];
    logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        slot_buffer_id_q [0:SLOTS-1];
    logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        slot_base_offset_q [0:SLOTS-1];

    logic ingest_active_q;
    logic [SLOT_INDEX_WIDTH-1:0] ingest_slot_q;
    logic [SLOT_INDEX_WIDTH-1:0] slot_write_pointer_q;
    logic [SLOT_INDEX_WIDTH-1:0] slot_read_pointer_q;
    logic [SLOT_LEVEL_WIDTH-1:0] slot_level_q;
    logic [4:0] drain_segment_q;
    logic [3:0] drain_column_q;

    logic completion_valid_q;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_q;
    logic completion_success_q;

    npu_scheduler_pkg::npu_post_result_beat_t input_beat [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t input_command [0:CHANNELS-1];
    logic [127:0] quantized_data [0:CHANNELS-1];
    logic [15:0] quantized_overflow [0:CHANNELS-1];
    logic [15:0] quantized_inexact [0:CHANNELS-1];
    logic [CHANNELS-1:0] input_fire;
    logic [CHANNELS-1:0] completed_bank_mask;
    logic [CHANNELS-1:0] expected_bank_mask;
    logic [SLOT_INDEX_WIDTH-1:0] selected_ingest_slot;
    logic allocate_fire;
    logic ingest_complete;
    logic first_valid_found;
    logic [CHANNEL_INDEX_WIDTH-1:0] first_valid_channel;

    logic drain_active;
    logic [CHANNELS-1:0] drain_bank_mask;
    logic drain_ready;
    logic drain_fire;
    logic drain_last;
    logic drain_release;
    logic completion_slot_available;

    generate
        for (genvar channel = 0; channel < CHANNELS; channel++) begin : g_input
            assign input_beat[channel] =
                npu_scheduler_pkg::npu_post_result_beat_t'(
                    feedback_result_i[
                        channel*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
                    ]);
            assign input_command[channel] =
                npu_scheduler_pkg::npu_post_command_t'(
                    feedback_command_i[
                        channel*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH
                    ]);

            for (genvar element = 0; element < 16; element++) begin : g_quantize
                fp32_to_fp8 u_quantize (
                    .data_i(input_beat[channel].data[element*32 +: 32]),
                    .format_i(input_command[channel].destination_format),
                    .rounding_i(input_command[channel].destination_rounding),
                    .data_o(quantized_data[channel][element*8 +: 8]),
                    .overflow_o(quantized_overflow[channel][element]),
                    .inexact_o(quantized_inexact[channel][element])
                );
            end
        end
    endgenerate

    always_comb begin
        feedback_ready_o = {CHANNELS{
            !rst_i && !clear_i &&
            (ingest_active_q ||
             (slot_level_q < SLOT_LEVEL_WIDTH'(SLOTS)))
        }};
    end

    always_comb begin
        completion_slot_available = !completion_valid_q || completion_ready_i;
        drain_active = (slot_level_q != '0) &&
            slot_input_done_q[slot_read_pointer_q];
        drain_bank_mask = '0;
        for (integer bank = 0; bank < CHANNELS; bank++) begin
            if (bank < integer'(slot_segments_q[slot_read_pointer_q])) begin
                drain_bank_mask[bank] = 1'b1;
            end
        end
        drain_last = drain_active &&
            (drain_column_q == 4'd15) &&
            ((drain_segment_q + 5'd1) ==
             slot_segments_q[slot_read_pointer_q]);
        drain_ready =
            ((activation_write_ready_i & drain_bank_mask) == drain_bank_mask) &&
            (!drain_last || completion_slot_available);
        drain_fire = drain_active && drain_ready;
        drain_release = drain_fire && drain_last;

        selected_ingest_slot = ingest_active_q ? ingest_slot_q :
            slot_write_pointer_q;
        input_fire = feedback_valid_i & feedback_ready_o;
        allocate_fire = !ingest_active_q && (|input_fire);
        first_valid_found = 1'b0;
        first_valid_channel = '0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            if (!first_valid_found && input_fire[channel]) begin
                first_valid_found = 1'b1;
                first_valid_channel = CHANNEL_INDEX_WIDTH'(channel);
            end
        end

        completed_bank_mask = ingest_active_q ?
            slot_bank_done_q[selected_ingest_slot] : '0;
        expected_bank_mask = '0;
        if (ingest_active_q) begin
            for (integer bank = 0; bank < CHANNELS; bank++) begin
                if (bank < integer'(slot_segments_q[selected_ingest_slot])) begin
                    expected_bank_mask[bank] = 1'b1;
                end
            end
        end else begin
            for (integer bank = 0; bank < CHANNELS; bank++) begin
                if (bank < integer'(
                    input_command[first_valid_channel].vectors_per_row)) begin
                    expected_bank_mask[bank] = 1'b1;
                end
            end
        end
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            logic [4:0] logical_bank;
            logical_bank = 5'(input_beat[channel].row >> 4);
            if (input_fire[channel] &&
                (input_beat[channel].row[3:0] == 4'd15) &&
                ((input_beat[channel].segment + 5'd1) ==
                 input_command[channel].vectors_per_row) &&
                (integer'(logical_bank) < CHANNELS)) begin
                completed_bank_mask[CHANNEL_INDEX_WIDTH'(logical_bank)] = 1'b1;
            end
        end
        ingest_complete = (|input_fire) &&
            ((completed_bank_mask & expected_bank_mask) == expected_bank_mask);
    end

    always_comb begin
        activation_write_valid_o = '0;
        activation_write_buffer_id_o = '0;
        activation_write_offset_o = '0;
        activation_write_data_o = '0;
        if (drain_active) begin
            for (integer bank = 0; bank < CHANNELS; bank++) begin
                if (drain_bank_mask[bank]) begin
                    activation_write_valid_o[bank] = 1'b1;
                    activation_write_buffer_id_o[
                        bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                        npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH
                    ] = slot_buffer_id_q[slot_read_pointer_q];
                    activation_write_offset_o[
                        bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                        npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH
                    ] = slot_base_offset_q[slot_read_pointer_q] +
                        npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH'(
                            ((integer'(drain_segment_q) * 16) +
                             integer'(drain_column_q)) * 16);
                    activation_write_data_o[bank*128 +: 128] =
                        transpose_mem[slot_read_pointer_q][bank]
                                     [SEGMENT_INDEX_WIDTH'(drain_segment_q)]
                                     [drain_column_q];
                end
            end
        end

        completion_valid_o = completion_valid_q;
        completion_tag_o = completion_tag_q;
        completion_success_o = completion_success_q;
        busy_o = ingest_active_q || (slot_level_q != '0) ||
            completion_valid_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            slot_input_done_q <= '0;
            ingest_active_q <= 1'b0;
            ingest_slot_q <= '0;
            slot_write_pointer_q <= '0;
            slot_read_pointer_q <= '0;
            slot_level_q <= '0;
            drain_segment_q <= '0;
            drain_column_q <= '0;
            completion_valid_q <= 1'b0;
            completion_tag_q <= '0;
            completion_success_q <= 1'b0;
            protocol_error_o <= 1'b0;
            for (integer slot = 0; slot < SLOTS; slot++) begin
                slot_bank_done_q[slot] <= '0;
                slot_job_id_q[slot] <= '0;
                slot_tag_q[slot] <= '0;
                slot_segments_q[slot] <= '0;
                slot_buffer_id_q[slot] <= '0;
                slot_base_offset_q[slot] <= '0;
            end
        end else begin
            if (completion_valid_q && completion_ready_i) begin
                completion_valid_q <= 1'b0;
            end

            if (allocate_fire) begin
                ingest_active_q <= 1'b1;
                ingest_slot_q <= slot_write_pointer_q;
                slot_input_done_q[slot_write_pointer_q] <= 1'b0;
                slot_bank_done_q[slot_write_pointer_q] <= '0;
                slot_job_id_q[slot_write_pointer_q] <=
                    input_beat[first_valid_channel].job_id;
                slot_tag_q[slot_write_pointer_q] <=
                    input_beat[first_valid_channel].tag;
                slot_segments_q[slot_write_pointer_q] <=
                    input_command[first_valid_channel].vectors_per_row;
                slot_buffer_id_q[slot_write_pointer_q] <=
                    input_command[first_valid_channel].destination_buffer_id;
                slot_base_offset_q[slot_write_pointer_q] <=
                    input_command[first_valid_channel].destination_base_offset;
                if (slot_write_pointer_q == SLOT_INDEX_WIDTH'(SLOTS - 1)) begin
                    slot_write_pointer_q <= '0;
                end else begin
                    slot_write_pointer_q <= slot_write_pointer_q + 1'b1;
                end
            end

            for (integer channel = 0; channel < CHANNELS; channel++) begin
                if (input_fire[channel]) begin
                    logic [4:0] logical_bank;
                    logical_bank = 5'(input_beat[channel].row >> 4);
                    if ((integer'(logical_bank) >= CHANNELS) ||
                        (integer'(input_beat[channel].segment) >=
                         MAX_SEGMENTS) ||
                        (input_command[channel].route !=
                         npu_scheduler_pkg::NPU_POST_GEMM) ||
                        input_command[channel].destination_operand ||
                        !input_command[channel].transpose_enable ||
                        (input_command[channel].output_format !=
                         npu_scheduler_pkg::NPU_OUTPUT_FP8)) begin
                        protocol_error_o <= 1'b1;
                    end else begin
                        for (integer element = 0; element < 16; element++) begin
                            transpose_mem[selected_ingest_slot]
                                         [CHANNEL_INDEX_WIDTH'(logical_bank)]
                                         [SEGMENT_INDEX_WIDTH'(
                                             input_beat[channel].segment)]
                                         [element]
                                         [input_beat[channel].row[3:0]*8 +: 8] <=
                                input_beat[channel].invalid[element] ? 8'd0 :
                                quantized_data[channel][element*8 +: 8];
                        end
                    end
                    if ((input_beat[channel].job_id !=
                         (allocate_fire ?
                          input_beat[first_valid_channel].job_id :
                          slot_job_id_q[selected_ingest_slot])) ||
                        (input_beat[channel].tag !=
                         (allocate_fire ?
                          input_beat[first_valid_channel].tag :
                          slot_tag_q[selected_ingest_slot]))) begin
                        protocol_error_o <= 1'b1;
                    end
                end
            end

            if (|input_fire) begin
                slot_bank_done_q[selected_ingest_slot] <= completed_bank_mask;
            end
            if (ingest_complete) begin
                slot_input_done_q[selected_ingest_slot] <= 1'b1;
                ingest_active_q <= 1'b0;
            end

            if (drain_fire) begin
                if (drain_last) begin
                    slot_input_done_q[slot_read_pointer_q] <= 1'b0;
                    slot_bank_done_q[slot_read_pointer_q] <= '0;
                    drain_segment_q <= '0;
                    drain_column_q <= '0;
                    completion_valid_q <= 1'b1;
                    completion_tag_q <= slot_tag_q[slot_read_pointer_q];
                    completion_success_q <= 1'b1;
                    if (slot_read_pointer_q ==
                        SLOT_INDEX_WIDTH'(SLOTS - 1)) begin
                        slot_read_pointer_q <= '0;
                    end else begin
                        slot_read_pointer_q <= slot_read_pointer_q + 1'b1;
                    end
                end else if (drain_column_q == 4'd15) begin
                    drain_column_q <= '0;
                    drain_segment_q <= drain_segment_q + 5'd1;
                end else begin
                    drain_column_q <= drain_column_q + 4'd1;
                end
            end

            unique case ({allocate_fire, drain_release})
                2'b10: slot_level_q <= slot_level_q + 1'b1;
                2'b01: slot_level_q <= slot_level_q - 1'b1;
                default: slot_level_q <= slot_level_q;
            endcase
        end
    end

    wire _unused_quantization_status = &{1'b0, quantized_overflow,
        quantized_inexact};

    initial begin
        assert ((CHANNELS >= 1) && (CHANNELS <= 16))
            else $error("npu_gemm_feedback_writer16 CHANNELS must be 1..16");
        assert (SLOTS >= 2)
            else $error("npu_gemm_feedback_writer16 requires at least two slots");
        assert (MAX_SEGMENTS >= CHANNELS)
            else $error("npu_gemm_feedback_writer16 segment storage too small");
    end

endmodule

`default_nettype wire
