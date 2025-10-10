`timescale 1ns/1ps

package npu_scheduler_pkg;

    localparam int unsigned NPU_JOB_ID_WIDTH = 16;
    localparam int unsigned NPU_TAG_WIDTH = 8;
    localparam int unsigned NPU_EVENT_ID_WIDTH = 8;
    localparam int unsigned NPU_BUFFER_ID_WIDTH = 4;
    localparam int unsigned NPU_BUFFER_OFFSET_WIDTH = 32;
    localparam int unsigned NPU_DIMENSION_WIDTH = 16;

    typedef enum logic [2:0] {
        NPU_TASK_GEMM = 3'd0
    } npu_task_operation_e;

    typedef enum logic {
        NPU_OUTPUT_FP32 = 1'b0,
        NPU_OUTPUT_FP8  = 1'b1
    } npu_output_format_e;

    typedef enum logic {
        NPU_RESULT_FROM_GEMM   = 1'b0,
        NPU_RESULT_FROM_VECTOR = 1'b1
    } npu_result_source_e;

    typedef enum logic [1:0] {
        NPU_POST_EXTERNAL = 2'd0,
        NPU_POST_VECTOR   = 2'd1,
        NPU_POST_GEMM     = 2'd2
    } npu_post_route_e;

    typedef enum logic [3:0] {
        NPU_TASK_STATUS_OK                  = 4'd0,
        NPU_TASK_ERROR_VERSION             = 4'd1,
        NPU_TASK_ERROR_OPERATION           = 4'd2,
        NPU_TASK_ERROR_DIMENSION           = 4'd3,
        NPU_TASK_ERROR_SIZE_ALIGNMENT      = 4'd4,
        NPU_TASK_ERROR_BUFFER_ALIGNMENT    = 4'd5,
        NPU_TASK_ERROR_REGION              = 4'd6,
        NPU_TASK_ERROR_RESERVED_7          = 4'd7,
        NPU_TASK_ERROR_VECTOR_OPERATION    = 4'd8,
        NPU_TASK_ERROR_COMPLETION          = 4'd9
    } npu_task_status_code_e;

    // Every referenced tensor already resides in the input buffers when this
    // descriptor reaches the scheduler. Addresses are local buffer offsets,
    // never HBM or system-physical addresses.
    typedef struct packed {
        logic [3:0]                         version;
        npu_task_operation_e                operation;
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic                               wait_event_valid;
        logic [NPU_EVENT_ID_WIDTH-1:0]      wait_event_id;
        logic                               signal_event_valid;
        logic [NPU_EVENT_ID_WIDTH-1:0]      signal_event_id;
        logic [3:0]                         tile_anchor_x;
        logic [3:0]                         tile_anchor_y;
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        logic [4:0]                         tile_span;
        logic [15:0]                        k_blocks;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     activation_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] activation_base_offset;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     weight_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] weight_base_offset;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     output_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] output_base_offset;
        fp8_pkg::fp8_format_e               activation_format;
        fp8_pkg::fp8_format_e               weight_format;
        fp8_pkg::fp8_rounding_e             rounding;
        npu_post_route_e                    post_route;
        vector_pkg::vector_engine_control_t vector_control;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     vector_b_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] vector_b_base_offset;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     vector_c_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] vector_c_base_offset;
        logic [31:0]                        vector_scalar;
        logic                               feedback_operand;
        logic                               feedback_transpose;
        npu_output_format_e                 output_format;
    } npu_task_descriptor_t;

    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]    job_id;
        logic [NPU_TAG_WIDTH-1:0]       tag;
        logic [3:0]                     tile_anchor_x;
        logic [3:0]                     tile_anchor_y;
        logic [4:0]                     tile_span;
        logic [15:0]                    k_blocks;
        logic [NPU_DIMENSION_WIDTH-1:0] matrix_size;
        fp8_pkg::fp8_format_e           activation_format;
        fp8_pkg::fp8_format_e           weight_format;
        fp8_pkg::fp8_rounding_e         rounding;
    } npu_gemm_command_t;

    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic [NPU_TAG_WIDTH-1:0]           tag;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] base_offset;
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        logic [3:0]                         tile_anchor_x;
        logic [3:0]                         tile_anchor_y;
        logic [4:0]                         tile_span;
        fp8_pkg::fp8_format_e               format;
        fp8_pkg::fp8_rounding_e             rounding;
    } npu_buffer_read_command_t;

    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic [NPU_TAG_WIDTH-1:0]           tag;
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        logic [4:0]                         vectors_per_row;
        vector_pkg::vector_engine_control_t control;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_b_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_b_base_offset;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_c_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_c_base_offset;
        logic [31:0]                        scalar;
    } npu_vector_command_t;

    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic [NPU_TAG_WIDTH-1:0]           tag;
        npu_result_source_e                 source;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] base_offset;
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        logic [4:0]                         vectors_per_row;
        npu_output_format_e                 output_format;
        logic                               signal_event_valid;
        logic [NPU_EVENT_ID_WIDTH-1:0]      signal_event_id;
    } npu_result_command_t;

    // Internal command allocated atomically with the GEMM/A/B commands.  It is
    // indexed by the hardware tag and read once when a result matrix starts.
    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic [NPU_TAG_WIDTH-1:0]           tag;
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        logic [4:0]                         vectors_per_row;
        npu_post_route_e                    route;
        vector_pkg::vector_engine_control_t vector_control;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_b_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_b_base_offset;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_c_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_c_base_offset;
        logic [31:0]                        scalar;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     destination_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] destination_base_offset;
        logic                               destination_operand;
        logic                               transpose_enable;
        fp8_pkg::fp8_format_e               destination_format;
        fp8_pkg::fp8_rounding_e             destination_rounding;
        npu_output_format_e                 output_format;
        logic                               signal_event_valid;
        logic [NPU_EVENT_ID_WIDTH-1:0]      signal_event_id;
    } npu_post_command_t;

    // Atomic result beat used after the GEMM collector.  Independent route
    // backpressure can never advance data without its identity and coordinates.
    typedef struct packed {
        logic [511:0]                       data;
        logic [15:0]                        invalid;
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic [NPU_TAG_WIDTH-1:0]           tag;
        logic [NPU_DIMENSION_WIDTH-1:0]     row;
        logic [4:0]                         segment;
        logic                               last;
    } npu_post_result_beat_t;

    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0] job_id;
        logic [NPU_TAG_WIDTH-1:0]    tag;
        logic                        success;
        npu_task_status_code_e       code;
    } npu_task_status_t;

    /* verilator lint_off UNUSEDPARAM */
    localparam int unsigned NPU_TASK_DESCRIPTOR_WIDTH =
        $bits(npu_task_descriptor_t);
    localparam int unsigned NPU_GEMM_COMMAND_WIDTH = $bits(npu_gemm_command_t);
    localparam int unsigned NPU_BUFFER_READ_COMMAND_WIDTH =
        $bits(npu_buffer_read_command_t);
    localparam int unsigned NPU_VECTOR_COMMAND_WIDTH =
        $bits(npu_vector_command_t);
    localparam int unsigned NPU_RESULT_COMMAND_WIDTH =
        $bits(npu_result_command_t);
    localparam int unsigned NPU_POST_COMMAND_WIDTH = $bits(npu_post_command_t);
    localparam int unsigned NPU_POST_RESULT_WIDTH =
        $bits(npu_post_result_beat_t);
    localparam int unsigned NPU_TASK_STATUS_WIDTH = $bits(npu_task_status_t);
    /* verilator lint_on UNUSEDPARAM */

endpackage
