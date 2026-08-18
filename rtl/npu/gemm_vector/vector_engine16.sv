`timescale 1ns/1ps
`default_nettype none

// Full-throughput framework wrapper for the 16-lane Transformer vector backend.
// Requests are issued directly into independent fixed-latency pipelines.  A
// multi-enqueue response FIFO absorbs results that return on the same cycle, so
// one slow operation never serializes a following independent operation.
/* verilator lint_off DECLFILENAME */
module vector_engine16 #(
    parameter bit FTZ = 1'b0
) (
    input  logic                                           clk_i,
    input  logic                                           rst_i,
    input  logic                                           clear_i,
    input  logic                                           request_valid_i,
    output logic                                           request_ready_o,
    input  vector_pkg::vector_fp32_data_t                  data_a_i,
    input  vector_pkg::vector_fp32_data_t                  data_b_i,
    input  vector_pkg::vector_fp32_data_t                  data_c_i,
    input  logic [31:0]                                    scalar_i,
    input  vector_pkg::vector_lane_mask_t                  invalid_a_i,
    input  vector_pkg::vector_lane_mask_t                  invalid_b_i,
    input  vector_pkg::vector_lane_mask_t                  invalid_c_i,
    input  logic                                           scalar_invalid_i,
    input  vector_pkg::vector_engine_control_t             control_i,
    output logic                                           response_valid_o,
    input  logic                                           response_ready_i,
    output vector_pkg::vector_fp32_data_t                  fp32_vector_o,
    output vector_pkg::vector_fp8_data_t                   fp8_vector_o,
    output logic [31:0]                                    fp32_scalar_o,
    output vector_pkg::vector_lane_mask_t                  invalid_o,
    output vector_pkg::vector_lane_mask_t                  overflow_o,
    output vector_pkg::vector_lane_mask_t                  inexact_o,
    output logic                                           empty_o,
    output vector_pkg::vector_engine_response_control_t    response_control_o
);
    localparam int unsigned PRODUCER_COUNT = 7;
    localparam int unsigned OUTSTANDING_WIDTH = 9;

    logic request_fire;
    logic alu_request_valid;
    logic epilogue_request_valid;
    logic reduce_request_valid;
    logic softmax_request_valid;
    logic norm_request_valid;
    logic gelu_request_valid;
    logic silu_request_valid;

    vector_pkg::vector_control_t alu_control_i;
    vector_pkg::epilogue_control_t epilogue_control_i;
    vector_pkg::vector_reduce_control_t reduce_control_i;
    vector_pkg::vector_softmax_control_t softmax_control_i;
    vector_pkg::vector_norm_control_t norm_control_i;
    vector_pkg::vector_activation_control_t activation_control_i;

    logic alu_valid_o;
    vector_pkg::vector_fp32_data_t alu_result_o;
    vector_pkg::vector_lane_mask_t alu_invalid_o;
    vector_pkg::vector_control_t alu_control_o;

    logic epilogue_valid_o;
    vector_pkg::vector_fp32_data_t epilogue_fp32_o;
    vector_pkg::vector_fp8_data_t epilogue_fp8_o;
    vector_pkg::vector_lane_mask_t epilogue_invalid_o;
    vector_pkg::vector_lane_mask_t epilogue_overflow_o;
    vector_pkg::vector_lane_mask_t epilogue_inexact_o;
    vector_pkg::epilogue_control_t epilogue_control_o;

    logic reduce_valid_o;
    logic [31:0] reduce_result_o;
    logic reduce_invalid_o;
    logic reduce_empty_o;
    vector_pkg::vector_reduce_control_t reduce_control_o;

    logic softmax_valid_o;
    vector_pkg::vector_fp32_data_t softmax_data_o;
    vector_pkg::vector_lane_mask_t softmax_invalid_o;
    logic softmax_empty_o;
    vector_pkg::vector_softmax_control_t softmax_control_o;

    logic norm_valid_o;
    vector_pkg::vector_fp32_data_t norm_data_o;
    vector_pkg::vector_lane_mask_t norm_invalid_o;
    logic norm_empty_o;
    vector_pkg::vector_norm_control_t norm_control_o;

    logic gelu_valid_o;
    vector_pkg::vector_fp32_data_t gelu_data_o;
    vector_pkg::vector_lane_mask_t gelu_invalid_o;
    logic gelu_empty_o;
    vector_pkg::vector_activation_control_t gelu_control_o;

    logic silu_valid_o;
    vector_pkg::vector_fp32_data_t silu_data_o;
    vector_pkg::vector_lane_mask_t silu_invalid_o;
    logic silu_empty_o;
    vector_pkg::vector_activation_control_t silu_control_o;

    logic [PRODUCER_COUNT-1:0] producer_valid;
    vector_pkg::vector_engine_result_t
        producer_result [0:PRODUCER_COUNT-1];
    logic [PRODUCER_COUNT-1:0] producer_fifo_input_ready;
    logic [PRODUCER_COUNT-1:0] producer_fifo_output_valid;
    logic [PRODUCER_COUNT-1:0] producer_fifo_output_ready;
    vector_pkg::vector_engine_result_t
        producer_fifo_output [0:PRODUCER_COUNT-1];
    logic [OUTSTANDING_WIDTH-1:0]
        producer_outstanding_q [0:PRODUCER_COUNT-1];
    logic [OUTSTANDING_WIDTH-1:0] selected_capacity;
    logic [OUTSTANDING_WIDTH-1:0] selected_outstanding;
    logic [2:0] issue_producer;
    logic [2:0] arbitration_producer;
    logic arbitration_valid;
    logic response_fire;
    logic response_slot_available;
    logic response_valid_q;
    logic [2:0] response_producer_q;
    logic [2:0] round_robin_q;
    vector_pkg::vector_engine_result_t response_q;

    always_comb begin
        issue_producer = 3'd0;
        case (control_i.operation)
            vector_pkg::VECTOR_ENGINE_OP_EPILOGUE:
                issue_producer = 3'd1;
            vector_pkg::VECTOR_ENGINE_OP_REDUCE_SUM,
            vector_pkg::VECTOR_ENGINE_OP_REDUCE_MAX:
                issue_producer = 3'd2;
            vector_pkg::VECTOR_ENGINE_OP_SOFTMAX:
                issue_producer = 3'd3;
            vector_pkg::VECTOR_ENGINE_OP_LAYERNORM,
            vector_pkg::VECTOR_ENGINE_OP_RMSNORM:
                issue_producer = 3'd4;
            vector_pkg::VECTOR_ENGINE_OP_GELU:
                issue_producer = 3'd5;
            vector_pkg::VECTOR_ENGINE_OP_SILU:
                issue_producer = 3'd6;
            default: issue_producer = 3'd0;
        endcase

        selected_capacity = OUTSTANDING_WIDTH'(20);
        case (issue_producer)
            3'd2: selected_capacity = OUTSTANDING_WIDTH'(32);
            3'd3: selected_capacity = OUTSTANDING_WIDTH'(80);
            3'd4: selected_capacity = OUTSTANDING_WIDTH'(160);
            3'd5,
            3'd6: selected_capacity = OUTSTANDING_WIDTH'(64);
            default: selected_capacity = OUTSTANDING_WIDTH'(20);
        endcase
        selected_outstanding = producer_outstanding_q[issue_producer];
        request_ready_o = !rst_i && !clear_i &&
            ((selected_outstanding < selected_capacity) ||
             (response_fire && (response_producer_q == issue_producer)));
        request_fire = request_valid_i && request_ready_o;

        alu_request_valid = 1'b0;
        epilogue_request_valid = 1'b0;
        reduce_request_valid = 1'b0;
        softmax_request_valid = 1'b0;
        norm_request_valid = 1'b0;
        gelu_request_valid = 1'b0;
        silu_request_valid = 1'b0;
        case (control_i.operation)
            vector_pkg::VECTOR_ENGINE_OP_PASS,
            vector_pkg::VECTOR_ENGINE_OP_ADD,
            vector_pkg::VECTOR_ENGINE_OP_MUL,
            vector_pkg::VECTOR_ENGINE_OP_MIN,
            vector_pkg::VECTOR_ENGINE_OP_MAX:
                alu_request_valid = request_fire;
            vector_pkg::VECTOR_ENGINE_OP_EPILOGUE:
                epilogue_request_valid = request_fire;
            vector_pkg::VECTOR_ENGINE_OP_REDUCE_SUM,
            vector_pkg::VECTOR_ENGINE_OP_REDUCE_MAX:
                reduce_request_valid = request_fire;
            vector_pkg::VECTOR_ENGINE_OP_SOFTMAX:
                softmax_request_valid = request_fire;
            vector_pkg::VECTOR_ENGINE_OP_LAYERNORM,
            vector_pkg::VECTOR_ENGINE_OP_RMSNORM:
                norm_request_valid = request_fire;
            vector_pkg::VECTOR_ENGINE_OP_GELU:
                gelu_request_valid = request_fire;
            vector_pkg::VECTOR_ENGINE_OP_SILU:
                silu_request_valid = request_fire;
            default: alu_request_valid = request_fire;
        endcase

        alu_control_i = '0;
        alu_control_i.lane_mask = control_i.lane_mask;
        alu_control_i.tag = control_i.tag;
        alu_control_i.last = control_i.last;
        alu_control_i.operand_b_source = control_i.operand_b_source;
        alu_control_i.rounding = control_i.rounding;
        case (control_i.operation)
            vector_pkg::VECTOR_ENGINE_OP_ADD:
                alu_control_i.operation = vector_pkg::VECTOR_OP_ADD;
            vector_pkg::VECTOR_ENGINE_OP_MUL:
                alu_control_i.operation = vector_pkg::VECTOR_OP_MUL;
            vector_pkg::VECTOR_ENGINE_OP_MIN:
                alu_control_i.operation = vector_pkg::VECTOR_OP_MIN;
            vector_pkg::VECTOR_ENGINE_OP_MAX:
                alu_control_i.operation = vector_pkg::VECTOR_OP_MAX;
            default:
                alu_control_i.operation = vector_pkg::VECTOR_OP_PASS;
        endcase

        epilogue_control_i = '0;
        epilogue_control_i.lane_mask = control_i.lane_mask;
        epilogue_control_i.tag = control_i.tag;
        epilogue_control_i.last = control_i.last;
        epilogue_control_i.bias_enable = control_i.bias_enable;
        epilogue_control_i.bias_is_scalar = control_i.bias_is_scalar;
        epilogue_control_i.residual_enable = control_i.residual_enable;
        epilogue_control_i.activation = control_i.activation;
        epilogue_control_i.output_format = control_i.output_format;
        epilogue_control_i.fp8_format = control_i.fp8_format;
        epilogue_control_i.rounding = control_i.rounding;

        reduce_control_i = '0;
        reduce_control_i.lane_mask = control_i.lane_mask;
        reduce_control_i.tag = control_i.tag;
        reduce_control_i.last = control_i.last;
        reduce_control_i.rounding = control_i.rounding;
        reduce_control_i.operation =
            (control_i.operation == vector_pkg::VECTOR_ENGINE_OP_REDUCE_MAX) ?
            vector_pkg::VECTOR_REDUCE_MAX : vector_pkg::VECTOR_REDUCE_SUM;

        softmax_control_i = '0;
        softmax_control_i.lane_mask = control_i.lane_mask;
        softmax_control_i.tag = control_i.tag;
        softmax_control_i.last = control_i.last;

        norm_control_i = '0;
        norm_control_i.lane_mask = control_i.lane_mask;
        norm_control_i.tag = control_i.tag;
        norm_control_i.last = control_i.last;
        norm_control_i.mode =
            (control_i.operation == vector_pkg::VECTOR_ENGINE_OP_RMSNORM) ?
            vector_pkg::VECTOR_NORM_RMS : vector_pkg::VECTOR_NORM_LAYER;
        norm_control_i.affine_enable = control_i.affine_enable;
        norm_control_i.beta_enable = control_i.beta_enable;

        activation_control_i = '0;
        activation_control_i.lane_mask = control_i.lane_mask;
        activation_control_i.tag = control_i.tag;
        activation_control_i.last = control_i.last;
    end

    vector_alu16 #(.FTZ(FTZ)) u_alu (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(alu_request_valid), .a_i(data_a_i), .b_i(data_b_i),
        .scalar_b_i(scalar_i), .invalid_a_i(invalid_a_i),
        .invalid_b_i(invalid_b_i),
        .scalar_b_invalid_i(scalar_invalid_i), .control_i(alu_control_i),
        .valid_o(alu_valid_o), .result_o(alu_result_o),
        .invalid_o(alu_invalid_o), .control_o(alu_control_o)
    );

    gemm_epilogue16 #(.FTZ(FTZ)) u_epilogue (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(epilogue_request_valid), .accumulator_i(data_a_i),
        .bias_i(data_b_i), .scalar_bias_i(scalar_i),
        .residual_i(data_c_i), .accumulator_invalid_i(invalid_a_i),
        .bias_invalid_i(invalid_b_i),
        .scalar_bias_invalid_i(scalar_invalid_i),
        .residual_invalid_i(invalid_c_i), .control_i(epilogue_control_i),
        .valid_o(epilogue_valid_o), .fp32_o(epilogue_fp32_o),
        .fp8_o(epilogue_fp8_o), .invalid_o(epilogue_invalid_o),
        .overflow_o(epilogue_overflow_o), .inexact_o(epilogue_inexact_o),
        .control_o(epilogue_control_o)
    );

    vector_reduce16 #(.FTZ(FTZ)) u_reduce (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(reduce_request_valid), .data_i(data_a_i),
        .invalid_i(invalid_a_i), .control_i(reduce_control_i),
        .valid_o(reduce_valid_o), .result_o(reduce_result_o),
        .invalid_o(reduce_invalid_o), .empty_o(reduce_empty_o),
        .control_o(reduce_control_o)
    );

    vector_softmax16 #(.FTZ(FTZ)) u_softmax (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(softmax_request_valid), .data_i(data_a_i),
        .invalid_i(invalid_a_i), .control_i(softmax_control_i),
        .valid_o(softmax_valid_o), .data_o(softmax_data_o),
        .invalid_o(softmax_invalid_o), .empty_o(softmax_empty_o),
        .control_o(softmax_control_o)
    );

    vector_norm16 #(.FTZ(FTZ)) u_norm (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(norm_request_valid), .data_i(data_a_i),
        .invalid_i(invalid_a_i), .gamma_i(data_b_i), .beta_i(data_c_i),
        .epsilon_i(scalar_i), .control_i(norm_control_i),
        .valid_o(norm_valid_o), .data_o(norm_data_o),
        .invalid_o(norm_invalid_o), .empty_o(norm_empty_o),
        .control_o(norm_control_o)
    );

    vector_gelu16 #(.FTZ(FTZ)) u_gelu (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(gelu_request_valid), .data_i(data_a_i),
        .invalid_i(invalid_a_i), .control_i(activation_control_i),
        .valid_o(gelu_valid_o), .data_o(gelu_data_o),
        .invalid_o(gelu_invalid_o), .empty_o(gelu_empty_o),
        .control_o(gelu_control_o)
    );

    vector_silu16 #(.FTZ(FTZ)) u_silu (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(silu_request_valid), .data_i(data_a_i),
        .invalid_i(invalid_a_i), .control_i(activation_control_i),
        .valid_o(silu_valid_o), .data_o(silu_data_o),
        .invalid_o(silu_invalid_o), .empty_o(silu_empty_o),
        .control_o(silu_control_o)
    );

    always_comb begin
        for (integer producer_index = 0;
             producer_index < PRODUCER_COUNT;
             producer_index++) begin
            producer_result[producer_index] = '0;
        end

        producer_valid[0] = alu_valid_o;
        producer_result[0].fp32_vector = alu_result_o;
        producer_result[0].invalid = alu_invalid_o;
        producer_result[0].empty = !(|alu_control_o.lane_mask);
        producer_result[0].control.lane_mask = alu_control_o.lane_mask;
        producer_result[0].control.tag = alu_control_o.tag;
        producer_result[0].control.last = alu_control_o.last;
        producer_result[0].control.operation =
            vector_pkg::vector_engine_op_e'(alu_control_o.operation);
        producer_result[0].control.operand_b_source =
            alu_control_o.operand_b_source;
        producer_result[0].control.rounding = alu_control_o.rounding;
        producer_result[0].control.result_kind =
            vector_pkg::VECTOR_ENGINE_RESULT_FP32_VECTOR;

        producer_valid[1] = epilogue_valid_o;
        producer_result[1].fp32_vector = epilogue_fp32_o;
        producer_result[1].fp8_vector = epilogue_fp8_o;
        producer_result[1].invalid = epilogue_invalid_o;
        producer_result[1].overflow = epilogue_overflow_o;
        producer_result[1].inexact = epilogue_inexact_o;
        producer_result[1].empty = !(|epilogue_control_o.lane_mask);
        producer_result[1].control.lane_mask = epilogue_control_o.lane_mask;
        producer_result[1].control.tag = epilogue_control_o.tag;
        producer_result[1].control.last = epilogue_control_o.last;
        producer_result[1].control.operation =
            vector_pkg::VECTOR_ENGINE_OP_EPILOGUE;
        producer_result[1].control.rounding = epilogue_control_o.rounding;
        producer_result[1].control.bias_enable =
            epilogue_control_o.bias_enable;
        producer_result[1].control.bias_is_scalar =
            epilogue_control_o.bias_is_scalar;
        producer_result[1].control.residual_enable =
            epilogue_control_o.residual_enable;
        producer_result[1].control.activation = epilogue_control_o.activation;
        producer_result[1].control.output_format =
            epilogue_control_o.output_format;
        producer_result[1].control.fp8_format = epilogue_control_o.fp8_format;
        producer_result[1].control.result_kind =
            (epilogue_control_o.output_format == vector_pkg::EPILOGUE_OUT_FP8) ?
            vector_pkg::VECTOR_ENGINE_RESULT_FP8_VECTOR :
            vector_pkg::VECTOR_ENGINE_RESULT_FP32_VECTOR;

        producer_valid[2] = reduce_valid_o;
        producer_result[2].fp32_scalar = reduce_result_o;
        producer_result[2].invalid[0] = reduce_invalid_o;
        producer_result[2].empty = reduce_empty_o;
        producer_result[2].control.lane_mask = reduce_control_o.lane_mask;
        producer_result[2].control.tag = reduce_control_o.tag;
        producer_result[2].control.last = reduce_control_o.last;
        producer_result[2].control.operation =
            (reduce_control_o.operation == vector_pkg::VECTOR_REDUCE_MAX) ?
            vector_pkg::VECTOR_ENGINE_OP_REDUCE_MAX :
            vector_pkg::VECTOR_ENGINE_OP_REDUCE_SUM;
        producer_result[2].control.rounding = reduce_control_o.rounding;
        producer_result[2].control.result_kind =
            vector_pkg::VECTOR_ENGINE_RESULT_FP32_SCALAR;

        producer_valid[3] = softmax_valid_o;
        producer_result[3].fp32_vector = softmax_data_o;
        producer_result[3].invalid = softmax_invalid_o;
        producer_result[3].empty = softmax_empty_o;
        producer_result[3].control.lane_mask = softmax_control_o.lane_mask;
        producer_result[3].control.tag = softmax_control_o.tag;
        producer_result[3].control.last = softmax_control_o.last;
        producer_result[3].control.operation =
            vector_pkg::VECTOR_ENGINE_OP_SOFTMAX;
        producer_result[3].control.result_kind =
            vector_pkg::VECTOR_ENGINE_RESULT_FP32_VECTOR;

        producer_valid[4] = norm_valid_o;
        producer_result[4].fp32_vector = norm_data_o;
        producer_result[4].invalid = norm_invalid_o;
        producer_result[4].empty = norm_empty_o;
        producer_result[4].control.lane_mask = norm_control_o.lane_mask;
        producer_result[4].control.tag = norm_control_o.tag;
        producer_result[4].control.last = norm_control_o.last;
        producer_result[4].control.operation =
            (norm_control_o.mode == vector_pkg::VECTOR_NORM_RMS) ?
            vector_pkg::VECTOR_ENGINE_OP_RMSNORM :
            vector_pkg::VECTOR_ENGINE_OP_LAYERNORM;
        producer_result[4].control.affine_enable =
            norm_control_o.affine_enable;
        producer_result[4].control.beta_enable = norm_control_o.beta_enable;
        producer_result[4].control.result_kind =
            vector_pkg::VECTOR_ENGINE_RESULT_FP32_VECTOR;

        producer_valid[5] = gelu_valid_o;
        producer_result[5].fp32_vector = gelu_data_o;
        producer_result[5].invalid = gelu_invalid_o;
        producer_result[5].empty = gelu_empty_o;
        producer_result[5].control.lane_mask = gelu_control_o.lane_mask;
        producer_result[5].control.tag = gelu_control_o.tag;
        producer_result[5].control.last = gelu_control_o.last;
        producer_result[5].control.operation =
            vector_pkg::VECTOR_ENGINE_OP_GELU;
        producer_result[5].control.result_kind =
            vector_pkg::VECTOR_ENGINE_RESULT_FP32_VECTOR;

        producer_valid[6] = silu_valid_o;
        producer_result[6].fp32_vector = silu_data_o;
        producer_result[6].invalid = silu_invalid_o;
        producer_result[6].empty = silu_empty_o;
        producer_result[6].control.lane_mask = silu_control_o.lane_mask;
        producer_result[6].control.tag = silu_control_o.tag;
        producer_result[6].control.last = silu_control_o.last;
        producer_result[6].control.operation =
            vector_pkg::VECTOR_ENGINE_OP_SILU;
        producer_result[6].control.result_kind =
            vector_pkg::VECTOR_ENGINE_RESULT_FP32_VECTOR;

    end

    vector_engine_result_fifo #(.DEPTH(20)) u_alu_result_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(producer_valid[0]),
        .input_ready_o(producer_fifo_input_ready[0]),
        .input_result_i(producer_result[0]),
        .output_valid_o(producer_fifo_output_valid[0]),
        .output_ready_i(producer_fifo_output_ready[0]),
        .output_result_o(producer_fifo_output[0])
    );

    vector_engine_result_fifo #(.DEPTH(20)) u_epilogue_result_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(producer_valid[1]),
        .input_ready_o(producer_fifo_input_ready[1]),
        .input_result_i(producer_result[1]),
        .output_valid_o(producer_fifo_output_valid[1]),
        .output_ready_i(producer_fifo_output_ready[1]),
        .output_result_o(producer_fifo_output[1])
    );

    vector_engine_result_fifo #(.DEPTH(32)) u_reduce_result_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(producer_valid[2]),
        .input_ready_o(producer_fifo_input_ready[2]),
        .input_result_i(producer_result[2]),
        .output_valid_o(producer_fifo_output_valid[2]),
        .output_ready_i(producer_fifo_output_ready[2]),
        .output_result_o(producer_fifo_output[2])
    );

    vector_engine_result_fifo #(.DEPTH(80)) u_softmax_result_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(producer_valid[3]),
        .input_ready_o(producer_fifo_input_ready[3]),
        .input_result_i(producer_result[3]),
        .output_valid_o(producer_fifo_output_valid[3]),
        .output_ready_i(producer_fifo_output_ready[3]),
        .output_result_o(producer_fifo_output[3])
    );

    vector_engine_result_fifo #(.DEPTH(160)) u_norm_result_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(producer_valid[4]),
        .input_ready_o(producer_fifo_input_ready[4]),
        .input_result_i(producer_result[4]),
        .output_valid_o(producer_fifo_output_valid[4]),
        .output_ready_i(producer_fifo_output_ready[4]),
        .output_result_o(producer_fifo_output[4])
    );

    vector_engine_result_fifo #(.DEPTH(64)) u_gelu_result_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(producer_valid[5]),
        .input_ready_o(producer_fifo_input_ready[5]),
        .input_result_i(producer_result[5]),
        .output_valid_o(producer_fifo_output_valid[5]),
        .output_ready_i(producer_fifo_output_ready[5]),
        .output_result_o(producer_fifo_output[5])
    );

    vector_engine_result_fifo #(.DEPTH(64)) u_silu_result_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(producer_valid[6]),
        .input_ready_o(producer_fifo_input_ready[6]),
        .input_result_i(producer_result[6]),
        .output_valid_o(producer_fifo_output_valid[6]),
        .output_ready_i(producer_fifo_output_ready[6]),
        .output_result_o(producer_fifo_output[6])
    );

    integer arbitration_offset;
    integer arbitration_candidate;
    always_comb begin
        response_valid_o = response_valid_q;
        response_fire = response_valid_o && response_ready_i;
        response_slot_available = !response_valid_q || response_ready_i;

        fp32_vector_o = response_q.fp32_vector;
        fp8_vector_o = response_q.fp8_vector;
        fp32_scalar_o = response_q.fp32_scalar;
        invalid_o = response_q.invalid;
        overflow_o = response_q.overflow |
            {vector_pkg::VECTOR_LANES{producer_overflow_q}};
        inexact_o = response_q.inexact;
        empty_o = response_q.empty;
        response_control_o = response_q.control;

        arbitration_valid = 1'b0;
        arbitration_producer = '0;
        producer_fifo_output_ready = '0;
        for (arbitration_offset = 0;
             arbitration_offset < PRODUCER_COUNT;
             arbitration_offset = arbitration_offset + 1) begin
            arbitration_candidate = int'(round_robin_q) + arbitration_offset;
            if (arbitration_candidate >= PRODUCER_COUNT) begin
                arbitration_candidate =
                    arbitration_candidate - PRODUCER_COUNT;
            end
            if (!arbitration_valid &&
                producer_fifo_output_valid[arbitration_candidate]) begin
                arbitration_valid = 1'b1;
                arbitration_producer = 3'(arbitration_candidate);
            end
        end
        if (response_slot_available && arbitration_valid) begin
            producer_fifo_output_ready[arbitration_producer] = 1'b1;
        end
    end

    logic producer_overflow_q;
    integer outstanding_index;
    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            response_valid_q <= 1'b0;
            response_producer_q <= '0;
            round_robin_q <= '0;
            response_q <= '0;
            producer_overflow_q <= 1'b0;
            for (outstanding_index = 0;
                 outstanding_index < PRODUCER_COUNT;
                 outstanding_index = outstanding_index + 1) begin
                producer_outstanding_q[outstanding_index] <= '0;
            end
        end else begin
            if (|(producer_valid & ~producer_fifo_input_ready)) begin
                producer_overflow_q <= 1'b1;
            end

            if (response_slot_available) begin
                if (arbitration_valid) begin
                    response_valid_q <= 1'b1;
                    response_producer_q <= arbitration_producer;
                    response_q <= producer_fifo_output[arbitration_producer];
                    if (arbitration_producer == 3'd6) begin
                        round_robin_q <= '0;
                    end else begin
                        round_robin_q <= arbitration_producer + 1'b1;
                    end
                end else if (response_fire) begin
                    response_valid_q <= 1'b0;
                end
            end

            for (outstanding_index = 0;
                 outstanding_index < PRODUCER_COUNT;
                 outstanding_index = outstanding_index + 1) begin
                case ({
                    request_fire &&
                        (issue_producer == 3'(outstanding_index)),
                    response_fire &&
                        (response_producer_q == 3'(outstanding_index))
                })
                    2'b10: producer_outstanding_q[outstanding_index] <=
                        producer_outstanding_q[outstanding_index] + 1'b1;
                    2'b01: producer_outstanding_q[outstanding_index] <=
                        producer_outstanding_q[outstanding_index] - 1'b1;
                    default: producer_outstanding_q[outstanding_index] <=
                        producer_outstanding_q[outstanding_index];
                endcase
            end
        end
    end

endmodule
/* verilator lint_on DECLFILENAME */

`default_nettype wire
