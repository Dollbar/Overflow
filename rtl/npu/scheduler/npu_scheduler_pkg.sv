`timescale 1ns/1ps

package npu_scheduler_pkg;

    localparam int unsigned NPU_JOB_ID_WIDTH = 16;
    localparam int unsigned NPU_TAG_WIDTH = 8;
    localparam int unsigned NPU_EVENT_ID_WIDTH = 8;
    localparam int unsigned NPU_BUFFER_ID_WIDTH = 4;
    localparam int unsigned NPU_BUFFER_OFFSET_WIDTH = 32;
    localparam int unsigned NPU_DIMENSION_WIDTH = 16;
    // Some leaf environments compile the package without the scheduler.
    /* verilator lint_off UNUSEDPARAM */
    localparam logic [3:0] NPU_TASK_DESCRIPTOR_VERSION = 4'd2;
    localparam logic [3:0] NPU_VECTOR_TASK_DESCRIPTOR_VERSION = 4'd3;
    /* verilator lint_on UNUSEDPARAM */

    typedef enum logic [2:0] {
        NPU_TASK_GEMM   = 3'd0,
        NPU_TASK_VECTOR = 3'd1
    } npu_task_operation_e;

    typedef enum logic {
        NPU_OUTPUT_FP32 = 1'b0,
        NPU_OUTPUT_MX   = 1'b1
    } npu_output_format_e;

    typedef enum logic [1:0] {
        NPU_PAYLOAD_FP32_VECTOR = 2'd0,
        NPU_PAYLOAD_MX_VECTOR   = 2'd1,
        NPU_PAYLOAD_FP32_SCALAR = 2'd2
    } npu_result_payload_e;

    typedef enum logic {
        NPU_RESULT_FROM_GEMM   = 1'b0,
        NPU_RESULT_FROM_VECTOR = 1'b1
    } npu_result_source_e;

    typedef enum logic [1:0] {
        NPU_POST_EXTERNAL = 2'd0,
        NPU_POST_VECTOR   = 2'd1,
        NPU_POST_GEMM     = 2'd2
    } npu_post_route_e;

    typedef enum logic {
        NPU_VECTOR_TO_EXTERNAL = 1'b0,
        NPU_VECTOR_TO_FEEDBACK = 1'b1
    } npu_vector_result_route_e;

    typedef enum logic [3:0] {
        NPU_TASK_STATUS_OK                  = 4'd0,
        NPU_TASK_ERROR_VERSION             = 4'd1,
        NPU_TASK_ERROR_OPERATION           = 4'd2,
        NPU_TASK_ERROR_DIMENSION           = 4'd3,
        NPU_TASK_ERROR_SIZE_ALIGNMENT      = 4'd4,
        NPU_TASK_ERROR_BUFFER_ALIGNMENT    = 4'd5,
        NPU_TASK_ERROR_REGION              = 4'd6,
        NPU_TASK_ERROR_FORMAT              = 4'd7,
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
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        logic [15:0]                        k_blocks;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     activation_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] activation_base_offset;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     weight_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] weight_base_offset;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     output_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] output_base_offset;
        mxfp_pkg::mxfp_format_e             activation_format;
        mxfp_pkg::mxfp_format_e             weight_format;
        npu_post_route_e                    post_route;
        vector_pkg::vector_engine_control_t vector_control;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     vector_b_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] vector_b_base_offset;
        mxfp_pkg::mxfp_format_e             vector_b_format;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     vector_c_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] vector_c_base_offset;
        mxfp_pkg::mxfp_format_e             vector_c_format;
        logic [31:0]                        vector_scalar;
        logic                               feedback_operand;
        logic                               feedback_transpose;
        npu_vector_result_route_e           vector_result_route;
        npu_output_format_e                 output_format;
        mxfp_pkg::mxfp_format_e             output_mx_format;
    } npu_task_descriptor_t;

    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]    job_id;
        logic [NPU_TAG_WIDTH-1:0]       tag;
        logic [15:0]                    k_blocks;
        logic [NPU_DIMENSION_WIDTH-1:0] matrix_size;
        mxfp_pkg::mxfp_format_e         activation_format;
        mxfp_pkg::mxfp_format_e         weight_format;
    } npu_gemm_command_t;

    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic [NPU_TAG_WIDTH-1:0]           tag;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] base_offset;
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        mxfp_pkg::mxfp_format_e             format;
    } npu_buffer_read_command_t;

    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic [NPU_TAG_WIDTH-1:0]           tag;
        logic                               standalone;
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        logic [4:0]                         vectors_per_row;
        vector_pkg::vector_engine_control_t control;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_a_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_a_base_offset;
        mxfp_pkg::mxfp_format_e             operand_a_format;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_b_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_b_base_offset;
        mxfp_pkg::mxfp_format_e             operand_b_format;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_c_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_c_base_offset;
        mxfp_pkg::mxfp_format_e             operand_c_format;
        logic [31:0]                        scalar;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     destination_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] destination_base_offset;
        logic                               destination_operand;
        logic                               transpose_enable;
        mxfp_pkg::mxfp_format_e             destination_format;
        npu_vector_result_route_e           result_route;
        npu_output_format_e                 output_format;
        mxfp_pkg::mxfp_format_e             output_mx_format;
        logic                               signal_event_valid;
        logic [NPU_EVENT_ID_WIDTH-1:0]      signal_event_id;
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
        mxfp_pkg::mxfp_format_e             output_mx_format;
        npu_vector_result_route_e           vector_result_route;
        logic                               signal_event_valid;
        logic [NPU_EVENT_ID_WIDTH-1:0]      signal_event_id;
    } npu_result_command_t;

    // Internal command allocated atomically with the GEMM/A/B commands.  It is
    // indexed by the hardware tag and read once when a result matrix starts.
    typedef struct packed {
        logic [NPU_JOB_ID_WIDTH-1:0]        job_id;
        logic [NPU_TAG_WIDTH-1:0]           tag;
        logic                               standalone;
        logic [NPU_DIMENSION_WIDTH-1:0]     matrix_size;
        logic [4:0]                         vectors_per_row;
        npu_post_route_e                    route;
        npu_vector_result_route_e           vector_result_route;
        vector_pkg::vector_engine_control_t vector_control;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_b_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_b_base_offset;
        mxfp_pkg::mxfp_format_e             operand_b_format;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     operand_c_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] operand_c_base_offset;
        mxfp_pkg::mxfp_format_e             operand_c_format;
        logic [31:0]                        scalar;
        logic [NPU_BUFFER_ID_WIDTH-1:0]     destination_buffer_id;
        logic [NPU_BUFFER_OFFSET_WIDTH-1:0] destination_base_offset;
        logic                               destination_operand;
        logic                               transpose_enable;
        mxfp_pkg::mxfp_format_e             destination_format;
        npu_output_format_e                 output_format;
        mxfp_pkg::mxfp_format_e             output_mx_format;
        logic                               signal_event_valid;
        logic [NPU_EVENT_ID_WIDTH-1:0]      signal_event_id;
    } npu_post_command_t;

    // Atomic result beat used after the GEMM collector.  Independent route
    // backpressure can never advance data without its identity and coordinates.
    typedef struct packed {
        logic [511:0]                       data;
        npu_result_payload_e                payload_kind;
        mxfp_pkg::mxfp_format_e             mx_format;
        mxfp_pkg::mxfp_scale_t              mx_scale;
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

    // Explicit v0.2/v0.3 ABI widths keep the package consumable by the
    // repository Yosys frontend, which cannot evaluate $bits(type_name) here.
    // Packed struct/vector conversions remain type-checked by RTL lint.
    /* verilator lint_off UNUSEDPARAM */
    localparam int unsigned NPU_TASK_DESCRIPTOR_WIDTH = 342;
    localparam int unsigned NPU_GEMM_COMMAND_WIDTH = 60;
    localparam int unsigned NPU_BUFFER_READ_COMMAND_WIDTH = 78;
    localparam int unsigned NPU_VECTOR_COMMAND_WIDTH = 286;
    localparam int unsigned NPU_RESULT_COMMAND_WIDTH = 95;
    localparam int unsigned NPU_POST_COMMAND_WIDTH = 250;
    localparam int unsigned NPU_POST_RESULT_WIDTH = 586;
    localparam int unsigned NPU_TASK_STATUS_WIDTH = 29;
    /* verilator lint_on UNUSEDPARAM */

endpackage
