`timescale 1ns/1ps
`default_nettype none

// GEMM-to-activation feedback path. Each channel pairs adjacent FP32 result
// segments into one 32-element MX block. The block store decouples full-rate
// result ingestion from the one-word-per-bank activation SRAM write ports.
module npu_gemm_feedback_writer16 #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned SLOTS = 2,
    parameter int unsigned MAX_SEGMENTS = 16,
    parameter int unsigned SLOT_INDEX_WIDTH =
        (SLOTS <= 1) ? 1 : $clog2(SLOTS),
    parameter int unsigned STORE_ADDRESS_WIDTH =
        $clog2(SLOTS * 16 * (MAX_SEGMENTS / 2))
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
    output logic [CHANNELS*8-1:0] activation_write_scale_o,

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
    localparam int unsigned PAIRS_PER_ROW = MAX_SEGMENTS / 2;
    localparam int unsigned PAIR_INDEX_WIDTH =
        (PAIRS_PER_ROW <= 1) ? 1 : $clog2(PAIRS_PER_ROW);
    localparam int unsigned STORE_DATA_WIDTH = 264;

    npu_scheduler_pkg::npu_post_result_beat_t input_beat [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t input_command [0:CHANNELS-1];

    logic [CHANNELS-1:0] quantizer_input_ready;
    logic [CHANNELS-1:0] quantizer_output_valid;
    logic [CHANNELS*256-1:0] quantizer_output_data;
    logic [CHANNELS*8-1:0] quantizer_output_scale;
    logic [CHANNELS*32-1:0] quantizer_output_invalid;
    logic [CHANNELS*32-1:0] quantizer_output_overflow;
    logic [CHANNELS*32-1:0] quantizer_output_inexact;
    logic [CHANNELS-1:0] quantizer_output_last;
    logic [CHANNELS-1:0] input_fire;
    logic [CHANNELS-1:0] second_input_fire;

    logic [15:0] quantizer_row_q [0:CHANNELS-1];
    logic [4:0] quantizer_pair_q [0:CHANNELS-1];
    logic [npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        quantizer_job_id_q [0:CHANNELS-1];
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
        quantizer_tag_q [0:CHANNELS-1];

    logic [SLOTS-1:0] slot_input_done_q;
    logic [npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        slot_job_id_q [0:SLOTS-1];
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
        slot_tag_q [0:SLOTS-1];
    logic [4:0] slot_segments_q [0:SLOTS-1];
    mxfp_pkg::mxfp_format_e slot_format_q [0:SLOTS-1];
    logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        slot_buffer_id_q [0:SLOTS-1];
    logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        slot_base_offset_q [0:SLOTS-1];

    logic ingest_active_q;
    logic [SLOT_INDEX_WIDTH-1:0] ingest_slot_q;
    logic [SLOT_INDEX_WIDTH-1:0] slot_write_pointer_q;
    logic [SLOT_INDEX_WIDTH-1:0] slot_read_pointer_q;
    logic [SLOT_LEVEL_WIDTH-1:0] slot_level_q;
    logic [SLOT_INDEX_WIDTH-1:0] selected_ingest_slot;
    logic allocate_fire;
    logic first_valid_found;
    logic [CHANNEL_INDEX_WIDTH-1:0] first_valid_channel;

    logic [CHANNELS-1:0] store_write_valid;
    logic [CHANNELS*STORE_ADDRESS_WIDTH-1:0] store_write_address;
    logic [CHANNELS*STORE_DATA_WIDTH-1:0] store_write_data;
    logic [CHANNELS-1:0] store_read_enable;
    logic [CHANNELS*STORE_ADDRESS_WIDTH-1:0] store_read_address;
    logic [CHANNELS-1:0] store_read_valid;
    logic [CHANNELS*STORE_DATA_WIDTH-1:0] store_read_data;
    logic store_response;

    logic [PAIR_INDEX_WIDTH-1:0] drain_issue_pair_q;
    logic [3:0] drain_issue_stream_q;
    logic drain_all_issued_q;
    logic drain_read_pending_q;
    logic [PAIR_INDEX_WIDTH-1:0] drain_pending_pair_q;
    logic [3:0] drain_pending_stream_q;
    logic drain_read_issue;
    logic drain_issue_last;
    logic [1:0] drain_queue_level_q;
    logic drain_queue_write_pointer_q;
    logic drain_queue_read_pointer_q;
    logic [CHANNELS*STORE_DATA_WIDTH-1:0] drain_queue_data_q [0:1];
    logic [PAIR_INDEX_WIDTH-1:0] drain_queue_pair_q [0:1];
    logic [3:0] drain_queue_stream_q [0:1];
    logic drain_output_valid;
    logic drain_output_half_q;
    logic [CHANNELS*STORE_DATA_WIDTH-1:0] drain_output_data;
    logic [PAIR_INDEX_WIDTH-1:0] drain_output_pair;
    logic [3:0] drain_output_stream;
    logic drain_block_pop;
    logic drain_active;
    logic [CHANNELS-1:0] drain_bank_mask;
    logic drain_output_fire;
    logic drain_output_last_half;
    logic drain_output_last;
    logic drain_release;
    logic completion_slot_available;

    logic completion_valid_q;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_q;

    generate
        for (genvar channel = 0; channel < CHANNELS; channel++) begin : g_channel
            assign input_beat[channel] =
                npu_scheduler_pkg::npu_post_result_beat_t'(
                    feedback_result_i[
                        channel*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]);
            assign input_command[channel] =
                npu_scheduler_pkg::npu_post_command_t'(
                    feedback_command_i[
                        channel*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]);

            mxfp_quantize_block32 u_quantizer (
                .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
                .input_valid_i(feedback_valid_i[channel] &&
                    (ingest_active_q ||
                     (slot_level_q < SLOT_LEVEL_WIDTH'(SLOTS)))),
                .input_ready_o(quantizer_input_ready[channel]),
                .input_data_i(input_beat[channel].data),
                .input_invalid_i(input_beat[channel].invalid),
                .input_last_i(input_beat[channel].last),
                .format_i(input_command[channel].destination_format),
                .output_valid_o(quantizer_output_valid[channel]),
                .output_ready_i(1'b1),
                .output_data_o(quantizer_output_data[channel*256 +: 256]),
                .output_scale_o(quantizer_output_scale[channel*8 +: 8]),
                .output_invalid_o(
                    quantizer_output_invalid[channel*32 +: 32]),
                .output_overflow_o(
                    quantizer_output_overflow[channel*32 +: 32]),
                .output_inexact_o(
                    quantizer_output_inexact[channel*32 +: 32]),
                .output_last_o(quantizer_output_last[channel])
            );
        end
    endgenerate

    always_comb begin
        feedback_ready_o = '0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            feedback_ready_o[channel] = !rst_i && !clear_i &&
                (ingest_active_q ||
                 (slot_level_q < SLOT_LEVEL_WIDTH'(SLOTS))) &&
                quantizer_input_ready[channel];
        end
        input_fire = feedback_valid_i & feedback_ready_o;
        second_input_fire = '0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            second_input_fire[channel] = input_fire[channel] &&
                input_beat[channel].segment[0];
        end

        selected_ingest_slot = ingest_active_q ? ingest_slot_q :
            slot_write_pointer_q;
        allocate_fire = !ingest_active_q && (|input_fire);
        first_valid_found = 1'b0;
        first_valid_channel = '0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            if (!first_valid_found && input_fire[channel]) begin
                first_valid_found = 1'b1;
                first_valid_channel = CHANNEL_INDEX_WIDTH'(channel);
            end
        end
    end

    always_comb begin
        store_write_valid = '0;
        store_write_address = '0;
        store_write_data = '0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            logic [CHANNEL_INDEX_WIDTH-1:0] target_bank;
            logic [STORE_ADDRESS_WIDTH-1:0] target_address;
            logic [255:0] masked_data;
            target_bank = CHANNEL_INDEX_WIDTH'(
                quantizer_row_q[channel] >> 4);
            target_address = STORE_ADDRESS_WIDTH'(
                (integer'(selected_ingest_slot) * 16 * PAIRS_PER_ROW) +
                (integer'(quantizer_row_q[channel][3:0]) * PAIRS_PER_ROW) +
                integer'(quantizer_pair_q[channel]));
            masked_data = quantizer_output_data[channel*256 +: 256];
            for (integer lane = 0; lane < 32; lane++) begin
                if (quantizer_output_invalid[channel*32 + lane]) begin
                    if (slot_format_q[selected_ingest_slot] ==
                        mxfp_pkg::MXFP4_E2M1) begin
                        masked_data[lane*4 +: 4] = 4'd0;
                    end else begin
                        masked_data[lane*8 +: 8] = 8'd0;
                    end
                end
            end
            if (quantizer_output_valid[channel] &&
                (integer'(target_bank) < CHANNELS)) begin
                store_write_valid[target_bank] = 1'b1;
                store_write_address[
                    target_bank*STORE_ADDRESS_WIDTH +:
                    STORE_ADDRESS_WIDTH] = target_address;
                store_write_data[target_bank*STORE_DATA_WIDTH +:
                    STORE_DATA_WIDTH] = {
                        quantizer_output_scale[channel*8 +: 8], masked_data};
            end
        end
    end

    assign drain_active = (slot_level_q != '0) &&
        slot_input_done_q[slot_read_pointer_q];
    always_comb begin
        drain_bank_mask = '0;
        for (integer bank = 0; bank < CHANNELS; bank++) begin
            if (bank < integer'(slot_segments_q[slot_read_pointer_q])) begin
                drain_bank_mask[bank] = 1'b1;
            end
        end

        store_read_enable = '0;
        store_read_address = '0;
        drain_read_issue = drain_active && !drain_all_issued_q &&
            (({1'b0, drain_queue_level_q} +
              {2'd0, drain_read_pending_q}) < 3'd2 || drain_block_pop);
        drain_issue_last =
            ((drain_issue_pair_q + PAIR_INDEX_WIDTH'(1)) ==
             PAIR_INDEX_WIDTH'(slot_segments_q[slot_read_pointer_q] >> 1)) &&
            (drain_issue_stream_q == 4'd15);
        if (drain_read_issue) begin
            store_read_enable = drain_bank_mask;
            for (integer bank = 0; bank < CHANNELS; bank++) begin
                store_read_address[bank*STORE_ADDRESS_WIDTH +:
                    STORE_ADDRESS_WIDTH] = STORE_ADDRESS_WIDTH'(
                        (integer'(slot_read_pointer_q) * 16 * PAIRS_PER_ROW) +
                        (integer'(drain_issue_stream_q) * PAIRS_PER_ROW) +
                        integer'(drain_issue_pair_q));
            end
        end
        store_response = ((store_read_valid & drain_bank_mask) ==
                          drain_bank_mask) && (drain_bank_mask != '0);
    end

    npu_feedback_block_store_macro #(
        .CHANNELS(CHANNELS),
        .ADDRESS_WIDTH(STORE_ADDRESS_WIDTH),
        .DATA_WIDTH(STORE_DATA_WIDTH)
    ) u_block_store (
        .clk_i(clk_i), .rst_i(rst_i || clear_i),
        .write_valid_i(store_write_valid),
        .write_address_i(store_write_address),
        .write_data_i(store_write_data),
        .read_enable_i(store_read_enable),
        .read_address_i(store_read_address),
        .read_valid_o(store_read_valid),
        .read_data_o(store_read_data)
    );

    always_comb begin
        drain_output_valid = drain_queue_level_q != 2'd0;
        drain_output_data =
            drain_queue_data_q[drain_queue_read_pointer_q];
        drain_output_pair =
            drain_queue_pair_q[drain_queue_read_pointer_q];
        drain_output_stream =
            drain_queue_stream_q[drain_queue_read_pointer_q];
        completion_slot_available = !completion_valid_q || completion_ready_i;
        drain_output_last_half =
            (slot_format_q[slot_read_pointer_q] == mxfp_pkg::MXFP4_E2M1) ||
            drain_output_half_q;
        drain_output_last = drain_output_valid && drain_output_last_half &&
            ((drain_output_pair + PAIR_INDEX_WIDTH'(1)) ==
             PAIR_INDEX_WIDTH'(slot_segments_q[slot_read_pointer_q] >> 1)) &&
            (drain_output_stream == 4'd15);
        drain_output_fire = drain_output_valid &&
            ((activation_write_ready_i & drain_bank_mask) == drain_bank_mask) &&
            (!drain_output_last || completion_slot_available);
        drain_block_pop = drain_output_fire && drain_output_last_half;
        drain_release = drain_output_fire && drain_output_last;

        activation_write_valid_o = drain_output_valid ? drain_bank_mask : '0;
        activation_write_buffer_id_o = '0;
        activation_write_offset_o = '0;
        activation_write_data_o = '0;
        activation_write_scale_o = '0;
        for (integer bank = 0; bank < CHANNELS; bank++) begin
            logic [255:0] block_data;
            logic [7:0] block_scale;
            logic [19:0] physical_word;
            block_data = drain_output_data[
                bank*STORE_DATA_WIDTH +: 256];
            block_scale = drain_output_data[
                bank*STORE_DATA_WIDTH + 256 +: 8];
            physical_word = 20'd0;
            if (slot_format_q[slot_read_pointer_q] ==
                mxfp_pkg::MXFP4_E2M1) begin
                physical_word =
                    (20'(drain_output_pair) * 20'd16) +
                    20'(drain_output_stream);
                activation_write_data_o[bank*128 +: 128] =
                    block_data[127:0];
            end else begin
                physical_word =
                    (((20'(drain_output_pair) * 20'd2) +
                      20'(drain_output_half_q)) * 20'd16) +
                    20'(drain_output_stream);
                activation_write_data_o[bank*128 +: 128] =
                    drain_output_half_q ? block_data[255:128] :
                                          block_data[127:0];
            end
            activation_write_buffer_id_o[
                bank*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH] =
                slot_buffer_id_q[slot_read_pointer_q];
            activation_write_offset_o[
                bank*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH] =
                slot_base_offset_q[slot_read_pointer_q] +
                npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH'(
                    physical_word * 20'd16);
            activation_write_scale_o[bank*8 +: 8] = block_scale;
        end

        completion_valid_o = completion_valid_q;
        completion_tag_o = completion_tag_q;
        completion_success_o = 1'b1;
        busy_o = ingest_active_q || (slot_level_q != '0) ||
            drain_read_pending_q || drain_output_valid || completion_valid_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            ingest_active_q <= 1'b0;
            ingest_slot_q <= '0;
            slot_write_pointer_q <= '0;
            slot_read_pointer_q <= '0;
            slot_level_q <= '0;
            slot_input_done_q <= '0;
            drain_issue_pair_q <= '0;
            drain_issue_stream_q <= '0;
            drain_all_issued_q <= 1'b0;
            drain_read_pending_q <= 1'b0;
            drain_pending_pair_q <= '0;
            drain_pending_stream_q <= '0;
            drain_queue_level_q <= '0;
            drain_queue_write_pointer_q <= 1'b0;
            drain_queue_read_pointer_q <= 1'b0;
            drain_output_half_q <= 1'b0;
            completion_valid_q <= 1'b0;
            completion_tag_q <= '0;
            protocol_error_o <= 1'b0;
            for (integer slot = 0; slot < SLOTS; slot++) begin
                slot_job_id_q[slot] <= '0;
                slot_tag_q[slot] <= '0;
                slot_segments_q[slot] <= '0;
                slot_format_q[slot] <= mxfp_pkg::MXFP8_E4M3;
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
                slot_job_id_q[slot_write_pointer_q] <=
                    input_beat[first_valid_channel].job_id;
                slot_tag_q[slot_write_pointer_q] <=
                    input_beat[first_valid_channel].tag;
                slot_segments_q[slot_write_pointer_q] <=
                    input_command[first_valid_channel].vectors_per_row;
                slot_format_q[slot_write_pointer_q] <=
                    input_command[first_valid_channel].destination_format;
                slot_buffer_id_q[slot_write_pointer_q] <=
                    input_command[first_valid_channel].destination_buffer_id;
                slot_base_offset_q[slot_write_pointer_q] <=
                    input_command[first_valid_channel].destination_base_offset;
                slot_write_pointer_q <= (slot_write_pointer_q ==
                    SLOT_INDEX_WIDTH'(SLOTS-1)) ? '0 :
                    slot_write_pointer_q + 1'b1;
            end

            for (integer channel = 0; channel < CHANNELS; channel++) begin
                if (second_input_fire[channel]) begin
                    quantizer_row_q[channel] <= input_beat[channel].row;
                    quantizer_pair_q[channel] <= input_beat[channel].segment >> 1;
                    quantizer_job_id_q[channel] <= input_beat[channel].job_id;
                    quantizer_tag_q[channel] <= input_beat[channel].tag;
                end
                if (input_fire[channel]) begin
                    if (!((input_command[channel].route ==
                           npu_scheduler_pkg::NPU_POST_GEMM) ||
                          ((input_command[channel].route ==
                            npu_scheduler_pkg::NPU_POST_VECTOR) &&
                           (input_command[channel].vector_result_route ==
                            npu_scheduler_pkg::NPU_VECTOR_TO_FEEDBACK))) ||
                        input_command[channel].destination_operand ||
                        input_command[channel].transpose_enable ||
                        (input_command[channel].output_format !=
                         npu_scheduler_pkg::NPU_OUTPUT_MX)) begin
                        protocol_error_o <= 1'b1;
                    end
                    if (ingest_active_q &&
                        ((input_beat[channel].job_id !=
                          slot_job_id_q[ingest_slot_q]) ||
                         (input_beat[channel].tag !=
                          slot_tag_q[ingest_slot_q]))) begin
                        protocol_error_o <= 1'b1;
                    end
                end
                if (quantizer_output_valid[channel]) begin
                    if ((quantizer_job_id_q[channel] !=
                         slot_job_id_q[selected_ingest_slot]) ||
                        (quantizer_tag_q[channel] !=
                         slot_tag_q[selected_ingest_slot])) begin
                        protocol_error_o <= 1'b1;
                    end
                    if (quantizer_output_last[channel]) begin
                        slot_input_done_q[selected_ingest_slot] <= 1'b1;
                        ingest_active_q <= 1'b0;
                    end
                end
            end

            if (drain_read_issue) begin
                drain_pending_pair_q <= drain_issue_pair_q;
                drain_pending_stream_q <= drain_issue_stream_q;
                if (drain_issue_last) begin
                    drain_all_issued_q <= 1'b1;
                end else if ((drain_issue_pair_q + PAIR_INDEX_WIDTH'(1)) ==
                             PAIR_INDEX_WIDTH'(
                                 slot_segments_q[slot_read_pointer_q] >> 1)) begin
                    drain_issue_pair_q <= '0;
                    drain_issue_stream_q <= drain_issue_stream_q + 4'd1;
                end else begin
                    drain_issue_pair_q <= drain_issue_pair_q + 1'b1;
                end
            end
            if (store_response) begin
                drain_queue_data_q[drain_queue_write_pointer_q] <=
                    store_read_data;
                drain_queue_pair_q[drain_queue_write_pointer_q] <=
                    drain_pending_pair_q;
                drain_queue_stream_q[drain_queue_write_pointer_q] <=
                    drain_pending_stream_q;
                drain_queue_write_pointer_q <=
                    ~drain_queue_write_pointer_q;
            end
            unique case ({drain_read_issue, store_response})
                2'b10: drain_read_pending_q <= 1'b1;
                2'b01: drain_read_pending_q <= 1'b0;
                2'b11: drain_read_pending_q <= 1'b1;
                default: drain_read_pending_q <= drain_read_pending_q;
            endcase
            if (drain_output_fire) begin
                if (!drain_output_last_half) begin
                    drain_output_half_q <= 1'b1;
                end else begin
                    drain_output_half_q <= 1'b0;
                    drain_queue_read_pointer_q <=
                        ~drain_queue_read_pointer_q;
                end
                if (drain_output_last) begin
                    slot_input_done_q[slot_read_pointer_q] <= 1'b0;
                    completion_valid_q <= 1'b1;
                    completion_tag_q <= slot_tag_q[slot_read_pointer_q];
                    slot_read_pointer_q <= (slot_read_pointer_q ==
                        SLOT_INDEX_WIDTH'(SLOTS-1)) ? '0 :
                        slot_read_pointer_q + 1'b1;
                    drain_issue_pair_q <= '0;
                    drain_issue_stream_q <= '0;
                    drain_all_issued_q <= 1'b0;
                end
            end

            unique case ({store_response, drain_block_pop})
                2'b10: drain_queue_level_q <= drain_queue_level_q + 1'b1;
                2'b01: drain_queue_level_q <= drain_queue_level_q - 1'b1;
                default: drain_queue_level_q <= drain_queue_level_q;
            endcase

            unique case ({allocate_fire, drain_release})
                2'b10: slot_level_q <= slot_level_q + 1'b1;
                2'b01: slot_level_q <= slot_level_q - 1'b1;
                default: slot_level_q <= slot_level_q;
            endcase
        end
    end

    wire _unused_quantization_status = &{1'b0, quantizer_output_overflow,
        quantizer_output_inexact};

    initial begin
        assert ((CHANNELS >= 1) && (CHANNELS <= 16))
            else $error("npu_gemm_feedback_writer16 CHANNELS must be 1..16");
        assert (SLOTS >= 2)
            else $error("npu_gemm_feedback_writer16 requires at least two slots");
        assert ((MAX_SEGMENTS >= 2) && ((MAX_SEGMENTS % 2) == 0))
            else $error("npu_gemm_feedback_writer16 requires even segments");
    end

endmodule

`default_nettype wire
