`timescale 1ns/1ps
`default_nettype none

// Converts one independent Vector task into the same tagged row/segment stream
// consumed by the shared GEMM/Vector backend. Vector A is read from the banked
// Activation Buffer; B/C remain owned by the existing Vector operand buffer.
module npu_vector_stream_frontend16 #(
    parameter int unsigned CHANNELS = 16
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic command_valid_i,
    output logic command_ready_o,
    input  logic [npu_scheduler_pkg::NPU_VECTOR_COMMAND_WIDTH-1:0]
                 command_i,

    output logic activation_read_valid_o,
    input  logic activation_read_ready_i,
    output logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 activation_read_buffer_id_o,
    output logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 activation_read_offset_o,
    input  logic activation_response_valid_i,
    input  logic [CHANNELS*128-1:0] activation_response_data_i,
    input  logic [CHANNELS*128-1:0] activation_response_scale_i,

    output logic [CHANNELS-1:0] stream_valid_o,
    input  logic [CHANNELS-1:0] stream_ready_i,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 stream_result_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 stream_command_o,

    output logic busy_o,
    output logic protocol_error_o
);

    npu_scheduler_pkg::npu_vector_command_t command_input;
    /* verilator lint_off UNUSEDSIGNAL */
    npu_scheduler_pkg::npu_vector_command_t command_q;
    /* verilator lint_on UNUSEDSIGNAL */
    npu_scheduler_pkg::npu_post_result_beat_t candidate_beat [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t candidate_command [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t output_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t output_command_q [0:CHANNELS-1];

    logic active_q;
    logic read_inflight_q;
    logic [4:0] local_row_q;
    logic [4:0] segment_q;
    logic [4:0] local_row_count;
    logic [20:0] storage_word_index;
    logic command_fire;
    logic read_fire;
    logic [CHANNELS-1:0] output_valid_q;
    logic [CHANNELS-1:0] output_fire;
    logic output_drained;
    logic last_source_read;
    logic [CHANNELS*512-1:0] decoded_a_data;
    logic [CHANNELS*16-1:0] decoded_a_invalid;

    always_comb begin
        command_input = npu_scheduler_pkg::npu_vector_command_t'(command_i);
        command_ready_o = !rst_i && !clear_i && !active_q &&
            !read_inflight_q && (output_valid_q == '0);
        command_fire = command_valid_i && command_ready_o;

        local_row_count = (command_q.matrix_size < 16'd16) ?
            5'(command_q.matrix_size) : 5'd16;
        // Reuse the Tensor Activation Buffer's Tile-K-major layout so DMA,
        // feedback, GEMM, and standalone Vector tasks share one image.
        storage_word_index =
            (command_q.operand_a_format == mxfp_pkg::MXFP4_E2M1) ?
            ((21'(segment_q) >> 1) * 21'd16 + 21'(local_row_q)) :
            (21'(segment_q) * 21'd16 + 21'(local_row_q));

        activation_read_valid_o = active_q && !read_inflight_q &&
            (output_valid_q == '0);
        activation_read_buffer_id_o = command_q.operand_a_buffer_id;
        activation_read_offset_o = command_q.operand_a_base_offset +
            npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH'(
                storage_word_index << 4);
        read_fire = activation_read_valid_o && activation_read_ready_i;

        stream_valid_o = output_valid_q;
        output_fire = output_valid_q & stream_ready_i;
        output_drained = (output_valid_q != '0) &&
            ((output_valid_q & ~stream_ready_i) == '0);
        last_source_read = (segment_q + 5'd1 ==
                            command_q.vectors_per_row) &&
                           (local_row_q + 5'd1 == local_row_count);
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            stream_result_o[
                lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                npu_scheduler_pkg::NPU_POST_RESULT_WIDTH] = output_beat_q[lane];
            stream_command_o[
                lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH] =
                output_command_q[lane];
        end
        busy_o = active_q || read_inflight_q || (output_valid_q != '0);
    end

    generate
        for (genvar lane = 0; lane < CHANNELS; lane++) begin : g_decode_lane
            for (genvar element = 0; element < 16; element++) begin : g_decode_element
                logic [7:0] packed_element;

                always_comb begin
                    if (command_q.operand_a_format == mxfp_pkg::MXFP4_E2M1) begin
                        packed_element = {4'd0, activation_response_data_i[
                            lane*128 + (segment_q[0] ? 64 : 0) +
                            element*4 +: 4]};
                    end else begin
                        packed_element = activation_response_data_i[
                            lane*128 + element*8 +: 8];
                    end
                end

                mxfp_to_fp32 #(.DAZ(1'b0)) u_decode (
                    .data_i(packed_element),
                    .format_i(command_q.operand_a_format),
                    .scale_i(activation_response_scale_i[
                        lane*128 + element*8 +: 8]),
                    .data_o(decoded_a_data[
                        lane*512 + element*32 +: 32]),
                    .invalid_o(decoded_a_invalid[lane*16 + element])
                );
            end
        end
    endgenerate

    always_comb begin
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            logic [npu_scheduler_pkg::NPU_DIMENSION_WIDTH-1:0] logical_row;
            logic row_active;
            logic [15:0] lane_mask;
            logic [15:0] invalid_mask;

            logical_row = npu_scheduler_pkg::NPU_DIMENSION_WIDTH'(
                lane * 16) +
                npu_scheduler_pkg::NPU_DIMENSION_WIDTH'(local_row_q);
            row_active = logical_row < command_q.matrix_size;
            lane_mask = '0;
            invalid_mask = decoded_a_invalid[lane*16 +: 16];
            for (integer element = 0; element < 16; element++) begin
                if (((16'(segment_q) * 16'd16) + 16'(element)) <
                    command_q.matrix_size) begin
                    lane_mask[element] = command_q.control.lane_mask[element];
                end else begin
                    invalid_mask[element] = 1'b1;
                end
            end

            candidate_beat[lane] = '0;
            candidate_beat[lane].data = decoded_a_data[lane*512 +: 512];
            candidate_beat[lane].payload_kind =
                npu_scheduler_pkg::NPU_PAYLOAD_FP32_VECTOR;
            candidate_beat[lane].mx_format = command_q.operand_a_format;
            candidate_beat[lane].mx_scale = mxfp_pkg::mxfp_scale_t'(0);
            candidate_beat[lane].invalid = invalid_mask;
            candidate_beat[lane].job_id = command_q.job_id;
            candidate_beat[lane].tag = command_q.tag;
            candidate_beat[lane].row = logical_row;
            candidate_beat[lane].segment = segment_q;
            candidate_beat[lane].last = row_active &&
                (logical_row + 16'd1 == command_q.matrix_size) &&
                (segment_q + 5'd1 == command_q.vectors_per_row);

            candidate_command[lane] = '0;
            candidate_command[lane].job_id = command_q.job_id;
            candidate_command[lane].tag = command_q.tag;
            candidate_command[lane].standalone = 1'b1;
            candidate_command[lane].matrix_size = command_q.matrix_size;
            candidate_command[lane].vectors_per_row =
                command_q.vectors_per_row;
            candidate_command[lane].route =
                npu_scheduler_pkg::NPU_POST_VECTOR;
            candidate_command[lane].vector_result_route = command_q.result_route;
            candidate_command[lane].vector_control = command_q.control;
            candidate_command[lane].vector_control.lane_mask = lane_mask;
            candidate_command[lane].operand_b_buffer_id =
                command_q.operand_b_buffer_id;
            candidate_command[lane].operand_b_base_offset =
                command_q.operand_b_base_offset;
            candidate_command[lane].operand_b_format =
                command_q.operand_b_format;
            candidate_command[lane].operand_c_buffer_id =
                command_q.operand_c_buffer_id;
            candidate_command[lane].operand_c_base_offset =
                command_q.operand_c_base_offset;
            candidate_command[lane].operand_c_format =
                command_q.operand_c_format;
            candidate_command[lane].scalar = command_q.scalar;
            candidate_command[lane].destination_buffer_id =
                command_q.destination_buffer_id;
            candidate_command[lane].destination_base_offset =
                command_q.destination_base_offset;
            candidate_command[lane].destination_operand =
                command_q.destination_operand;
            candidate_command[lane].transpose_enable =
                command_q.transpose_enable;
            candidate_command[lane].destination_format =
                command_q.destination_format;
            candidate_command[lane].output_format = command_q.output_format;
            candidate_command[lane].output_mx_format =
                command_q.output_mx_format;
            candidate_command[lane].signal_event_valid =
                command_q.signal_event_valid;
            candidate_command[lane].signal_event_id =
                command_q.signal_event_id;
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            command_q <= '0;
            active_q <= 1'b0;
            read_inflight_q <= 1'b0;
            local_row_q <= '0;
            segment_q <= '0;
            output_valid_q <= '0;
            protocol_error_o <= 1'b0;
            for (integer lane = 0; lane < CHANNELS; lane++) begin
                output_beat_q[lane] <= '0;
                output_command_q[lane] <= '0;
            end
        end else begin
            if (command_fire) begin
                command_q <= command_input;
                active_q <= 1'b1;
                local_row_q <= '0;
                segment_q <= '0;
                if (!command_input.standalone ||
                    (command_input.vectors_per_row == 5'd0) ||
                    (command_input.matrix_size == 16'd0) ||
                    (command_input.matrix_size > 16'(CHANNELS * 16))) begin
                    protocol_error_o <= 1'b1;
                    active_q <= 1'b0;
                end
            end

            if (read_fire) begin
                read_inflight_q <= 1'b1;
            end
            if (activation_response_valid_i) begin
                if (read_inflight_q) begin
                    read_inflight_q <= 1'b0;
                    for (integer lane = 0; lane < CHANNELS; lane++) begin
                        output_valid_q[lane] <=
                            candidate_beat[lane].row < command_q.matrix_size;
                        output_beat_q[lane] <= candidate_beat[lane];
                        output_command_q[lane] <= candidate_command[lane];
                    end
                end else begin
                    protocol_error_o <= 1'b1;
                end
            end

            if (output_drained) begin
                output_valid_q <= '0;
                if (last_source_read) begin
                    active_q <= 1'b0;
                    local_row_q <= '0;
                    segment_q <= '0;
                end else if (segment_q + 5'd1 ==
                             command_q.vectors_per_row) begin
                    segment_q <= '0;
                    local_row_q <= local_row_q + 5'd1;
                end else begin
                    segment_q <= segment_q + 5'd1;
                end
            end else if (|output_fire) begin
                // Channels retire independently. Never replay a lane that
                // has already handshaken while another lane is stalled.
                output_valid_q <= output_valid_q & ~output_fire;
            end

            if (activation_response_valid_i && !read_inflight_q) begin
                protocol_error_o <= 1'b1;
            end
            if ((output_fire & ~output_valid_q) != '0) begin
                protocol_error_o <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
