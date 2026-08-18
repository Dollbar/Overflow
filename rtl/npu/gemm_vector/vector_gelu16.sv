`timescale 1ns/1ps
`default_nettype none

// Full-throughput 16-lane QuickGELU pipeline: x * sigmoid(1.702 * x).
// Masked lanes are forced to zero and do not report invalid status.
module vector_gelu16 #(
    parameter bit FTZ = 1'b0
) (
    input  logic                                      clk_i,
    input  logic                                      rst_i,
    input  logic                                      clear_i,
    input  logic                                      valid_i,
    input  vector_pkg::vector_fp32_data_t             data_i,
    input  vector_pkg::vector_lane_mask_t             invalid_i,
    input  vector_pkg::vector_activation_control_t    control_i,
    output logic                                      valid_o,
    output vector_pkg::vector_fp32_data_t             data_o,
    output vector_pkg::vector_lane_mask_t             invalid_o,
    output logic                                      empty_o,
    output vector_pkg::vector_activation_control_t    control_o
);

    localparam int unsigned LANES = vector_pkg::VECTOR_LANES;
    localparam int unsigned MUL_LATENCY = 13;
    localparam int unsigned SIGMOID_LATENCY = 44;
    localparam int unsigned GELU_LATENCY =
        MUL_LATENCY + SIGMOID_LATENCY + MUL_LATENCY;
    localparam int unsigned PRE_FINAL_LATENCY =
        MUL_LATENCY + SIGMOID_LATENCY;
    localparam int unsigned CONTROL_WIDTH = 25;
    localparam logic [31:0] FP32_QUICK_GELU_SCALE = 32'h3fd9db23;
    localparam logic [31:0] FP32_NEGATIVE_INFINITY = 32'hff800000;

    logic scale_valid [0:LANES-1];
    logic [31:0] scale_result [0:LANES-1];
    logic scale_invalid [0:LANES-1];
    logic sigmoid_valid [0:LANES-1];
    logic [31:0] sigmoid_result [0:LANES-1];
    logic sigmoid_invalid [0:LANES-1];
    logic final_valid [0:LANES-1];
    logic [31:0] final_result [0:LANES-1];
    logic final_invalid [0:LANES-1];
    logic [31:0] original_data_q [0:LANES-1][0:PRE_FINAL_LATENCY];
    logic [31:0] final_x_operand [0:LANES-1];
    logic [CONTROL_WIDTH-1:0] pre_final_control_q [0:PRE_FINAL_LATENCY];
    logic [CONTROL_WIDTH-1:0] final_control_q [0:MUL_LATENCY-1];
    logic [GELU_LATENCY:0] valid_pipe_q;

    generate
        for (genvar lane = 0; lane < LANES; lane++) begin : g_lane
            always_comb begin
                final_x_operand[lane] = original_data_q[lane][PRE_FINAL_LATENCY];
                if (original_data_q[lane][PRE_FINAL_LATENCY] ==
                    FP32_NEGATIVE_INFINITY) begin
                    final_x_operand[lane] = 32'd0;
                end
            end

            fp32_mul_pipeline #(.FTZ(FTZ)) u_scale (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(valid_i), .a_i(data_i[lane*32 +: 32]),
                .b_i(FP32_QUICK_GELU_SCALE),
                .invalid_i({invalid_i[lane], invalid_i[lane]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(scale_valid[lane]),
                .result_o(scale_result[lane]), .invalid_o(scale_invalid[lane])
            );

            fp32_sigmoid_pipeline #(.FTZ(FTZ)) u_sigmoid (
                .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
                .valid_i(scale_valid[lane]), .data_i(scale_result[lane]),
                .invalid_i(scale_invalid[lane]), .valid_o(sigmoid_valid[lane]),
                .result_o(sigmoid_result[lane]),
                .invalid_o(sigmoid_invalid[lane])
            );

            fp32_mul_pipeline #(.FTZ(FTZ)) u_apply (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(sigmoid_valid[lane]), .a_i(final_x_operand[lane]),
                .b_i(sigmoid_result[lane]),
                .invalid_i({sigmoid_invalid[lane], sigmoid_invalid[lane]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(final_valid[lane]),
                .result_o(final_result[lane]), .invalid_o(final_invalid[lane])
            );
        end
    endgenerate

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_pipe_q <= '0;
        end else begin
            valid_pipe_q[0] <= valid_i;
            for (integer stage = 1; stage <= GELU_LATENCY; stage++) begin
                valid_pipe_q[stage] <= valid_pipe_q[stage-1];
            end
        end

        for (integer lane = 0; lane < LANES; lane++) begin
            original_data_q[lane][0] <= data_i[lane*32 +: 32];
            for (integer stage = 1; stage <= PRE_FINAL_LATENCY; stage++) begin
                original_data_q[lane][stage] <= original_data_q[lane][stage-1];
            end
        end

        pre_final_control_q[0] <= control_i;
        for (integer stage = 1; stage <= PRE_FINAL_LATENCY; stage++) begin
            pre_final_control_q[stage] <= pre_final_control_q[stage-1];
        end
        final_control_q[0] <= pre_final_control_q[PRE_FINAL_LATENCY];
        for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
            final_control_q[stage] <= final_control_q[stage-1];
        end
    end

    always_comb begin
        valid_o = valid_pipe_q[GELU_LATENCY];
        control_o = final_control_q[MUL_LATENCY-1];
        empty_o = !(|control_o.lane_mask);
        for (integer lane = 0; lane < LANES; lane++) begin
            if (control_o.lane_mask[lane] && !empty_o) begin
                data_o[lane*32 +: 32] = final_result[lane];
                invalid_o[lane] = final_invalid[lane];
            end else begin
                data_o[lane*32 +: 32] = 32'd0;
                invalid_o[lane] = 1'b0;
            end
        end
    end

    logic lane_valid_mismatch;
    always_comb begin
        lane_valid_mismatch = 1'b0;
        for (integer lane = 1; lane < LANES; lane++) begin
            lane_valid_mismatch |= scale_valid[lane] != scale_valid[0];
            lane_valid_mismatch |= sigmoid_valid[lane] != sigmoid_valid[0];
            lane_valid_mismatch |= final_valid[lane] != final_valid[0];
        end
    end

endmodule

`default_nettype wire
