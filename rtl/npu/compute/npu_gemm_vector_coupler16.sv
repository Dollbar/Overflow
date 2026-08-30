`timescale 1ns/1ps
`default_nettype none

// Connects the sixteen GEMM row-result streams to sixteen independent Vector
// engines.  Commands and result coordinates are retained by hardware tag so
// different operator latencies may return out of issue order without losing
// task identity.
module npu_gemm_vector_coupler16 #(
    parameter int unsigned CHANNELS = 16,
    parameter int unsigned CONTEXTS = 16,
    parameter int unsigned FIFO_DEPTH = 4,
    parameter bit FTZ = 1'b0,
    parameter int unsigned CONTEXT_INDEX_WIDTH =
        (CONTEXTS <= 1) ? 1 : $clog2(CONTEXTS)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic vector_command_valid_i,
    output logic vector_command_ready_o,
    input  logic [npu_scheduler_pkg::NPU_VECTOR_COMMAND_WIDTH-1:0]
                 vector_command_i,

    input  logic [CHANNELS-1:0] gemm_valid_i,
    output logic [CHANNELS-1:0] gemm_ready_o,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_result_i,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_command_i,

    output logic [CHANNELS-1:0] operand_b_read_enable_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 operand_b_read_buffer_id_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 operand_b_read_offset_o,
    input  logic [CHANNELS-1:0] operand_b_read_valid_i,
    input  logic [CHANNELS*128-1:0] operand_b_read_data_i,
    input  logic [CHANNELS*8-1:0] operand_b_read_scale_i,
    output logic [CHANNELS-1:0] operand_c_read_enable_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 operand_c_read_buffer_id_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 operand_c_read_offset_o,
    input  logic [CHANNELS-1:0] operand_c_read_valid_i,
    input  logic [CHANNELS*128-1:0] operand_c_read_data_i,
    input  logic [CHANNELS*8-1:0] operand_c_read_scale_i,

    output logic [CHANNELS-1:0] result_valid_o,
    input  logic [CHANNELS-1:0] result_ready_i,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 result_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 result_command_o,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_o,
    output logic completion_success_o,
    output logic completion_feedback_o,
    output logic busy_o,
    output logic protocol_error_o
);
    localparam int unsigned ENGINE_GROUP_SIZE = 2;
    localparam int unsigned ENGINE_GROUP_COUNT =
        (CHANNELS + ENGINE_GROUP_SIZE - 1) / ENGINE_GROUP_SIZE;
    localparam int unsigned LANE_INPUT_WIDTH =
        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +
        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH;

    npu_scheduler_pkg::npu_vector_command_t command_input;
    logic command_index_in_range;
    logic [CONTEXT_INDEX_WIDTH-1:0] command_index;
    logic command_fire;
    logic [CONTEXTS-1:0] context_valid_q;
    npu_scheduler_pkg::npu_vector_command_t
        context_vector_command_mem [0:CONTEXTS-1];
    npu_scheduler_pkg::npu_post_command_t
        context_post_command_mem [0:CONTEXTS-1];
    logic [20:0] context_expected_count_mem [0:CONTEXTS-1];
    logic [20:0] context_response_count_q [0:CONTEXTS-1];
    logic [CONTEXTS-1:0] context_last_seen_q;

    logic [CHANNELS-1:0] pending_valid_q;
    logic [CHANNELS-1:0] pending_need_b_q;
    logic [CHANNELS-1:0] pending_need_c_q;
    logic [CHANNELS-1:0] pending_b_valid_q;
    logic [CHANNELS-1:0] pending_c_valid_q;
    logic [511:0] pending_b_data_q [0:CHANNELS-1];
    logic [511:0] pending_c_data_q [0:CHANNELS-1];
    logic [15:0] pending_b_invalid_q [0:CHANNELS-1];
    logic [15:0] pending_c_invalid_q [0:CHANNELS-1];
    logic [511:0] decoded_b_data [0:CHANNELS-1];
    logic [511:0] decoded_c_data [0:CHANNELS-1];
    logic [15:0] decoded_b_invalid [0:CHANNELS-1];
    logic [15:0] decoded_c_invalid [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t
        pending_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t
        pending_command_q [0:CHANNELS-1];
    logic [CHANNELS-1:0] request_valid_q;
    vector_pkg::vector_engine_request_t request_q [0:CHANNELS-1];
    logic [CHANNELS-1:0] fetch_complete;
    vector_pkg::vector_engine_request_t fetch_request [0:CHANNELS-1];

    logic lane_started_q [0:CONTEXTS-1][0:CHANNELS-1];
    logic [npu_scheduler_pkg::NPU_DIMENSION_WIDTH-1:0]
        response_row_q [0:CONTEXTS-1][0:CHANNELS-1];
    logic [4:0] response_segment_q [0:CONTEXTS-1][0:CHANNELS-1];

    logic [CHANNELS-1:0] backend_request_valid;
    logic [CHANNELS-1:0] backend_request_ready;
    logic [CHANNELS*vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH-1:0]
        backend_request;
    logic [CHANNELS-1:0] backend_response_valid;
    logic [CHANNELS-1:0] backend_response_ready;
    logic [CHANNELS*vector_pkg::VECTOR_ENGINE_RESULT_WIDTH-1:0]
        backend_response;

    logic [CHANNELS-1:0] input_fire;
    logic [CHANNELS-1:0] request_consume;
    logic [CHANNELS-1:0] fetch_transfer;
    logic [CHANNELS-1:0] response_fire;
    logic [CHANNELS-1:0] response_context_match;
    logic completion_valid_q;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_q;
    logic completion_success_q;
    logic completion_feedback_q;
    logic [CONTEXTS*6-1:0] response_context_increment;
    logic [CONTEXTS-1:0] response_context_last_fire;
    logic [CONTEXTS-1:0] response_context_complete;
    logic [5:0] response_completion_count;
    logic [CHANNELS-1:0] lane_fifo_input_valid;
    logic [CHANNELS-1:0] lane_fifo_input_ready;
    logic [CHANNELS*LANE_INPUT_WIDTH-1:0] lane_fifo_input_data;
    logic [CHANNELS-1:0] lane_fifo_output_valid;
    logic [CHANNELS-1:0] lane_fifo_output_ready;
    logic [CHANNELS*LANE_INPUT_WIDTH-1:0] lane_fifo_output_data;
    logic [CHANNELS*$clog2(FIFO_DEPTH+1)-1:0] lane_fifo_level_unused;
    npu_scheduler_pkg::npu_post_result_beat_t
        lane_fifo_beat [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t
        lane_fifo_command [0:CHANNELS-1];
    vector_pkg::vector_engine_result_t
        backend_response_decoded [0:CHANNELS-1];
    logic [CHANNELS-1:0] backend_response_observation;

    generate
        for (genvar decode_channel = 0; decode_channel < CHANNELS;
             decode_channel++) begin : g_operand_decode
            for (genvar element = 0; element < 16; element++) begin : g_element
                logic [7:0] b_element;
                logic [7:0] c_element;
                logic b_high_half;
                logic c_high_half;

                assign b_high_half = pending_command_q[decode_channel].
                    operand_b_format == mxfp_pkg::MXFP4_E2M1 &&
                    ((pending_beat_q[decode_channel].row[3:0] *
                      pending_command_q[decode_channel].vectors_per_row +
                      pending_beat_q[decode_channel].segment) % 2 == 1);
                assign c_high_half = pending_command_q[decode_channel].
                    operand_c_format == mxfp_pkg::MXFP4_E2M1 &&
                    ((pending_beat_q[decode_channel].row[3:0] *
                      pending_command_q[decode_channel].vectors_per_row +
                      pending_beat_q[decode_channel].segment) % 2 == 1);
                assign b_element =
                    (pending_command_q[decode_channel].operand_b_format ==
                     mxfp_pkg::MXFP4_E2M1) ?
                    {4'd0, operand_b_read_data_i[
                        decode_channel*128 + (b_high_half ? 64 : 0) +
                        element*4 +: 4]} :
                    operand_b_read_data_i[
                        decode_channel*128 + element*8 +: 8];
                assign c_element =
                    (pending_command_q[decode_channel].operand_c_format ==
                     mxfp_pkg::MXFP4_E2M1) ?
                    {4'd0, operand_c_read_data_i[
                        decode_channel*128 + (c_high_half ? 64 : 0) +
                        element*4 +: 4]} :
                    operand_c_read_data_i[
                        decode_channel*128 + element*8 +: 8];

                mxfp_to_fp32 #(.DAZ(1'b0)) u_b_decode (
                    .data_i(b_element),
                    .format_i(pending_command_q[decode_channel].operand_b_format),
                    .scale_i(operand_b_read_scale_i[
                        decode_channel*8 +: 8]),
                    .data_o(decoded_b_data[decode_channel][element*32 +: 32]),
                    .invalid_o(decoded_b_invalid[decode_channel][element])
                );
                mxfp_to_fp32 #(.DAZ(1'b0)) u_c_decode (
                    .data_i(c_element),
                    .format_i(pending_command_q[decode_channel].operand_c_format),
                    .scale_i(operand_c_read_scale_i[
                        decode_channel*8 +: 8]),
                    .data_o(decoded_c_data[decode_channel][element*32 +: 32]),
                    .invalid_o(decoded_c_invalid[decode_channel][element])
                );
            end
        end
    endgenerate

    always_comb begin
        command_input = npu_scheduler_pkg::npu_vector_command_t'(
            vector_command_i
        );
        command_index_in_range =
            ({1'b0, command_input.tag[3:0]} < 5'(CONTEXTS));
        command_index = CONTEXT_INDEX_WIDTH'(command_input.tag[3:0]);
        vector_command_ready_o = !rst_i && !clear_i &&
            command_index_in_range && !context_valid_q[command_index];
        command_fire = vector_command_valid_i && vector_command_ready_o;
    end

    generate
        for (genvar decode_lane = 0; decode_lane < CHANNELS;
             decode_lane++) begin : g_decode
            always_comb begin
                lane_fifo_beat[decode_lane] =
                    npu_scheduler_pkg::npu_post_result_beat_t'(
                        lane_fifo_output_data[
                            decode_lane*LANE_INPUT_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
                        ]
                    );
                lane_fifo_command[decode_lane] =
                    npu_scheduler_pkg::npu_post_command_t'(
                        lane_fifo_output_data[
                            decode_lane*LANE_INPUT_WIDTH +
                            npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH
                        ]
                    );
                backend_response_decoded[decode_lane] =
                    vector_pkg::vector_engine_result_t'(
                        backend_response[
                            decode_lane*vector_pkg::VECTOR_ENGINE_RESULT_WIDTH +:
                            vector_pkg::VECTOR_ENGINE_RESULT_WIDTH
                        ]
                    );
                backend_response_observation[decode_lane] = ^{
                    backend_response_decoded[decode_lane].overflow,
                    backend_response_decoded[decode_lane].inexact,
                    backend_response_decoded[decode_lane].empty,
                    backend_response_decoded[decode_lane].control.lane_mask,
                    backend_response_decoded[decode_lane].control.operation,
                    backend_response_decoded[decode_lane].control.
                        operand_b_source,
                    backend_response_decoded[decode_lane].control.bias_enable,
                    backend_response_decoded[decode_lane].control.bias_is_scalar,
                    backend_response_decoded[decode_lane].control.
                        residual_enable,
                    backend_response_decoded[decode_lane].control.activation,
                    backend_response_decoded[decode_lane].control.output_format,
                    backend_response_decoded[decode_lane].control.mx_format,
                    backend_response_decoded[decode_lane].control.affine_enable,
                    backend_response_decoded[decode_lane].control.beta_enable
                };
            end
        end
    endgenerate

    always_comb begin
        gemm_ready_o = '0;
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            gemm_ready_o[lane] = lane_fifo_input_ready[lane];
        end
    end

    always_comb begin
        lane_fifo_input_valid = '0;
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            npu_scheduler_pkg::npu_post_result_beat_t input_beat;
            npu_scheduler_pkg::npu_post_command_t input_command;

            input_beat = npu_scheduler_pkg::npu_post_result_beat_t'(
                gemm_result_i[
                    lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
                ]
            );
            input_command = npu_scheduler_pkg::npu_post_command_t'(
                gemm_command_i[
                    lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH
                ]
            );
            lane_fifo_input_valid[lane] = gemm_valid_i[lane];
            lane_fifo_input_data[lane*LANE_INPUT_WIDTH +: LANE_INPUT_WIDTH] =
                {input_command, input_beat};
        end
    end

    always_comb begin
        backend_request_valid = '0;

        for (integer lane = 0; lane < CHANNELS; lane++) begin
            backend_request_valid[lane] = request_valid_q[lane] ||
                fetch_complete[lane];
            backend_request[
                lane*vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH +:
                vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH
            ] = request_valid_q[lane] ? request_q[lane] :
                fetch_request[lane];
        end
    end

    // Complete each fetched beat from either the live synchronous-SRAM return
    // or the retained operand copy when the Vector request path was blocked.
    always_comb begin
        fetch_complete = '0;
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            logic fetch_b_valid;
            logic fetch_c_valid;

            fetch_b_valid = !pending_need_b_q[lane] ||
                pending_b_valid_q[lane] || operand_b_read_valid_i[lane];
            fetch_c_valid = !pending_need_c_q[lane] ||
                pending_c_valid_q[lane] || operand_c_read_valid_i[lane];
            fetch_complete[lane] = pending_valid_q[lane] &&
                fetch_b_valid && fetch_c_valid;

            fetch_request[lane] = '0;
            fetch_request[lane].data_a = pending_beat_q[lane].data;
            if (pending_need_b_q[lane]) begin
                fetch_request[lane].data_b = pending_b_valid_q[lane] ?
                    pending_b_data_q[lane] :
                    decoded_b_data[lane];
            end
            if (pending_need_c_q[lane]) begin
                fetch_request[lane].data_c = pending_c_valid_q[lane] ?
                    pending_c_data_q[lane] :
                    decoded_c_data[lane];
            end
            fetch_request[lane].scalar = pending_command_q[lane].scalar;
            fetch_request[lane].invalid_a = pending_beat_q[lane].invalid;
            fetch_request[lane].invalid_b = pending_need_b_q[lane] ?
                (pending_b_valid_q[lane] ? pending_b_invalid_q[lane] :
                 decoded_b_invalid[lane]) : '0;
            fetch_request[lane].invalid_c = pending_need_c_q[lane] ?
                (pending_c_valid_q[lane] ? pending_c_invalid_q[lane] :
                 decoded_c_invalid[lane]) : '0;
            fetch_request[lane].control =
                pending_command_q[lane].vector_control;
            fetch_request[lane].control.tag = pending_beat_q[lane].tag;
            fetch_request[lane].control.last = pending_beat_q[lane].last;
        end
    end

    // The request register is a fall-through skid stage: ready traffic bypasses
    // it, while a blocked engine receives an atomically retained A/B/C request.
    always_comb begin
        request_consume = '0;
        fetch_transfer = '0;
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            logic request_slot_available;

            request_consume[lane] = request_valid_q[lane] &&
                backend_request_ready[lane];
            request_slot_available = !request_valid_q[lane] ||
                request_consume[lane];
            fetch_transfer[lane] = fetch_complete[lane] &&
                request_slot_available;
        end
    end

    always_comb begin
        operand_b_read_enable_o = '0;
        operand_b_read_buffer_id_o = '0;
        operand_b_read_offset_o = '0;
        operand_c_read_enable_o = '0;
        operand_c_read_buffer_id_o = '0;
        operand_c_read_offset_o = '0;
        input_fire = '0;
        lane_fifo_output_ready = '0;

        for (integer lane = 0; lane < CHANNELS; lane++) begin
            logic current_slot_available;
            logic [CONTEXT_INDEX_WIDTH-1:0] input_index;
            logic input_context_match;
            logic next_need_b;
            logic next_need_c;
            logic [31:0] vector_offset;

            current_slot_available = !pending_valid_q[lane] ||
                fetch_transfer[lane];
            input_index = CONTEXT_INDEX_WIDTH'(
                lane_fifo_beat[lane].tag[3:0]
            );
            input_context_match =
                ({1'b0, lane_fifo_beat[lane].tag[3:0]} < 5'(CONTEXTS)) &&
                context_valid_q[input_index] &&
                (context_vector_command_mem[input_index].tag ==
                 lane_fifo_beat[lane].tag) &&
                (context_vector_command_mem[input_index].job_id ==
                 lane_fifo_beat[lane].job_id) &&
                (lane_fifo_command[lane].tag ==
                 lane_fifo_beat[lane].tag) &&
                (lane_fifo_command[lane].job_id ==
                 lane_fifo_beat[lane].job_id);
            lane_fifo_output_ready[lane] = !rst_i && !clear_i &&
                current_slot_available && input_context_match;
            input_fire[lane] = lane_fifo_output_valid[lane] &&
                lane_fifo_output_ready[lane];

            next_need_b = 1'b0;
            next_need_c = 1'b0;
            unique case (lane_fifo_command[lane].vector_control.operation)
                vector_pkg::VECTOR_ENGINE_OP_ADD,
                vector_pkg::VECTOR_ENGINE_OP_MUL,
                vector_pkg::VECTOR_ENGINE_OP_MIN,
                vector_pkg::VECTOR_ENGINE_OP_MAX: begin
                    next_need_b =
                        lane_fifo_command[lane].vector_control.operand_b_source ==
                        vector_pkg::VECTOR_SRC_VECTOR;
                end
                vector_pkg::VECTOR_ENGINE_OP_EPILOGUE: begin
                    next_need_b =
                        lane_fifo_command[lane].vector_control.bias_enable &&
                        !lane_fifo_command[lane].vector_control.bias_is_scalar;
                    next_need_c =
                        lane_fifo_command[lane].vector_control.residual_enable;
                end
                vector_pkg::VECTOR_ENGINE_OP_LAYERNORM,
                vector_pkg::VECTOR_ENGINE_OP_RMSNORM: begin
                    next_need_b =
                        lane_fifo_command[lane].vector_control.affine_enable;
                    next_need_c =
                        lane_fifo_command[lane].vector_control.beta_enable;
                end
                default: begin
                    next_need_b = 1'b0;
                    next_need_c = 1'b0;
                end
            endcase

            vector_offset = (32'(lane_fifo_beat[lane].row[3:0]) *
                             32'(lane_fifo_command[lane].vectors_per_row)) +
                            32'(lane_fifo_beat[lane].segment);
            operand_b_read_enable_o[lane] = input_fire[lane] && next_need_b;
            operand_b_read_buffer_id_o[
                lane*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH
            ] = lane_fifo_command[lane].operand_b_buffer_id;
            operand_b_read_offset_o[
                lane*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH
            ] = lane_fifo_command[lane].operand_b_base_offset +
                ((lane_fifo_command[lane].operand_b_format ==
                  mxfp_pkg::MXFP4_E2M1) ?
                 ((vector_offset >> 1) << 4) : (vector_offset << 4));
            operand_c_read_enable_o[lane] = input_fire[lane] && next_need_c;
            operand_c_read_buffer_id_o[
                lane*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH
            ] = lane_fifo_command[lane].operand_c_buffer_id;
            operand_c_read_offset_o[
                lane*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH +:
                npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH
            ] = lane_fifo_command[lane].operand_c_base_offset +
                ((lane_fifo_command[lane].operand_c_format ==
                  mxfp_pkg::MXFP4_E2M1) ?
                 ((vector_offset >> 1) << 4) : (vector_offset << 4));
        end
    end

    always_comb begin
        result_valid_o = '0;
        response_context_match = '0;

        for (integer lane = 0; lane < CHANNELS; lane++) begin
            npu_scheduler_pkg::npu_post_result_beat_t output_beat;
            npu_scheduler_pkg::npu_post_command_t output_command;
            logic [CONTEXT_INDEX_WIDTH-1:0] output_index;
            logic output_index_in_range;

            output_index = CONTEXT_INDEX_WIDTH'(
                backend_response_decoded[lane].control.tag[3:0]
            );
            output_index_in_range =
                ({1'b0, backend_response_decoded[lane].control.tag[3:0]} <
                 5'(CONTEXTS));
            response_context_match[lane] = output_index_in_range &&
                context_valid_q[output_index] &&
                (context_vector_command_mem[output_index].tag ==
                 backend_response_decoded[lane].control.tag) &&
                lane_started_q[output_index][lane];
            output_command = context_post_command_mem[output_index];
            // Per-beat controls (notably tail lane_mask and last) travel
            // through the Vector engine. The context copy may already have
            // advanced to a later input beat, so it cannot drive a stalled
            // output's control field.
            output_command.vector_control.lane_mask =
                backend_response_decoded[lane].control.lane_mask;
            output_command.vector_control.tag =
                backend_response_decoded[lane].control.tag;
            output_command.vector_control.last =
                backend_response_decoded[lane].control.last;
            output_command.vector_control.operation =
                backend_response_decoded[lane].control.operation;
            output_command.vector_control.operand_b_source =
                backend_response_decoded[lane].control.operand_b_source;
            output_command.vector_control.bias_enable =
                backend_response_decoded[lane].control.bias_enable;
            output_command.vector_control.bias_is_scalar =
                backend_response_decoded[lane].control.bias_is_scalar;
            output_command.vector_control.residual_enable =
                backend_response_decoded[lane].control.residual_enable;
            output_command.vector_control.activation =
                backend_response_decoded[lane].control.activation;
            output_command.vector_control.output_format =
                backend_response_decoded[lane].control.output_format;
            output_command.vector_control.mx_format =
                backend_response_decoded[lane].control.mx_format;
            output_command.vector_control.affine_enable =
                backend_response_decoded[lane].control.affine_enable;
            output_command.vector_control.beta_enable =
                backend_response_decoded[lane].control.beta_enable;

            output_beat = '0;
            unique case (backend_response_decoded[lane].control.result_kind)
                vector_pkg::VECTOR_ENGINE_RESULT_MX_VECTOR: begin
                    output_beat.data[127:0] =
                        backend_response_decoded[lane].mx_vector;
                    output_beat.payload_kind =
                        npu_scheduler_pkg::NPU_PAYLOAD_MX_VECTOR;
                    output_beat.mx_format =
                        backend_response_decoded[lane].control.mx_format;
                    output_beat.mx_scale =
                        backend_response_decoded[lane].mx_scale;
                end
                vector_pkg::VECTOR_ENGINE_RESULT_FP32_SCALAR: begin
                    output_beat.data[31:0] =
                        backend_response_decoded[lane].fp32_scalar;
                    output_beat.payload_kind =
                        npu_scheduler_pkg::NPU_PAYLOAD_FP32_SCALAR;
                end
                default: begin
                    output_beat.data =
                        backend_response_decoded[lane].fp32_vector;
                    output_beat.payload_kind =
                        npu_scheduler_pkg::NPU_PAYLOAD_FP32_VECTOR;
                end
            endcase
            output_beat.invalid = backend_response_decoded[lane].invalid;
            output_beat.job_id = output_command.job_id;
            output_beat.tag = backend_response_decoded[lane].control.tag;
            output_beat.row = response_row_q[output_index][lane];
            output_beat.segment = response_segment_q[output_index][lane];
            output_beat.last = backend_response_decoded[lane].control.last;

            result_valid_o[lane] = backend_response_valid[lane] &&
                response_context_match[lane];
            result_o[
                lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
            ] = output_beat;
            result_command_o[
                lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH
            ] = output_command;
        end
    end

    // Ready is deliberately isolated from payload/command generation. This
    // keeps the downstream ready path from appearing to feed the route field
    // that selects that same path in the system-level result router.
    always_comb begin
        logic completion_slot_available;

        backend_response_ready = '0;
        response_fire = '0;
        completion_slot_available = !completion_valid_q ||
            completion_ready_i;
        for (integer lane = 0; lane < CHANNELS; lane++) begin
            backend_response_ready[lane] = result_ready_i[lane] &&
                response_context_match[lane] &&
                (!backend_response_decoded[lane].control.last ||
                 completion_slot_available);
            response_fire[lane] = backend_response_valid[lane] &&
                backend_response_ready[lane];
        end

        completion_valid_o = completion_valid_q;
        completion_tag_o = completion_tag_q;
        completion_success_o = completion_success_q;
        completion_feedback_o = completion_feedback_q;
        busy_o = (|context_valid_q) || (|pending_valid_q) ||
            (|request_valid_q) || completion_valid_q ||
            (|backend_response_valid);
    end

    always_comb begin
        response_context_increment = '0;
        response_context_last_fire = '0;
        response_context_complete = '0;
        for (integer context_index = 0; context_index < CONTEXTS;
             context_index++) begin
            for (integer lane = 0; lane < CHANNELS; lane++) begin
                if (response_fire[lane] &&
                    (backend_response_decoded[lane].control.tag[3:0] ==
                     4'(context_index))) begin
                    response_context_increment[context_index*6 +: 6] =
                        response_context_increment[context_index*6 +: 6] +
                        6'd1;
                    if (backend_response_decoded[lane].control.last) begin
                        response_context_last_fire[context_index] = 1'b1;
                    end
                end
            end
            response_context_complete[context_index] =
                context_valid_q[context_index] &&
                (response_context_increment[context_index*6 +: 6] != 6'd0) &&
                ((context_response_count_q[context_index] +
                  21'(response_context_increment[
                      context_index*6 +: 6
                  ])) == context_expected_count_mem[context_index]);
        end
        response_completion_count = 6'($countones(response_context_complete));
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            context_valid_q <= '0;
            context_last_seen_q <= '0;
            pending_valid_q <= '0;
            pending_need_b_q <= '0;
            pending_need_c_q <= '0;
            pending_b_valid_q <= '0;
            pending_c_valid_q <= '0;
            request_valid_q <= '0;
            completion_valid_q <= 1'b0;
            completion_tag_q <= '0;
            completion_success_q <= 1'b0;
            completion_feedback_q <= 1'b0;
            protocol_error_o <= 1'b0;
            for (integer context_index = 0; context_index < CONTEXTS;
                 context_index++) begin
                context_vector_command_mem[context_index] <= '0;
                context_post_command_mem[context_index] <= '0;
                context_expected_count_mem[context_index] <= '0;
                context_response_count_q[context_index] <= '0;
                for (integer lane = 0; lane < CHANNELS; lane++) begin
                    lane_started_q[context_index][lane] <= 1'b0;
                    response_row_q[context_index][lane] <= '0;
                    response_segment_q[context_index][lane] <= '0;
                end
            end
            for (integer lane = 0; lane < CHANNELS; lane++) begin
                pending_beat_q[lane] <= '0;
                pending_command_q[lane] <= '0;
                pending_b_data_q[lane] <= '0;
                pending_c_data_q[lane] <= '0;
                pending_b_invalid_q[lane] <= '0;
                pending_c_invalid_q[lane] <= '0;
                request_q[lane] <= '0;
            end
        end else begin
            if (completion_valid_q && completion_ready_i) begin
                context_valid_q[
                    CONTEXT_INDEX_WIDTH'(completion_tag_q[3:0])
                ] <= 1'b0;
                context_last_seen_q[
                    CONTEXT_INDEX_WIDTH'(completion_tag_q[3:0])
                ] <= 1'b0;
                for (integer lane = 0; lane < CHANNELS; lane++) begin
                    lane_started_q[
                        CONTEXT_INDEX_WIDTH'(completion_tag_q[3:0])
                    ][lane] <= 1'b0;
                end
                completion_valid_q <= 1'b0;
                completion_feedback_q <= 1'b0;
            end

            if (command_fire) begin
                context_valid_q[command_index] <= 1'b1;
                context_vector_command_mem[command_index] <= command_input;
                context_expected_count_mem[command_index] <=
                    command_input.matrix_size * command_input.vectors_per_row;
                context_response_count_q[command_index] <= '0;
                context_last_seen_q[command_index] <= 1'b0;
            end

            if (vector_command_valid_i && !command_index_in_range) begin
                protocol_error_o <= 1'b1;
            end
            if (response_completion_count > 6'd1) begin
                protocol_error_o <= 1'b1;
            end

            for (integer context_index = 0; context_index < CONTEXTS;
                 context_index++) begin
                if (response_context_increment[
                    context_index*6 +: 6
                ] != 6'd0) begin
                    context_response_count_q[context_index] <=
                        context_response_count_q[context_index] +
                        21'(response_context_increment[
                            context_index*6 +: 6
                        ]);
                    if (response_context_last_fire[context_index]) begin
                        if (context_last_seen_q[context_index]) begin
                            protocol_error_o <= 1'b1;
                        end
                        context_last_seen_q[context_index] <= 1'b1;
                    end
                    if ((context_response_count_q[context_index] +
                         21'(response_context_increment[
                             context_index*6 +: 6
                         ])) > context_expected_count_mem[context_index]) begin
                        protocol_error_o <= 1'b1;
                    end
                    if (response_context_complete[context_index]) begin
                        completion_valid_q <= 1'b1;
                        completion_tag_q <=
                            context_vector_command_mem[context_index].tag;
                        completion_success_q <=
                            context_last_seen_q[context_index] ||
                            response_context_last_fire[context_index];
                        completion_feedback_q <=
                            context_post_command_mem[context_index].
                                vector_result_route ==
                            npu_scheduler_pkg::NPU_VECTOR_TO_FEEDBACK;
                        if (!(context_last_seen_q[context_index] ||
                              response_context_last_fire[context_index])) begin
                            protocol_error_o <= 1'b1;
                        end
                    end
                end
            end

            for (integer lane = 0; lane < CHANNELS; lane++) begin
                logic [CONTEXT_INDEX_WIDTH-1:0] input_index;
                logic next_need_b;
                logic next_need_c;

                input_index = CONTEXT_INDEX_WIDTH'(
                    lane_fifo_beat[lane].tag[3:0]
                );
                next_need_b = 1'b0;
                next_need_c = 1'b0;
                unique case (lane_fifo_command[lane].vector_control.operation)
                    vector_pkg::VECTOR_ENGINE_OP_ADD,
                    vector_pkg::VECTOR_ENGINE_OP_MUL,
                    vector_pkg::VECTOR_ENGINE_OP_MIN,
                    vector_pkg::VECTOR_ENGINE_OP_MAX: begin
                        next_need_b =
                            lane_fifo_command[lane].vector_control.
                                operand_b_source ==
                            vector_pkg::VECTOR_SRC_VECTOR;
                    end
                    vector_pkg::VECTOR_ENGINE_OP_EPILOGUE: begin
                        next_need_b =
                            lane_fifo_command[lane].vector_control.bias_enable &&
                            !lane_fifo_command[lane].vector_control.
                                bias_is_scalar;
                        next_need_c =
                            lane_fifo_command[lane].vector_control.
                                residual_enable;
                    end
                    vector_pkg::VECTOR_ENGINE_OP_LAYERNORM,
                    vector_pkg::VECTOR_ENGINE_OP_RMSNORM: begin
                        next_need_b =
                            lane_fifo_command[lane].vector_control.affine_enable;
                        next_need_c =
                            lane_fifo_command[lane].vector_control.beta_enable;
                    end
                    default: begin
                        next_need_b = 1'b0;
                        next_need_c = 1'b0;
                    end
                endcase

                if (fetch_transfer[lane]) begin
                    if (request_valid_q[lane] ||
                        !backend_request_ready[lane]) begin
                        request_valid_q[lane] <= 1'b1;
                        request_q[lane] <= fetch_request[lane];
                    end else begin
                        request_valid_q[lane] <= 1'b0;
                    end
                end else if (request_consume[lane]) begin
                    request_valid_q[lane] <= 1'b0;
                end

                if (fetch_transfer[lane] && !input_fire[lane]) begin
                    pending_valid_q[lane] <= 1'b0;
                    pending_b_valid_q[lane] <= 1'b0;
                    pending_c_valid_q[lane] <= 1'b0;
                end
                if (input_fire[lane]) begin
                    pending_valid_q[lane] <= 1'b1;
                    pending_need_b_q[lane] <= next_need_b;
                    pending_need_c_q[lane] <= next_need_c;
                    pending_b_valid_q[lane] <= 1'b0;
                    pending_c_valid_q[lane] <= 1'b0;
                    pending_beat_q[lane] <= lane_fifo_beat[lane];
                    pending_command_q[lane] <= lane_fifo_command[lane];
                    context_post_command_mem[input_index] <=
                        lane_fifo_command[lane];
                    if (!lane_started_q[input_index][lane]) begin
                        lane_started_q[input_index][lane] <= 1'b1;
                        response_row_q[input_index][lane] <=
                            lane_fifo_beat[lane].row;
                        response_segment_q[input_index][lane] <=
                            lane_fifo_beat[lane].segment;
                    end
                end else begin
                    if (operand_b_read_valid_i[lane] &&
                        pending_valid_q[lane] &&
                        pending_need_b_q[lane]) begin
                        pending_b_valid_q[lane] <= 1'b1;
                        pending_b_data_q[lane] <=
                            decoded_b_data[lane];
                        pending_b_invalid_q[lane] <=
                            decoded_b_invalid[lane];
                    end
                    if (operand_c_read_valid_i[lane] &&
                        pending_valid_q[lane] &&
                        pending_need_c_q[lane]) begin
                        pending_c_valid_q[lane] <= 1'b1;
                        pending_c_data_q[lane] <=
                            decoded_c_data[lane];
                        pending_c_invalid_q[lane] <=
                            decoded_c_invalid[lane];
                    end
                end

                if (backend_response_valid[lane]) begin
                    logic [CONTEXT_INDEX_WIDTH-1:0] output_index;
                    output_index = CONTEXT_INDEX_WIDTH'(
                        backend_response_decoded[lane].control.tag[3:0]
                    );
                    if (!context_valid_q[output_index] ||
                        (context_vector_command_mem[output_index].tag !=
                         backend_response_decoded[lane].control.tag)) begin
                        protocol_error_o <= 1'b1;
                    end
                    if (response_fire[lane]) begin
                        if ((response_segment_q[output_index][lane] + 5'd1) ==
                            context_vector_command_mem[
                                output_index
                            ].vectors_per_row) begin
                            response_segment_q[output_index][lane] <= '0;
                            response_row_q[output_index][lane] <=
                                response_row_q[output_index][lane] + 1'b1;
                        end else begin
                            response_segment_q[output_index][lane] <=
                                response_segment_q[output_index][lane] + 1'b1;
                        end
                    end
                end
            end

        end
    end

    generate
        for (genvar lane = 0; lane < CHANNELS; lane++) begin : g_lane_input_fifo
            npu_scheduler_fifo #(
                .WIDTH(LANE_INPUT_WIDTH),
                .DEPTH(FIFO_DEPTH),
                // Keep the full-credit boundary registered. This prevents a
                // response-ready path from crossing the vector engine and
                // returning combinationally to this ingress. At every
                // non-full operating point the FIFO still accepts one beat
                // per cycle, so steady-state peak throughput is unchanged.
                .ALLOW_FULL_POP(1'b0)
            ) u_input_fifo (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .clear_i(clear_i),
                .input_valid_i(lane_fifo_input_valid[lane]),
                .input_ready_o(lane_fifo_input_ready[lane]),
                .input_data_i(lane_fifo_input_data[
                    lane*LANE_INPUT_WIDTH +: LANE_INPUT_WIDTH
                ]),
                .output_valid_o(lane_fifo_output_valid[lane]),
                .output_ready_i(lane_fifo_output_ready[lane]),
                .output_data_o(lane_fifo_output_data[
                    lane*LANE_INPUT_WIDTH +: LANE_INPUT_WIDTH
                ]),
                .level_o(lane_fifo_level_unused[
                    lane*$clog2(FIFO_DEPTH+1) +: $clog2(FIFO_DEPTH+1)
                ])
            );
        end
    endgenerate

    generate
        for (genvar group_index = 0; group_index < ENGINE_GROUP_COUNT;
             group_index++) begin : g_engine_group
            localparam int unsigned GROUP_BASE =
                group_index * ENGINE_GROUP_SIZE;
            localparam int unsigned GROUP_CHANNELS =
                ((GROUP_BASE + ENGINE_GROUP_SIZE) <= CHANNELS) ?
                    ENGINE_GROUP_SIZE : (CHANNELS - GROUP_BASE);

            npu_vector_engine_group #(
                .CHANNELS(GROUP_CHANNELS),
                .FTZ(FTZ)
            ) u_group (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .clear_i(clear_i),
                .request_valid_i(backend_request_valid[
                    GROUP_BASE +: GROUP_CHANNELS
                ]),
                .request_ready_o(backend_request_ready[
                    GROUP_BASE +: GROUP_CHANNELS
                ]),
                .request_i(backend_request[
                    GROUP_BASE*vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH +:
                    GROUP_CHANNELS*vector_pkg::VECTOR_ENGINE_REQUEST_WIDTH
                ]),
                .response_valid_o(backend_response_valid[
                    GROUP_BASE +: GROUP_CHANNELS
                ]),
                .response_ready_i(backend_response_ready[
                    GROUP_BASE +: GROUP_CHANNELS
                ]),
                .response_o(backend_response[
                    GROUP_BASE*vector_pkg::VECTOR_ENGINE_RESULT_WIDTH +:
                    GROUP_CHANNELS*vector_pkg::VECTOR_ENGINE_RESULT_WIDTH
                ])
            );
        end
    endgenerate

    initial begin
        assert ((CHANNELS > 0) && (CHANNELS <= 16))
            else $error("npu_gemm_vector_coupler16 CHANNELS must be in 1..16");
        assert ((CONTEXTS > 0) && (CONTEXTS <= 16))
            else $error("npu_gemm_vector_coupler16 CONTEXTS must be in 1..16");
    end

    wire _unused_backend_response_observation =
        &{1'b0, backend_response_observation};

endmodule

`default_nettype wire
