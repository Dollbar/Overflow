`timescale 1ns/1ps
`default_nettype none

// Dynamic square-GEMM feeder. A/B reads, Tile issue, and result retirement are
// independent streams; the compiler owns descriptor legality and Tile hazards.
module npu_square_gemm_executor #(
    parameter int unsigned ARRAY_DIM = 16,
    parameter int unsigned CONTEXT_DEPTH = 16,
    parameter int unsigned PAIR_DEPTH = 2,
    parameter int unsigned RESULT_FIFO_DEPTH = 4
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic gemm_command_valid_i,
    output logic gemm_command_ready_o,
    input  logic [npu_scheduler_pkg::NPU_GEMM_COMMAND_WIDTH-1:0]
                 gemm_command_i,
    input  logic activation_command_valid_i,
    output logic activation_command_ready_o,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_READ_COMMAND_WIDTH-1:0]
                 activation_command_i,
    input  logic weight_command_valid_i,
    output logic weight_command_ready_o,
    input  logic [npu_scheduler_pkg::NPU_BUFFER_READ_COMMAND_WIDTH-1:0]
                 weight_command_i,
    input  logic result_command_valid_i,
    output logic result_command_ready_o,
    input  logic [npu_scheduler_pkg::NPU_RESULT_COMMAND_WIDTH-1:0]
                 result_command_i,

    output logic activation_read_enable_o,
    output logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 activation_read_buffer_id_o,
    output logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 activation_read_offset_o,
    input  logic activation_read_valid_i,
    input  logic [ARRAY_DIM*128-1:0] activation_read_data_i,
    output logic weight_read_enable_o,
    output logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 weight_read_buffer_id_o,
    output logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 weight_read_offset_o,
    input  logic weight_read_valid_i,
    input  logic [ARRAY_DIM*128-1:0] weight_read_data_i,

    output logic [ARRAY_DIM-1:0] direct_a_valid_o,
    input  logic [ARRAY_DIM-1:0] direct_a_ready_i,
    output logic [ARRAY_DIM*128-1:0] direct_a_data_o,
    output logic [ARRAY_DIM-1:0] direct_a_format_o,
    output logic [ARRAY_DIM*2-1:0] direct_a_rounding_o,
    output logic [ARRAY_DIM-1:0] direct_b_valid_o,
    input  logic [ARRAY_DIM-1:0] direct_b_ready_i,
    output logic [ARRAY_DIM*128-1:0] direct_b_data_o,
    output logic [ARRAY_DIM-1:0] direct_b_format_o,

    output logic [ARRAY_DIM*ARRAY_DIM-1:0] accumulate_start_o,
    input  logic [ARRAY_DIM*ARRAY_DIM-1:0] accumulate_start_ready_i,
    output logic [ARRAY_DIM*ARRAY_DIM*5-1:0] accumulate_rows_o,
    output logic [ARRAY_DIM*ARRAY_DIM*16-1:0] accumulate_k_blocks_o,
    output logic [ARRAY_DIM*ARRAY_DIM*2-1:0] accumulate_rounding_o,
    input  logic [ARRAY_DIM*ARRAY_DIM-1:0] accumulate_protocol_error_i,

    output logic [ARRAY_DIM*ARRAY_DIM-1:0] result_ready_o,
    input  logic [ARRAY_DIM*ARRAY_DIM-1:0] result_valid_i,
    input  logic [ARRAY_DIM*ARRAY_DIM*512-1:0] result_data_i,
    input  logic [ARRAY_DIM*ARRAY_DIM*16-1:0] result_invalid_i,
    output logic [ARRAY_DIM-1:0] vector_result_valid_o,
    input  logic [ARRAY_DIM-1:0] vector_result_ready_i,
    output logic [ARRAY_DIM*512-1:0] vector_result_data_o,
    output logic [ARRAY_DIM*16-1:0] vector_result_invalid_o,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
                 vector_result_job_id_o,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
                 vector_result_tag_o,
    output logic [ARRAY_DIM*npu_scheduler_pkg::NPU_DIMENSION_WIDTH-1:0]
                 vector_result_row_o,
    output logic [ARRAY_DIM*5-1:0] vector_result_segment_o,
    output logic [ARRAY_DIM-1:0] vector_result_last_o,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_o,
    output logic completion_success_o,
    output logic busy_o,
    output logic protocol_error_o
);

    localparam int unsigned NODE_COUNT = ARRAY_DIM * ARRAY_DIM;
    localparam int unsigned PAIR_POINTER_WIDTH =
        (PAIR_DEPTH <= 1) ? 1 : $clog2(PAIR_DEPTH);
    localparam int unsigned PAIR_LEVEL_WIDTH = $clog2(PAIR_DEPTH + 1);
    localparam int unsigned CONTEXT_POINTER_WIDTH =
        (CONTEXT_DEPTH <= 1) ? 1 : $clog2(CONTEXT_DEPTH);
    localparam int unsigned CONTEXT_LEVEL_WIDTH = $clog2(CONTEXT_DEPTH + 1);
    localparam int unsigned RESULT_ENTRY_WIDTH = 528;
    localparam int unsigned RESULT_LEVEL_WIDTH =
        $clog2(RESULT_FIFO_DEPTH + 1);

    npu_scheduler_pkg::npu_gemm_command_t gemm_command;
    npu_scheduler_pkg::npu_buffer_read_command_t activation_command;
    npu_scheduler_pkg::npu_buffer_read_command_t weight_command;

    logic command_bundle_valid;
    logic command_bundle_ready;
    logic command_fire;
    logic context_credit;
    logic incoming_start_credit;
    logic [ARRAY_DIM-1:0] incoming_row_mask;
    logic [ARRAY_DIM-1:0] incoming_column_mask;
    logic [NODE_COUNT-1:0] incoming_tile_mask;

    logic feed_active_q;
    logic [19:0] feed_read_index_q;
    logic [20:0] feed_read_count_q;
    logic [ARRAY_DIM-1:0] feed_row_mask_q;
    logic [ARRAY_DIM-1:0] feed_column_mask_q;
    logic [3:0] feed_anchor_x_q;
    logic [3:0] feed_anchor_y_q;
    logic [4:0] feed_tile_span_q;
    fp8_pkg::fp8_format_e feed_activation_format_q;
    fp8_pkg::fp8_format_e feed_weight_format_q;
    fp8_pkg::fp8_rounding_e feed_rounding_q;
    logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        feed_activation_buffer_id_q;
    logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        feed_activation_base_offset_q;
    logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
        feed_weight_buffer_id_q;
    logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
        feed_weight_base_offset_q;
    logic feed_last_read;
    logic read_credit;
    logic read_issue;
    logic [19:0] read_index;
    logic [31:0] read_byte_offset;

    logic read_meta_valid_q;
    logic [ARRAY_DIM-1:0] read_meta_row_mask_q;
    logic [ARRAY_DIM-1:0] read_meta_column_mask_q;
    logic [3:0] read_meta_anchor_x_q;
    logic [3:0] read_meta_anchor_y_q;
    fp8_pkg::fp8_format_e read_meta_activation_format_q;
    fp8_pkg::fp8_format_e read_meta_weight_format_q;
    fp8_pkg::fp8_rounding_e read_meta_rounding_q;

    logic [ARRAY_DIM*128-1:0] pair_activation_mem [0:PAIR_DEPTH-1];
    logic [ARRAY_DIM*128-1:0] pair_weight_mem [0:PAIR_DEPTH-1];
    logic [ARRAY_DIM-1:0] pair_row_mask_mem [0:PAIR_DEPTH-1];
    logic [ARRAY_DIM-1:0] pair_column_mask_mem [0:PAIR_DEPTH-1];
    logic [3:0] pair_anchor_x_mem [0:PAIR_DEPTH-1];
    logic [3:0] pair_anchor_y_mem [0:PAIR_DEPTH-1];
    fp8_pkg::fp8_format_e pair_activation_format_mem [0:PAIR_DEPTH-1];
    fp8_pkg::fp8_format_e pair_weight_format_mem [0:PAIR_DEPTH-1];
    fp8_pkg::fp8_rounding_e pair_rounding_mem [0:PAIR_DEPTH-1];
    logic [PAIR_POINTER_WIDTH-1:0] pair_write_pointer_q;
    logic [PAIR_POINTER_WIDTH-1:0] pair_read_pointer_q;
    logic [PAIR_LEVEL_WIDTH-1:0] pair_level_q;
    logic pair_push;
    logic pair_pop;
    logic pair_valid;
    logic pair_sink_ready;

    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
        context_tag_mem [0:CONTEXT_DEPTH-1];
    logic [npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        context_job_id_mem [0:CONTEXT_DEPTH-1];
    logic [NODE_COUNT-1:0] context_tile_mask_mem [0:CONTEXT_DEPTH-1];
    logic [3:0] context_anchor_x_mem [0:CONTEXT_DEPTH-1];
    logic [3:0] context_anchor_y_mem [0:CONTEXT_DEPTH-1];
    logic [4:0] context_tile_span_mem [0:CONTEXT_DEPTH-1];
    logic [CONTEXT_POINTER_WIDTH-1:0] context_write_pointer_q;
    logic [CONTEXT_POINTER_WIDTH-1:0] context_read_pointer_q;
    logic [CONTEXT_LEVEL_WIDTH-1:0] context_level_q;
    logic [CONTEXT_POINTER_WIDTH-1:0] collect_context_pointer_q;
    logic [CONTEXT_LEVEL_WIDTH-1:0] collect_context_level_q;
    logic [NODE_COUNT-1:0] context_head_tile_mask;
    logic [ARRAY_DIM-1:0] context_head_row_mask;
    logic [3:0] context_head_anchor_y;
    logic [4:0] context_head_tile_span;
    logic [ARRAY_DIM-1:0] collect_context_row_mask;
    logic [3:0] collect_context_anchor_x;
    logic [3:0] collect_context_anchor_y;
    logic [4:0] collect_context_tile_span;
    logic context_collect_active;
    logic [ARRAY_DIM-1:0] collect_row_last_fire;
    logic collect_context_complete;
    logic [3:0] collect_local_row_q [0:ARRAY_DIM-1];
    logic [4:0] collect_segment_q [0:ARRAY_DIM-1];
    logic [ARRAY_DIM-1:0] collect_done_q;
    logic [ARRAY_DIM-1:0] row_fifo_input_valid;
    logic [ARRAY_DIM-1:0] row_fifo_input_ready;
    logic [ARRAY_DIM*RESULT_ENTRY_WIDTH-1:0] row_fifo_input_data;
    logic [ARRAY_DIM-1:0] row_fifo_output_valid;
    logic [ARRAY_DIM-1:0] row_fifo_output_ready;
    logic [ARRAY_DIM*RESULT_ENTRY_WIDTH-1:0] row_fifo_output_data;
    logic [ARRAY_DIM*RESULT_LEVEL_WIDTH-1:0] row_fifo_level;
    logic [3:0] vector_output_local_row_q [0:ARRAY_DIM-1];
    logic [4:0] vector_output_segment_q [0:ARRAY_DIM-1];
    logic [ARRAY_DIM-1:0] vector_output_done_q;
    logic [ARRAY_DIM-1:0] vector_result_fire;
    logic [ARRAY_DIM-1:0] vector_row_done_fire;
    logic vector_context_complete;
    logic context_output_done_q;
    logic context_complete;
    logic context_pop;

    always_comb begin
        gemm_command = npu_scheduler_pkg::npu_gemm_command_t'(gemm_command_i);
        activation_command =
            npu_scheduler_pkg::npu_buffer_read_command_t'(activation_command_i);
        weight_command =
            npu_scheduler_pkg::npu_buffer_read_command_t'(weight_command_i);

        incoming_row_mask = '0;
        incoming_column_mask = '0;
        incoming_tile_mask = '0;
        for (integer row = 0; row < ARRAY_DIM; row++) begin
            if ((row >= integer'(gemm_command.tile_anchor_y)) &&
                (row < integer'(gemm_command.tile_anchor_y) +
                       integer'(gemm_command.tile_span))) begin
                incoming_row_mask[row] = 1'b1;
            end
        end
        for (integer column = 0; column < ARRAY_DIM; column++) begin
            if ((column >= integer'(gemm_command.tile_anchor_x)) &&
                (column < integer'(gemm_command.tile_anchor_x) +
                          integer'(gemm_command.tile_span))) begin
                incoming_column_mask[column] = 1'b1;
            end
        end
        for (integer tile_y = 0; tile_y < ARRAY_DIM; tile_y++) begin
            for (integer tile_x = 0; tile_x < ARRAY_DIM; tile_x++) begin
                incoming_tile_mask[tile_y*ARRAY_DIM + tile_x] =
                    incoming_row_mask[tile_y] && incoming_column_mask[tile_x];
            end
        end

        command_bundle_valid = gemm_command_valid_i &&
            activation_command_valid_i && weight_command_valid_i &&
            result_command_valid_i;
        context_credit =
            (context_level_q < CONTEXT_LEVEL_WIDTH'(CONTEXT_DEPTH)) || context_pop;
        incoming_start_credit =
            (accumulate_start_ready_i & incoming_tile_mask) == incoming_tile_mask;
        command_bundle_ready = context_credit && incoming_start_credit &&
            (!feed_active_q || (read_credit && feed_last_read));
        command_fire = command_bundle_valid && command_bundle_ready;
        gemm_command_ready_o = command_bundle_ready &&
            activation_command_valid_i && weight_command_valid_i &&
            result_command_valid_i;
        activation_command_ready_o = command_bundle_ready &&
            gemm_command_valid_i && weight_command_valid_i &&
            result_command_valid_i;
        weight_command_ready_o = command_bundle_ready &&
            gemm_command_valid_i && activation_command_valid_i &&
            result_command_valid_i;
        result_command_ready_o = command_bundle_ready &&
            gemm_command_valid_i && activation_command_valid_i &&
            weight_command_valid_i;
    end

    always_comb begin
        pair_valid = pair_level_q != '0;
        pair_sink_ready =
            ((direct_a_ready_i & pair_row_mask_mem[pair_read_pointer_q]) ==
             pair_row_mask_mem[pair_read_pointer_q]) &&
            ((direct_b_ready_i & pair_column_mask_mem[pair_read_pointer_q]) ==
             pair_column_mask_mem[pair_read_pointer_q]);
        pair_pop = pair_valid && pair_sink_ready;
        pair_push = activation_read_valid_i && weight_read_valid_i &&
                    read_meta_valid_q;
        read_credit = (((PAIR_LEVEL_WIDTH+1)'(pair_level_q) +
                        (PAIR_LEVEL_WIDTH+1)'(read_meta_valid_q)) <
                       (PAIR_LEVEL_WIDTH+1)'(PAIR_DEPTH)) || pair_pop;
        feed_last_read = feed_active_q &&
            (({1'b0, feed_read_index_q} + 21'd1) == feed_read_count_q);
        read_issue = read_credit &&
                     (feed_active_q || (!feed_active_q && command_fire));
        read_index = feed_active_q ? feed_read_index_q : 20'd0;
        read_byte_offset = {8'd0, read_index, 4'd0};

        activation_read_enable_o = read_issue;
        weight_read_enable_o = read_issue;
        activation_read_buffer_id_o = feed_active_q ?
            feed_activation_buffer_id_q : activation_command.buffer_id;
        weight_read_buffer_id_o = feed_active_q ?
            feed_weight_buffer_id_q : weight_command.buffer_id;
        activation_read_offset_o =
            (feed_active_q ? feed_activation_base_offset_q :
                             activation_command.base_offset) + read_byte_offset;
        weight_read_offset_o =
            (feed_active_q ? feed_weight_base_offset_q :
                             weight_command.base_offset) + read_byte_offset;
    end

    always_comb begin
        direct_a_valid_o = '0;
        direct_a_data_o = '0;
        direct_a_format_o = '0;
        direct_a_rounding_o = '0;
        direct_b_valid_o = '0;
        direct_b_data_o = '0;
        direct_b_format_o = '0;
        if (pair_valid) begin
            direct_a_valid_o = pair_row_mask_mem[pair_read_pointer_q];
            direct_b_valid_o = pair_column_mask_mem[pair_read_pointer_q];
        end
        for (integer physical = 0; physical < ARRAY_DIM; physical++) begin
            direct_a_format_o[physical] =
                pair_activation_format_mem[pair_read_pointer_q];
            direct_a_rounding_o[physical*2 +: 2] =
                pair_rounding_mem[pair_read_pointer_q];
            direct_b_format_o[physical] =
                pair_weight_format_mem[pair_read_pointer_q];
            if (pair_row_mask_mem[pair_read_pointer_q][physical]) begin
                direct_a_data_o[physical*128 +: 128] =
                    pair_activation_mem[pair_read_pointer_q][
                        (physical - integer'(pair_anchor_y_mem[pair_read_pointer_q]))*
                        128 +: 128];
            end
            if (pair_column_mask_mem[pair_read_pointer_q][physical]) begin
                direct_b_data_o[physical*128 +: 128] =
                    pair_weight_mem[pair_read_pointer_q][
                        (physical - integer'(pair_anchor_x_mem[pair_read_pointer_q]))*
                        128 +: 128];
            end
        end
    end

    always_comb begin
        accumulate_start_o = command_fire ? incoming_tile_mask : '0;
        accumulate_rows_o = '0;
        accumulate_k_blocks_o = '0;
        accumulate_rounding_o = '0;
        for (integer node = 0; node < NODE_COUNT; node++) begin
            accumulate_rows_o[node*5 +: 5] = 5'd16;
            accumulate_k_blocks_o[node*16 +: 16] = gemm_command.k_blocks;
            accumulate_rounding_o[node*2 +: 2] = gemm_command.rounding;
        end
    end

    generate
        for (genvar row_channel = 0; row_channel < ARRAY_DIM;
             row_channel++) begin : g_result_row_fifo
            npu_gemm_result_fifo #(
                .WIDTH(RESULT_ENTRY_WIDTH),
                .DEPTH(RESULT_FIFO_DEPTH)
            ) u_result_fifo (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .clear_i(clear_i),
                .input_valid_i(row_fifo_input_valid[row_channel]),
                .input_ready_o(row_fifo_input_ready[row_channel]),
                .input_data_i(row_fifo_input_data[
                    row_channel*RESULT_ENTRY_WIDTH +: RESULT_ENTRY_WIDTH
                ]),
                .output_valid_o(row_fifo_output_valid[row_channel]),
                .output_ready_i(row_fifo_output_ready[row_channel]),
                .output_data_o(row_fifo_output_data[
                    row_channel*RESULT_ENTRY_WIDTH +: RESULT_ENTRY_WIDTH
                ]),
                .level_o(row_fifo_level[
                    row_channel*RESULT_LEVEL_WIDTH +: RESULT_LEVEL_WIDTH
                ])
            );
        end
    endgenerate

    // Collection and retirement use independent Context pointers. Once all
    // Tile results for one Context have entered the row FIFOs, collection may
    // prefetch the next Context while the current one is still retiring. FIFO
    // order preserves Context order without storing a tag in every row entry.
    always_comb begin
        context_head_tile_mask = '0;
        context_head_row_mask = '0;
        context_head_anchor_y = '0;
        context_head_tile_span = '0;
        if (context_level_q != '0) begin
            context_head_tile_mask =
                context_tile_mask_mem[context_read_pointer_q];
            context_head_anchor_y =
                context_anchor_y_mem[context_read_pointer_q];
            context_head_tile_span =
                context_tile_span_mem[context_read_pointer_q];
            for (integer context_row = 0; context_row < ARRAY_DIM;
                 context_row++) begin
                if ((context_row >= integer'(context_head_anchor_y)) &&
                    (context_row < integer'(context_head_anchor_y) +
                                   integer'(context_head_tile_span))) begin
                    context_head_row_mask[context_row] = 1'b1;
                end
            end
        end

        collect_context_row_mask = '0;
        collect_context_anchor_x = '0;
        collect_context_anchor_y = '0;
        collect_context_tile_span = '0;
        if (collect_context_level_q != '0) begin
            collect_context_anchor_x =
                context_anchor_x_mem[collect_context_pointer_q];
            collect_context_anchor_y =
                context_anchor_y_mem[collect_context_pointer_q];
            collect_context_tile_span =
                context_tile_span_mem[collect_context_pointer_q];
            for (integer collect_context_row = 0;
                 collect_context_row < ARRAY_DIM; collect_context_row++) begin
                if ((collect_context_row >=
                     integer'(collect_context_anchor_y)) &&
                    (collect_context_row <
                     integer'(collect_context_anchor_y) +
                     integer'(collect_context_tile_span))) begin
                    collect_context_row_mask[collect_context_row] = 1'b1;
                end
            end
        end

        context_collect_active = collect_context_level_q != '0;

        result_ready_o = '0;
        row_fifo_input_valid = '0;
        collect_row_last_fire = '0;
        for (integer physical_y = 0; physical_y < ARRAY_DIM;
             physical_y++) begin
            row_fifo_input_data[
                physical_y*RESULT_ENTRY_WIDTH +: RESULT_ENTRY_WIDTH
            ] = '0;
            if (context_collect_active && !collect_done_q[physical_y] &&
                (physical_y >= integer'(collect_context_anchor_y)) &&
                (physical_y < integer'(collect_context_anchor_y) +
                              integer'(collect_context_tile_span))) begin
                for (integer physical_x = 0; physical_x < ARRAY_DIM;
                     physical_x++) begin
                    if (physical_x == integer'(collect_context_anchor_x) +
                                      integer'(collect_segment_q[physical_y])) begin
                        row_fifo_input_valid[physical_y] =
                            result_valid_i[physical_y*ARRAY_DIM + physical_x];
                        row_fifo_input_data[
                            physical_y*RESULT_ENTRY_WIDTH +: RESULT_ENTRY_WIDTH
                        ] = {
                            result_invalid_i[
                                (physical_y*ARRAY_DIM + physical_x)*16 +: 16
                            ],
                            result_data_i[
                                (physical_y*ARRAY_DIM + physical_x)*512 +: 512
                            ]
                        };
                        result_ready_o[physical_y*ARRAY_DIM + physical_x] =
                            row_fifo_input_ready[physical_y];
                        collect_row_last_fire[physical_y] =
                            result_valid_i[physical_y*ARRAY_DIM + physical_x] &&
                            row_fifo_input_ready[physical_y] &&
                            (collect_local_row_q[physical_y] == 4'd15) &&
                            (collect_segment_q[physical_y] + 5'd1 ==
                             collect_context_tile_span);
                    end
                end
            end
        end
        collect_context_complete = context_collect_active &&
            (collect_context_row_mask != '0) &&
            (((collect_done_q | collect_row_last_fire) &
              collect_context_row_mask) == collect_context_row_mask);
    end

    // Every route retires through the same physical-row result plane. Each row
    // has an independent ready/valid handshake, so one blocked destination row
    // cannot stop the other rows.
    always_comb begin
        vector_result_valid_o = '0;
        vector_result_data_o = '0;
        vector_result_invalid_o = '0;
        vector_result_job_id_o = '0;
        vector_result_tag_o = '0;
        vector_result_row_o = '0;
        vector_result_segment_o = '0;
        vector_result_last_o = '0;
        row_fifo_output_ready = '0;

        if ((context_level_q != '0) && !context_output_done_q) begin
            for (integer physical_y = 0; physical_y < ARRAY_DIM;
                 physical_y++) begin
                if ((physical_y >= integer'(context_head_anchor_y)) &&
                    (physical_y < integer'(context_head_anchor_y) +
                                  integer'(context_head_tile_span)) &&
                    !vector_output_done_q[physical_y]) begin
                    vector_result_valid_o[physical_y] =
                        row_fifo_output_valid[physical_y];
                    vector_result_data_o[physical_y*512 +: 512] =
                        row_fifo_output_data[
                            physical_y*RESULT_ENTRY_WIDTH +: 512
                        ];
                    vector_result_invalid_o[physical_y*16 +: 16] =
                        row_fifo_output_data[
                            physical_y*RESULT_ENTRY_WIDTH + 512 +: 16
                        ];
                    vector_result_job_id_o[
                        physical_y*npu_scheduler_pkg::NPU_JOB_ID_WIDTH +:
                        npu_scheduler_pkg::NPU_JOB_ID_WIDTH
                    ] = context_job_id_mem[context_read_pointer_q];
                    vector_result_tag_o[
                        physical_y*npu_scheduler_pkg::NPU_TAG_WIDTH +:
                        npu_scheduler_pkg::NPU_TAG_WIDTH
                    ] = context_tag_mem[context_read_pointer_q];
                    vector_result_row_o[
                        physical_y*npu_scheduler_pkg::NPU_DIMENSION_WIDTH +:
                        npu_scheduler_pkg::NPU_DIMENSION_WIDTH
                    ] = npu_scheduler_pkg::NPU_DIMENSION_WIDTH'(
                        ((physical_y - integer'(context_head_anchor_y)) * 16) +
                        integer'(vector_output_local_row_q[physical_y])
                    );
                    vector_result_segment_o[physical_y*5 +: 5] =
                        vector_output_segment_q[physical_y];
                    vector_result_last_o[physical_y] =
                        (physical_y + 1 == integer'(context_head_anchor_y) +
                                           integer'(context_head_tile_span)) &&
                        (vector_output_local_row_q[physical_y] == 4'd15) &&
                        (vector_output_segment_q[physical_y] + 5'd1 ==
                         context_head_tile_span);
                    row_fifo_output_ready[physical_y] =
                        vector_result_ready_i[physical_y];
                end
            end
        end

        vector_result_fire = vector_result_valid_o & vector_result_ready_i;
        vector_row_done_fire = '0;
        for (integer physical_y = 0; physical_y < ARRAY_DIM;
             physical_y++) begin
            vector_row_done_fire[physical_y] =
                vector_result_fire[physical_y] &&
                (vector_output_local_row_q[physical_y] == 4'd15) &&
                (vector_output_segment_q[physical_y] + 5'd1 ==
                 context_head_tile_span);
        end
        vector_context_complete = (context_head_row_mask != '0) &&
            (((vector_output_done_q | vector_row_done_fire) &
              context_head_row_mask) == context_head_row_mask);
        context_complete = (context_level_q != '0) &&
            (context_output_done_q || vector_context_complete);
        completion_valid_o = context_complete;
        completion_tag_o = (context_level_q != '0) ?
            context_tag_mem[context_read_pointer_q] : '0;
        completion_success_o = 1'b1;
        context_pop = completion_valid_o && completion_ready_i;
    end

    assign busy_o = feed_active_q || read_meta_valid_q ||
                    (pair_level_q != '0) || (context_level_q != '0);

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            feed_active_q <= 1'b0;
            feed_read_index_q <= '0;
            feed_read_count_q <= '0;
            feed_row_mask_q <= '0;
            feed_column_mask_q <= '0;
            feed_anchor_x_q <= '0;
            feed_anchor_y_q <= '0;
            feed_tile_span_q <= '0;
            feed_activation_format_q <= fp8_pkg::FP8_E4M3;
            feed_weight_format_q <= fp8_pkg::FP8_E4M3;
            feed_rounding_q <= fp8_pkg::RNE;
            feed_activation_buffer_id_q <= '0;
            feed_activation_base_offset_q <= '0;
            feed_weight_buffer_id_q <= '0;
            feed_weight_base_offset_q <= '0;
            read_meta_valid_q <= 1'b0;
            read_meta_row_mask_q <= '0;
            read_meta_column_mask_q <= '0;
            read_meta_anchor_x_q <= '0;
            read_meta_anchor_y_q <= '0;
            read_meta_activation_format_q <= fp8_pkg::FP8_E4M3;
            read_meta_weight_format_q <= fp8_pkg::FP8_E4M3;
            read_meta_rounding_q <= fp8_pkg::RNE;
            pair_write_pointer_q <= '0;
            pair_read_pointer_q <= '0;
            pair_level_q <= '0;
            context_write_pointer_q <= '0;
            context_read_pointer_q <= '0;
            context_level_q <= '0;
            collect_context_pointer_q <= '0;
            collect_context_level_q <= '0;
            collect_done_q <= '0;
            context_output_done_q <= 1'b0;
            vector_output_done_q <= '0;
            protocol_error_o <= 1'b0;
            for (integer physical_y = 0; physical_y < ARRAY_DIM;
                 physical_y++) begin
                collect_local_row_q[physical_y] <= '0;
                collect_segment_q[physical_y] <= '0;
                vector_output_local_row_q[physical_y] <= '0;
                vector_output_segment_q[physical_y] <= '0;
            end
        end else begin
            if (activation_read_valid_i != weight_read_valid_i) begin
                protocol_error_o <= 1'b1;
            end
            if (|(accumulate_protocol_error_i & context_head_tile_mask)) begin
                protocol_error_o <= 1'b1;
            end

            if (command_fire) begin
                feed_active_q <= 1'b1;
                feed_read_index_q <= '0;
                feed_read_count_q <= {1'b0, gemm_command.k_blocks, 4'd0};
                feed_row_mask_q <= incoming_row_mask;
                feed_column_mask_q <= incoming_column_mask;
                feed_anchor_x_q <= gemm_command.tile_anchor_x;
                feed_anchor_y_q <= gemm_command.tile_anchor_y;
                feed_tile_span_q <= gemm_command.tile_span;
                feed_activation_format_q <= gemm_command.activation_format;
                feed_weight_format_q <= gemm_command.weight_format;
                feed_rounding_q <= gemm_command.rounding;
                feed_activation_buffer_id_q <= activation_command.buffer_id;
                feed_activation_base_offset_q <= activation_command.base_offset;
                feed_weight_buffer_id_q <= weight_command.buffer_id;
                feed_weight_base_offset_q <= weight_command.base_offset;
            end
            if (read_issue) begin
                if (feed_active_q) begin
                    if (feed_last_read) begin
                        if (!command_fire) begin
                            feed_active_q <= 1'b0;
                        end
                        feed_read_index_q <= '0;
                    end else begin
                        feed_read_index_q <= feed_read_index_q + 20'd1;
                    end
                end else begin
                    feed_read_index_q <= 20'd1;
                end
            end

            read_meta_valid_q <= read_issue;
            if (read_issue) begin
                read_meta_row_mask_q <= feed_active_q ?
                    feed_row_mask_q : incoming_row_mask;
                read_meta_column_mask_q <= feed_active_q ?
                    feed_column_mask_q : incoming_column_mask;
                read_meta_anchor_x_q <= feed_active_q ?
                    feed_anchor_x_q : gemm_command.tile_anchor_x;
                read_meta_anchor_y_q <= feed_active_q ?
                    feed_anchor_y_q : gemm_command.tile_anchor_y;
                read_meta_activation_format_q <= feed_active_q ?
                    feed_activation_format_q : gemm_command.activation_format;
                read_meta_weight_format_q <= feed_active_q ?
                    feed_weight_format_q : gemm_command.weight_format;
                read_meta_rounding_q <= feed_active_q ?
                    feed_rounding_q : gemm_command.rounding;
            end

            if (pair_push) begin
                pair_activation_mem[pair_write_pointer_q] <= activation_read_data_i;
                pair_weight_mem[pair_write_pointer_q] <= weight_read_data_i;
                pair_row_mask_mem[pair_write_pointer_q] <= read_meta_row_mask_q;
                pair_column_mask_mem[pair_write_pointer_q] <=
                    read_meta_column_mask_q;
                pair_anchor_x_mem[pair_write_pointer_q] <= read_meta_anchor_x_q;
                pair_anchor_y_mem[pair_write_pointer_q] <= read_meta_anchor_y_q;
                pair_activation_format_mem[pair_write_pointer_q] <=
                    read_meta_activation_format_q;
                pair_weight_format_mem[pair_write_pointer_q] <=
                    read_meta_weight_format_q;
                pair_rounding_mem[pair_write_pointer_q] <= read_meta_rounding_q;
                if (pair_write_pointer_q ==
                    PAIR_POINTER_WIDTH'(PAIR_DEPTH - 1)) begin
                    pair_write_pointer_q <= '0;
                end else begin
                    pair_write_pointer_q <= pair_write_pointer_q + 1'b1;
                end
            end
            if (pair_pop) begin
                if (pair_read_pointer_q ==
                    PAIR_POINTER_WIDTH'(PAIR_DEPTH - 1)) begin
                    pair_read_pointer_q <= '0;
                end else begin
                    pair_read_pointer_q <= pair_read_pointer_q + 1'b1;
                end
            end
            unique case ({pair_push, pair_pop})
                2'b10: pair_level_q <= pair_level_q + 1'b1;
                2'b01: pair_level_q <= pair_level_q - 1'b1;
                default: pair_level_q <= pair_level_q;
            endcase

            if (command_fire) begin
                context_tag_mem[context_write_pointer_q] <= gemm_command.tag;
                context_job_id_mem[context_write_pointer_q] <=
                    gemm_command.job_id;
                context_tile_mask_mem[context_write_pointer_q] <= incoming_tile_mask;
                context_anchor_x_mem[context_write_pointer_q] <=
                    gemm_command.tile_anchor_x;
                context_anchor_y_mem[context_write_pointer_q] <=
                    gemm_command.tile_anchor_y;
                context_tile_span_mem[context_write_pointer_q] <=
                    gemm_command.tile_span;
                if (context_write_pointer_q ==
                    CONTEXT_POINTER_WIDTH'(CONTEXT_DEPTH - 1)) begin
                    context_write_pointer_q <= '0;
                end else begin
                    context_write_pointer_q <= context_write_pointer_q + 1'b1;
                end
            end
            if (context_pop) begin
                if (context_read_pointer_q ==
                    CONTEXT_POINTER_WIDTH'(CONTEXT_DEPTH - 1)) begin
                    context_read_pointer_q <= '0;
                end else begin
                    context_read_pointer_q <= context_read_pointer_q + 1'b1;
                end
                context_output_done_q <= 1'b0;
                vector_output_done_q <= '0;
                for (integer physical_y = 0; physical_y < ARRAY_DIM;
                     physical_y++) begin
                    vector_output_local_row_q[physical_y] <= '0;
                    vector_output_segment_q[physical_y] <= '0;
                end
            end

            if (collect_context_complete) begin
                if (collect_context_pointer_q ==
                    CONTEXT_POINTER_WIDTH'(CONTEXT_DEPTH - 1)) begin
                    collect_context_pointer_q <= '0;
                end else begin
                    collect_context_pointer_q <=
                        collect_context_pointer_q + 1'b1;
                end
                collect_done_q <= '0;
                for (integer physical_y = 0; physical_y < ARRAY_DIM;
                     physical_y++) begin
                    collect_local_row_q[physical_y] <= '0;
                    collect_segment_q[physical_y] <= '0;
                end
            end else begin
                for (integer physical_y = 0; physical_y < ARRAY_DIM;
                     physical_y++) begin
                    if (row_fifo_input_valid[physical_y] &&
                        row_fifo_input_ready[physical_y]) begin
                        if (collect_segment_q[physical_y] + 5'd1 ==
                            collect_context_tile_span) begin
                            collect_segment_q[physical_y] <= '0;
                            if (collect_local_row_q[physical_y] == 4'd15) begin
                                collect_done_q[physical_y] <= 1'b1;
                            end else begin
                                collect_local_row_q[physical_y] <=
                                    collect_local_row_q[physical_y] + 4'd1;
                            end
                        end else begin
                            collect_segment_q[physical_y] <=
                                collect_segment_q[physical_y] + 5'd1;
                        end
                    end
                end
            end

            if (!context_pop) begin
                for (integer physical_y = 0; physical_y < ARRAY_DIM;
                     physical_y++) begin
                    if (vector_result_fire[physical_y]) begin
                        if ((vector_output_segment_q[physical_y] + 5'd1) ==
                            context_head_tile_span) begin
                            vector_output_segment_q[physical_y] <= '0;
                            if (vector_output_local_row_q[physical_y] == 4'd15) begin
                                vector_output_local_row_q[physical_y] <= '0;
                                vector_output_done_q[physical_y] <= 1'b1;
                            end else begin
                                vector_output_local_row_q[physical_y] <=
                                    vector_output_local_row_q[physical_y] + 4'd1;
                            end
                        end else begin
                            vector_output_segment_q[physical_y] <=
                                vector_output_segment_q[physical_y] + 5'd1;
                        end
                    end
                end
                if (vector_context_complete) begin
                    context_output_done_q <= 1'b1;
                end
            end
            unique case ({command_fire, context_pop})
                2'b10: context_level_q <= context_level_q + 1'b1;
                2'b01: context_level_q <= context_level_q - 1'b1;
                default: context_level_q <= context_level_q;
            endcase
            unique case ({command_fire, collect_context_complete})
                2'b10: collect_context_level_q <=
                    collect_context_level_q + 1'b1;
                2'b01: collect_context_level_q <=
                    collect_context_level_q - 1'b1;
                default: collect_context_level_q <= collect_context_level_q;
            endcase
        end
    end

    initial begin
        assert (PAIR_DEPTH > 1)
            else $error("npu_square_gemm_executor PAIR_DEPTH must exceed one");
        assert (CONTEXT_DEPTH > 0)
            else $error("npu_square_gemm_executor CONTEXT_DEPTH must be positive");
        assert (RESULT_FIFO_DEPTH > 0)
            else $error("npu_square_gemm_executor RESULT_FIFO_DEPTH must be positive");
    end

    wire _unused_command_fields = &{1'b0, gemm_command.matrix_size,
        activation_command.job_id,
        activation_command.tag, activation_command.matrix_size,
        activation_command.tile_anchor_x, activation_command.tile_anchor_y,
        activation_command.tile_span, activation_command.format,
        activation_command.rounding, weight_command.job_id, weight_command.tag,
        weight_command.matrix_size, weight_command.tile_anchor_x,
        weight_command.tile_anchor_y, weight_command.tile_span,
        weight_command.format, weight_command.rounding, result_command_i,
        feed_tile_span_q, row_fifo_level};

endmodule

`default_nettype wire
