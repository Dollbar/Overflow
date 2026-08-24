`timescale 1ns/1ps
`default_nettype none

// Full-throughput FP32 sigmoid approximation.
//
// The stable formulation evaluates exp(-abs(x)) and selects
//   exp(-abs(x)) / (1 + exp(-abs(x))) for negative x, or
//   1 / (1 + exp(-abs(x))) for non-negative x.
// It therefore keeps the existing exp approximation inside its [-16, 0]
// domain and naturally saturates for larger finite magnitudes.
(* keep_hierarchy = "yes" *)
module fp32_sigmoid_pipeline #(
    parameter bit FTZ = 1'b0
) (
    input  logic        clk_i,
    input  logic        rst_i,
    input  logic        clear_i,
    input  logic        valid_i,
    input  logic [31:0] data_i,
    input  logic        invalid_i,
    output logic        valid_o,
    output logic [31:0] result_o,
    output logic        invalid_o
);

    localparam int unsigned EXP_LATENCY = 16;
    localparam int unsigned ADD_LATENCY = 3;
    localparam int unsigned RECIP_LATENCY = 11;
    localparam int unsigned MUL_LATENCY = 13;
    localparam int unsigned PRE_OUTPUT_LATENCY =
        EXP_LATENCY + ADD_LATENCY + RECIP_LATENCY + MUL_LATENCY;
    localparam int unsigned SIGMOID_LATENCY = PRE_OUTPUT_LATENCY + 1;
    localparam int unsigned EXP_TO_RECIP_LATENCY = ADD_LATENCY + RECIP_LATENCY;
    localparam logic [31:0] FP32_ONE = 32'h3f800000;
    localparam logic [31:0] FP32_CANONICAL_NAN = 32'h7fc00000;

    logic [31:0] negative_magnitude_comb;
    logic input_nan_comb;
    logic input_inf_comb;

    logic exp_valid;
    logic [31:0] exp_result;
    logic exp_invalid;
    logic denominator_valid;
    logic [31:0] denominator_result;
    logic denominator_invalid;
    logic reciprocal_valid;
    logic [31:0] reciprocal_result;
    logic reciprocal_invalid;
    logic negative_valid;
    logic [31:0] negative_result;
    logic negative_invalid;
    logic [31:0] selected_result_q;
    logic selected_invalid_q;
    logic [SIGMOID_LATENCY:0] valid_pipe_q;

    logic [31:0] exp_align_q [0:EXP_TO_RECIP_LATENCY-1];
    logic exp_invalid_align_q [0:EXP_TO_RECIP_LATENCY-1];
    logic [31:0] positive_align_q [0:MUL_LATENCY-1];
    logic positive_invalid_align_q [0:MUL_LATENCY-1];
    logic sign_pipe_q [0:PRE_OUTPUT_LATENCY-1];
    logic nan_pipe_q [0:PRE_OUTPUT_LATENCY-1];
    logic inf_pipe_q [0:PRE_OUTPUT_LATENCY-1];
    logic input_invalid_pipe_q [0:PRE_OUTPUT_LATENCY-1];

    always_comb begin
        negative_magnitude_comb = {1'b1, data_i[30:0]};
        input_nan_comb = (data_i[30:23] == 8'hff) &&
                         (data_i[22:0] != 23'd0);
        input_inf_comb = (data_i[30:23] == 8'hff) &&
                         (data_i[22:0] == 23'd0);
    end

    fp32_exp_approx u_exponential (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(valid_i), .data_i(negative_magnitude_comb),
        .invalid_i(invalid_i), .valid_o(exp_valid),
        .result_o(exp_result), .invalid_o(exp_invalid)
    );

    fp32_add_one_pipeline u_denominator (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(exp_valid), .data_i(exp_result), .invalid_i(exp_invalid),
        .valid_o(denominator_valid),
        .result_o(denominator_result), .invalid_o(denominator_invalid)
    );

    fp32_recip_pipeline u_reciprocal (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(denominator_valid), .data_i(denominator_result),
        .invalid_i(denominator_invalid), .valid_o(reciprocal_valid),
        .result_o(reciprocal_result), .invalid_o(reciprocal_invalid)
    );

    fp32_mul_pipeline #(.FTZ(FTZ)) u_negative_probability (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(reciprocal_valid),
        .a_i(exp_align_q[EXP_TO_RECIP_LATENCY-1]),
        .b_i(reciprocal_result),
        .invalid_i({exp_invalid_align_q[EXP_TO_RECIP_LATENCY-1],
                    reciprocal_invalid}),
        .rounding_i(fp8_pkg::RNE), .valid_o(negative_valid),
        .result_o(negative_result), .invalid_o(negative_invalid)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_pipe_q <= '0;
        end else begin
            valid_pipe_q[0] <= valid_i;
            for (integer stage = 1; stage <= SIGMOID_LATENCY; stage++) begin
                valid_pipe_q[stage] <= valid_pipe_q[stage-1];
            end
        end

        exp_align_q[0] <= exp_result;
        exp_invalid_align_q[0] <= exp_invalid;
        for (integer stage = 1; stage < EXP_TO_RECIP_LATENCY; stage++) begin
            exp_align_q[stage] <= exp_align_q[stage-1];
            exp_invalid_align_q[stage] <= exp_invalid_align_q[stage-1];
        end

        positive_align_q[0] <= reciprocal_result;
        positive_invalid_align_q[0] <= reciprocal_invalid;
        for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
            positive_align_q[stage] <= positive_align_q[stage-1];
            positive_invalid_align_q[stage] <=
                positive_invalid_align_q[stage-1];
        end

        sign_pipe_q[0] <= data_i[31];
        nan_pipe_q[0] <= input_nan_comb;
        inf_pipe_q[0] <= input_inf_comb;
        input_invalid_pipe_q[0] <= invalid_i;
        for (integer stage = 1; stage < PRE_OUTPUT_LATENCY; stage++) begin
            sign_pipe_q[stage] <= sign_pipe_q[stage-1];
            nan_pipe_q[stage] <= nan_pipe_q[stage-1];
            inf_pipe_q[stage] <= inf_pipe_q[stage-1];
            input_invalid_pipe_q[stage] <= input_invalid_pipe_q[stage-1];
        end

        if (nan_pipe_q[PRE_OUTPUT_LATENCY-1]) begin
            selected_result_q <= FP32_CANONICAL_NAN;
            selected_invalid_q <= 1'b1;
        end else if (inf_pipe_q[PRE_OUTPUT_LATENCY-1]) begin
            selected_result_q <=
                sign_pipe_q[PRE_OUTPUT_LATENCY-1] ? 32'd0 : FP32_ONE;
            selected_invalid_q <= input_invalid_pipe_q[PRE_OUTPUT_LATENCY-1];
        end else if (sign_pipe_q[PRE_OUTPUT_LATENCY-1]) begin
            selected_result_q <= negative_result;
            selected_invalid_q <= negative_invalid;
        end else begin
            selected_result_q <= positive_align_q[MUL_LATENCY-1];
            selected_invalid_q <= positive_invalid_align_q[MUL_LATENCY-1];
        end
    end

    // This interface boundary keeps the sign/special selection out of the
    // consuming multiplier input path while retaining the registered valid
    // timing established above.
    always_ff @(posedge clk_i) begin
        result_o <= selected_result_q;
        invalid_o <= selected_invalid_q;
    end

    always_comb begin
        valid_o = valid_pipe_q[SIGMOID_LATENCY];
    end

    logic internal_valid_unused;
    always_comb begin
        internal_valid_unused = negative_valid;
    end

endmodule

`default_nettype wire
