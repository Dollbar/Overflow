`timescale 1ns/1ps

package vector_pkg;

    localparam int unsigned VECTOR_LANES = 16;
    localparam int unsigned VECTOR_FP32_WIDTH = 32;
    localparam int unsigned VECTOR_DATA_WIDTH = VECTOR_LANES * VECTOR_FP32_WIDTH;
    localparam int unsigned VECTOR_FP8_DATA_WIDTH = VECTOR_LANES * 8;
    localparam int unsigned VECTOR_TAG_WIDTH = 8;

    typedef logic [VECTOR_DATA_WIDTH-1:0] vector_fp32_data_t;
    typedef logic [VECTOR_FP8_DATA_WIDTH-1:0] vector_fp8_data_t;
    typedef logic [VECTOR_LANES-1:0] vector_lane_mask_t;

    typedef enum logic [3:0] {
        VECTOR_OP_PASS = 4'd0,
        VECTOR_OP_ADD  = 4'd1,
        VECTOR_OP_MUL  = 4'd2,
        VECTOR_OP_MIN  = 4'd3,
        VECTOR_OP_MAX  = 4'd4
    } vector_alu_op_e;

    typedef enum logic [1:0] {
        VECTOR_SRC_VECTOR = 2'd0,
        VECTOR_SRC_SCALAR = 2'd1,
        VECTOR_SRC_ZERO   = 2'd2,
        VECTOR_SRC_ONE    = 2'd3
    } vector_operand_source_e;

    typedef struct packed {
        vector_lane_mask_t        lane_mask;
        logic [VECTOR_TAG_WIDTH-1:0] tag;
        logic                     last;
        vector_alu_op_e           operation;
        vector_operand_source_e   operand_b_source;
        logic [1:0]               rounding;
    } vector_control_t;

    typedef enum logic [1:0] {
        EPILOGUE_ACT_NONE = 2'd0,
        EPILOGUE_ACT_RELU = 2'd1
    } epilogue_activation_e;

    typedef enum logic {
        EPILOGUE_OUT_FP32 = 1'b0,
        EPILOGUE_OUT_FP8  = 1'b1
    } epilogue_output_format_e;

    typedef struct packed {
        vector_lane_mask_t          lane_mask;
        logic [VECTOR_TAG_WIDTH-1:0] tag;
        logic                       last;
        logic                       bias_enable;
        logic                       bias_is_scalar;
        logic                       residual_enable;
        epilogue_activation_e       activation;
        epilogue_output_format_e    output_format;
        logic                       fp8_format;
        logic [1:0]                 rounding;
    } epilogue_control_t;

    typedef enum logic {
        VECTOR_REDUCE_SUM = 1'b0,
        VECTOR_REDUCE_MAX = 1'b1
    } vector_reduce_op_e;

    typedef struct packed {
        vector_lane_mask_t          lane_mask;
        logic [VECTOR_TAG_WIDTH-1:0] tag;
        logic                       last;
        vector_reduce_op_e          operation;
        logic [1:0]                 rounding;
    } vector_reduce_control_t;

    typedef struct packed {
        vector_lane_mask_t          lane_mask;
        logic [VECTOR_TAG_WIDTH-1:0] tag;
        logic                       last;
    } vector_softmax_control_t;

    typedef enum logic {
        VECTOR_NORM_LAYER = 1'b0,
        VECTOR_NORM_RMS   = 1'b1
    } vector_norm_mode_e;

    typedef struct packed {
        vector_lane_mask_t          lane_mask;
        logic [VECTOR_TAG_WIDTH-1:0] tag;
        logic                       last;
        vector_norm_mode_e          mode;
        logic                       affine_enable;
        logic                       beta_enable;
    } vector_norm_control_t;

    typedef struct packed {
        vector_lane_mask_t          lane_mask;
        logic [VECTOR_TAG_WIDTH-1:0] tag;
        logic                       last;
    } vector_activation_control_t;

    typedef enum logic [3:0] {
        VECTOR_ENGINE_OP_PASS       = 4'd0,
        VECTOR_ENGINE_OP_ADD        = 4'd1,
        VECTOR_ENGINE_OP_MUL        = 4'd2,
        VECTOR_ENGINE_OP_MIN        = 4'd3,
        VECTOR_ENGINE_OP_MAX        = 4'd4,
        VECTOR_ENGINE_OP_EPILOGUE   = 4'd5,
        VECTOR_ENGINE_OP_REDUCE_SUM = 4'd6,
        VECTOR_ENGINE_OP_REDUCE_MAX = 4'd7,
        VECTOR_ENGINE_OP_SOFTMAX    = 4'd8,
        VECTOR_ENGINE_OP_LAYERNORM  = 4'd9,
        VECTOR_ENGINE_OP_RMSNORM    = 4'd10,
        VECTOR_ENGINE_OP_GELU       = 4'd11,
        VECTOR_ENGINE_OP_SILU       = 4'd12
    } vector_engine_op_e;

    typedef enum logic [1:0] {
        VECTOR_ENGINE_RESULT_FP32_VECTOR = 2'd0,
        VECTOR_ENGINE_RESULT_FP8_VECTOR  = 2'd1,
        VECTOR_ENGINE_RESULT_FP32_SCALAR = 2'd2
    } vector_engine_result_kind_e;

    typedef struct packed {
        vector_lane_mask_t          lane_mask;
        logic [VECTOR_TAG_WIDTH-1:0] tag;
        logic                       last;
        vector_engine_op_e          operation;
        vector_operand_source_e     operand_b_source;
        logic [1:0]                 rounding;
        logic                       bias_enable;
        logic                       bias_is_scalar;
        logic                       residual_enable;
        epilogue_activation_e       activation;
        epilogue_output_format_e    output_format;
        logic                       fp8_format;
        logic                       affine_enable;
        logic                       beta_enable;
    } vector_engine_control_t;

    // Complete request transported between the GEMM result fabric and the
    // shared vector backend.  Keeping the payload and its descriptor atomic
    // prevents metadata from advancing independently under backpressure.
    typedef struct packed {
        vector_fp32_data_t          data_a;
        vector_fp32_data_t          data_b;
        vector_fp32_data_t          data_c;
        logic [31:0]                scalar;
        vector_lane_mask_t          invalid_a;
        vector_lane_mask_t          invalid_b;
        vector_lane_mask_t          invalid_c;
        logic                       scalar_invalid;
        vector_engine_control_t     control;
    } vector_engine_request_t;

    // Scheduler metadata paired with a GEMM result at the multi-channel
    // ingress.  data_a/invalid_a come from the selected Tile result itself.
    typedef struct packed {
        vector_fp32_data_t          data_b;
        vector_fp32_data_t          data_c;
        logic [31:0]                scalar;
        vector_lane_mask_t          invalid_b;
        vector_lane_mask_t          invalid_c;
        logic                       scalar_invalid;
        vector_engine_control_t     control;
    } vector_engine_descriptor_t;

    // Fixed hierarchy-boundary widths.  Arrays of packed structs are flattened
    // at top-level module ports because Yosys does not accept unpacked struct
    // arrays as synthesizable ports.
    // Some leaf targets use only one of these shared ABI constants; keep the
    // unused counterpart from failing an otherwise unrelated leaf lint target.
    /* verilator lint_off UNUSEDPARAM */
    localparam int unsigned VECTOR_ENGINE_DESCRIPTOR_WIDTH = 1131;
    localparam int unsigned VECTOR_ENGINE_REQUEST_WIDTH = 1659;
    /* verilator lint_on UNUSEDPARAM */

    typedef struct packed {
        vector_lane_mask_t          lane_mask;
        logic [VECTOR_TAG_WIDTH-1:0] tag;
        logic                       last;
        vector_engine_op_e          operation;
        vector_operand_source_e     operand_b_source;
        logic [1:0]                 rounding;
        logic                       bias_enable;
        logic                       bias_is_scalar;
        logic                       residual_enable;
        epilogue_activation_e       activation;
        epilogue_output_format_e    output_format;
        logic                       fp8_format;
        logic                       affine_enable;
        logic                       beta_enable;
        vector_engine_result_kind_e result_kind;
    } vector_engine_response_control_t;

    typedef struct packed {
        vector_fp32_data_t               fp32_vector;
        vector_fp8_data_t                fp8_vector;
        logic [31:0]                     fp32_scalar;
        vector_lane_mask_t               invalid;
        vector_lane_mask_t               overflow;
        vector_lane_mask_t               inexact;
        logic                            empty;
        vector_engine_response_control_t control;
    } vector_engine_result_t;

    /* verilator lint_off UNUSEDPARAM */
    localparam int unsigned VECTOR_ENGINE_RESULT_WIDTH = 765;
    /* verilator lint_on UNUSEDPARAM */

endpackage
