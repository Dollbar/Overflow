`timescale 1ns/1ps

package npu_gemm_vector_tb_pkg;

    import fp8_pkg::*;
    import vector_pkg::*;
    import npu_scheduler_pkg::*;

    typedef enum logic {
        TB_DESCRIPTOR_WRITE  = 1'b0,
        TB_DESCRIPTOR_SUBMIT = 1'b1
    } tb_descriptor_action_e;

    function automatic npu_task_descriptor_t make_square_gemm_descriptor(
        input logic [NPU_JOB_ID_WIDTH-1:0] job_id,
        input logic [NPU_DIMENSION_WIDTH-1:0] matrix_size,
        input logic [3:0] tile_anchor_x,
        input logic [3:0] tile_anchor_y
    );
        npu_task_descriptor_t descriptor;
        begin
            descriptor = '0;
            descriptor.version = 4'd1;
            descriptor.operation = NPU_TASK_GEMM;
            descriptor.job_id = job_id;
            descriptor.tile_anchor_x = tile_anchor_x;
            descriptor.tile_anchor_y = tile_anchor_y;
            descriptor.matrix_size = matrix_size;
            descriptor.tile_span = matrix_size[8:4];
            descriptor.k_blocks = {11'd0, matrix_size[8:4]};
            descriptor.activation_buffer_id = 4'd0;
            descriptor.weight_buffer_id = 4'd1;
            descriptor.output_buffer_id = 4'd2;
            descriptor.activation_format = FP8_E4M3;
            descriptor.weight_format = FP8_E5M2;
            descriptor.rounding = RNE;
            descriptor.post_route = NPU_POST_EXTERNAL;
            descriptor.vector_control = '0;
            descriptor.vector_control.lane_mask = 16'hffff;
            descriptor.vector_control.operation = VECTOR_ENGINE_OP_PASS;
            descriptor.vector_control.operand_b_source = VECTOR_SRC_VECTOR;
            descriptor.output_format = NPU_OUTPUT_FP32;
            make_square_gemm_descriptor = descriptor;
        end
    endfunction

endpackage
