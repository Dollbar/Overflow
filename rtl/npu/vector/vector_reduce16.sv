`timescale 1ns/1ps
`default_nettype none

// 16-to-1 FP32 SUM/MAX归约树。四级平衡树，固定24周期延迟，每周期接收一个向量。
module vector_reduce16 #(
    parameter bit FTZ = 1'b0
) (
    input  logic                              clk_i,
    input  logic                              rst_i,
    input  logic                              clear_i,
    input  logic                              valid_i,
    input  vector_pkg::vector_fp32_data_t     data_i,
    input  vector_pkg::vector_lane_mask_t     invalid_i,
    input  vector_pkg::vector_reduce_control_t control_i,
    output logic                              valid_o,
    output logic [31:0]                       result_o,
    output logic                              invalid_o,
    output logic                              empty_o,
    output vector_pkg::vector_reduce_control_t control_o
);

    localparam int unsigned LANES = vector_pkg::VECTOR_LANES;
    localparam int unsigned LATENCY = 24;
    localparam int unsigned MAX_DELAY = 20;
    localparam int unsigned CONTROL_WIDTH = 26;
    localparam int unsigned CONTROL_OPERATION_BIT = 0;
    localparam int unsigned CONTROL_LANE_MASK_LSB = 10;
    localparam logic [31:0] FP32_NEGATIVE_INF = 32'hff800000;

    vector_pkg::vector_fp32_data_t sum_input_entry_q;
    vector_pkg::vector_fp32_data_t max_input_entry_q;
    vector_pkg::vector_lane_mask_t sum_invalid_entry_q;
    logic valid_entry_q;
    logic [31:0] sum_input_lane [0:LANES-1];
    logic [31:0] max_input_lane [0:LANES-1];
    logic sum_input_invalid_lane [0:LANES-1];

    logic [31:0] sum_l1 [0:7];
    logic [31:0] sum_l2 [0:3];
    logic [31:0] sum_l3 [0:1];
    logic [31:0] sum_l4;
    logic sum_invalid_l1 [0:7];
    logic sum_invalid_l2 [0:3];
    logic sum_invalid_l3 [0:1];
    logic sum_invalid_l4;
    logic sum_valid_l1 [0:7];
    logic sum_valid_l2 [0:3];
    logic sum_valid_l3 [0:1];
    logic sum_valid_l4;

    logic [31:0] max_l1_comb [0:7];
    logic [31:0] max_l2_comb [0:3];
    logic [31:0] max_l3_comb [0:1];
    logic [31:0] max_l4_comb;
    logic [31:0] max_l1_q [0:7];
    logic [31:0] max_l2_q [0:3];
    logic [31:0] max_l3_q [0:1];
    logic [31:0] max_l4_q;
    logic [31:0] max_delay_q [0:MAX_DELAY-1];

    logic valid_delay_q [0:LATENCY];
    logic masked_invalid_delay_q [0:LATENCY];
    logic [CONTROL_WIDTH-1:0] control_delay_q [0:LATENCY];

    function automatic logic [31:0] fp32_maximum_value(
        input logic [31:0] a,
        input logic [31:0] b
    );
        logic a_nan;
        logic b_nan;
        logic a_zero;
        logic b_zero;
        logic a_less;
        begin
            a_nan = (a[30:23] == 8'hff) && (a[22:0] != 23'd0);
            b_nan = (b[30:23] == 8'hff) && (b[22:0] != 23'd0);
            a_zero = (a[30:0] == 31'd0);
            b_zero = (b[30:0] == 31'd0);
            a_less = 1'b0;
            if ((a != b) && !(a_zero && b_zero)) begin
                if (a[31] != b[31]) begin
                    a_less = a[31];
                end else if (!a[31]) begin
                    a_less = a[30:0] < b[30:0];
                end else begin
                    a_less = a[30:0] > b[30:0];
                end
            end

            if (a_nan && b_nan) begin
                fp32_maximum_value = 32'h7fc00000;
            end else if (a_nan) begin
                fp32_maximum_value = b;
            end else if (b_nan) begin
                fp32_maximum_value = a;
            end else if (a_zero && b_zero) begin
                fp32_maximum_value = {a[31] & b[31], 31'd0};
            end else begin
                fp32_maximum_value = a_less ? b : a;
            end
        end
    endfunction

    always_comb begin
        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            sum_input_lane[lane_index] =
                sum_input_entry_q[lane_index*32 +: 32];
            max_input_lane[lane_index] =
                max_input_entry_q[lane_index*32 +: 32];
            sum_input_invalid_lane[lane_index] = sum_invalid_entry_q[lane_index];
        end
    end

    generate
        for (genvar pair = 0; pair < 8; pair++) begin : g_sum_l1
            fp32_add_pipeline #(.FTZ(FTZ)) u_add (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0), .valid_i(valid_entry_q),
                .a_i(sum_input_lane[pair*2]), .b_i(sum_input_lane[pair*2+1]),
                .invalid_i({sum_input_invalid_lane[pair*2+1],
                            sum_input_invalid_lane[pair*2]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(sum_valid_l1[pair]),
                .result_o(sum_l1[pair]), .invalid_o(sum_invalid_l1[pair]));
        end
        for (genvar pair = 0; pair < 4; pair++) begin : g_sum_l2
            fp32_add_pipeline #(.FTZ(FTZ)) u_add (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(sum_valid_l1[0]),
                .a_i(sum_l1[pair*2]), .b_i(sum_l1[pair*2+1]),
                .invalid_i({sum_invalid_l1[pair*2+1], sum_invalid_l1[pair*2]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(sum_valid_l2[pair]),
                .result_o(sum_l2[pair]), .invalid_o(sum_invalid_l2[pair]));
        end
        for (genvar pair = 0; pair < 2; pair++) begin : g_sum_l3
            fp32_add_pipeline #(.FTZ(FTZ)) u_add (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(sum_valid_l2[0]),
                .a_i(sum_l2[pair*2]), .b_i(sum_l2[pair*2+1]),
                .invalid_i({sum_invalid_l2[pair*2+1], sum_invalid_l2[pair*2]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(sum_valid_l3[pair]),
                .result_o(sum_l3[pair]), .invalid_o(sum_invalid_l3[pair]));
        end
    endgenerate

    fp32_add_pipeline #(.FTZ(FTZ)) u_sum_l4 (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(sum_valid_l3[0]), .a_i(sum_l3[0]), .b_i(sum_l3[1]),
        .invalid_i({sum_invalid_l3[1], sum_invalid_l3[0]}),
        .rounding_i(fp8_pkg::RNE), .valid_o(sum_valid_l4),
        .result_o(sum_l4), .invalid_o(sum_invalid_l4));

    generate
        for (genvar pair = 0; pair < 8; pair++) begin : g_max_l1
            always_comb begin
                max_l1_comb[pair] = fp32_maximum_value(
                    max_input_lane[pair*2], max_input_lane[pair*2+1]);
            end
        end
        for (genvar pair = 0; pair < 4; pair++) begin : g_max_l2
            always_comb begin
                max_l2_comb[pair] = fp32_maximum_value(
                    max_l1_q[pair*2], max_l1_q[pair*2+1]);
            end
        end
        for (genvar pair = 0; pair < 2; pair++) begin : g_max_l3
            always_comb begin
                max_l3_comb[pair] = fp32_maximum_value(
                    max_l2_q[pair*2], max_l2_q[pair*2+1]);
            end
        end
    endgenerate

    always_comb begin
        max_l4_comb = fp32_maximum_value(max_l3_q[0], max_l3_q[1]);
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            valid_entry_q <= 1'b0;
            for (integer stage_index = 0; stage_index <= LATENCY; stage_index++) begin
                valid_delay_q[stage_index] <= 1'b0;
            end
        end else begin
            valid_entry_q <= valid_i;
            valid_delay_q[0] <= valid_i;
            for (integer stage_index = 1; stage_index <= LATENCY; stage_index++) begin
                valid_delay_q[stage_index] <= valid_delay_q[stage_index-1];
            end
        end

        for (integer lane_index = 0; lane_index < LANES; lane_index++) begin
            sum_input_entry_q[lane_index*32 +: 32] <=
                control_i.lane_mask[lane_index] ?
                    data_i[lane_index*32 +: 32] : 32'd0;
            max_input_entry_q[lane_index*32 +: 32] <=
                control_i.lane_mask[lane_index] ?
                    data_i[lane_index*32 +: 32] : FP32_NEGATIVE_INF;
            sum_invalid_entry_q[lane_index] <=
                control_i.lane_mask[lane_index] && invalid_i[lane_index];
        end
        control_delay_q[0] <= control_i;
        masked_invalid_delay_q[0] <= |(invalid_i & control_i.lane_mask);
        for (integer stage_index = 1; stage_index <= LATENCY; stage_index++) begin
            control_delay_q[stage_index] <= control_delay_q[stage_index-1];
            masked_invalid_delay_q[stage_index] <=
                masked_invalid_delay_q[stage_index-1];
        end

        for (integer index = 0; index < 8; index++) max_l1_q[index] <= max_l1_comb[index];
        for (integer index = 0; index < 4; index++) max_l2_q[index] <= max_l2_comb[index];
        for (integer index = 0; index < 2; index++) max_l3_q[index] <= max_l3_comb[index];
        max_l4_q <= max_l4_comb;
        max_delay_q[0] <= max_l4_q;
        for (integer stage_index = 1; stage_index < MAX_DELAY; stage_index++) begin
            max_delay_q[stage_index] <= max_delay_q[stage_index-1];
        end
    end

    always_comb begin
        valid_o = valid_delay_q[LATENCY] &&
                  ((control_delay_q[LATENCY][CONTROL_OPERATION_BIT] ==
                    vector_pkg::VECTOR_REDUCE_MAX) || sum_valid_l4);
        control_o = control_delay_q[LATENCY];
        empty_o = !(|control_delay_q[LATENCY][CONTROL_LANE_MASK_LSB +: LANES]);
        if (empty_o) begin
            result_o = 32'd0;
            invalid_o = 1'b0;
        end else if (control_delay_q[LATENCY][CONTROL_OPERATION_BIT] ==
                     vector_pkg::VECTOR_REDUCE_MAX) begin
            result_o = max_delay_q[MAX_DELAY-1];
            invalid_o = masked_invalid_delay_q[LATENCY];
        end else begin
            result_o = sum_l4;
            invalid_o = sum_invalid_l4;
        end
    end

endmodule

`default_nettype wire
