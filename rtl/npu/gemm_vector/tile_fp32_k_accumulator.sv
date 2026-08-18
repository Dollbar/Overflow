`timescale 1ns/1ps
`default_nettype none

module tile_fp32_k_accumulator #(
    parameter bit FTZ = 1'b0,
    parameter int unsigned COMMAND_DEPTH = 4,
    parameter int unsigned RESULT_DEPTH = 32,
    parameter int unsigned ACCUM_WIDTH = 85
) (
    input  logic                    clk_i,
    input  logic                    rst_i,
    input  logic                    clear_i,
    input  logic                    start_i,
    output logic                    start_ready_o,
    input  logic              [4:0] rows_i,
    input  logic             [15:0] k_blocks_i,
    input  fp8_pkg::fp8_rounding_e rounding_i,
    input  logic                    partial_valid_i,
    output logic                    partial_ready_o,
    input  logic           [1103:0] partial_exact_i,
    input  logic             [31:0] partial_special_i,
    input  logic             [31:0] partial_zero_sign_i,
    input  logic             [15:0] partial_invalid_i,
    input  logic                    result_ready_i,
    output logic                    result_valid_o,
    output logic            [511:0] result_data_o,
    output logic             [15:0] result_invalid_o,
    output logic                    busy_o,
    output logic                    block_done_o,
    output logic                    done_o,
    output logic                    protocol_error_o
);

    localparam int unsigned COMMAND_POINTER_WIDTH =
        (COMMAND_DEPTH <= 1) ? 1 : $clog2(COMMAND_DEPTH);
    localparam int unsigned COMMAND_LEVEL_WIDTH = $clog2(COMMAND_DEPTH + 1);
    localparam int unsigned RESULT_POINTER_WIDTH =
        (RESULT_DEPTH <= 1) ? 1 : $clog2(RESULT_DEPTH);
    localparam int unsigned RESULT_LEVEL_WIDTH = $clog2(RESULT_DEPTH + 1);
    localparam int unsigned CONVERT_META_DEPTH = 9;
    localparam int unsigned REQUIRED_ACCUM_WIDTH = 69 + 16;
    localparam int unsigned CPA_LOW_WIDTH = 44;
    localparam int unsigned CPA_HIGH_WIDTH = ACCUM_WIDTH - CPA_LOW_WIDTH;
    localparam int unsigned STATE_VECTOR_WIDTH = 16 * ACCUM_WIDTH;
    localparam int unsigned STATE_CARRY_BASE = STATE_VECTOR_WIDTH;
    localparam int unsigned STATE_SPECIAL_BASE = 2 * STATE_VECTOR_WIDTH;
    localparam int unsigned STATE_ZERO_SIGN_BASE = STATE_SPECIAL_BASE + 32;
    localparam int unsigned STATE_INVALID_BASE = STATE_ZERO_SIGN_BASE + 32;
    localparam int unsigned STATE_WIDTH = STATE_INVALID_BASE + 16;
    localparam int unsigned CORE_CONTROL_BRANCHES = 6;
    localparam int unsigned CONVERTER_CONTROL_BASE = CORE_CONTROL_BRANCHES;
    localparam int unsigned CONTROL_BRANCHES = CORE_CONTROL_BRANCHES + 16;
    localparam int unsigned RESULT_RESET_BRANCHES = 5;

    logic [CONTROL_BRANCHES-1:0] local_control_flush;
    logic [RESULT_RESET_BRANCHES:0] local_reset_branch;

    logic [4:0] command_rows_mem [0:COMMAND_DEPTH-1];
    logic [15:0] command_k_blocks_mem [0:COMMAND_DEPTH-1];
    fp8_pkg::fp8_rounding_e command_rounding_mem [0:COMMAND_DEPTH-1];
    logic [COMMAND_POINTER_WIDTH-1:0] command_write_pointer_q;
    logic [COMMAND_POINTER_WIDTH-1:0] command_read_pointer_q;
    logic [COMMAND_POINTER_WIDTH-1:0] command_next_read_pointer;
    logic [COMMAND_LEVEL_WIDTH-1:0] command_level_q;
    logic command_push;
    logic command_push_n;
    logic command_rows_push;
    logic command_k_blocks_push;
    logic command_rounding_push;
    logic command_pop;
    logic command_active;
    logic command_has_space;
    logic [4:0] command_rows;
    logic [15:0] command_k_blocks;
    fp8_pkg::fp8_rounding_e command_rounding;
    logic [4:0] command_rows_q;
    logic [15:0] command_k_blocks_q;
    fp8_pkg::fp8_rounding_e command_rounding_q;

    logic [4:0] row_index_q;
    logic [15:0] block_index_q;
    logic partial_stage_valid_q;
    logic [15:0] partial_stage_first_lane_q;
    logic partial_stage_final_q;
    logic partial_stage_last_q;
    logic [3:0] partial_stage_row_q;
    fp8_pkg::fp8_rounding_e partial_stage_rounding_q;
    logic signed [68:0] partial_stage_exact_q [0:15];
    fp8_pkg::fp8_reduce_special_e partial_stage_special_q [0:15];
    fp8_pkg::fp8_reduce_zero_sign_e partial_stage_zero_sign_q [0:15];
    logic partial_stage_invalid_q [0:15];
    logic [STATE_WIDTH-1:0] state_mem_wdata;
    logic [STATE_WIDTH-1:0] state_mem_rdata;
    logic state_mem_write;
    logic state_mem_read;
    logic [4:0] state_mem_write_addr;
    logic [4:0] state_mem_read_addr;
    logic signed [ACCUM_WIDTH-1:0] merged_sum [0:15];
    logic signed [ACCUM_WIDTH-1:0] merged_carry [0:15];
    fp8_pkg::fp8_reduce_special_e merged_special [0:15];
    fp8_pkg::fp8_reduce_zero_sign_e merged_zero_sign [0:15];
    logic merged_invalid [0:15];
    logic partial_fire;
    logic first_block;
    logic final_block;
    logic final_row;
    logic first_block_q;
    logic final_block_q;

    logic merge_valid_q;
    logic merge_final_q;
    logic merge_last_q;
    logic [3:0] merge_row_q;
    logic signed [ACCUM_WIDTH-1:0] merge_sum_q [0:15];
    logic signed [ACCUM_WIDTH-1:0] merge_carry_q [0:15];
    fp8_pkg::fp8_reduce_special_e merge_special_q [0:15];
    fp8_pkg::fp8_reduce_zero_sign_e merge_zero_sign_q [0:15];
    logic [15:0] merge_invalid_q;
    fp8_pkg::fp8_rounding_e merge_rounding_q;

    // One-cycle write forwarding covers the rows=2 SRAM read/write hazard.
    // rows=1 forwards directly from merge_q; rows>=3 read the SRAM state.
    logic forward_valid_q;
    logic [3:0] forward_row_q;
    logic signed [ACCUM_WIDTH-1:0] forward_sum_q [0:15];
    logic signed [ACCUM_WIDTH-1:0] forward_carry_q [0:15];
    fp8_pkg::fp8_reduce_special_e forward_special_q [0:15];
    fp8_pkg::fp8_reduce_zero_sign_e forward_zero_sign_q [0:15];
    logic [15:0] forward_invalid_q;

    logic cpa_stage_valid_q;
    logic cpa_stage_last_q;
    logic [CPA_LOW_WIDTH:0] cpa_low_sum_ext [0:15];
    logic [CPA_LOW_WIDTH-1:0] cpa_low_sum_q [0:15];
    logic [CPA_HIGH_WIDTH-1:0] cpa_high_sum_operand_q [0:15];
    logic [CPA_HIGH_WIDTH-1:0] cpa_high_carry_operand_q [0:15];
    logic cpa_low_carry_q [0:15];
    logic [CPA_HIGH_WIDTH-1:0] cpa_high_sum [0:15];
    fp8_pkg::fp8_reduce_special_e cpa_stage_special_q [0:15];
    fp8_pkg::fp8_reduce_zero_sign_e cpa_stage_zero_sign_q [0:15];
    logic [15:0] cpa_stage_invalid_q;
    fp8_pkg::fp8_rounding_e cpa_stage_rounding_q;

    logic final_valid_q;
    logic final_last_q;
    logic signed [ACCUM_WIDTH-1:0] final_exact_q [0:15];
    fp8_pkg::fp8_reduce_special_e final_special_q [0:15];
    fp8_pkg::fp8_reduce_zero_sign_e final_zero_sign_q [0:15];
    logic [15:0] final_invalid_q;
    fp8_pkg::fp8_rounding_e final_rounding_q;

    logic [15:0] convert_valid;
    logic [511:0] convert_data;
    logic [15:0] convert_invalid;
    logic [CONVERT_META_DEPTH-1:0] convert_meta_valid_q;
    logic [CONVERT_META_DEPTH-1:0] convert_meta_last_q;
    logic converter_launch;
    logic converter_return;
    logic converter_return_last;
    logic [6:0] converter_inflight_q;

    logic [RESULT_POINTER_WIDTH-1:0] result_write_pointer_q;
    logic [RESULT_POINTER_WIDTH-1:0] result_read_pointer_q;
    logic [RESULT_LEVEL_WIDTH-1:0] result_level_q;
    logic [RESULT_LEVEL_WIDTH-1:0] result_reserved_q;
    logic [RESULT_LEVEL_WIDTH-1:0] result_mem_level_q;
    logic [1:0] result_queue_level_q;
    logic result_queue_write_slot_q;
    logic result_queue_read_slot_q;
    logic [16:0] result_bank_read_valid;
    logic [511:0] result_queue_data;
    // Bits 31:17 are physical 32-bit bank padding.
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] result_queue_meta;
    /* verilator lint_on UNUSEDSIGNAL */
    logic result_mem_read;
    logic result_mem_response;
    logic [4:0] result_mem_write_addr;
    logic [4:0] result_mem_read_addr;
    logic result_push;
    logic result_pop;
    logic final_result_accept;

    assign command_active = command_level_q != '0;
    assign command_rows = command_rows_q;
    assign command_k_blocks = command_k_blocks_q;
    assign command_rounding = command_rounding_q;
    assign command_next_read_pointer =
        (command_read_pointer_q ==
         COMMAND_POINTER_WIDTH'(COMMAND_DEPTH - 1)) ? '0 :
        (command_read_pointer_q + 1'b1);
    assign command_has_space =
        command_level_q < COMMAND_LEVEL_WIDTH'(COMMAND_DEPTH);
    assign command_push = start_i && command_has_space;
    assign first_block = first_block_q;
    assign final_block = final_block_q;
    assign final_row = (row_index_q + 5'd1) == command_rows;
    assign partial_ready_o = command_active &&
        (!final_block ||
         (result_reserved_q < RESULT_LEVEL_WIDTH'(RESULT_DEPTH)) || result_pop);
    assign partial_fire = partial_valid_i && partial_ready_o;
    assign final_result_accept = partial_fire && final_block;
    assign command_pop = partial_fire && final_block && final_row;
    assign start_ready_o = !local_control_flush[0] &&
        command_has_space;

    generate
        for (genvar control_branch = 0;
             control_branch < CONTROL_BRANCHES;
             control_branch = control_branch + 1) begin : gen_control_flush
            (* keep = "true", dont_touch = "true" *)
            tile_flush_buffer #(
                .BUFFER_ID (200 + control_branch)
            ) u_control_flush_buffer (
                .rst_i   (rst_i),
                .clear_i (clear_i),
                .flush_o (local_control_flush[control_branch])
            );
        end

        for (genvar reset_branch = 0;
             reset_branch <= RESULT_RESET_BRANCHES;
             reset_branch = reset_branch + 1) begin : gen_reset_branch
            (* keep = "true", dont_touch = "true" *)
            tile_flush_buffer #(
                .BUFFER_ID (300 + reset_branch)
            ) u_reset_buffer (
                .rst_i   (rst_i),
                .clear_i (1'b0),
                .flush_o (local_reset_branch[reset_branch])
            );
        end

        (* keep = "true", dont_touch = "true" *)
        gemm_root_dispatcher_control_inverter u_command_push_root_inverter (
            .data_i (command_push),
            .data_o (command_push_n)
        );

        (* keep = "true", dont_touch = "true" *)
        gemm_root_dispatcher_control_inverter u_command_rows_push_inverter (
            .data_i (command_push_n),
            .data_o (command_rows_push)
        );

        (* keep = "true", dont_touch = "true" *)
        gemm_root_dispatcher_control_inverter u_command_k_blocks_push_inverter (
            .data_i (command_push_n),
            .data_o (command_k_blocks_push)
        );

        (* keep = "true", dont_touch = "true" *)
        gemm_root_dispatcher_control_inverter u_command_rounding_push_inverter (
            .data_i (command_push_n),
            .data_o (command_rounding_push)
        );
    endgenerate

    assign state_mem_write = merge_valid_q && !merge_final_q;
    assign state_mem_write_addr = {1'b0, merge_row_q};
    assign state_mem_read_addr = {1'b0, row_index_q[3:0]};
    assign state_mem_read = partial_fire && !first_block &&
        !(partial_stage_valid_q &&
          (partial_stage_row_q == row_index_q[3:0])) &&
        !(merge_valid_q && !merge_final_q &&
          (merge_row_q == row_index_q[3:0]));

    /* verilator lint_off PINCONNECTEMPTY */
    tile_k_accum_state_mem #(
        .DATA_WIDTH (STATE_WIDTH)
    ) u_state_mem (
        .clk_i      (clk_i),
        .rst_i      (local_reset_branch[0]),
        .a_req_i    (state_mem_write),
        .a_we_i     (state_mem_write),
        .a_addr_i   (state_mem_write_addr),
        .a_wdata_i  (state_mem_wdata),
        .a_rdata_o  (),
        .a_rvalid_o (),
        .b_req_i    (state_mem_read),
        .b_we_i     (1'b0),
        .b_addr_i   (state_mem_read_addr),
        .b_wdata_i  ('0),
        .b_rdata_o  (state_mem_rdata),
        .b_rvalid_o ()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always_comb begin
        state_mem_wdata = '0;
        for (integer state_lane = 0; state_lane < 16;
             state_lane = state_lane + 1) begin
            state_mem_wdata[state_lane*ACCUM_WIDTH +: ACCUM_WIDTH] =
                merge_sum_q[state_lane];
            state_mem_wdata[STATE_CARRY_BASE +
                            state_lane*ACCUM_WIDTH +: ACCUM_WIDTH] =
                merge_carry_q[state_lane];
            state_mem_wdata[STATE_SPECIAL_BASE + state_lane*2 +: 2] =
                merge_special_q[state_lane];
            state_mem_wdata[STATE_ZERO_SIGN_BASE + state_lane*2 +: 2] =
                merge_zero_sign_q[state_lane];
            state_mem_wdata[STATE_INVALID_BASE + state_lane] =
                merge_invalid_q[state_lane];
        end
    end

    generate
        for (genvar first_lane = 0; first_lane < 16;
             first_lane = first_lane + 1) begin : gen_first_flag_replica
            (* keep = "true", dont_touch = "true" *)
            gemm_control_tree_register #(
                .REGISTER_ID (1000 + first_lane)
            ) u_first_flag_register (
                .clk_i  (clk_i),
                .data_i (first_block),
                .data_o (partial_stage_first_lane_q[first_lane])
            );
        end

        for (genvar lane = 0; lane < 16; lane = lane + 1) begin : gen_exact_merge
            logic signed [ACCUM_WIDTH-1:0] partial_extended;
            logic old_pos_inf;
            logic old_neg_inf;
            logic new_pos_inf;
            logic new_neg_inf;
            logic infinity_conflict;
            logic signed [ACCUM_WIDTH-1:0] old_sum;
            logic signed [ACCUM_WIDTH-1:0] old_carry;
            fp8_pkg::fp8_reduce_special_e old_special;
            fp8_pkg::fp8_reduce_zero_sign_e old_zero_sign;
            logic old_invalid;
            logic old_from_merge;
            logic old_from_forward;
            logic signed [ACCUM_WIDTH-1:0] csa_sum;
            logic signed [ACCUM_WIDTH-1:0] csa_carry;

            assign partial_extended =
                {{(ACCUM_WIDTH-69){partial_stage_exact_q[lane][68]}},
                 partial_stage_exact_q[lane]};
            assign old_from_merge = merge_valid_q && !merge_final_q &&
                                    (merge_row_q == partial_stage_row_q);
            assign old_from_forward = forward_valid_q &&
                                      (forward_row_q == partial_stage_row_q);
            assign old_sum = old_from_merge ? merge_sum_q[lane] :
                (old_from_forward ? forward_sum_q[lane] :
                 $signed(state_mem_rdata[
                     lane*ACCUM_WIDTH +: ACCUM_WIDTH]));
            assign old_carry = old_from_merge ? merge_carry_q[lane] :
                (old_from_forward ? forward_carry_q[lane] :
                 $signed(state_mem_rdata[STATE_CARRY_BASE +
                     lane*ACCUM_WIDTH +: ACCUM_WIDTH]));
            assign old_special = old_from_merge ? merge_special_q[lane] :
                (old_from_forward ? forward_special_q[lane] :
                 fp8_pkg::fp8_reduce_special_e'(state_mem_rdata[
                     STATE_SPECIAL_BASE + lane*2 +: 2]));
            assign old_zero_sign = old_from_merge ?
                merge_zero_sign_q[lane] :
                (old_from_forward ? forward_zero_sign_q[lane] :
                 fp8_pkg::fp8_reduce_zero_sign_e'(state_mem_rdata[
                     STATE_ZERO_SIGN_BASE + lane*2 +: 2]));
            assign old_invalid = old_from_merge ? merge_invalid_q[lane] :
                (old_from_forward ? forward_invalid_q[lane] :
                 state_mem_rdata[STATE_INVALID_BASE + lane]);
            assign old_pos_inf = old_special ==
                                 fp8_pkg::FP8_REDUCE_POS_INF;
            assign old_neg_inf = old_special ==
                                 fp8_pkg::FP8_REDUCE_NEG_INF;
            assign new_pos_inf = partial_stage_special_q[lane] ==
                                 fp8_pkg::FP8_REDUCE_POS_INF;
            assign new_neg_inf = partial_stage_special_q[lane] ==
                                 fp8_pkg::FP8_REDUCE_NEG_INF;
            assign infinity_conflict = (old_pos_inf && new_neg_inf) ||
                                       (old_neg_inf && new_pos_inf);
            assign csa_sum = old_sum ^ old_carry ^ partial_extended;
            assign csa_carry = ((old_sum & old_carry) |
                                (old_sum & partial_extended) |
                                (old_carry & partial_extended)) << 1;
            assign merged_sum[lane] = partial_stage_first_lane_q[lane] ?
                {{(ACCUM_WIDTH-69){partial_stage_exact_q[lane][68]}},
                 partial_stage_exact_q[lane]} :
                csa_sum;
            assign merged_carry[lane] = partial_stage_first_lane_q[lane] ?
                '0 : csa_carry;

            kogge_stone_adder_48 #(
                .WIDTH (CPA_LOW_WIDTH + 1)
            ) u_final_low_adder (
                .a_i   ({1'b0, merge_sum_q[lane][CPA_LOW_WIDTH-1:0]}),
                .b_i   ({1'b0, merge_carry_q[lane][CPA_LOW_WIDTH-1:0]}),
                .cin_i (1'b0),
                .sum_o (cpa_low_sum_ext[lane])
            );

            kogge_stone_adder_48 #(
                .WIDTH (CPA_HIGH_WIDTH)
            ) u_final_high_adder (
                .a_i   (cpa_high_sum_operand_q[lane]),
                .b_i   (cpa_high_carry_operand_q[lane]),
                .cin_i (cpa_low_carry_q[lane]),
                .sum_o (cpa_high_sum[lane])
            );

            always_comb begin
                merged_invalid[lane] = partial_stage_invalid_q[lane];
                merged_special[lane] = fp8_pkg::fp8_reduce_special_e'(
                    partial_stage_special_q[lane]);
                merged_zero_sign[lane] = fp8_pkg::fp8_reduce_zero_sign_e'(
                    partial_stage_zero_sign_q[lane]);
                if (!partial_stage_first_lane_q[lane]) begin
                    merged_invalid[lane] = old_invalid ||
                                           partial_stage_invalid_q[lane] ||
                                           infinity_conflict;
                    if ((old_special == fp8_pkg::FP8_REDUCE_NAN) ||
                        (partial_stage_special_q[lane] ==
                         fp8_pkg::FP8_REDUCE_NAN) || infinity_conflict) begin
                        merged_special[lane] = fp8_pkg::FP8_REDUCE_NAN;
                    end else if (old_pos_inf || new_pos_inf) begin
                        merged_special[lane] = fp8_pkg::FP8_REDUCE_POS_INF;
                    end else if (old_neg_inf || new_neg_inf) begin
                        merged_special[lane] = fp8_pkg::FP8_REDUCE_NEG_INF;
                    end else begin
                        merged_special[lane] = fp8_pkg::FP8_REDUCE_NORMAL;
                    end
                    if ((old_zero_sign == fp8_pkg::FP8_ZERO_SIGN_NEGATIVE) &&
                        (partial_stage_zero_sign_q[lane] ==
                         fp8_pkg::FP8_ZERO_SIGN_NEGATIVE)) begin
                        merged_zero_sign[lane] = fp8_pkg::FP8_ZERO_SIGN_NEGATIVE;
                    end else if ((old_zero_sign ==
                                  fp8_pkg::FP8_ZERO_SIGN_POSITIVE) &&
                                 (partial_stage_zero_sign_q[lane] ==
                                  fp8_pkg::FP8_ZERO_SIGN_POSITIVE)) begin
                        merged_zero_sign[lane] = fp8_pkg::FP8_ZERO_SIGN_POSITIVE;
                    end else begin
                        merged_zero_sign[lane] = fp8_pkg::FP8_ZERO_SIGN_ROUNDING;
                    end
                end
            end

            fp8_fixed_q32_to_fp32 #(
                .WIDTH (ACCUM_WIDTH),
                .FTZ   (FTZ)
            ) u_final_converter (
                .clk_i       (clk_i),
                .rst_i       (local_control_flush[
                                  CONVERTER_CONTROL_BASE + lane]),
                .clear_i     (1'b0),
                .valid_i     (converter_launch),
                .fixed_i     (final_exact_q[lane]),
                .special_i   (final_special_q[lane]),
                .zero_sign_i (final_zero_sign_q[lane]),
                .invalid_i   (final_invalid_q[lane]),
                .rounding_i  (final_rounding_q),
                .valid_o     (convert_valid[lane]),
                .result_o    (convert_data[lane*32 +: 32]),
                .invalid_o   (convert_invalid[lane])
            );
        end
    endgenerate

    assign converter_launch = final_valid_q;
    assign converter_return = (&convert_valid) &&
                              convert_meta_valid_q[CONVERT_META_DEPTH-1];
    assign converter_return_last = convert_meta_last_q[CONVERT_META_DEPTH-1];
    assign result_push = converter_return;
    assign result_mem_write_addr = 5'(result_write_pointer_q);
    assign result_mem_read_addr = 5'(result_read_pointer_q);
    assign result_mem_response = &result_bank_read_valid;
    assign result_mem_read = (result_mem_level_q != '0) &&
        (({1'b0, result_queue_level_q} +
          {2'd0, result_mem_response}) <
         (3'd2 + {2'd0, result_pop}));
    assign result_valid_o = result_queue_level_q != 2'd0;
    assign result_data_o = result_valid_o ? result_queue_data : 512'd0;
    assign result_invalid_o = result_valid_o ? result_queue_meta[15:0] : 16'd0;
    assign result_pop = result_valid_o && result_ready_i;
    assign busy_o = command_active || partial_stage_valid_q || merge_valid_q ||
                    cpa_stage_valid_q || final_valid_q ||
                    (converter_inflight_q != 7'd0) ||
                    (result_level_q != '0);

    generate
        for (genvar result_lane = 0; result_lane < 16;
             result_lane = result_lane + 1) begin : gen_result_lane_bank
            tile_k_accum_result_bank u_result_bank (
                .clk_i               (clk_i),
                .rst_i               (local_reset_branch[
                                          1 + result_lane/4]),
                .mem_write_i         (result_push),
                .mem_write_addr_i    (result_mem_write_addr),
                .mem_write_data_i    (convert_data[result_lane*32 +: 32]),
                .mem_read_i          (result_mem_read),
                .mem_read_addr_i     (result_mem_read_addr),
                .queue_write_slot_i  (result_queue_write_slot_q),
                .queue_read_slot_i   (result_queue_read_slot_q),
                .queue_data_o        (result_queue_data[
                                          result_lane*32 +: 32]),
                .mem_read_valid_o    (result_bank_read_valid[result_lane])
            );
        end
    endgenerate

    tile_k_accum_result_bank u_result_meta_bank (
        .clk_i               (clk_i),
        .rst_i               (local_reset_branch[RESULT_RESET_BRANCHES]),
        .mem_write_i         (result_push),
        .mem_write_addr_i    (result_mem_write_addr),
        .mem_write_data_i    ({15'd0, converter_return_last, convert_invalid}),
        .mem_read_i          (result_mem_read),
        .mem_read_addr_i     (result_mem_read_addr),
        .queue_write_slot_i  (result_queue_write_slot_q),
        .queue_read_slot_i   (result_queue_read_slot_q),
        .queue_data_o        (result_queue_meta),
        .mem_read_valid_o    (result_bank_read_valid[16])
    );

    // Command payload fields use separate physical write-control branches so a
    // slot decode never drives all 23 payload bits as one high-fanout enable.
    always_ff @(posedge clk_i) begin
        if (command_rows_push) begin
            command_rows_mem[command_write_pointer_q] <= rows_i;
        end
    end

    always_ff @(posedge clk_i) begin
        if (command_k_blocks_push) begin
            command_k_blocks_mem[command_write_pointer_q] <= k_blocks_i;
        end
    end

    always_ff @(posedge clk_i) begin
        if (command_rounding_push) begin
            command_rounding_mem[command_write_pointer_q] <= rounding_i;
        end
    end

    // Payload registers are validity-protected and intentionally have no reset.
    // Keeping them outside the synchronous control reset removes reset/clear
    // muxes from the wide exact-state datapath without exposing stale payloads.
    always_ff @(posedge clk_i) begin
        for (integer merge_lane = 0; merge_lane < 16;
             merge_lane = merge_lane + 1) begin
            forward_sum_q[merge_lane] <= merge_sum_q[merge_lane];
            forward_carry_q[merge_lane] <= merge_carry_q[merge_lane];
            forward_special_q[merge_lane] <= merge_special_q[merge_lane];
            forward_zero_sign_q[merge_lane] <= merge_zero_sign_q[merge_lane];
            forward_invalid_q[merge_lane] <= merge_invalid_q[merge_lane];
            cpa_low_sum_q[merge_lane] <=
                cpa_low_sum_ext[merge_lane][CPA_LOW_WIDTH-1:0];
            cpa_low_carry_q[merge_lane] <=
                cpa_low_sum_ext[merge_lane][CPA_LOW_WIDTH];
            cpa_high_sum_operand_q[merge_lane] <=
                merge_sum_q[merge_lane][ACCUM_WIDTH-1:CPA_LOW_WIDTH];
            cpa_high_carry_operand_q[merge_lane] <=
                merge_carry_q[merge_lane][ACCUM_WIDTH-1:CPA_LOW_WIDTH];
            cpa_stage_special_q[merge_lane] <= merge_special_q[merge_lane];
            cpa_stage_zero_sign_q[merge_lane] <= merge_zero_sign_q[merge_lane];
            final_exact_q[merge_lane] <=
                {cpa_high_sum[merge_lane], cpa_low_sum_q[merge_lane]};
            final_special_q[merge_lane] <= cpa_stage_special_q[merge_lane];
            final_zero_sign_q[merge_lane] <= cpa_stage_zero_sign_q[merge_lane];
            merge_sum_q[merge_lane] <= merged_sum[merge_lane];
            merge_carry_q[merge_lane] <= merged_carry[merge_lane];
            merge_special_q[merge_lane] <= merged_special[merge_lane];
            merge_zero_sign_q[merge_lane] <= merged_zero_sign[merge_lane];
            merge_invalid_q[merge_lane] <= merged_invalid[merge_lane];
        end

        cpa_stage_invalid_q <= merge_invalid_q;
        final_invalid_q <= cpa_stage_invalid_q;
        for (integer stage_lane = 0; stage_lane < 16;
             stage_lane = stage_lane + 1) begin
            partial_stage_exact_q[stage_lane] <=
                partial_exact_i[stage_lane*69 +: 69];
            partial_stage_special_q[stage_lane] <=
                fp8_pkg::fp8_reduce_special_e'(
                    partial_special_i[stage_lane*2 +: 2]);
            partial_stage_zero_sign_q[stage_lane] <=
                fp8_pkg::fp8_reduce_zero_sign_e'(
                    partial_zero_sign_i[stage_lane*2 +: 2]);
            partial_stage_invalid_q[stage_lane] <=
                partial_invalid_i[stage_lane];
        end
    end

    always_ff @(posedge clk_i) begin
        if (local_control_flush[1]) begin
            command_write_pointer_q <= '0;
            command_read_pointer_q <= '0;
            command_level_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            if (start_i && !start_ready_o) begin
                protocol_error_o <= 1'b1;
            end
            if (partial_valid_i && !command_active) begin
                protocol_error_o <= 1'b1;
            end

            if (command_push) begin
                if (command_write_pointer_q ==
                    COMMAND_POINTER_WIDTH'(COMMAND_DEPTH - 1)) begin
                    command_write_pointer_q <= '0;
                end else begin
                    command_write_pointer_q <= command_write_pointer_q + 1'b1;
                end
            end
            if (command_pop) begin
                if (command_read_pointer_q ==
                    COMMAND_POINTER_WIDTH'(COMMAND_DEPTH - 1)) begin
                    command_read_pointer_q <= '0;
                end else begin
                    command_read_pointer_q <= command_read_pointer_q + 1'b1;
                end
            end
            unique case ({command_push, command_pop})
                2'b10: command_level_q <= command_level_q + 1'b1;
                2'b01: command_level_q <= command_level_q - 1'b1;
                default: command_level_q <= command_level_q;
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
        if (local_control_flush[2]) begin
            command_rows_q <= '0;
            command_k_blocks_q <= '0;
            command_rounding_q <= fp8_pkg::RNE;
            row_index_q <= '0;
            block_index_q <= '0;
            first_block_q <= 1'b1;
            final_block_q <= 1'b0;
            partial_stage_valid_q <= 1'b0;
            partial_stage_final_q <= 1'b0;
            partial_stage_last_q <= 1'b0;
            partial_stage_row_q <= '0;
            partial_stage_rounding_q <= fp8_pkg::RNE;
            block_done_o <= 1'b0;
        end else begin
            block_done_o <= 1'b0;
            partial_stage_valid_q <= partial_fire;
            partial_stage_final_q <= final_block;
            partial_stage_last_q <= final_row;
            partial_stage_row_q <= row_index_q[3:0];
            partial_stage_rounding_q <= command_rounding;
            if (partial_fire) begin
                if (final_row) begin
                    block_done_o <= 1'b1;
                    row_index_q <= '0;
                    if (final_block) begin
                        block_index_q <= '0;
                    end else begin
                        block_index_q <= block_index_q + 16'd1;
                        first_block_q <= 1'b0;
                        final_block_q <=
                            (block_index_q + 16'd2) == command_k_blocks;
                    end
                end else begin
                    row_index_q <= row_index_q + 5'd1;
                end
            end

            if (command_push && (command_level_q == '0)) begin
                command_rows_q <= rows_i;
                command_k_blocks_q <= k_blocks_i;
                command_rounding_q <= rounding_i;
                first_block_q <= 1'b1;
                final_block_q <= k_blocks_i == 16'd1;
            end
            if (command_pop) begin
                first_block_q <= 1'b1;
                if (command_level_q > COMMAND_LEVEL_WIDTH'(1)) begin
                    command_rows_q <=
                        command_rows_mem[command_next_read_pointer];
                    command_k_blocks_q <=
                        command_k_blocks_mem[command_next_read_pointer];
                    command_rounding_q <=
                        command_rounding_mem[command_next_read_pointer];
                    final_block_q <=
                        command_k_blocks_mem[command_next_read_pointer] == 16'd1;
                end else if (command_push) begin
                    command_rows_q <= rows_i;
                    command_k_blocks_q <= k_blocks_i;
                    command_rounding_q <= rounding_i;
                    final_block_q <= k_blocks_i == 16'd1;
                end else begin
                    final_block_q <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (local_control_flush[3]) begin
            merge_valid_q <= 1'b0;
            merge_final_q <= 1'b0;
            merge_last_q <= 1'b0;
            merge_row_q <= '0;
            merge_rounding_q <= fp8_pkg::RNE;
            forward_valid_q <= 1'b0;
            forward_row_q <= '0;
            cpa_stage_valid_q <= 1'b0;
            cpa_stage_last_q <= 1'b0;
            cpa_stage_rounding_q <= fp8_pkg::RNE;
            final_valid_q <= 1'b0;
            final_last_q <= 1'b0;
            final_rounding_q <= fp8_pkg::RNE;
        end else begin
            forward_valid_q <= merge_valid_q && !merge_final_q;
            forward_row_q <= merge_row_q;
            cpa_stage_valid_q <= merge_valid_q && merge_final_q;
            cpa_stage_last_q <= merge_last_q;
            cpa_stage_rounding_q <= merge_rounding_q;
            final_valid_q <= cpa_stage_valid_q;
            final_last_q <= cpa_stage_last_q;
            final_rounding_q <= cpa_stage_rounding_q;
            merge_valid_q <= partial_stage_valid_q;
            merge_final_q <= partial_stage_final_q;
            merge_last_q <= partial_stage_last_q;
            merge_row_q <= partial_stage_row_q;
            merge_rounding_q <= partial_stage_rounding_q;
        end
    end

    always_ff @(posedge clk_i) begin
        if (local_control_flush[4]) begin
            convert_meta_valid_q <= '0;
            convert_meta_last_q <= '0;
            converter_inflight_q <= '0;
        end else begin
            convert_meta_valid_q[0] <= converter_launch;
            convert_meta_last_q[0] <= final_last_q;
            for (integer meta_stage = 1; meta_stage < CONVERT_META_DEPTH;
                 meta_stage = meta_stage + 1) begin
                convert_meta_valid_q[meta_stage] <=
                    convert_meta_valid_q[meta_stage-1];
                convert_meta_last_q[meta_stage] <=
                    convert_meta_last_q[meta_stage-1];
            end
            unique case ({converter_launch, converter_return})
                2'b10: converter_inflight_q <= converter_inflight_q + 7'd1;
                2'b01: converter_inflight_q <= converter_inflight_q - 7'd1;
                default: converter_inflight_q <= converter_inflight_q;
            endcase
        end
    end

    always_ff @(posedge clk_i) begin
        if (local_control_flush[5]) begin
            result_write_pointer_q <= '0;
            result_read_pointer_q <= '0;
            result_level_q <= '0;
            result_reserved_q <= '0;
            result_mem_level_q <= '0;
            result_queue_level_q <= '0;
            result_queue_write_slot_q <= 1'b0;
            result_queue_read_slot_q <= 1'b0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (result_push) begin
                if (result_write_pointer_q ==
                    RESULT_POINTER_WIDTH'(RESULT_DEPTH - 1)) begin
                    result_write_pointer_q <= '0;
                end else begin
                    result_write_pointer_q <= result_write_pointer_q + 1'b1;
                end
            end
            if (result_mem_read) begin
                if (result_read_pointer_q ==
                    RESULT_POINTER_WIDTH'(RESULT_DEPTH - 1)) begin
                    result_read_pointer_q <= '0;
                end else begin
                    result_read_pointer_q <= result_read_pointer_q + 1'b1;
                end
            end
            unique case ({result_push, result_mem_read})
                2'b10: result_mem_level_q <= result_mem_level_q + 1'b1;
                2'b01: result_mem_level_q <= result_mem_level_q - 1'b1;
                default: result_mem_level_q <= result_mem_level_q;
            endcase

            if (result_mem_response) begin
                result_queue_write_slot_q <= ~result_queue_write_slot_q;
            end
            if (result_pop) begin
                result_queue_read_slot_q <= ~result_queue_read_slot_q;
                if (result_queue_meta[16]) begin
                    done_o <= 1'b1;
                end
            end
            unique case ({result_mem_response, result_pop})
                2'b10: result_queue_level_q <= result_queue_level_q + 2'd1;
                2'b01: result_queue_level_q <= result_queue_level_q - 2'd1;
                default: result_queue_level_q <= result_queue_level_q;
            endcase
            unique case ({result_push, result_pop})
                2'b10: result_level_q <= result_level_q + 1'b1;
                2'b01: result_level_q <= result_level_q - 1'b1;
                default: result_level_q <= result_level_q;
            endcase
            unique case ({final_result_accept, result_pop})
                2'b10: result_reserved_q <= result_reserved_q + 1'b1;
                2'b01: result_reserved_q <= result_reserved_q - 1'b1;
                default: result_reserved_q <= result_reserved_q;
            endcase
        end
    end

`ifndef YOSYS
    initial begin
        assert (COMMAND_DEPTH > 0)
            else $error("tile_fp32_k_accumulator COMMAND_DEPTH must be positive");
        assert (RESULT_DEPTH > CONVERT_META_DEPTH)
            else $error("tile_fp32_k_accumulator RESULT_DEPTH is too small");
        assert (RESULT_DEPTH <= 32)
            else $error("tile_fp32_k_accumulator RESULT_DEPTH exceeds the physical SRAM depth");
        assert (ACCUM_WIDTH >= REQUIRED_ACCUM_WIDTH)
            else $error("tile_fp32_k_accumulator ACCUM_WIDTH must cover every 16-bit K-block count");
    end
`endif

endmodule

`default_nettype wire
