`timescale 1ns/1ps
`default_nettype none

// 16-lane GEMM后处理流水：可选bias、残差、ReLU以及FP8量化。
// 固定14周期延迟、每周期可接收一个向量；lane mask为0时完整保留累加器输入。
module gemm_epilogue16 #(
    parameter bit FTZ = 1'b0
) (
    input  logic                            clk_i,
    input  logic                            rst_i,
    input  logic                            clear_i,
    input  logic                            valid_i,
    input  vector_pkg::vector_fp32_data_t   accumulator_i,
    input  vector_pkg::vector_fp32_data_t   bias_i,
    input  logic [31:0]                     scalar_bias_i,
    input  vector_pkg::vector_fp32_data_t   residual_i,
    input  vector_pkg::vector_lane_mask_t   accumulator_invalid_i,
    input  vector_pkg::vector_lane_mask_t   bias_invalid_i,
    input  logic                            scalar_bias_invalid_i,
    input  vector_pkg::vector_lane_mask_t   residual_invalid_i,
    input  vector_pkg::epilogue_control_t   control_i,
    output logic                            valid_o,
    output vector_pkg::vector_fp32_data_t   fp32_o,
    output vector_pkg::vector_fp8_data_t    fp8_o,
    output vector_pkg::vector_lane_mask_t   invalid_o,
    output vector_pkg::vector_lane_mask_t   overflow_o,
    output vector_pkg::vector_lane_mask_t   inexact_o,
    output vector_pkg::epilogue_control_t   control_o
);

    localparam int unsigned LANES = vector_pkg::VECTOR_LANES;
    localparam int unsigned LATENCY = 14;
    localparam int unsigned STAGE1_ALIGNMENT = 6;
    localparam int unsigned ADD_ALIGNMENT = 5;
    localparam int unsigned CONTROL_WIDTH = 34;
    localparam int unsigned CONTROL_ROUNDING_LSB = 0;
    localparam int unsigned CONTROL_FP8_FORMAT_BIT = 2;
    localparam int unsigned CONTROL_ACTIVATION_LSB = 4;
    localparam int unsigned CONTROL_RESIDUAL_ENABLE_BIT = 6;
    localparam int unsigned CONTROL_BIAS_ENABLE_BIT = 8;
    localparam int unsigned CONTROL_LANE_MASK_LSB = 18;

    logic [31:0] accumulator_lane [0:LANES-1];
    logic [31:0] bias_lane [0:LANES-1];
    logic [31:0] residual_lane [0:LANES-1];
    logic [31:0] selected_bias_lane [0:LANES-1];
    logic selected_bias_invalid_lane [0:LANES-1];
    logic [31:0] bias_add_a_q [0:LANES-1];
    logic [31:0] bias_add_b_q [0:LANES-1];
    logic bias_add_invalid_a_q [0:LANES-1];
    logic bias_add_invalid_b_q [0:LANES-1];
    (* keep *) logic [1:0] bias_add_rounding_q [0:LANES-1];
    logic bias_add_valid_q [0:LANES-1];

    logic [31:0] input_accumulator_delay_q [0:STAGE1_ALIGNMENT][0:LANES-1];
    logic [31:0] input_residual_delay_q [0:STAGE1_ALIGNMENT][0:LANES-1];
    logic input_accumulator_invalid_delay_q [0:STAGE1_ALIGNMENT][0:LANES-1];
    logic input_residual_invalid_delay_q [0:STAGE1_ALIGNMENT][0:LANES-1];

    logic [31:0] bias_add_result_lane [0:LANES-1];
    logic bias_add_invalid_lane [0:LANES-1];
    logic [31:0] stage1_selected_lane [0:LANES-1];
    logic stage1_invalid_lane [0:LANES-1];
    logic [31:0] stage1_delay_q [0:ADD_ALIGNMENT][0:LANES-1];
    logic stage1_invalid_delay_q [0:ADD_ALIGNMENT][0:LANES-1];

    logic [31:0] residual_add_result_lane [0:LANES-1];
    logic residual_add_invalid_lane [0:LANES-1];
    logic [31:0] stage2_selected_lane [0:LANES-1];
    logic stage2_invalid_lane [0:LANES-1];
    logic [31:0] activated_lane [0:LANES-1];
    logic [31:0] activated_q [0:LANES-1];
    logic activated_invalid_q [0:LANES-1];

    logic [7:0] quantized_lane [0:LANES-1];
    logic quantized_overflow_lane [0:LANES-1];
    logic quantized_inexact_lane [0:LANES-1];

    logic valid_delay_q [0:LATENCY];
    logic [CONTROL_WIDTH-1:0] control_delay_q [0:LATENCY];

    /* Arithmetic valid outputs are not architectural; the shared valid pipe is authoritative. */
    /* verilator lint_off UNUSEDSIGNAL */
    logic bias_add_valid_unused [0:LANES-1];
    logic residual_add_valid_unused [0:LANES-1];
    /* verilator lint_on UNUSEDSIGNAL */

    logic [1:0] stage1_rounding_comb;
    logic [1:0] stage2_rounding_comb;
    logic [1:0] quantize_rounding_comb;
    logic quantize_format_comb;

    always_comb begin
        stage1_rounding_comb = control_i.rounding;
        stage2_rounding_comb =
            control_delay_q[STAGE1_ALIGNMENT]
                [CONTROL_ROUNDING_LSB +: 2];
        quantize_rounding_comb = control_delay_q[LATENCY-1]
            [CONTROL_ROUNDING_LSB +: 2];
        quantize_format_comb = control_delay_q[LATENCY-1]
            [CONTROL_FP8_FORMAT_BIT];
        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            accumulator_lane[lane_index] = accumulator_i[lane_index*32 +: 32];
            bias_lane[lane_index] = bias_i[lane_index*32 +: 32];
            residual_lane[lane_index] = residual_i[lane_index*32 +: 32];
            if (control_i.bias_is_scalar) begin
                selected_bias_lane[lane_index] = scalar_bias_i;
                selected_bias_invalid_lane[lane_index] = scalar_bias_invalid_i;
            end else begin
                selected_bias_lane[lane_index] = bias_lane[lane_index];
                selected_bias_invalid_lane[lane_index] = bias_invalid_i[lane_index];
            end
        end
    end

    generate
        for (genvar lane = 0; lane < LANES; lane++) begin : g_lane
            fp32_add_pipeline #(.FTZ(FTZ)) u_bias_add (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(bias_add_valid_q[lane]),
                .a_i(bias_add_a_q[lane]), .b_i(bias_add_b_q[lane]),
                .invalid_i({bias_add_invalid_b_q[lane], bias_add_invalid_a_q[lane]}),
                .rounding_i(bias_add_rounding_q[lane]),
                .valid_o(bias_add_valid_unused[lane]),
                .result_o(bias_add_result_lane[lane]),
                .invalid_o(bias_add_invalid_lane[lane]));

            fp32_add_pipeline #(.FTZ(FTZ)) u_residual_add (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(valid_delay_q[STAGE1_ALIGNMENT]),
                .a_i(stage1_selected_lane[lane]),
                .b_i(input_residual_delay_q[STAGE1_ALIGNMENT][lane]),
                .invalid_i({input_residual_invalid_delay_q[STAGE1_ALIGNMENT][lane],
                            stage1_invalid_lane[lane]}),
                .rounding_i(stage2_rounding_comb),
                .valid_o(residual_add_valid_unused[lane]),
                .result_o(residual_add_result_lane[lane]),
                .invalid_o(residual_add_invalid_lane[lane]));

            fp32_to_fp8 u_quantize (
                .data_i(activated_q[lane]),
                .format_i(quantize_format_comb),
                .rounding_i(quantize_rounding_comb),
                .data_o(quantized_lane[lane]),
                .overflow_o(quantized_overflow_lane[lane]),
                .inexact_o(quantized_inexact_lane[lane]));
        end
    endgenerate

    always_comb begin
        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            stage1_selected_lane[lane_index] = bias_add_result_lane[lane_index];
            stage1_invalid_lane[lane_index] = bias_add_invalid_lane[lane_index];
            if (!control_delay_q[STAGE1_ALIGNMENT]
                    [CONTROL_LANE_MASK_LSB + lane_index] ||
                !control_delay_q[STAGE1_ALIGNMENT]
                    [CONTROL_BIAS_ENABLE_BIT]) begin
                stage1_selected_lane[lane_index] =
                    input_accumulator_delay_q[STAGE1_ALIGNMENT][lane_index];
                stage1_invalid_lane[lane_index] =
                    input_accumulator_invalid_delay_q[STAGE1_ALIGNMENT][lane_index];
            end

            stage2_selected_lane[lane_index] = residual_add_result_lane[lane_index];
            stage2_invalid_lane[lane_index] = residual_add_invalid_lane[lane_index];
            if (!control_delay_q[12]
                    [CONTROL_LANE_MASK_LSB + lane_index] ||
                !control_delay_q[12][CONTROL_RESIDUAL_ENABLE_BIT]) begin
                stage2_selected_lane[lane_index] =
                    stage1_delay_q[ADD_ALIGNMENT][lane_index];
                stage2_invalid_lane[lane_index] =
                    stage1_invalid_delay_q[ADD_ALIGNMENT][lane_index];
            end

            activated_lane[lane_index] = stage2_selected_lane[lane_index];
            if (control_delay_q[12]
                    [CONTROL_LANE_MASK_LSB + lane_index] &&
                (control_delay_q[12][CONTROL_ACTIVATION_LSB +: 2] ==
                 vector_pkg::EPILOGUE_ACT_RELU) &&
                stage2_selected_lane[lane_index][31] &&
                !((stage2_selected_lane[lane_index][30:23] == 8'hff) &&
                  (stage2_selected_lane[lane_index][22:0] != 23'd0))) begin
                activated_lane[lane_index] = 32'd0;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            for (integer stage_index = 0; stage_index <= LATENCY; stage_index++) begin
                valid_delay_q[stage_index] <= 1'b0;
            end
        end else begin
            valid_delay_q[0] <= valid_i;
            for (integer stage_index = 1; stage_index <= LATENCY; stage_index++) begin
                valid_delay_q[stage_index] <= valid_delay_q[stage_index-1];
            end
        end

        control_delay_q[0] <= control_i;
        for (integer stage_index = 1; stage_index <= LATENCY; stage_index++) begin
            control_delay_q[stage_index] <= control_delay_q[stage_index-1];
        end

        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            bias_add_a_q[lane_index] <= accumulator_lane[lane_index];
            bias_add_b_q[lane_index] <= selected_bias_lane[lane_index];
            bias_add_invalid_a_q[lane_index] <= accumulator_invalid_i[lane_index];
            bias_add_invalid_b_q[lane_index] <= selected_bias_invalid_lane[lane_index];
            bias_add_rounding_q[lane_index] <= stage1_rounding_comb;
            if (rst_i || clear_i) begin
                bias_add_valid_q[lane_index] <= 1'b0;
            end else begin
                bias_add_valid_q[lane_index] <= valid_i;
            end
            input_accumulator_delay_q[0][lane_index] <= accumulator_lane[lane_index];
            input_residual_delay_q[0][lane_index] <= residual_lane[lane_index];
            input_accumulator_invalid_delay_q[0][lane_index] <=
                accumulator_invalid_i[lane_index];
            input_residual_invalid_delay_q[0][lane_index] <=
                residual_invalid_i[lane_index];
            stage1_delay_q[0][lane_index] <= stage1_selected_lane[lane_index];
            stage1_invalid_delay_q[0][lane_index] <= stage1_invalid_lane[lane_index];
            for (integer stage_index = 1; stage_index <= STAGE1_ALIGNMENT; stage_index++) begin
                input_accumulator_delay_q[stage_index][lane_index] <=
                    input_accumulator_delay_q[stage_index-1][lane_index];
                input_residual_delay_q[stage_index][lane_index] <=
                    input_residual_delay_q[stage_index-1][lane_index];
                input_accumulator_invalid_delay_q[stage_index][lane_index] <=
                    input_accumulator_invalid_delay_q[stage_index-1][lane_index];
                input_residual_invalid_delay_q[stage_index][lane_index] <=
                    input_residual_invalid_delay_q[stage_index-1][lane_index];
            end
            for (integer stage_index = 1; stage_index <= ADD_ALIGNMENT; stage_index++) begin
                stage1_delay_q[stage_index][lane_index] <=
                    stage1_delay_q[stage_index-1][lane_index];
                stage1_invalid_delay_q[stage_index][lane_index] <=
                    stage1_invalid_delay_q[stage_index-1][lane_index];
            end
            activated_q[lane_index] <= activated_lane[lane_index];
            fp32_o[lane_index*32 +: 32] <= activated_q[lane_index];
            fp8_o[lane_index*8 +: 8] <= quantized_lane[lane_index];
            invalid_o[lane_index] <= activated_invalid_q[lane_index];
            overflow_o[lane_index] <= quantized_overflow_lane[lane_index];
            inexact_o[lane_index] <= quantized_inexact_lane[lane_index];
            activated_invalid_q[lane_index] <= stage2_invalid_lane[lane_index];
        end
    end

    always_comb begin
        valid_o = valid_delay_q[LATENCY];
        control_o = control_delay_q[LATENCY];
    end

endmodule

`default_nettype wire
