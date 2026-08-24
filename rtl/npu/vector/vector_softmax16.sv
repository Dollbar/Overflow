`timescale 1ns/1ps
`default_nettype none

// 16-lane FP32 Softmax pipeline.
//
// The implementation accepts one vector per cycle and has a fixed 75-cycle
// input-to-output latency. Masked lanes do not participate in MAX or SUM and
// are forced to zero at the output. If any active input lane is invalid, every
// active output lane is marked invalid while the numerical pipeline continues.
module vector_softmax16 #(
    parameter bit FTZ = 1'b0
) (
    input  logic                                  clk_i,
    input  logic                                  rst_i,
    input  logic                                  clear_i,
    input  logic                                  valid_i,
    input  vector_pkg::vector_fp32_data_t         data_i,
    input  vector_pkg::vector_lane_mask_t         invalid_i,
    input  vector_pkg::vector_softmax_control_t   control_i,
    output logic                                  valid_o,
    output vector_pkg::vector_fp32_data_t         data_o,
    output vector_pkg::vector_lane_mask_t         invalid_o,
    output logic                                  empty_o,
    output vector_pkg::vector_softmax_control_t   control_o
);

    localparam int unsigned LANES = vector_pkg::VECTOR_LANES;
    localparam int unsigned MAX_LATENCY = 4;
    localparam int unsigned ADD_LATENCY = 6;
    localparam int unsigned EXP_LATENCY = 16;
    localparam int unsigned SUM_LATENCY = 24;
    localparam int unsigned RECIP_LATENCY = 11;
    localparam int unsigned MUL_LATENCY = 13;
    localparam logic [31:0] FP32_NEGATIVE_INFINITY = 32'hff800000;

    logic [31:0] max_input [0:LANES-1];
    logic [31:0] max_l1_comb [0:7];
    logic [31:0] max_l2_comb [0:3];
    logic [31:0] max_l3_comb [0:1];
    logic [31:0] max_l4_comb;
    logic [31:0] max_l1_q [0:7];
    logic [31:0] max_l2_q [0:3];
    logic [31:0] max_l3_q [0:1];
    logic [31:0] max_broadcast_q [0:LANES-1];
    logic max_valid_q [0:MAX_LATENCY-1];
    vector_pkg::vector_fp32_data_t max_data_q [0:MAX_LATENCY-1];
    vector_pkg::vector_softmax_control_t max_control_q [0:MAX_LATENCY-1];
    logic max_transaction_invalid_q [0:MAX_LATENCY-1];
    logic max_empty_q [0:MAX_LATENCY-1];

    logic sub_valid [0:LANES-1];
    logic [31:0] sub_result [0:LANES-1];
    logic sub_invalid [0:LANES-1];
    vector_pkg::vector_softmax_control_t sub_control_q [0:ADD_LATENCY-1];
    logic sub_transaction_invalid_q [0:ADD_LATENCY-1];
    logic sub_empty_q [0:ADD_LATENCY-1];
    logic sub_shared_valid_q [0:ADD_LATENCY-1];

    logic exp_valid [0:LANES-1];
    logic [31:0] exp_result [0:LANES-1];
    logic exp_invalid [0:LANES-1];
    vector_pkg::vector_fp32_data_t exp_data_comb;
    vector_pkg::vector_lane_mask_t exp_invalid_comb;
    vector_pkg::vector_softmax_control_t exp_control_q [0:EXP_LATENCY-1];
    logic exp_transaction_invalid_q [0:EXP_LATENCY-1];
    logic exp_empty_q [0:EXP_LATENCY-1];
    logic exp_shared_valid_q [0:EXP_LATENCY-1];

    vector_pkg::vector_reduce_control_t sum_control_i;
    logic sum_valid;
    logic [31:0] sum_result;
    logic sum_invalid;
    logic sum_empty;
    vector_pkg::vector_reduce_control_t sum_control_o;
    vector_pkg::vector_fp32_data_t sum_exp_data_q [0:SUM_LATENCY];
    vector_pkg::vector_lane_mask_t sum_exp_invalid_q [0:SUM_LATENCY];
    vector_pkg::vector_softmax_control_t sum_softmax_control_q [0:SUM_LATENCY];
    logic sum_transaction_invalid_q [0:SUM_LATENCY];
    logic sum_empty_q [0:SUM_LATENCY];

    logic recip_valid;
    logic [31:0] recip_result;
    logic recip_invalid;
    vector_pkg::vector_fp32_data_t recip_exp_data_q [0:RECIP_LATENCY-1];
    vector_pkg::vector_lane_mask_t recip_exp_invalid_q [0:RECIP_LATENCY-1];
    vector_pkg::vector_softmax_control_t recip_control_q [0:RECIP_LATENCY-1];
    logic recip_transaction_invalid_q [0:RECIP_LATENCY-1];
    logic recip_empty_q [0:RECIP_LATENCY-1];
    logic recip_shared_valid_q [0:RECIP_LATENCY-1];
    logic recip_broadcast_valid_q;
    logic [31:0] recip_broadcast_q [0:LANES-1];
    vector_pkg::vector_fp32_data_t recip_broadcast_exp_data_q;
    vector_pkg::vector_lane_mask_t recip_broadcast_exp_invalid_q;
    vector_pkg::vector_softmax_control_t recip_broadcast_control_q;
    logic recip_broadcast_transaction_invalid_q;
    logic recip_broadcast_empty_q;

    logic mul_valid [0:LANES-1];
    logic [31:0] mul_result [0:LANES-1];
    logic mul_invalid [0:LANES-1];
    vector_pkg::vector_softmax_control_t mul_control_q [0:MUL_LATENCY-1];
    logic mul_transaction_invalid_q [0:MUL_LATENCY-1];
    logic mul_empty_q [0:MUL_LATENCY-1];
    logic mul_shared_valid_q [0:MUL_LATENCY-1];

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
        for (integer lane = 0; lane < LANES; lane++) begin
            max_input[lane] = control_i.lane_mask[lane] ?
                              data_i[lane*32 +: 32] : FP32_NEGATIVE_INFINITY;
            exp_data_comb[lane*32 +: 32] = exp_result[lane];
            exp_invalid_comb[lane] = exp_invalid[lane];
        end
        for (integer pair = 0; pair < 8; pair++) begin
            max_l1_comb[pair] = fp32_maximum_value(
                max_input[pair*2], max_input[pair*2+1]);
        end
        for (integer pair = 0; pair < 4; pair++) begin
            max_l2_comb[pair] = fp32_maximum_value(
                max_l1_q[pair*2], max_l1_q[pair*2+1]);
        end
        for (integer pair = 0; pair < 2; pair++) begin
            max_l3_comb[pair] = fp32_maximum_value(
                max_l2_q[pair*2], max_l2_q[pair*2+1]);
        end
        max_l4_comb = fp32_maximum_value(max_l3_q[0], max_l3_q[1]);

        sum_control_i = {exp_control_q[EXP_LATENCY-1],
                         vector_pkg::VECTOR_REDUCE_SUM};
    end

    generate
        for (genvar lane = 0; lane < LANES; lane++) begin : g_lane_datapath
            vector_softmax_max_broadcast_slice u_max_broadcast (
                .clk_i(clk_i), .maximum_i(max_l4_comb),
                .maximum_o(max_broadcast_q[lane]));

            fp32_add_pipeline #(.FTZ(FTZ)) u_subtract_max (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(max_valid_q[MAX_LATENCY-1]),
                .a_i(max_data_q[MAX_LATENCY-1][lane*32 +: 32]),
                .b_i({~max_broadcast_q[lane][31],
                      max_broadcast_q[lane][30:0]}),
                .invalid_i({max_transaction_invalid_q[MAX_LATENCY-1],
                            max_transaction_invalid_q[MAX_LATENCY-1]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(sub_valid[lane]),
                .result_o(sub_result[lane]), .invalid_o(sub_invalid[lane]));

            fp32_exp_approx u_exp (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(sub_shared_valid_q[ADD_LATENCY-1]),
                .data_i(sub_result[lane]),
                .invalid_i(sub_invalid[lane]), .valid_o(exp_valid[lane]),
                .result_o(exp_result[lane]), .invalid_o(exp_invalid[lane]));

            fp32_mul_pipeline #(.FTZ(FTZ)) u_normalize (
                .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
                .valid_i(recip_broadcast_valid_q),
                .a_i(recip_broadcast_exp_data_q[lane*32 +: 32]),
                .b_i(recip_broadcast_q[lane]),
                .invalid_i({recip_broadcast_transaction_invalid_q,
                            recip_broadcast_exp_invalid_q[lane]}),
                .rounding_i(fp8_pkg::RNE), .valid_o(mul_valid[lane]),
                .result_o(mul_result[lane]), .invalid_o(mul_invalid[lane]));

            vector_softmax_recip_broadcast_slice u_recip_broadcast (
                .clk_i(clk_i), .reciprocal_i(recip_result),
                .reciprocal_o(recip_broadcast_q[lane]));
        end
    endgenerate

    vector_reduce16 #(.FTZ(FTZ)) u_sum (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .valid_i(exp_shared_valid_q[EXP_LATENCY-1]), .data_i(exp_data_comb),
        .invalid_i(exp_invalid_comb), .control_i(sum_control_i),
        .valid_o(sum_valid), .result_o(sum_result), .invalid_o(sum_invalid),
        .empty_o(sum_empty), .control_o(sum_control_o));

    fp32_recip_pipeline u_reciprocal (
        .clk_i(clk_i), .rst_i(1'b0), .clear_i(1'b0),
        .valid_i(sum_valid), .data_i(sum_result), .invalid_i(sum_invalid),
        .valid_o(recip_valid), .result_o(recip_result),
        .invalid_o(recip_invalid));

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            recip_broadcast_valid_q <= 1'b0;
            for (integer stage = 0; stage < MAX_LATENCY; stage++) begin
                max_valid_q[stage] <= 1'b0;
            end
            for (integer stage = 0; stage < ADD_LATENCY; stage++) begin
                sub_shared_valid_q[stage] <= 1'b0;
            end
            for (integer stage = 0; stage < EXP_LATENCY; stage++) begin
                exp_shared_valid_q[stage] <= 1'b0;
            end
            for (integer stage = 0; stage < RECIP_LATENCY; stage++) begin
                recip_shared_valid_q[stage] <= 1'b0;
            end
            for (integer stage = 0; stage < MUL_LATENCY; stage++) begin
                mul_shared_valid_q[stage] <= 1'b0;
            end
        end else begin
            recip_broadcast_valid_q <= recip_shared_valid_q[RECIP_LATENCY-1];
            max_valid_q[0] <= valid_i;
            for (integer stage = 1; stage < MAX_LATENCY; stage++) begin
                max_valid_q[stage] <= max_valid_q[stage-1];
            end
            sub_shared_valid_q[0] <= max_valid_q[MAX_LATENCY-1];
            for (integer stage = 1; stage < ADD_LATENCY; stage++) begin
                sub_shared_valid_q[stage] <= sub_shared_valid_q[stage-1];
            end
            exp_shared_valid_q[0] <= sub_shared_valid_q[ADD_LATENCY-1];
            for (integer stage = 1; stage < EXP_LATENCY; stage++) begin
                exp_shared_valid_q[stage] <= exp_shared_valid_q[stage-1];
            end
            recip_shared_valid_q[0] <= sum_valid;
            for (integer stage = 1; stage < RECIP_LATENCY; stage++) begin
                recip_shared_valid_q[stage] <= recip_shared_valid_q[stage-1];
            end
            mul_shared_valid_q[0] <= recip_broadcast_valid_q;
            for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
                mul_shared_valid_q[stage] <= mul_shared_valid_q[stage-1];
            end
        end

        for (integer pair = 0; pair < 8; pair++) max_l1_q[pair] <= max_l1_comb[pair];
        for (integer pair = 0; pair < 4; pair++) max_l2_q[pair] <= max_l2_comb[pair];
        for (integer pair = 0; pair < 2; pair++) max_l3_q[pair] <= max_l3_comb[pair];
        max_data_q[0] <= data_i;
        max_control_q[0] <= control_i;
        max_transaction_invalid_q[0] <= |(invalid_i & control_i.lane_mask);
        max_empty_q[0] <= !(|control_i.lane_mask);
        for (integer stage = 1; stage < MAX_LATENCY; stage++) begin
            max_data_q[stage] <= max_data_q[stage-1];
            max_control_q[stage] <= max_control_q[stage-1];
            max_transaction_invalid_q[stage] <= max_transaction_invalid_q[stage-1];
            max_empty_q[stage] <= max_empty_q[stage-1];
        end

        sub_control_q[0] <= max_control_q[MAX_LATENCY-1];
        sub_transaction_invalid_q[0] <= max_transaction_invalid_q[MAX_LATENCY-1];
        sub_empty_q[0] <= max_empty_q[MAX_LATENCY-1];
        for (integer stage = 1; stage < ADD_LATENCY; stage++) begin
            sub_control_q[stage] <= sub_control_q[stage-1];
            sub_transaction_invalid_q[stage] <= sub_transaction_invalid_q[stage-1];
            sub_empty_q[stage] <= sub_empty_q[stage-1];
        end

        exp_control_q[0] <= sub_control_q[ADD_LATENCY-1];
        exp_transaction_invalid_q[0] <= sub_transaction_invalid_q[ADD_LATENCY-1];
        exp_empty_q[0] <= sub_empty_q[ADD_LATENCY-1];
        for (integer stage = 1; stage < EXP_LATENCY; stage++) begin
            exp_control_q[stage] <= exp_control_q[stage-1];
            exp_transaction_invalid_q[stage] <= exp_transaction_invalid_q[stage-1];
            exp_empty_q[stage] <= exp_empty_q[stage-1];
        end

        sum_exp_data_q[0] <= exp_data_comb;
        sum_exp_invalid_q[0] <= exp_invalid_comb;
        sum_softmax_control_q[0] <= exp_control_q[EXP_LATENCY-1];
        sum_transaction_invalid_q[0] <= exp_transaction_invalid_q[EXP_LATENCY-1];
        sum_empty_q[0] <= exp_empty_q[EXP_LATENCY-1];
        for (integer stage = 1; stage <= SUM_LATENCY; stage++) begin
            sum_exp_data_q[stage] <= sum_exp_data_q[stage-1];
            sum_exp_invalid_q[stage] <= sum_exp_invalid_q[stage-1];
            sum_softmax_control_q[stage] <= sum_softmax_control_q[stage-1];
            sum_transaction_invalid_q[stage] <= sum_transaction_invalid_q[stage-1];
            sum_empty_q[stage] <= sum_empty_q[stage-1];
        end

        recip_exp_data_q[0] <= sum_exp_data_q[SUM_LATENCY];
        recip_exp_invalid_q[0] <= sum_exp_invalid_q[SUM_LATENCY];
        recip_control_q[0] <= sum_softmax_control_q[SUM_LATENCY];
        recip_transaction_invalid_q[0] <= sum_transaction_invalid_q[SUM_LATENCY];
        recip_empty_q[0] <= sum_empty_q[SUM_LATENCY];
        for (integer stage = 1; stage < RECIP_LATENCY; stage++) begin
            recip_exp_data_q[stage] <= recip_exp_data_q[stage-1];
            recip_exp_invalid_q[stage] <= recip_exp_invalid_q[stage-1];
            recip_control_q[stage] <= recip_control_q[stage-1];
            recip_transaction_invalid_q[stage] <= recip_transaction_invalid_q[stage-1];
            recip_empty_q[stage] <= recip_empty_q[stage-1];
        end

        recip_broadcast_exp_data_q <= recip_exp_data_q[RECIP_LATENCY-1];
        recip_broadcast_exp_invalid_q <= recip_exp_invalid_q[RECIP_LATENCY-1];
        recip_broadcast_control_q <= recip_control_q[RECIP_LATENCY-1];
        recip_broadcast_transaction_invalid_q <= recip_invalid ||
            recip_transaction_invalid_q[RECIP_LATENCY-1];
        recip_broadcast_empty_q <= recip_empty_q[RECIP_LATENCY-1];

        mul_control_q[0] <= recip_broadcast_control_q;
        mul_transaction_invalid_q[0] <= recip_broadcast_transaction_invalid_q;
        mul_empty_q[0] <= recip_broadcast_empty_q;
        for (integer stage = 1; stage < MUL_LATENCY; stage++) begin
            mul_control_q[stage] <= mul_control_q[stage-1];
            mul_transaction_invalid_q[stage] <= mul_transaction_invalid_q[stage-1];
            mul_empty_q[stage] <= mul_empty_q[stage-1];
        end
    end

    always_comb begin
        valid_o = mul_shared_valid_q[MUL_LATENCY-1];
        control_o = mul_control_q[MUL_LATENCY-1];
        empty_o = mul_empty_q[MUL_LATENCY-1];
        for (integer lane = 0; lane < LANES; lane++) begin
            if (control_o.lane_mask[lane] && !empty_o) begin
                data_o[lane*32 +: 32] = mul_result[lane];
                invalid_o[lane] = mul_invalid[lane] ||
                                  mul_transaction_invalid_q[MUL_LATENCY-1];
            end else begin
                data_o[lane*32 +: 32] = 32'd0;
                invalid_o[lane] = 1'b0;
            end
        end
    end

    // All lanes share the same fixed-latency valid pipeline. These reductions
    // make divergence visible to lint/formal without adding functional control.
    logic lane_valid_mismatch;
    logic internal_status_unused;
    always_comb begin
        lane_valid_mismatch = 1'b0;
        for (integer lane = 1; lane < LANES; lane++) begin
            lane_valid_mismatch |= (sub_valid[lane] != sub_valid[0]);
            lane_valid_mismatch |= (exp_valid[lane] != exp_valid[0]);
            lane_valid_mismatch |= (mul_valid[lane] != mul_valid[0]);
        end
        internal_status_unused = lane_valid_mismatch || sum_empty ||
                                 (|sum_control_o) || recip_valid;
    end

endmodule

`default_nettype wire
