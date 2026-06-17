`timescale 1ns/1ps
`default_nettype none

// Origin-anchored square-GEMM feeder. A/B reads, array issue, and result
// retirement are independent streams. matrix_size selects only the logical
// prefix of the physical array; software cannot place or route Tile subarrays.
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
    input  logic activation_read_ready_i,
    output logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 activation_read_buffer_id_o,
    output logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 activation_read_offset_o,
    input  logic activation_read_valid_i,
    input  logic [ARRAY_DIM*128-1:0] activation_read_data_i,
    input  logic [ARRAY_DIM*128-1:0] activation_read_scale_i,
    output logic weight_read_enable_o,
    output logic [npu_scheduler_pkg::NPU_BUFFER_ID_WIDTH-1:0]
                 weight_read_buffer_id_o,
    output logic [npu_scheduler_pkg::NPU_BUFFER_OFFSET_WIDTH-1:0]
                 weight_read_offset_o,
    input  logic weight_read_valid_i,
    input  logic [ARRAY_DIM*128-1:0] weight_read_data_i,
    input  logic [ARRAY_DIM*128-1:0] weight_read_scale_i,

    output logic [ARRAY_DIM*16-1:0] wave_a_valid_o,
    output logic [ARRAY_DIM*128-1:0] wave_a_data_o,
    output logic [ARRAY_DIM*32-1:0] wave_a_format_o,
    output logic [ARRAY_DIM*128-1:0] wave_a_scale_o,
    output logic [ARRAY_DIM*16-1:0] wave_a_block_first_o,
    output logic [ARRAY_DIM*16-1:0] wave_a_block_last_o,
    output logic [ARRAY_DIM*16-1:0] wave_a_matrix_first_o,
    output logic [ARRAY_DIM*16-1:0] wave_a_matrix_last_o,
    output logic [ARRAY_DIM*128-1:0] wave_a_tag_o,
    output logic [ARRAY_DIM*16-1:0] wave_b_valid_o,
    output logic [ARRAY_DIM*128-1:0] wave_b_data_o,
    output logic [ARRAY_DIM*32-1:0] wave_b_format_o,
    output logic [ARRAY_DIM*128-1:0] wave_b_scale_o,

    output logic [ARRAY_DIM*ARRAY_DIM-1:0] result_ready_o,
    input  logic [ARRAY_DIM*ARRAY_DIM-1:0] result_valid_i,
    input  logic [ARRAY_DIM*ARRAY_DIM*512-1:0] result_data_i,
    input  logic [ARRAY_DIM*ARRAY_DIM*16-1:0] result_invalid_i,
    input  logic [ARRAY_DIM*ARRAY_DIM*8-1:0] result_tag_i,
    input  logic [ARRAY_DIM*ARRAY_DIM*4-1:0] result_row_i,
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
    logic [4:0] incoming_vectors_per_row;
    logic [ARRAY_DIM-1:0] incoming_row_mask;
    logic [ARRAY_DIM-1:0] incoming_column_mask;

    logic feed_active_q;
    logic [21:0] feed_read_index_q;
    logic [21:0] feed_read_count_q;
    logic [20:0] feed_k_elements_q;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] feed_tag_q;
    logic [ARRAY_DIM-1:0] feed_row_mask_q;
    logic [ARRAY_DIM-1:0] feed_column_mask_q;
    mxfp_pkg::mxfp_format_e feed_activation_format_q;
    mxfp_pkg::mxfp_format_e feed_weight_format_q;
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
    logic read_request;
    logic read_fire;
    logic [21:0] read_index;
    logic [21:0] incoming_read_count;
    logic [31:0] activation_read_byte_offset;
    logic [31:0] weight_read_byte_offset;

    logic read_meta_valid_q;
    logic [ARRAY_DIM-1:0] read_meta_row_mask_q;
    logic [ARRAY_DIM-1:0] read_meta_column_mask_q;
    logic [21:0] read_meta_wave_index_q;
    logic [20:0] read_meta_k_elements_q;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] read_meta_tag_q;
    mxfp_pkg::mxfp_format_e read_meta_activation_format_q;
    mxfp_pkg::mxfp_format_e read_meta_weight_format_q;
    logic [ARRAY_DIM*128-1:0] pair_activation_mem [0:PAIR_DEPTH-1];
    logic [ARRAY_DIM*128-1:0] pair_weight_mem [0:PAIR_DEPTH-1];
    logic [ARRAY_DIM*128-1:0] pair_activation_scale_mem [0:PAIR_DEPTH-1];
    logic [ARRAY_DIM*128-1:0] pair_weight_scale_mem [0:PAIR_DEPTH-1];
    logic [ARRAY_DIM-1:0] pair_row_mask_mem [0:PAIR_DEPTH-1];
    logic [ARRAY_DIM-1:0] pair_column_mask_mem [0:PAIR_DEPTH-1];
    logic [21:0] pair_wave_index_mem [0:PAIR_DEPTH-1];
    logic [20:0] pair_k_elements_mem [0:PAIR_DEPTH-1];
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
        pair_tag_mem [0:PAIR_DEPTH-1];
    mxfp_pkg::mxfp_format_e pair_activation_format_mem [0:PAIR_DEPTH-1];
    mxfp_pkg::mxfp_format_e pair_weight_format_mem [0:PAIR_DEPTH-1];
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
    logic [4:0] context_vectors_per_row_mem [0:CONTEXT_DEPTH-1];
    logic [CONTEXT_POINTER_WIDTH-1:0] context_write_pointer_q;
    logic [CONTEXT_POINTER_WIDTH-1:0] context_read_pointer_q;
    logic [CONTEXT_LEVEL_WIDTH-1:0] context_level_q;
    logic [CONTEXT_POINTER_WIDTH-1:0] collect_context_pointer_q;
    logic [CONTEXT_LEVEL_WIDTH-1:0] collect_context_level_q;
    logic [ARRAY_DIM-1:0] context_head_row_mask;
    logic [4:0] context_head_vectors_per_row;
    logic [ARRAY_DIM-1:0] collect_context_row_mask;
    logic [4:0] collect_context_vectors_per_row;
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

        incoming_vectors_per_row = 5'(
            (gemm_command.matrix_size + 16'd15) >> 4);
        incoming_row_mask = '0;
        incoming_column_mask = '0;
        for (integer row = 0; row < ARRAY_DIM; row++) begin
            if (row < integer'(incoming_vectors_per_row)) begin
                incoming_row_mask[row] = 1'b1;
            end
        end
        for (integer column = 0; column < ARRAY_DIM; column++) begin
            if (column < integer'(incoming_vectors_per_row)) begin
                incoming_column_mask[column] = 1'b1;
            end
        end
        command_bundle_valid = gemm_command_valid_i &&
            activation_command_valid_i && weight_command_valid_i &&
            result_command_valid_i;
        context_credit =
            (context_level_q < CONTEXT_LEVEL_WIDTH'(CONTEXT_DEPTH)) || context_pop;
        incoming_start_credit = 1'b1;
        command_bundle_ready = context_credit && incoming_start_credit &&
            (!feed_active_q ||
             (read_credit && feed_last_read && activation_read_ready_i));
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
        pair_sink_ready = 1'b1;
        pair_pop = pair_valid && pair_sink_ready;
        pair_push = activation_read_valid_i && weight_read_valid_i &&
                    read_meta_valid_q;
        read_credit = (((PAIR_LEVEL_WIDTH+1)'(pair_level_q) +
                        (PAIR_LEVEL_WIDTH+1)'(read_meta_valid_q)) <
                       (PAIR_LEVEL_WIDTH+1)'(PAIR_DEPTH)) || pair_pop;
        feed_last_read = feed_active_q &&
            ((feed_read_index_q + 22'd1) == feed_read_count_q);
        read_request = read_credit &&
                       (feed_active_q || (!feed_active_q && command_fire));
        read_fire = read_request && activation_read_ready_i;
        read_index = feed_active_q ? feed_read_index_q : 22'd0;
        incoming_read_count = {1'b0, gemm_command.k_blocks, 5'd0};
        activation_read_byte_offset = {6'd0, read_index, 4'd0};
        weight_read_byte_offset = {6'd0, read_index, 4'd0};

        activation_read_enable_o = read_request;
        // A and W remain a logical pair. The uncontended Weight SRAM is
        // launched only after the shared Activation SRAM accepts this wave.
        weight_read_enable_o = read_fire;
        activation_read_buffer_id_o = feed_active_q ?
            feed_activation_buffer_id_q : activation_command.buffer_id;
        weight_read_buffer_id_o = feed_active_q ?
            feed_weight_buffer_id_q : weight_command.buffer_id;
        activation_read_offset_o =
            (feed_active_q ? feed_activation_base_offset_q :
                             activation_command.base_offset) +
            activation_read_byte_offset;
        weight_read_offset_o =
            (feed_active_q ? feed_weight_base_offset_q :
                             weight_command.base_offset) + weight_read_byte_offset;
    end

    always_comb begin
        wave_a_valid_o = '0;
        wave_a_data_o = '0;
        wave_a_format_o = '0;
        wave_a_scale_o = '0;
        wave_a_block_first_o = '0;
        wave_a_block_last_o = '0;
        wave_a_matrix_first_o = '0;
        wave_a_matrix_last_o = '0;
        wave_a_tag_o = '0;
        wave_b_valid_o = '0;
        wave_b_data_o = '0;
        wave_b_format_o = '0;
        wave_b_scale_o = '0;
        for (integer physical = 0; physical < ARRAY_DIM; physical++) begin
            wave_a_format_o[physical*32 +: 32] =
                {16{pair_activation_format_mem[pair_read_pointer_q]}};
            wave_a_scale_o[physical*128 +: 128] =
                pair_activation_scale_mem[pair_read_pointer_q][physical*128 +: 128];
            wave_a_tag_o[physical*128 +: 128] = {16{
                pair_tag_mem[pair_read_pointer_q]}};
            wave_b_format_o[physical*32 +: 32] =
                {16{pair_weight_format_mem[pair_read_pointer_q]}};
            wave_b_scale_o[physical*128 +: 128] =
                pair_weight_scale_mem[pair_read_pointer_q][physical*128 +: 128];
            if (pair_valid &&
                pair_row_mask_mem[pair_read_pointer_q][physical]) begin
                wave_a_data_o[physical*128 +: 128] =
                    pair_activation_mem[pair_read_pointer_q][physical*128 +: 128];
            end
            if (pair_valid &&
                pair_column_mask_mem[pair_read_pointer_q][physical]) begin
                wave_b_data_o[physical*128 +: 128] =
                    pair_weight_mem[pair_read_pointer_q][physical*128 +: 128];
            end
            for (integer lane = 0; lane < 16; lane++) begin
                if (pair_valid &&
                    pair_row_mask_mem[pair_read_pointer_q][physical]) begin
                    wave_a_valid_o[physical*16 + lane] = 1'b1;
                    wave_a_block_first_o[physical*16 + lane] =
                        !pair_wave_index_mem[pair_read_pointer_q][4];
                    wave_a_block_last_o[physical*16 + lane] =
                        pair_wave_index_mem[pair_read_pointer_q][4];
                    wave_a_matrix_first_o[physical*16 + lane] =
                        (pair_wave_index_mem[pair_read_pointer_q] < 22'd16);
                    wave_a_matrix_last_o[physical*16 + lane] =
                        (pair_wave_index_mem[pair_read_pointer_q] + 22'd16 >=
                         {1'b0, pair_k_elements_mem[pair_read_pointer_q]});
                end
                if (pair_valid &&
                    pair_column_mask_mem[pair_read_pointer_q][physical]) begin
                    wave_b_valid_o[physical*16 + lane] = 1'b1;
                end
            end
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
        context_head_row_mask = '0;
        context_head_vectors_per_row = '0;
        if (context_level_q != '0) begin
            context_head_vectors_per_row =
                context_vectors_per_row_mem[context_read_pointer_q];
            for (integer context_row = 0; context_row < ARRAY_DIM;
                 context_row++) begin
                if (context_row < integer'(context_head_vectors_per_row)) begin
                    context_head_row_mask[context_row] = 1'b1;
                end
            end
        end

        collect_context_row_mask = '0;
        collect_context_vectors_per_row = '0;
        if (collect_context_level_q != '0) begin
            collect_context_vectors_per_row =
                context_vectors_per_row_mem[collect_context_pointer_q];
            for (integer collect_context_row = 0;
                 collect_context_row < ARRAY_DIM; collect_context_row++) begin
                if (collect_context_row <
                    integer'(collect_context_vectors_per_row)) begin
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
                (physical_y < integer'(collect_context_vectors_per_row))) begin
                for (integer physical_x = 0; physical_x < ARRAY_DIM;
                     physical_x++) begin
                    if (physical_x ==
                        integer'(collect_segment_q[physical_y])) begin
                        row_fifo_input_valid[physical_y] =
                            result_valid_i[physical_y*ARRAY_DIM + physical_x] &&
                            (result_tag_i[
                                (physical_y*ARRAY_DIM + physical_x)*8 +: 8
                             ] == context_tag_mem[collect_context_pointer_q]);
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
                            row_fifo_input_ready[physical_y] &&
                            (result_tag_i[
                                (physical_y*ARRAY_DIM + physical_x)*8 +: 8
                             ] == context_tag_mem[collect_context_pointer_q]);
                        collect_row_last_fire[physical_y] =
                            result_valid_i[physical_y*ARRAY_DIM + physical_x] &&
                            row_fifo_input_ready[physical_y] &&
                            (result_tag_i[
                                (physical_y*ARRAY_DIM + physical_x)*8 +: 8
                             ] == context_tag_mem[collect_context_pointer_q]) &&
                            (result_row_i[
                                (physical_y*ARRAY_DIM + physical_x)*4 +: 4
                            ] == 4'd15) &&
                            (collect_segment_q[physical_y] + 5'd1 ==
                             collect_context_vectors_per_row);
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
                if ((physical_y < integer'(context_head_vectors_per_row)) &&
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
                        (physical_y * 16) +
                        integer'(vector_output_local_row_q[physical_y])
                    );
                    vector_result_segment_o[physical_y*5 +: 5] =
                        vector_output_segment_q[physical_y];
                    vector_result_last_o[physical_y] =
                        (physical_y + 1 ==
                         integer'(context_head_vectors_per_row)) &&
                        (vector_output_local_row_q[physical_y] == 4'd15) &&
                        (vector_output_segment_q[physical_y] + 5'd1 ==
                         context_head_vectors_per_row);
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
                 context_head_vectors_per_row);
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
            feed_k_elements_q <= '0;
            feed_tag_q <= '0;
            feed_row_mask_q <= '0;
            feed_column_mask_q <= '0;
            feed_activation_format_q <= mxfp_pkg::MXFP8_E4M3;
            feed_weight_format_q <= mxfp_pkg::MXFP8_E4M3;
            feed_activation_buffer_id_q <= '0;
            feed_activation_base_offset_q <= '0;
            feed_weight_buffer_id_q <= '0;
            feed_weight_base_offset_q <= '0;
            read_meta_valid_q <= 1'b0;
            read_meta_row_mask_q <= '0;
            read_meta_column_mask_q <= '0;
            read_meta_wave_index_q <= '0;
            read_meta_k_elements_q <= '0;
            read_meta_tag_q <= '0;
            read_meta_activation_format_q <= mxfp_pkg::MXFP8_E4M3;
            read_meta_weight_format_q <= mxfp_pkg::MXFP8_E4M3;
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

            if (command_fire) begin
                feed_active_q <= 1'b1;
                feed_read_index_q <= '0;
                feed_read_count_q <= incoming_read_count;
                feed_k_elements_q <= {gemm_command.k_blocks, 5'd0};
                feed_tag_q <= gemm_command.tag;
                feed_row_mask_q <= incoming_row_mask;
                feed_column_mask_q <= incoming_column_mask;
                feed_activation_format_q <= gemm_command.activation_format;
                feed_weight_format_q <= gemm_command.weight_format;
                feed_activation_buffer_id_q <= activation_command.buffer_id;
                feed_activation_base_offset_q <= activation_command.base_offset;
                feed_weight_buffer_id_q <= weight_command.buffer_id;
                feed_weight_base_offset_q <= weight_command.base_offset;
            end
            if (read_fire) begin
                if (feed_active_q) begin
                    if (feed_last_read) begin
                        if (!command_fire) begin
                            feed_active_q <= 1'b0;
                        end
                        feed_read_index_q <= '0;
                    end else begin
                        feed_read_index_q <= feed_read_index_q + 22'd1;
                    end
                end else begin
                    feed_read_index_q <= 22'd1;
                end
            end

            read_meta_valid_q <= read_fire;
            if (read_fire) begin
                read_meta_row_mask_q <= feed_active_q ?
                    feed_row_mask_q : incoming_row_mask;
                read_meta_column_mask_q <= feed_active_q ?
                    feed_column_mask_q : incoming_column_mask;
                read_meta_wave_index_q <= read_index;
                read_meta_k_elements_q <= feed_active_q ?
                    feed_k_elements_q : {gemm_command.k_blocks, 5'd0};
                read_meta_tag_q <= feed_active_q ? feed_tag_q : gemm_command.tag;
                read_meta_activation_format_q <= feed_active_q ?
                    feed_activation_format_q : gemm_command.activation_format;
                read_meta_weight_format_q <= feed_active_q ?
                    feed_weight_format_q : gemm_command.weight_format;
            end

            if (pair_push) begin
                pair_activation_mem[pair_write_pointer_q] <=
                    activation_read_data_i;
                pair_weight_mem[pair_write_pointer_q] <= weight_read_data_i;
                pair_activation_scale_mem[pair_write_pointer_q] <=
                    activation_read_scale_i;
                pair_weight_scale_mem[pair_write_pointer_q] <=
                    weight_read_scale_i;
                pair_row_mask_mem[pair_write_pointer_q] <= read_meta_row_mask_q;
                pair_column_mask_mem[pair_write_pointer_q] <=
                    read_meta_column_mask_q;
                pair_wave_index_mem[pair_write_pointer_q] <=
                    read_meta_wave_index_q;
                pair_k_elements_mem[pair_write_pointer_q] <=
                    read_meta_k_elements_q;
                pair_tag_mem[pair_write_pointer_q] <= read_meta_tag_q;
                pair_activation_format_mem[pair_write_pointer_q] <=
                    read_meta_activation_format_q;
                pair_weight_format_mem[pair_write_pointer_q] <=
                    read_meta_weight_format_q;
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
                context_vectors_per_row_mem[context_write_pointer_q] <=
                    incoming_vectors_per_row;
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
                            collect_context_vectors_per_row) begin
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
                            context_head_vectors_per_row) begin
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
        activation_command.format,
        weight_command.job_id, weight_command.tag, weight_command.matrix_size,
        weight_command.format, result_command_i,
        row_fifo_level};

endmodule

`default_nettype wire
