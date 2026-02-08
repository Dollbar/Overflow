`timescale 1ns/1ps
`default_nettype none

// Production boundary at the local input buffers. External logic writes
// descriptors and Tile-packed tensors; descriptor-selected consumers accept
// independent physical-row streams carrying 512-bit FP32 result vectors.
// GEMM feedback is block-quantized back into the Activation Buffer without
// changing the activation row/segment layout;
// the feedback outputs remain transaction monitors for integration debug.
module npu_square_gemm_system #(
    parameter int unsigned ARRAY_DIM = 16,
    parameter int unsigned BUFFER_COUNT = 4,
    parameter int unsigned DESCRIPTOR_ENTRIES = 16,
    // 4 logical buffer IDs x 16 banks x 8192 vectors x 16 bytes = 8 MiB
    // for each data store (tensor A, tensor B/vector B, and vector C).
    parameter int unsigned TENSOR_VECTOR_DEPTH = 8192,
    parameter int unsigned TASK_SLOTS = 8,
    parameter int unsigned ACTIVE_CONTEXTS = 16,
    parameter int unsigned COMMAND_FIFO_DEPTH = 4,
    parameter int unsigned DESCRIPTOR_INDEX_WIDTH =
        (DESCRIPTOR_ENTRIES <= 1) ? 1 : $clog2(DESCRIPTOR_ENTRIES),
    parameter int unsigned BANK_INDEX_WIDTH =
        (ARRAY_DIM <= 1) ? 1 : $clog2(ARRAY_DIM)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic descriptor_write_valid_i,
    output logic descriptor_write_ready_o,
    input  logic [DESCRIPTOR_INDEX_WIDTH-1:0] descriptor_write_index_i,
    input  logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0]
                 descriptor_write_data_i,
    input  logic descriptor_submit_valid_i,
    output logic descriptor_submit_ready_o,
    input  logic [DESCRIPTOR_INDEX_WIDTH-1:0] descriptor_submit_index_i,

    input  logic tensor_write_valid_i,
    output logic tensor_write_ready_o,
    input  logic tensor_write_weight_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 tensor_write_buffer_id_i,
    input  logic [BANK_INDEX_WIDTH-1:0] tensor_write_bank_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 tensor_write_offset_i,
    input  logic [127:0] tensor_write_data_i,
    input  logic [127:0] tensor_write_scale_i,

    input  logic vector_operand_write_valid_i,
    output logic vector_operand_write_ready_o,
    input  logic vector_operand_write_c_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 vector_operand_write_buffer_id_i,
    input  logic [BANK_INDEX_WIDTH-1:0] vector_operand_write_bank_i,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 vector_operand_write_offset_i,
    input  logic [127:0] vector_operand_write_data_i,
    input  logic [7:0] vector_operand_write_scale_i,

    output logic [ARRAY_DIM-1:0] gemm_output_valid_o,
    input  logic [ARRAY_DIM-1:0] gemm_output_ready_i,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_output_result_o,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_output_command_o,

    output logic [ARRAY_DIM-1:0] gemm_vector_valid_o,
    input  logic [ARRAY_DIM-1:0] gemm_vector_ready_i,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_vector_result_o,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_vector_command_o,
    output logic [ARRAY_DIM-1:0] gemm_feedback_valid_o,
    input  logic [ARRAY_DIM-1:0] gemm_feedback_ready_i,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_feedback_result_o,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 gemm_feedback_command_o,

    input  logic event_set_valid_i,
    input  logic [npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0] event_set_id_i,
    input  logic event_clear_valid_i,
    input  logic [npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0] event_clear_id_i,

    output logic status_valid_o,
    input  logic status_ready_i,
    output logic [npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH-1:0] status_o,
    output logic busy_o,
    output logic protocol_error_o
);

    localparam int unsigned NODE_COUNT = ARRAY_DIM * ARRAY_DIM;

    logic task_valid;
    logic task_ready;
    logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_data;
    logic descriptor_protocol_error;

    logic gemm_command_valid;
    logic gemm_command_ready;
    logic [npu_scheduler_pkg::NPU_GEMM_COMMAND_WIDTH-1:0] gemm_command;
    logic activation_command_valid;
    logic activation_command_ready;
    logic [npu_scheduler_pkg::NPU_BUFFER_READ_COMMAND_WIDTH-1:0]
        activation_command;
    logic weight_command_valid;
    logic weight_command_ready;
    logic [npu_scheduler_pkg::NPU_BUFFER_READ_COMMAND_WIDTH-1:0]
        weight_command;
    logic vector_command_valid;
    logic vector_command_ready;
    logic [npu_scheduler_pkg::NPU_VECTOR_COMMAND_WIDTH-1:0] vector_command;
    logic result_command_valid;
    logic result_command_ready;
    logic [npu_scheduler_pkg::NPU_RESULT_COMMAND_WIDTH-1:0] result_command;
    logic post_command_valid;
    logic post_command_ready;
    logic [npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0] post_command;
    logic scheduler_protocol_error;
    logic [$clog2(TASK_SLOTS+1)-1:0] task_level;
    logic [$clog2(ACTIVE_CONTEXTS+1)-1:0] active_contexts;

    logic completion_valid;
    logic completion_ready;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag;
    logic completion_success;
    logic executor_completion_valid;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] executor_completion_tag;
    logic executor_completion_success;
    logic [ARRAY_DIM-1:0] raw_vector_result_valid;
    logic [ARRAY_DIM-1:0] raw_vector_result_ready;
    logic [ARRAY_DIM*512-1:0] raw_vector_result_data;
    logic [ARRAY_DIM*16-1:0] raw_vector_result_invalid;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        raw_vector_result_job_id;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
        raw_vector_result_tag;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_DIMENSION_WIDTH-1:0]
        raw_vector_result_row;
    logic [ARRAY_DIM*5-1:0] raw_vector_result_segment;
    logic [ARRAY_DIM-1:0] raw_vector_result_last;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
        raw_post_result;
    logic post_busy;
    logic post_protocol_error;
    logic [ARRAY_DIM-1:0] post_external_valid;
    logic [ARRAY_DIM-1:0] post_external_ready;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
        post_external_result;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
        post_external_command;
    logic [ARRAY_DIM-1:0] external_fifo_valid;
    logic [ARRAY_DIM-1:0] external_fifo_ready;
    logic [ARRAY_DIM*(npu_scheduler_pkg::NPU_POST_RESULT_WIDTH+
                      npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH)-1:0]
        external_fifo_data;
    logic external_completion_valid;
    logic external_completion_ready;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] external_completion_tag;
    logic external_completion_success;
    logic external_formatter_busy;
    logic external_formatter_protocol_error;

    logic [ARRAY_DIM-1:0] post_vector_valid;
    logic [ARRAY_DIM-1:0] post_vector_ready;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
        post_vector_result;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
        post_vector_command;
    logic vector_completion_valid;
    logic vector_completion_ready;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] vector_completion_tag;
    logic vector_completion_success;
    logic vector_completion_feedback;
    logic vector_backend_busy;
    logic vector_backend_protocol_error;
    logic vector_operand_protocol_error;
    logic [ARRAY_DIM-1:0] vector_operand_b_read_enable;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        vector_operand_b_read_buffer_id;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        vector_operand_b_read_offset;
    logic [ARRAY_DIM-1:0] vector_operand_b_read_valid;
    logic [ARRAY_DIM*128-1:0] vector_operand_b_read_data;
    logic [ARRAY_DIM*8-1:0] vector_operand_b_read_scale;
    logic [ARRAY_DIM-1:0] vector_operand_c_read_enable;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        vector_operand_c_read_buffer_id;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        vector_operand_c_read_offset;
    logic [ARRAY_DIM-1:0] vector_operand_c_read_valid;
    logic [ARRAY_DIM*128-1:0] vector_operand_c_read_data;
    logic [ARRAY_DIM*8-1:0] vector_operand_c_read_scale;
    logic [ARRAY_DIM-1:0] post_feedback_valid;
    logic [ARRAY_DIM-1:0] post_feedback_ready;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
        post_feedback_result;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
        post_feedback_command;
    logic [ARRAY_DIM-1:0] vector_feedback_valid;
    logic [ARRAY_DIM-1:0] vector_feedback_ready;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
        vector_feedback_result;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
        vector_feedback_command;
    logic [ARRAY_DIM-1:0] feedback_writer_valid;
    logic [ARRAY_DIM-1:0] feedback_writer_ready;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
        feedback_writer_result;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
        feedback_writer_command;
    logic select_direct_feedback;
    logic [ARRAY_DIM-1:0] vector_backend_result_valid;
    logic [ARRAY_DIM-1:0] vector_backend_result_ready;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
        vector_backend_result;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
        vector_backend_command;
    logic [ARRAY_DIM-1:0] feedback_activation_write_valid;
    logic [ARRAY_DIM-1:0] feedback_activation_write_ready;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        feedback_activation_write_buffer_id;
    logic [ARRAY_DIM*npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        feedback_activation_write_offset;
    logic [ARRAY_DIM*128-1:0] feedback_activation_write_data;
    logic [ARRAY_DIM*8-1:0] feedback_activation_write_scale;
    logic feedback_completion_valid;
    logic feedback_completion_ready;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] feedback_completion_tag;
    logic feedback_completion_success;
    logic feedback_busy;
    logic feedback_protocol_error;

    generate
        for (genvar result_lane = 0; result_lane < ARRAY_DIM;
             result_lane++) begin : g_raw_post_result
            assign raw_post_result[
                result_lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
            ] = {
                raw_vector_result_data[result_lane*512 +: 512],
                npu_scheduler_pkg::NPU_PAYLOAD_FP32_VECTOR,
                mxfp_pkg::MXFP8_E4M3,
                mxfp_pkg::mxfp_scale_t'(0),
                raw_vector_result_invalid[result_lane*16 +: 16],
                raw_vector_result_job_id[
                    result_lane*npu_scheduler_pkg::NPU_JOB_ID_WIDTH +:
                    npu_scheduler_pkg::NPU_JOB_ID_WIDTH
                ],
                raw_vector_result_tag[
                    result_lane*npu_scheduler_pkg::NPU_TAG_WIDTH +:
                    npu_scheduler_pkg::NPU_TAG_WIDTH
                ],
                raw_vector_result_row[
                    result_lane*npu_scheduler_pkg::NPU_DIMENSION_WIDTH +:
                    npu_scheduler_pkg::NPU_DIMENSION_WIDTH
                ],
                raw_vector_result_segment[result_lane*5 +: 5],
                raw_vector_result_last[result_lane]
            };
        end
    endgenerate

    logic activation_read_enable;
    logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        activation_read_buffer_id;
    logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        activation_read_offset;
    logic activation_read_valid;
    logic [ARRAY_DIM*128-1:0] activation_read_data;
    logic [ARRAY_DIM*128-1:0] activation_read_scale;
    logic weight_read_enable;
    logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        weight_read_buffer_id;
    logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        weight_read_offset;
    logic weight_read_valid;
    logic [ARRAY_DIM*128-1:0] weight_read_data;
    logic [ARRAY_DIM*128-1:0] weight_read_scale;
    logic tensor_protocol_error;

    logic [ARRAY_DIM*16-1:0] wave_a_valid;
    logic [ARRAY_DIM*128-1:0] wave_a_data;
    logic [ARRAY_DIM*32-1:0] wave_a_format;
    logic [ARRAY_DIM*128-1:0] wave_a_scale;
    logic [ARRAY_DIM*16-1:0] wave_a_block_first;
    logic [ARRAY_DIM*16-1:0] wave_a_block_last;
    logic [ARRAY_DIM*16-1:0] wave_a_matrix_first;
    logic [ARRAY_DIM*16-1:0] wave_a_matrix_last;
    logic [ARRAY_DIM*128-1:0] wave_a_tag;
    logic [ARRAY_DIM*16-1:0] wave_b_valid;
    logic [ARRAY_DIM*128-1:0] wave_b_data;
    logic [ARRAY_DIM*32-1:0] wave_b_format;
    logic [ARRAY_DIM*128-1:0] wave_b_scale;

    logic [NODE_COUNT-1:0] gemm_result_ready;
    logic [NODE_COUNT-1:0] gemm_result_valid;
    logic [NODE_COUNT*512-1:0] gemm_result_data;
    logic [NODE_COUNT*16-1:0] gemm_result_invalid;
    logic [NODE_COUNT*8-1:0] gemm_result_tag;
    logic [NODE_COUNT*4-1:0] gemm_result_row;
    logic [NODE_COUNT*6-1:0] gemm_result_level;
    logic executor_busy;
    logic executor_protocol_error;

    logic [NODE_COUNT-1:0] input_pair_issue;
    logic [NODE_COUNT-1:0] output_overflow;

    npu_descriptor_buffer #(
        .ENTRY_COUNT(DESCRIPTOR_ENTRIES),
        .INDEX_WIDTH(DESCRIPTOR_INDEX_WIDTH)
    ) u_descriptor_buffer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .write_valid_i(descriptor_write_valid_i),
        .write_ready_o(descriptor_write_ready_o),
        .write_index_i(descriptor_write_index_i),
        .write_descriptor_i(descriptor_write_data_i),
        .submit_valid_i(descriptor_submit_valid_i),
        .submit_ready_o(descriptor_submit_ready_o),
        .submit_index_i(descriptor_submit_index_i),
        .task_valid_o(task_valid),
        .task_ready_i(task_ready),
        .task_o(task_data),
        .protocol_error_o(descriptor_protocol_error)
    );

    npu_input_scheduler #(
        .TASK_SLOTS(TASK_SLOTS),
        .ACTIVE_CONTEXTS(ACTIVE_CONTEXTS),
        .COMMAND_FIFO_DEPTH(COMMAND_FIFO_DEPTH),
        .ARRAY_DIM(ARRAY_DIM)
    ) u_scheduler (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .task_valid_i(task_valid),
        .task_ready_o(task_ready),
        .task_i(task_data),
        .completion_valid_i(completion_valid),
        .completion_ready_o(completion_ready),
        .completion_tag_i(completion_tag),
        .completion_success_i(completion_success),
        .event_set_valid_i(event_set_valid_i),
        .event_set_id_i(event_set_id_i),
        .event_clear_valid_i(event_clear_valid_i),
        .event_clear_id_i(event_clear_id_i),
        .gemm_command_valid_o(gemm_command_valid),
        .gemm_command_ready_i(gemm_command_ready),
        .gemm_command_o(gemm_command),
        .activation_command_valid_o(activation_command_valid),
        .activation_command_ready_i(activation_command_ready),
        .activation_command_o(activation_command),
        .weight_command_valid_o(weight_command_valid),
        .weight_command_ready_i(weight_command_ready),
        .weight_command_o(weight_command),
        .vector_command_valid_o(vector_command_valid),
        .vector_command_ready_i(vector_command_ready),
        .vector_command_o(vector_command),
        .result_command_valid_o(result_command_valid),
        .result_command_ready_i(result_command_ready),
        .result_command_o(result_command),
        .post_command_valid_o(post_command_valid),
        .post_command_ready_i(post_command_ready),
        .post_command_o(post_command),
        .status_valid_o(status_valid_o),
        .status_ready_i(status_ready_i),
        .status_o(status_o),
        .task_level_o(task_level),
        .active_contexts_o(active_contexts),
        .protocol_error_o(scheduler_protocol_error)
    );

    npu_local_vector_operand_buffer #(
        .BUFFER_COUNT(BUFFER_COUNT),
        .BANKS(ARRAY_DIM),
        .VECTOR_DEPTH(TENSOR_VECTOR_DEPTH),
        .BANK_INDEX_WIDTH(BANK_INDEX_WIDTH)
    ) u_vector_operand_buffer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .write_valid_i(vector_operand_write_valid_i),
        .write_ready_o(vector_operand_write_ready_o),
        .write_operand_c_i(vector_operand_write_c_i),
        .write_buffer_id_i(vector_operand_write_buffer_id_i),
        .write_bank_i(vector_operand_write_bank_i),
        .write_offset_i(vector_operand_write_offset_i),
        .write_data_i(vector_operand_write_data_i),
        .write_scale_i(vector_operand_write_scale_i),
        .read_b_enable_i(vector_operand_b_read_enable),
        .read_b_buffer_id_i(vector_operand_b_read_buffer_id),
        .read_b_offset_i(vector_operand_b_read_offset),
        .read_b_valid_o(vector_operand_b_read_valid),
        .read_b_data_o(vector_operand_b_read_data),
        .read_b_scale_o(vector_operand_b_read_scale),
        .read_c_enable_i(vector_operand_c_read_enable),
        .read_c_buffer_id_i(vector_operand_c_read_buffer_id),
        .read_c_offset_i(vector_operand_c_read_offset),
        .read_c_valid_o(vector_operand_c_read_valid),
        .read_c_data_o(vector_operand_c_read_data),
        .read_c_scale_o(vector_operand_c_read_scale),
        .protocol_error_o(vector_operand_protocol_error)
    );

    npu_local_tensor_buffer #(
        .BUFFER_COUNT(BUFFER_COUNT),
        .BANKS(ARRAY_DIM),
        .VECTOR_DEPTH(TENSOR_VECTOR_DEPTH)
    ) u_tensor_buffer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .tensor_write_valid_i(tensor_write_valid_i),
        .tensor_write_ready_o(tensor_write_ready_o),
        .tensor_write_weight_i(tensor_write_weight_i),
        .tensor_write_buffer_id_i(tensor_write_buffer_id_i),
        .tensor_write_bank_i(tensor_write_bank_i),
        .tensor_write_offset_i(tensor_write_offset_i),
        .tensor_write_data_i(tensor_write_data_i),
        .tensor_write_scale_i(tensor_write_scale_i),
        .feedback_write_valid_i(feedback_activation_write_valid),
        .feedback_write_ready_o(feedback_activation_write_ready),
        .feedback_write_buffer_id_i(feedback_activation_write_buffer_id),
        .feedback_write_offset_i(feedback_activation_write_offset),
        .feedback_write_data_i(feedback_activation_write_data),
        .feedback_write_scale_i(feedback_activation_write_scale),
        .activation_read_enable_i(activation_read_enable),
        .activation_read_buffer_id_i(activation_read_buffer_id),
        .activation_read_offset_i(activation_read_offset),
        .activation_read_valid_o(activation_read_valid),
        .activation_read_data_o(activation_read_data),
        .activation_read_scale_o(activation_read_scale),
        .weight_read_enable_i(weight_read_enable),
        .weight_read_buffer_id_i(weight_read_buffer_id),
        .weight_read_offset_i(weight_read_offset),
        .weight_read_valid_o(weight_read_valid),
        .weight_read_data_o(weight_read_data),
        .weight_read_scale_o(weight_read_scale),
        .protocol_error_o(tensor_protocol_error)
    );

    npu_square_gemm_executor #(
        .ARRAY_DIM(ARRAY_DIM)
    ) u_executor (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .gemm_command_valid_i(gemm_command_valid),
        .gemm_command_ready_o(gemm_command_ready),
        .gemm_command_i(gemm_command),
        .activation_command_valid_i(activation_command_valid),
        .activation_command_ready_o(activation_command_ready),
        .activation_command_i(activation_command),
        .weight_command_valid_i(weight_command_valid),
        .weight_command_ready_o(weight_command_ready),
        .weight_command_i(weight_command),
        .result_command_valid_i(result_command_valid),
        .result_command_ready_o(result_command_ready),
        .result_command_i(result_command),
        .activation_read_enable_o(activation_read_enable),
        .activation_read_buffer_id_o(activation_read_buffer_id),
        .activation_read_offset_o(activation_read_offset),
        .activation_read_valid_i(activation_read_valid),
        .activation_read_data_i(activation_read_data),
        .activation_read_scale_i(activation_read_scale),
        .weight_read_enable_o(weight_read_enable),
        .weight_read_buffer_id_o(weight_read_buffer_id),
        .weight_read_offset_o(weight_read_offset),
        .weight_read_valid_i(weight_read_valid),
        .weight_read_data_i(weight_read_data),
        .weight_read_scale_i(weight_read_scale),
        .wave_a_valid_o(wave_a_valid),
        .wave_a_data_o(wave_a_data),
        .wave_a_format_o(wave_a_format),
        .wave_a_scale_o(wave_a_scale),
        .wave_a_block_first_o(wave_a_block_first),
        .wave_a_block_last_o(wave_a_block_last),
        .wave_a_matrix_first_o(wave_a_matrix_first),
        .wave_a_matrix_last_o(wave_a_matrix_last),
        .wave_a_tag_o(wave_a_tag),
        .wave_b_valid_o(wave_b_valid),
        .wave_b_data_o(wave_b_data),
        .wave_b_format_o(wave_b_format),
        .wave_b_scale_o(wave_b_scale),
        .result_ready_o(gemm_result_ready),
        .result_valid_i(gemm_result_valid),
        .result_data_i(gemm_result_data),
        .result_invalid_i(gemm_result_invalid),
        .result_tag_i(gemm_result_tag),
        .result_row_i(gemm_result_row),
        .vector_result_valid_o(raw_vector_result_valid),
        .vector_result_ready_i(raw_vector_result_ready),
        .vector_result_data_o(raw_vector_result_data),
        .vector_result_invalid_o(raw_vector_result_invalid),
        .vector_result_job_id_o(raw_vector_result_job_id),
        .vector_result_tag_o(raw_vector_result_tag),
        .vector_result_row_o(raw_vector_result_row),
        .vector_result_segment_o(raw_vector_result_segment),
        .vector_result_last_o(raw_vector_result_last),
        .completion_valid_o(executor_completion_valid),
        .completion_ready_i(1'b1),
        .completion_tag_o(executor_completion_tag),
        .completion_success_o(executor_completion_success),
        .busy_o(executor_busy),
        .protocol_error_o(executor_protocol_error)
    );

    npu_gemm_post_scheduler #(
        .CONTEXTS(ACTIVE_CONTEXTS),
        .RESULT_CHANNELS(ARRAY_DIM)
    ) u_post_scheduler (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .post_command_valid_i(post_command_valid),
        .post_command_ready_o(post_command_ready),
        .post_command_i(post_command),
        .gemm_valid_i(raw_vector_result_valid),
        .gemm_ready_o(raw_vector_result_ready),
        .gemm_result_i(raw_post_result),
        .external_valid_o(post_external_valid),
        .external_ready_i(post_external_ready),
        .external_result_o(post_external_result),
        .external_command_o(post_external_command),
        .external_completion_valid_i(external_completion_valid),
        .external_completion_ready_o(external_completion_ready),
        .external_completion_tag_i(external_completion_tag),
        .external_completion_success_i(external_completion_success),
        .vector_valid_o(post_vector_valid),
        .vector_ready_i(post_vector_ready),
        .vector_result_o(post_vector_result),
        .vector_command_o(post_vector_command),
        .vector_completion_valid_i(vector_completion_valid &&
                                   !vector_completion_feedback),
        .vector_completion_ready_o(vector_completion_ready),
        .vector_completion_tag_i(vector_completion_tag),
        .vector_completion_success_i(vector_completion_success),
        .feedback_valid_o(post_feedback_valid),
        .feedback_ready_i(post_feedback_ready),
        .feedback_result_o(post_feedback_result),
        .feedback_command_o(post_feedback_command),
        .feedback_completion_valid_i(feedback_completion_valid),
        .feedback_completion_ready_o(feedback_completion_ready),
        .feedback_completion_tag_i(feedback_completion_tag),
        .feedback_completion_success_i(feedback_completion_success),
        .completion_valid_o(completion_valid),
        .completion_ready_i(completion_ready),
        .completion_tag_o(completion_tag),
        .completion_success_o(completion_success),
        .busy_o(post_busy),
        .protocol_error_o(post_protocol_error)
    );

    npu_post_output_formatter16 #(
        .CHANNELS(ARRAY_DIM)
    ) u_external_formatter (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .input_valid_i(external_fifo_valid),
        .input_ready_o(external_fifo_ready),
        .input_result_i(external_fifo_data[
            0 +: ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]),
        .input_command_i(external_fifo_data[
            ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
            ARRAY_DIM*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]),
        .output_valid_o(gemm_output_valid_o),
        .output_ready_i(gemm_output_ready_i),
        .output_result_o(gemm_output_result_o),
        .output_command_o(gemm_output_command_o),
        .completion_valid_o(external_completion_valid),
        .completion_ready_i(external_completion_ready),
        .completion_tag_o(external_completion_tag),
        .completion_success_o(external_completion_success),
        .busy_o(external_formatter_busy),
        .protocol_error_o(external_formatter_protocol_error)
    );

    generate
        for (genvar external_lane = 0; external_lane < ARRAY_DIM;
             external_lane++) begin : g_external_elastic
            localparam int unsigned EXTERNAL_FIFO_WIDTH =
                npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +
                npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH;
            logic [$clog2(2+1)-1:0] fifo_level_unused;
            logic [EXTERNAL_FIFO_WIDTH-1:0] fifo_output;

            npu_scheduler_fifo #(
                .WIDTH(EXTERNAL_FIFO_WIDTH), .DEPTH(2),
                .ALLOW_FULL_POP(1'b0)
            ) u_fifo (
                .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
                .input_valid_i(post_external_valid[external_lane]),
                .input_ready_o(post_external_ready[external_lane]),
                .input_data_i({
                    post_external_command[
                        external_lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH],
                    post_external_result[
                        external_lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]}),
                .output_valid_o(external_fifo_valid[external_lane]),
                .output_ready_i(external_fifo_ready[external_lane]),
                .output_data_o(fifo_output),
                .level_o(fifo_level_unused)
            );
            always_comb begin
                external_fifo_data[
                    external_lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_RESULT_WIDTH] =
                    fifo_output[0 +:
                        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH];
                external_fifo_data[
                    ARRAY_DIM*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +
                    external_lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH] =
                    fifo_output[npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH];
            end
            wire _unused_fifo_level = &{1'b0, fifo_level_unused};
        end
    endgenerate

    npu_gemm_feedback_writer16 #(
        .CHANNELS(ARRAY_DIM),
        .SLOTS(2),
        .MAX_SEGMENTS(ARRAY_DIM)
    ) u_feedback_writer (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .feedback_valid_i(feedback_writer_valid),
        .feedback_ready_o(feedback_writer_ready),
        .feedback_result_i(feedback_writer_result),
        .feedback_command_i(feedback_writer_command),
        .activation_write_valid_o(feedback_activation_write_valid),
        .activation_write_ready_i(feedback_activation_write_ready),
        .activation_write_buffer_id_o(feedback_activation_write_buffer_id),
        .activation_write_offset_o(feedback_activation_write_offset),
        .activation_write_data_o(feedback_activation_write_data),
        .activation_write_scale_o(feedback_activation_write_scale),
        .completion_valid_o(feedback_completion_valid),
        .completion_ready_i(feedback_completion_ready),
        .completion_tag_o(feedback_completion_tag),
        .completion_success_o(feedback_completion_success),
        .busy_o(feedback_busy),
        .protocol_error_o(feedback_protocol_error)
    );

    always_comb begin
        select_direct_feedback = |post_feedback_valid;
        feedback_writer_valid = select_direct_feedback ?
            post_feedback_valid : vector_feedback_valid;
        feedback_writer_result = select_direct_feedback ?
            post_feedback_result : vector_feedback_result;
        feedback_writer_command = select_direct_feedback ?
            post_feedback_command : vector_feedback_command;
        post_feedback_ready = select_direct_feedback ?
            feedback_writer_ready : '0;
        vector_feedback_ready = select_direct_feedback ?
            '0 : feedback_writer_ready;
        gemm_feedback_valid_o = feedback_writer_valid;
        gemm_feedback_result_o = feedback_writer_result;
        gemm_feedback_command_o = feedback_writer_command;
    end

    npu_gemm_vector_coupler16 #(
        .CHANNELS(ARRAY_DIM),
        .CONTEXTS(ACTIVE_CONTEXTS)
    ) u_vector_backend (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .vector_command_valid_i(vector_command_valid),
        .vector_command_ready_o(vector_command_ready),
        .vector_command_i(vector_command),
        .gemm_valid_i(post_vector_valid),
        .gemm_ready_o(post_vector_ready),
        .gemm_result_i(post_vector_result),
        .gemm_command_i(post_vector_command),
        .operand_b_read_enable_o(vector_operand_b_read_enable),
        .operand_b_read_buffer_id_o(vector_operand_b_read_buffer_id),
        .operand_b_read_offset_o(vector_operand_b_read_offset),
        .operand_b_read_valid_i(vector_operand_b_read_valid),
        .operand_b_read_data_i(vector_operand_b_read_data),
        .operand_b_read_scale_i(vector_operand_b_read_scale),
        .operand_c_read_enable_o(vector_operand_c_read_enable),
        .operand_c_read_buffer_id_o(vector_operand_c_read_buffer_id),
        .operand_c_read_offset_o(vector_operand_c_read_offset),
        .operand_c_read_valid_i(vector_operand_c_read_valid),
        .operand_c_read_data_i(vector_operand_c_read_data),
        .operand_c_read_scale_i(vector_operand_c_read_scale),
        .result_valid_o(vector_backend_result_valid),
        .result_ready_i(vector_backend_result_ready),
        .result_o(vector_backend_result),
        .result_command_o(vector_backend_command),
        .completion_valid_o(vector_completion_valid),
        .completion_ready_i(vector_completion_feedback ? 1'b1 :
                            vector_completion_ready),
        .completion_tag_o(vector_completion_tag),
        .completion_success_o(vector_completion_success),
        .completion_feedback_o(vector_completion_feedback),
        .busy_o(vector_backend_busy),
        .protocol_error_o(vector_backend_protocol_error)
    );

    generate
        for (genvar vector_lane = 0; vector_lane < ARRAY_DIM;
             vector_lane++) begin : g_vector_result_route
            npu_scheduler_pkg::npu_post_command_t routed_command;

            always_comb begin
                routed_command = npu_scheduler_pkg::npu_post_command_t'(
                    vector_backend_command[
                        vector_lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]);
                gemm_vector_valid_o[vector_lane] =
                    vector_backend_result_valid[vector_lane] &&
                    (routed_command.vector_result_route ==
                     npu_scheduler_pkg::NPU_VECTOR_TO_EXTERNAL);
                vector_feedback_valid[vector_lane] =
                    vector_backend_result_valid[vector_lane] &&
                    (routed_command.vector_result_route ==
                     npu_scheduler_pkg::NPU_VECTOR_TO_FEEDBACK);
                vector_backend_result_ready[vector_lane] =
                    (routed_command.vector_result_route ==
                     npu_scheduler_pkg::NPU_VECTOR_TO_FEEDBACK) ?
                    vector_feedback_ready[vector_lane] :
                    gemm_vector_ready_i[vector_lane];
                gemm_vector_result_o[
                    vector_lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_RESULT_WIDTH] =
                    vector_backend_result[
                        vector_lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH];
                gemm_vector_command_o[
                    vector_lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH] =
                    routed_command;
                vector_feedback_result[
                    vector_lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_RESULT_WIDTH] =
                    vector_backend_result[
                        vector_lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH];
                vector_feedback_command[
                    vector_lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH] =
                    routed_command;
            end
        end
    endgenerate

    GEMM_65536 #(
        .ARRAY_X(ARRAY_DIM),
        .ARRAY_Y(ARRAY_DIM)
    ) u_gemm (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .direct_a_valid_i(wave_a_valid),
        .direct_a_data_i(wave_a_data),
        .direct_a_format_i(wave_a_format),
        .direct_a_scale_i(wave_a_scale),
        .direct_a_block_first_i(wave_a_block_first),
        .direct_a_block_last_i(wave_a_block_last),
        .direct_a_matrix_first_i(wave_a_matrix_first),
        .direct_a_matrix_last_i(wave_a_matrix_last),
        .direct_a_tag_i(wave_a_tag),
        .direct_b_valid_i(wave_b_valid),
        .direct_b_data_i(wave_b_data),
        .direct_b_format_i(wave_b_format),
        .direct_b_scale_i(wave_b_scale),
        .result_ready_i(gemm_result_ready),
        .result_valid_o(gemm_result_valid),
        .result_data_o(gemm_result_data),
        .result_invalid_o(gemm_result_invalid),
        .result_tag_o(gemm_result_tag),
        .result_row_o(gemm_result_row),
        .result_level_o(gemm_result_level),
        .input_pair_issue_o(input_pair_issue),
        .output_overflow_o(output_overflow)
    );

    assign busy_o = executor_busy || post_busy || vector_backend_busy ||
                    feedback_busy || external_formatter_busy ||
                    (task_level != '0) ||
                    (active_contexts != '0);
    assign protocol_error_o = descriptor_protocol_error ||
        scheduler_protocol_error || tensor_protocol_error ||
        executor_protocol_error || post_protocol_error ||
        vector_backend_protocol_error || vector_operand_protocol_error ||
        feedback_protocol_error || external_formatter_protocol_error ||
        (|output_overflow);

    // Keep internal control-plane observability connected without exporting it.
    wire _unused_observation = &{1'b0,
        gemm_feedback_ready_i,
        input_pair_issue, executor_completion_valid, executor_completion_tag,
        executor_completion_success, gemm_result_level};

endmodule

`default_nettype wire
