`timescale 1ns/1ps
`default_nettype none

// Full-throughput 16-lane FP32 LayerNorm/RMSNorm pipeline.
// LayerNorm uses a numerically stable two-pass variance calculation. RMSNorm
// reuses the same datapath with the centering operand forced to zero.
module vector_norm16 #(
    parameter bit FTZ = 1'b0
) (
    input  logic                                clk_i,
    input  logic                                rst_i,
    input  logic                                clear_i,
    input  logic                                valid_i,
    input  vector_pkg::vector_fp32_data_t       data_i,
    input  vector_pkg::vector_lane_mask_t       invalid_i,
    input  vector_pkg::vector_fp32_data_t       gamma_i,
    input  vector_pkg::vector_fp32_data_t       beta_i,
    input  logic [31:0]                         epsilon_i,
    input  vector_pkg::vector_norm_control_t    control_i,
    output logic                                valid_o,
    output vector_pkg::vector_fp32_data_t       data_o,
    output vector_pkg::vector_lane_mask_t       invalid_o,
    output logic                                empty_o,
    output vector_pkg::vector_norm_control_t    control_o
);

    localparam int unsigned LANES = vector_pkg::VECTOR_LANES;
    localparam int unsigned ADD_LATENCY = 6;
    localparam int unsigned MUL_LATENCY = 13;
    localparam int unsigned REDUCE_LATENCY = 24;
    localparam int unsigned RSQRT_LATENCY = 11;
    localparam int unsigned NORM_LATENCY = 147;
    localparam int unsigned NORM_CONTROL_WIDTH = 28;
    localparam logic [31:0] FP32_ONE = 32'h3f800000;

    vector_pkg::vector_fp32_data_t selected_gamma_comb;
    vector_pkg::vector_fp32_data_t selected_beta_comb;

    vector_pkg::vector_reduce_control_t input_sum_control_i;
    logic input_sum_valid;
    logic [31:0] input_sum_result;
    logic input_sum_invalid;
    logic input_sum_empty;
    vector_pkg::vector_reduce_control_t input_sum_control_o;
    vector_pkg::vector_fp32_data_t input_sum_data_q [0:REDUCE_LATENCY];
    vector_pkg::vector_fp32_data_t input_sum_gamma_q [0:REDUCE_LATENCY];
    vector_pkg::vector_fp32_data_t input_sum_beta_q [0:REDUCE_LATENCY];
    logic [31:0] input_sum_epsilon_q [0:REDUCE_LATENCY];
    logic [4:0] input_lane_count_q;
    logic [31:0] input_sum_reciprocal_q [0:REDUCE_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] input_sum_norm_control_q [0:REDUCE_LATENCY];
    logic input_sum_transaction_invalid_q [0:REDUCE_LATENCY];

    logic input_sum_entry_valid_q;
    logic [31:0] input_sum_entry_result_q;
    logic input_sum_entry_invalid_q;
    vector_pkg::vector_fp32_data_t input_sum_entry_data_q;
    vector_pkg::vector_fp32_data_t input_sum_entry_gamma_q;
    vector_pkg::vector_fp32_data_t input_sum_entry_beta_q;
    logic [31:0] input_sum_entry_epsilon_q;
    logic [31:0] input_sum_entry_reciprocal_q;
    vector_pkg::vector_norm_control_t input_sum_entry_control_q;
    logic input_sum_entry_transaction_invalid_q;

    logic mean_valid;
    logic [31:0] mean_result;
    logic mean_invalid;
    vector_pkg::vector_fp32_data_t mean_data_q [0:MUL_LATENCY-1];
    vector_pkg::vector_fp32_data_t mean_gamma_q [0:MUL_LATENCY-1];
    vector_pkg::vector_fp32_data_t mean_beta_q [0:MUL_LATENCY-1];
    logic [31:0] mean_epsilon_q [0:MUL_LATENCY-1];
    logic [31:0] mean_reciprocal_q [0:MUL_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] mean_control_q [0:MUL_LATENCY-1];
    logic mean_transaction_invalid_q [0:MUL_LATENCY-1];

    logic mean_broadcast_valid_q;
    logic [31:0] center_operand_comb;
    logic [31:0] mean_broadcast_q [0:LANES-1];
    vector_pkg::vector_fp32_data_t mean_broadcast_data_q;
    vector_pkg::vector_fp32_data_t mean_broadcast_gamma_q;
    vector_pkg::vector_fp32_data_t mean_broadcast_beta_q;
    logic [31:0] mean_broadcast_epsilon_q;
    logic [31:0] mean_broadcast_reciprocal_q;
    vector_pkg::vector_norm_control_t mean_broadcast_control_q;
    logic mean_broadcast_transaction_invalid_q;

    logic center_valid [0:LANES-1];
    logic [31:0] center_result [0:LANES-1];
    logic center_invalid [0:LANES-1];
    vector_pkg::vector_fp32_data_t center_data_comb;
    vector_pkg::vector_lane_mask_t center_invalid_comb;
    vector_pkg::vector_fp32_data_t center_gamma_q [0:ADD_LATENCY-1];
    vector_pkg::vector_fp32_data_t center_beta_q [0:ADD_LATENCY-1];
    logic [31:0] center_epsilon_q [0:ADD_LATENCY-1];
    logic [31:0] center_reciprocal_q [0:ADD_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] center_control_q [0:ADD_LATENCY-1];
    logic center_transaction_invalid_q [0:ADD_LATENCY-1];

    logic square_valid [0:LANES-1];
    logic [31:0] square_result [0:LANES-1];
    logic square_invalid [0:LANES-1];
    vector_pkg::vector_fp32_data_t square_data_comb;
    vector_pkg::vector_lane_mask_t square_invalid_comb;
    vector_pkg::vector_fp32_data_t square_centered_q [0:MUL_LATENCY-1];
    vector_pkg::vector_fp32_data_t square_gamma_q [0:MUL_LATENCY-1];
    vector_pkg::vector_fp32_data_t square_beta_q [0:MUL_LATENCY-1];
    logic [31:0] square_epsilon_q [0:MUL_LATENCY-1];
    logic [31:0] square_reciprocal_q [0:MUL_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] square_control_q [0:MUL_LATENCY-1];
    logic square_transaction_invalid_q [0:MUL_LATENCY-1];

    vector_pkg::vector_reduce_control_t square_sum_control_i;
    logic square_sum_valid;
    logic [31:0] square_sum_result;
    logic square_sum_invalid;
    logic square_sum_empty;
    vector_pkg::vector_reduce_control_t square_sum_control_o;
    vector_pkg::vector_fp32_data_t square_sum_centered_q [0:REDUCE_LATENCY];
    vector_pkg::vector_fp32_data_t square_sum_gamma_q [0:REDUCE_LATENCY];
    vector_pkg::vector_fp32_data_t square_sum_beta_q [0:REDUCE_LATENCY];
    logic [31:0] square_sum_epsilon_q [0:REDUCE_LATENCY];
    logic [31:0] square_sum_reciprocal_q [0:REDUCE_LATENCY];
    logic [NORM_CONTROL_WIDTH-1:0] square_sum_norm_control_q [0:REDUCE_LATENCY];
    logic square_sum_transaction_invalid_q [0:REDUCE_LATENCY];

    logic square_sum_entry_valid_q;
    logic [31:0] square_sum_entry_result_q;
    logic square_sum_entry_invalid_q;
    vector_pkg::vector_fp32_data_t square_sum_entry_centered_q;
    vector_pkg::vector_fp32_data_t square_sum_entry_gamma_q;
    vector_pkg::vector_fp32_data_t square_sum_entry_beta_q;
    logic [31:0] square_sum_entry_epsilon_q;
    logic [31:0] square_sum_entry_reciprocal_q;
    vector_pkg::vector_norm_control_t square_sum_entry_control_q;
    logic square_sum_entry_transaction_invalid_q;

    logic variance_valid;
    logic [31:0] variance_result;
    logic variance_invalid;
    vector_pkg::vector_fp32_data_t variance_centered_q [0:MUL_LATENCY-1];
    vector_pkg::vector_fp32_data_t variance_gamma_q [0:MUL_LATENCY-1];
    vector_pkg::vector_fp32_data_t variance_beta_q [0:MUL_LATENCY-1];
    logic [31:0] variance_epsilon_q [0:MUL_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] variance_control_q [0:MUL_LATENCY-1];
    logic variance_transaction_invalid_q [0:MUL_LATENCY-1];

    logic epsilon_valid;
    logic [31:0] epsilon_result;
    logic epsilon_invalid;
    vector_pkg::vector_fp32_data_t epsilon_centered_q [0:ADD_LATENCY-1];
    vector_pkg::vector_fp32_data_t epsilon_gamma_q [0:ADD_LATENCY-1];
    vector_pkg::vector_fp32_data_t epsilon_beta_q [0:ADD_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] epsilon_control_q [0:ADD_LATENCY-1];
    logic epsilon_transaction_invalid_q [0:ADD_LATENCY-1];

    logic inverse_valid;
    logic [31:0] inverse_result;
    logic inverse_invalid;
    vector_pkg::vector_fp32_data_t inverse_centered_q [0:RSQRT_LATENCY-1];
    vector_pkg::vector_fp32_data_t inverse_gamma_q [0:RSQRT_LATENCY-1];
    vector_pkg::vector_fp32_data_t inverse_beta_q [0:RSQRT_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] inverse_control_q [0:RSQRT_LATENCY-1];
    logic inverse_transaction_invalid_q [0:RSQRT_LATENCY-1];

    logic inverse_broadcast_valid_q;
    logic [31:0] inverse_broadcast_q [0:LANES-1];
    vector_pkg::vector_fp32_data_t inverse_broadcast_centered_q;
    vector_pkg::vector_fp32_data_t inverse_broadcast_gamma_q;
    vector_pkg::vector_fp32_data_t inverse_broadcast_beta_q;
    vector_pkg::vector_norm_control_t inverse_broadcast_control_q;
    logic inverse_broadcast_transaction_invalid_q;

    logic normalize_valid [0:LANES-1];
    logic [31:0] normalize_result [0:LANES-1];
    logic normalize_invalid [0:LANES-1];
    vector_pkg::vector_lane_mask_t normalize_invalid_comb;
    vector_pkg::vector_fp32_data_t normalize_gamma_q [0:MUL_LATENCY-1];
    vector_pkg::vector_fp32_data_t normalize_beta_q [0:MUL_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] normalize_control_q [0:MUL_LATENCY-1];
    logic normalize_transaction_invalid_q [0:MUL_LATENCY-1];

    logic scale_valid [0:LANES-1];
    logic [31:0] scale_result [0:LANES-1];
    logic scale_invalid [0:LANES-1];
    vector_pkg::vector_lane_mask_t scale_invalid_comb;
    vector_pkg::vector_fp32_data_t scale_beta_q [0:MUL_LATENCY-1];
    logic [NORM_CONTROL_WIDTH-1:0] scale_control_q [0:MUL_LATENCY-1];
    logic scale_transaction_invalid_q [0:MUL_LATENCY-1];

    logic offset_valid [0:LANES-1];
    logic [31:0] offset_result [0:LANES-1];
    logic offset_invalid [0:LANES-1];
    logic [NORM_CONTROL_WIDTH-1:0] offset_control_q [0:ADD_LATENCY-1];
    logic offset_transaction_invalid_q [0:ADD_LATENCY-1];

    logic [NORM_LATENCY:0] valid_pipe_q;

    function automatic logic [4:0] active_lane_count(
        input vector_pkg::vector_lane_mask_t lane_mask
    );
        logic [4:0] count;
        begin
            count = 5'd0;
            for (integer lane = 0; lane < LANES; lane++) begin
                count = count + lane_mask[lane];
            end
            active_lane_count = count;
        end
    endfunction

    function automatic logic [31:0] reciprocal_lane_count(
        input logic [4:0] count
    );
        begin
            case (count)
                5'd1:  reciprocal_lane_count = 32'h3f800000;
                5'd2:  reciprocal_lane_count = 32'h3f000000;
                5'd3:  reciprocal_lane_count = 32'h3eaaaaab;
                5'd4:  reciprocal_lane_count = 32'h3e800000;
                5'd5:  reciprocal_lane_count = 32'h3e4ccccd;
                5'd6:  reciprocal_lane_count = 32'h3e2aaaab;
                5'd7:  reciprocal_lane_count = 32'h3e124925;
                5'd8:  reciprocal_lane_count = 32'h3e000000;
                5'd9:  reciprocal_lane_count = 32'h3de38e39;
                5'd10: reciprocal_lane_count = 32'h3dcccccd;
                5'd11: reciprocal_lane_count = 32'h3dba2e8c;
                5'd12: reciprocal_lane_count = 32'h3daaaaab;
                5'd13: reciprocal_lane_count = 32'h3d9d89d9;
                5'd14: reciprocal_lane_count = 32'h3d924925;
                5'd15: reciprocal_lane_count = 32'h3d888889;
                5'd16: reciprocal_lane_count = 32'h3d800000;
                default: reciprocal_lane_count = 32'd0;
            endcase
        end
    endfunction

    always_comb begin
        input_sum_control_i.lane_mask = control_i.lane_mask;
        input_sum_control_i.tag = control_i.tag;
        input_sum_control_i.last = control_i.last;
        input_sum_control_i.operation = vector_pkg::VECTOR_REDUCE_SUM;

        // Use one packed assignment here. Yosys can otherwise lose fields
        // selected from an unpacked array of packed structures.
        square_sum_control_i = {
            square_control_q[MUL_LATENCY-1][27:3],
            vector_pkg::VECTOR_REDUCE_SUM
        };

        center_operand_comb = 32'd0;
        if (mean_control_q[MUL_LATENCY-1][2] ==
            vector_pkg::VECTOR_NORM_LAYER) begin
            center_operand_comb = {~mean_result[31], mean_result[30:0]};
        end

        for (integer lane = 0; lane < LANES; lane++) begin
            selected_gamma_comb[lane*32 +: 32] = FP32_ONE;
            selected_beta_comb[lane*32 +: 32] = 32'd0;
            if (control_i.affine_enable) begin
                selected_gamma_comb[lane*32 +: 32] = gamma_i[lane*32 +: 32];
                if (control_i.beta_enable) begin
                    selected_beta_comb[lane*32 +: 32] = beta_i[lane*32 +: 32];
                end
            end
            center_data_comb[lane*32 +: 32] = center_result[lane];
            center_invalid_comb[lane] = center_invalid[lane];
            square_data_comb[lane*32 +: 32] = square_result[lane];
            square_invalid_comb[lane] = square_invalid[lane];
            normalize_invalid_comb[lane] = normalize_invalid[lane];
            scale_invalid_comb[lane] = scale_invalid[lane];
        end
    end

    vector_reduce16 #(.FTZ(FTZ)) u_input_sum (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(valid_i), .data_i(data_i), .invalid_i(invalid_i),
        .control_i(input_sum_control_i), .valid_o(input_sum_valid),
        .result_o(input_sum_result), .invalid_o(input_sum_invalid),
        .empty_o(input_sum_empty), .control_o(input_sum_control_o)
    );

    fp32_mul_pipeline #(.FTZ(FTZ)) u_mean (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(input_sum_entry_valid_q), .a_i(input_sum_entry_result_q),
        .b_i(input_sum_entry_reciprocal_q),
        .invalid_i({input_sum_entry_transaction_invalid_q, input_sum_entry_invalid_q}),
        .rounding_i(fp8_pkg::RNE), .valid_o(mean_valid),
        .result_o(mean_result), .invalid_o(mean_invalid)
    );

    generate
        for (genvar lane = 0; lane < LANES; lane++) begin : g_lane_datapath
            logic [31:0] center_operand;
            logic [31:0] scale_operand;
            logic [31:0] offset_operand;

            always_comb begin
                center_operand = mean_broadcast_q[lane];
                scale_operand = normalize_gamma_q[MUL_LATENCY-1][lane*32 +: 32];
                offset_operand = scale_beta_q[MUL_LATENCY-1][lane*32 +: 32];
            end

            vector_norm_broadcast_slice u_mean_broadcast (
                .clk_i(clk_i), .value_i(center_operand_comb),
                .value_o(mean_broadcast_q[lane])
            );

            fp32_add_pipeline #(.FTZ(FTZ)) u_center (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(mean_broadcast_valid_q),
                .a_i(mean_broadcast_data_q[lane*32 +: 32]),
                .b_i(center_operand),
                .invalid_i({mean_broadcast_transaction_invalid_q,
                            mean_broadcast_transaction_invalid_q}),
                .rounding_i(fp8_pkg::RNE), .valid_o(center_valid[lane]),
                .result_o(center_result[lane]), .invalid_o(center_invalid[lane])
            );

            fp32_mul_pipeline #(.FTZ(FTZ)) u_square (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(center_valid[lane]), .a_i(center_result[lane]),
                .b_i(center_result[lane]),
                .invalid_i({center_invalid[lane], center_invalid[lane]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(square_valid[lane]),
                .result_o(square_result[lane]), .invalid_o(square_invalid[lane])
            );

            vector_norm_broadcast_slice u_inverse_broadcast (
                .clk_i(clk_i), .value_i(inverse_result),
                .value_o(inverse_broadcast_q[lane])
            );

            fp32_mul_pipeline #(.FTZ(FTZ)) u_normalize (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(inverse_broadcast_valid_q),
                .a_i(inverse_broadcast_centered_q[lane*32 +: 32]),
                .b_i(inverse_broadcast_q[lane]),
                .invalid_i({inverse_broadcast_transaction_invalid_q,
                            inverse_broadcast_transaction_invalid_q}),
                .rounding_i(fp8_pkg::RNE), .valid_o(normalize_valid[lane]),
                .result_o(normalize_result[lane]), .invalid_o(normalize_invalid[lane])
            );

            fp32_mul_pipeline #(.FTZ(FTZ)) u_scale (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(normalize_valid[lane]), .a_i(normalize_result[lane]),
                .b_i(scale_operand),
                .invalid_i({normalize_invalid[lane],
                            normalize_transaction_invalid_q[MUL_LATENCY-1]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(scale_valid[lane]),
                .result_o(scale_result[lane]), .invalid_o(scale_invalid[lane])
            );

            fp32_add_pipeline #(.FTZ(FTZ)) u_offset (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(scale_valid[lane]), .a_i(scale_result[lane]),
                .b_i(offset_operand),
                .invalid_i({scale_invalid[lane],
                            scale_transaction_invalid_q[MUL_LATENCY-1]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(offset_valid[lane]),
                .result_o(offset_result[lane]), .invalid_o(offset_invalid[lane])
            );
        end
    endgenerate

    vector_reduce16 #(.FTZ(FTZ)) u_square_sum (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(square_valid[0]), .data_i(square_data_comb),
        .invalid_i(square_invalid_comb), .control_i(square_sum_control_i),
        .valid_o(square_sum_valid), .result_o(square_sum_result),
        .invalid_o(square_sum_invalid), .empty_o(square_sum_empty),
        .control_o(square_sum_control_o)
    );

    fp32_mul_pipeline #(.FTZ(FTZ)) u_variance (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(square_sum_entry_valid_q), .a_i(square_sum_entry_result_q),
        .b_i(square_sum_entry_reciprocal_q),
        .invalid_i({square_sum_entry_transaction_invalid_q,
                    square_sum_entry_invalid_q}),
        .rounding_i(fp8_pkg::RNE), .valid_o(variance_valid),
        .result_o(variance_result), .invalid_o(variance_invalid)
    );

    fp32_add_pipeline #(.FTZ(FTZ)) u_epsilon (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(variance_valid), .a_i(variance_result),
        .b_i(variance_epsilon_q[MUL_LATENCY-1]),
        .invalid_i({variance_transaction_invalid_q[MUL_LATENCY-1], variance_invalid}),
        .rounding_i(fp8_pkg::RNE), .valid_o(epsilon_valid),
        .result_o(epsilon_result), .invalid_o(epsilon_invalid)
    );

    fp32_rsqrt_pipeline u_inverse_stddev (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(epsilon_valid), .data_i(epsilon_result),
        .invalid_i(epsilon_invalid || epsilon_transaction_invalid_q[ADD_LATENCY-1]),
        .valid_o(inverse_valid), .result_o(inverse_result),
        .invalid_o(inverse_invalid)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_pipe_q <= '0;
        end else begin
            valid_pipe_q[0] <= valid_i;
            for (integer stage = 1; stage <= NORM_LATENCY; stage++) begin
                valid_pipe_q[stage] <= valid_pipe_q[stage-1];
            end
        end

        input_sum_data_q[0] <= data_i;
        input_sum_gamma_q[0] <= selected_gamma_comb;
        input_sum_beta_q[0] <= selected_beta_comb;
        input_sum_epsilon_q[0] <= epsilon_i;
        input_lane_count_q <= active_lane_count(control_i.lane_mask);
        input_sum_reciprocal_q[0] <= reciprocal_lane_count(input_lane_count_q);
        input_sum_norm_control_q[0] <= control_i;
        input_sum_transaction_invalid_q[0] <= |(invalid_i & control_i.lane_mask);
        for (integer stage = 1; stage <= REDUCE_LATENCY; stage++) begin
            input_sum_data_q[stage] <= input_sum_data_q[stage-1];
            input_sum_gamma_q[stage] <= input_sum_gamma_q[stage-1];
            input_sum_beta_q[stage] <= input_sum_beta_q[stage-1];
            input_sum_epsilon_q[stage] <= input_sum_epsilon_q[stage-1];
            input_sum_norm_control_q[stage] <= input_sum_norm_control_q[stage-1];
            input_sum_transaction_invalid_q[stage] <= input_sum_transaction_invalid_q[stage-1];
        end
        for (integer stage = 1; stage < REDUCE_LATENCY; stage++) begin
            input_sum_reciprocal_q[stage] <= input_sum_reciprocal_q[stage-1];
        end

        input_sum_entry_valid_q <= input_sum_valid;
        input_sum_entry_result_q <= input_sum_result;
        input_sum_entry_invalid_q <= input_sum_invalid;
        input_sum_entry_data_q <= input_sum_data_q[REDUCE_LATENCY];
        input_sum_entry_gamma_q <= input_sum_gamma_q[REDUCE_LATENCY];
        input_sum_entry_beta_q <= input_sum_beta_q[REDUCE_LATENCY];
        input_sum_entry_epsilon_q <= input_sum_epsilon_q[REDUCE_LATENCY];
        input_sum_entry_reciprocal_q <= input_sum_reciprocal_q[REDUCE_LATENCY-1];
        input_sum_entry_control_q <= input_sum_norm_control_q[REDUCE_LATENCY];
        input_sum_entry_transaction_invalid_q <= input_sum_transaction_invalid_q[REDUCE_LATENCY] || input_sum_invalid;

        mean_data_q[0] <= input_sum_entry_data_q;
        mean_gamma_q[0] <= input_sum_entry_gamma_q;
        mean_beta_q[0] <= input_sum_entry_beta_q;
        mean_epsilon_q[0] <= input_sum_entry_epsilon_q;
        mean_reciprocal_q[0] <= input_sum_entry_reciprocal_q;
        mean_control_q[0] <= input_sum_entry_control_q;
        mean_transaction_invalid_q[0] <= input_sum_entry_transaction_invalid_q || input_sum_entry_invalid_q;
        for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
            mean_data_q[stage] <= mean_data_q[stage-1];
            mean_gamma_q[stage] <= mean_gamma_q[stage-1];
            mean_beta_q[stage] <= mean_beta_q[stage-1];
            mean_epsilon_q[stage] <= mean_epsilon_q[stage-1];
            mean_reciprocal_q[stage] <= mean_reciprocal_q[stage-1];
            mean_control_q[stage] <= mean_control_q[stage-1];
            mean_transaction_invalid_q[stage] <= mean_transaction_invalid_q[stage-1];
        end

        mean_broadcast_valid_q <= mean_valid;
        mean_broadcast_data_q <= mean_data_q[MUL_LATENCY-1];
        mean_broadcast_gamma_q <= mean_gamma_q[MUL_LATENCY-1];
        mean_broadcast_beta_q <= mean_beta_q[MUL_LATENCY-1];
        mean_broadcast_epsilon_q <= mean_epsilon_q[MUL_LATENCY-1];
        mean_broadcast_reciprocal_q <= mean_reciprocal_q[MUL_LATENCY-1];
        mean_broadcast_control_q <= mean_control_q[MUL_LATENCY-1];
        mean_broadcast_transaction_invalid_q <= mean_transaction_invalid_q[MUL_LATENCY-1] || mean_invalid;

        center_gamma_q[0] <= mean_broadcast_gamma_q;
        center_beta_q[0] <= mean_broadcast_beta_q;
        center_epsilon_q[0] <= mean_broadcast_epsilon_q;
        center_reciprocal_q[0] <= mean_broadcast_reciprocal_q;
        center_control_q[0] <= mean_broadcast_control_q;
        center_transaction_invalid_q[0] <= mean_broadcast_transaction_invalid_q;
        for (integer stage = 1; stage < ADD_LATENCY; stage++) begin
            center_gamma_q[stage] <= center_gamma_q[stage-1];
            center_beta_q[stage] <= center_beta_q[stage-1];
            center_epsilon_q[stage] <= center_epsilon_q[stage-1];
            center_reciprocal_q[stage] <= center_reciprocal_q[stage-1];
            center_control_q[stage] <= center_control_q[stage-1];
            center_transaction_invalid_q[stage] <= center_transaction_invalid_q[stage-1];
        end

        square_centered_q[0] <= center_data_comb;
        square_gamma_q[0] <= center_gamma_q[ADD_LATENCY-1];
        square_beta_q[0] <= center_beta_q[ADD_LATENCY-1];
        square_epsilon_q[0] <= center_epsilon_q[ADD_LATENCY-1];
        square_reciprocal_q[0] <= center_reciprocal_q[ADD_LATENCY-1];
        square_control_q[0] <= center_control_q[ADD_LATENCY-1];
        square_transaction_invalid_q[0] <= center_transaction_invalid_q[ADD_LATENCY-1] || (|center_invalid_comb);
        for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
            square_centered_q[stage] <= square_centered_q[stage-1];
            square_gamma_q[stage] <= square_gamma_q[stage-1];
            square_beta_q[stage] <= square_beta_q[stage-1];
            square_epsilon_q[stage] <= square_epsilon_q[stage-1];
            square_reciprocal_q[stage] <= square_reciprocal_q[stage-1];
            square_control_q[stage] <= square_control_q[stage-1];
            square_transaction_invalid_q[stage] <= square_transaction_invalid_q[stage-1];
        end

        square_sum_centered_q[0] <= square_centered_q[MUL_LATENCY-1];
        square_sum_gamma_q[0] <= square_gamma_q[MUL_LATENCY-1];
        square_sum_beta_q[0] <= square_beta_q[MUL_LATENCY-1];
        square_sum_epsilon_q[0] <= square_epsilon_q[MUL_LATENCY-1];
        square_sum_reciprocal_q[0] <= square_reciprocal_q[MUL_LATENCY-1];
        square_sum_norm_control_q[0] <= square_control_q[MUL_LATENCY-1];
        square_sum_transaction_invalid_q[0] <= square_transaction_invalid_q[MUL_LATENCY-1] || (|square_invalid_comb);
        for (integer stage = 1; stage <= REDUCE_LATENCY; stage++) begin
            square_sum_centered_q[stage] <= square_sum_centered_q[stage-1];
            square_sum_gamma_q[stage] <= square_sum_gamma_q[stage-1];
            square_sum_beta_q[stage] <= square_sum_beta_q[stage-1];
            square_sum_epsilon_q[stage] <= square_sum_epsilon_q[stage-1];
            square_sum_reciprocal_q[stage] <= square_sum_reciprocal_q[stage-1];
            square_sum_norm_control_q[stage] <= square_sum_norm_control_q[stage-1];
            square_sum_transaction_invalid_q[stage] <= square_sum_transaction_invalid_q[stage-1];
        end

        square_sum_entry_valid_q <= square_sum_valid;
        square_sum_entry_result_q <= square_sum_result;
        square_sum_entry_invalid_q <= square_sum_invalid;
        square_sum_entry_centered_q <= square_sum_centered_q[REDUCE_LATENCY];
        square_sum_entry_gamma_q <= square_sum_gamma_q[REDUCE_LATENCY];
        square_sum_entry_beta_q <= square_sum_beta_q[REDUCE_LATENCY];
        square_sum_entry_epsilon_q <= square_sum_epsilon_q[REDUCE_LATENCY];
        square_sum_entry_reciprocal_q <= square_sum_reciprocal_q[REDUCE_LATENCY];
        square_sum_entry_control_q <= square_sum_norm_control_q[REDUCE_LATENCY];
        square_sum_entry_transaction_invalid_q <= square_sum_transaction_invalid_q[REDUCE_LATENCY] || square_sum_invalid;

        variance_centered_q[0] <= square_sum_entry_centered_q;
        variance_gamma_q[0] <= square_sum_entry_gamma_q;
        variance_beta_q[0] <= square_sum_entry_beta_q;
        variance_epsilon_q[0] <= square_sum_entry_epsilon_q;
        variance_control_q[0] <= square_sum_entry_control_q;
        variance_transaction_invalid_q[0] <= square_sum_entry_transaction_invalid_q || square_sum_entry_invalid_q;
        for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
            variance_centered_q[stage] <= variance_centered_q[stage-1];
            variance_gamma_q[stage] <= variance_gamma_q[stage-1];
            variance_beta_q[stage] <= variance_beta_q[stage-1];
            variance_epsilon_q[stage] <= variance_epsilon_q[stage-1];
            variance_control_q[stage] <= variance_control_q[stage-1];
            variance_transaction_invalid_q[stage] <= variance_transaction_invalid_q[stage-1];
        end

        epsilon_centered_q[0] <= variance_centered_q[MUL_LATENCY-1];
        epsilon_gamma_q[0] <= variance_gamma_q[MUL_LATENCY-1];
        epsilon_beta_q[0] <= variance_beta_q[MUL_LATENCY-1];
        epsilon_control_q[0] <= variance_control_q[MUL_LATENCY-1];
        epsilon_transaction_invalid_q[0] <= variance_transaction_invalid_q[MUL_LATENCY-1] || variance_invalid;
        for (integer stage = 1; stage < ADD_LATENCY; stage++) begin
            epsilon_centered_q[stage] <= epsilon_centered_q[stage-1];
            epsilon_gamma_q[stage] <= epsilon_gamma_q[stage-1];
            epsilon_beta_q[stage] <= epsilon_beta_q[stage-1];
            epsilon_control_q[stage] <= epsilon_control_q[stage-1];
            epsilon_transaction_invalid_q[stage] <= epsilon_transaction_invalid_q[stage-1];
        end

        inverse_centered_q[0] <= epsilon_centered_q[ADD_LATENCY-1];
        inverse_gamma_q[0] <= epsilon_gamma_q[ADD_LATENCY-1];
        inverse_beta_q[0] <= epsilon_beta_q[ADD_LATENCY-1];
        inverse_control_q[0] <= epsilon_control_q[ADD_LATENCY-1];
        inverse_transaction_invalid_q[0] <= epsilon_transaction_invalid_q[ADD_LATENCY-1] || epsilon_invalid;
        for (integer stage = 1; stage < RSQRT_LATENCY; stage++) begin
            inverse_centered_q[stage] <= inverse_centered_q[stage-1];
            inverse_gamma_q[stage] <= inverse_gamma_q[stage-1];
            inverse_beta_q[stage] <= inverse_beta_q[stage-1];
            inverse_control_q[stage] <= inverse_control_q[stage-1];
            inverse_transaction_invalid_q[stage] <= inverse_transaction_invalid_q[stage-1];
        end

        inverse_broadcast_valid_q <= inverse_valid;
        inverse_broadcast_centered_q <= inverse_centered_q[RSQRT_LATENCY-1];
        inverse_broadcast_gamma_q <= inverse_gamma_q[RSQRT_LATENCY-1];
        inverse_broadcast_beta_q <= inverse_beta_q[RSQRT_LATENCY-1];
        inverse_broadcast_control_q <= inverse_control_q[RSQRT_LATENCY-1];
        inverse_broadcast_transaction_invalid_q <= inverse_transaction_invalid_q[RSQRT_LATENCY-1] || inverse_invalid;

        normalize_gamma_q[0] <= inverse_broadcast_gamma_q;
        normalize_beta_q[0] <= inverse_broadcast_beta_q;
        normalize_control_q[0] <= inverse_broadcast_control_q;
        normalize_transaction_invalid_q[0] <= inverse_broadcast_transaction_invalid_q;
        for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
            normalize_gamma_q[stage] <= normalize_gamma_q[stage-1];
            normalize_beta_q[stage] <= normalize_beta_q[stage-1];
            normalize_control_q[stage] <= normalize_control_q[stage-1];
            normalize_transaction_invalid_q[stage] <= normalize_transaction_invalid_q[stage-1];
        end

        scale_beta_q[0] <= normalize_beta_q[MUL_LATENCY-1];
        scale_control_q[0] <= normalize_control_q[MUL_LATENCY-1];
        scale_transaction_invalid_q[0] <= normalize_transaction_invalid_q[MUL_LATENCY-1] || (|normalize_invalid_comb);
        for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
            scale_beta_q[stage] <= scale_beta_q[stage-1];
            scale_control_q[stage] <= scale_control_q[stage-1];
            scale_transaction_invalid_q[stage] <= scale_transaction_invalid_q[stage-1];
        end

        offset_control_q[0] <= scale_control_q[MUL_LATENCY-1];
        offset_transaction_invalid_q[0] <= scale_transaction_invalid_q[MUL_LATENCY-1] || (|scale_invalid_comb);
        for (integer stage = 1; stage < ADD_LATENCY; stage++) begin
            offset_control_q[stage] <= offset_control_q[stage-1];
            offset_transaction_invalid_q[stage] <= offset_transaction_invalid_q[stage-1];
        end
    end

    always_comb begin
        valid_o = valid_pipe_q[NORM_LATENCY];
        control_o = offset_control_q[ADD_LATENCY-1];
        empty_o = !(|control_o.lane_mask);
        for (integer lane = 0; lane < LANES; lane++) begin
            if (control_o.lane_mask[lane] && !empty_o) begin
                data_o[lane*32 +: 32] = offset_result[lane];
                invalid_o[lane] = offset_invalid[lane] ||
                                  offset_transaction_invalid_q[ADD_LATENCY-1];
            end else begin
                data_o[lane*32 +: 32] = 32'd0;
                invalid_o[lane] = 1'b0;
            end
        end
    end

    logic lane_valid_mismatch;
    logic internal_status_unused;
    always_comb begin
        lane_valid_mismatch = 1'b0;
        for (integer lane = 1; lane < LANES; lane++) begin
            lane_valid_mismatch |= center_valid[lane] != center_valid[0];
            lane_valid_mismatch |= square_valid[lane] != square_valid[0];
            lane_valid_mismatch |= normalize_valid[lane] != normalize_valid[0];
            lane_valid_mismatch |= scale_valid[lane] != scale_valid[0];
            lane_valid_mismatch |= offset_valid[lane] != offset_valid[0];
        end
        internal_status_unused = lane_valid_mismatch || input_sum_empty ||
            square_sum_empty || (|input_sum_control_o) ||
            (|square_sum_control_o) || offset_valid[0];
    end

endmodule

`default_nettype wire
