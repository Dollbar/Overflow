`timescale 1ns/1ps
`default_nettype none

// Verification-only compute-cluster interface model. It accepts one written
// descriptor, completes it after submit, and records loader writes while all
// high-bandwidth result streams remain idle.
/* verilator lint_off DECLFILENAME */
module npu_square_gemm_system #(
    parameter int unsigned ARRAY_DIM = 16,
    parameter int unsigned BUFFER_COUNT = 4,
    parameter int unsigned DESCRIPTOR_ENTRIES = 16,
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

    npu_scheduler_pkg::npu_task_descriptor_t descriptor_fields;
    /* verilator lint_off UNUSEDSIGNAL */
    npu_scheduler_pkg::npu_task_descriptor_t descriptor_q;
    npu_scheduler_pkg::npu_task_status_t status_q;
    logic descriptor_written_q;
    logic status_valid_q;
    logic [31:0] tensor_write_count_q;
    logic [31:0] vector_write_count_q;
    logic [127:0] last_tensor_data_q;
    logic [127:0] last_tensor_scale_q;
    logic [BANK_INDEX_WIDTH-1:0] last_tensor_bank_q;
    logic [127:0] last_vector_data_q;
    logic [7:0] last_vector_scale_q;
    logic [BANK_INDEX_WIDTH-1:0] last_vector_bank_q;
    /* verilator lint_on UNUSEDSIGNAL */
    logic _unused_inputs;

    assign descriptor_fields = descriptor_write_data_i;
    assign descriptor_write_ready_o = !rst_i && !clear_i;
    assign descriptor_submit_ready_o = !rst_i && !clear_i &&
                                       descriptor_written_q &&
                                       !status_valid_q;
    assign tensor_write_ready_o = !rst_i && !clear_i;
    assign vector_operand_write_ready_o = !rst_i && !clear_i;
    assign gemm_output_valid_o = '0;
    /* verilator lint_off WIDTHCONCAT */
    assign gemm_output_result_o = '0;
    assign gemm_output_command_o = '0;
    assign gemm_vector_valid_o = '0;
    assign gemm_vector_result_o = '0;
    assign gemm_vector_command_o = '0;
    assign gemm_feedback_valid_o = '0;
    assign gemm_feedback_result_o = '0;
    assign gemm_feedback_command_o = '0;
    /* verilator lint_on WIDTHCONCAT */
    assign status_valid_o = status_valid_q;
    assign status_o = status_q;
    assign busy_o = descriptor_written_q || status_valid_q;
    assign _unused_inputs = &{1'b0, descriptor_write_index_i,
        descriptor_submit_index_i, tensor_write_weight_i,
        tensor_write_buffer_id_i, tensor_write_offset_i,
        vector_operand_write_c_i, vector_operand_write_buffer_id_i,
        vector_operand_write_offset_i, gemm_output_ready_i,
        gemm_vector_ready_i, gemm_feedback_ready_i, event_set_valid_i,
        event_set_id_i, event_clear_valid_i, event_clear_id_i,
        BUFFER_COUNT, TENSOR_VECTOR_DEPTH, TASK_SLOTS, ACTIVE_CONTEXTS,
        COMMAND_FIFO_DEPTH};

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            descriptor_q <= '0;
            descriptor_written_q <= 1'b0;
            status_q <= '0;
            status_valid_q <= 1'b0;
            tensor_write_count_q <= '0;
            vector_write_count_q <= '0;
            last_tensor_data_q <= '0;
            last_tensor_scale_q <= '0;
            last_tensor_bank_q <= '0;
            last_vector_data_q <= '0;
            last_vector_scale_q <= '0;
            last_vector_bank_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            if (status_valid_q && status_ready_i) begin
                status_valid_q <= 1'b0;
            end
            if (descriptor_write_valid_i && descriptor_write_ready_o) begin
                descriptor_q <= descriptor_fields;
                descriptor_written_q <= 1'b1;
            end
            if (descriptor_submit_valid_i && descriptor_submit_ready_o) begin
                descriptor_written_q <= 1'b0;
                status_q.job_id <= descriptor_q.job_id;
                status_q.tag <= '0;
                status_q.success <= 1'b1;
                status_q.code <= npu_scheduler_pkg::NPU_TASK_STATUS_OK;
                status_valid_q <= 1'b1;
            end
            if (tensor_write_valid_i && tensor_write_ready_o) begin
                tensor_write_count_q <= tensor_write_count_q + 1'b1;
                last_tensor_data_q <= tensor_write_data_i;
                last_tensor_scale_q <= tensor_write_scale_i;
                last_tensor_bank_q <= tensor_write_bank_i;
            end
            if (vector_operand_write_valid_i &&
                vector_operand_write_ready_o) begin
                vector_write_count_q <= vector_write_count_q + 1'b1;
                last_vector_data_q <= vector_operand_write_data_i;
                last_vector_scale_q <= vector_operand_write_scale_i;
                last_vector_bank_q <= vector_operand_write_bank_i;
            end
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
