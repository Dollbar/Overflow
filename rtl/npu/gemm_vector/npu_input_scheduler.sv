`timescale 1ns/1ps
`default_nettype none

// Front-end boundary: task descriptors and every referenced tensor already
// reside in local input buffers. The compiler owns Tile placement and
// dependency legality; hardware allocates tags and atomically expands each ready
// task into independent command FIFOs.
module npu_input_scheduler #(
    parameter int unsigned TASK_SLOTS = 8,
    parameter int unsigned ACTIVE_CONTEXTS = 16,
    parameter int unsigned COMMAND_FIFO_DEPTH = 4
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic task_valid_i,
    output logic task_ready_o,
    input  logic [npu_scheduler_pkg::NPU_TASK_DESCRIPTOR_WIDTH-1:0] task_i,

    input  logic completion_valid_i,
    output logic completion_ready_o,
    input  logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_i,
    input  logic completion_success_i,

    input  logic event_set_valid_i,
    input  logic [npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0] event_set_id_i,
    input  logic event_clear_valid_i,
    input  logic [npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0] event_clear_id_i,

    output logic gemm_command_valid_o,
    input  logic gemm_command_ready_i,
    output logic [npu_scheduler_pkg::NPU_GEMM_COMMAND_WIDTH-1:0]
                 gemm_command_o,

    output logic activation_command_valid_o,
    input  logic activation_command_ready_i,
    output logic [npu_scheduler_pkg::NPU_BUFFER_READ_COMMAND_WIDTH-1:0]
                 activation_command_o,

    output logic weight_command_valid_o,
    input  logic weight_command_ready_i,
    output logic [npu_scheduler_pkg::NPU_BUFFER_READ_COMMAND_WIDTH-1:0]
                 weight_command_o,

    output logic vector_command_valid_o,
    input  logic vector_command_ready_i,
    output logic [npu_scheduler_pkg::NPU_VECTOR_COMMAND_WIDTH-1:0]
                 vector_command_o,

    output logic result_command_valid_o,
    input  logic result_command_ready_i,
    output logic [npu_scheduler_pkg::NPU_RESULT_COMMAND_WIDTH-1:0]
                 result_command_o,

    output logic post_command_valid_o,
    input  logic post_command_ready_i,
    output logic [npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 post_command_o,

    output logic status_valid_o,
    input  logic status_ready_i,
    output logic [npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH-1:0] status_o,

    output logic [$clog2(TASK_SLOTS+1)-1:0] task_level_o,
    output logic [$clog2(ACTIVE_CONTEXTS+1)-1:0] active_contexts_o,
    output logic protocol_error_o
);

    localparam int unsigned TASK_INDEX_WIDTH =
        (TASK_SLOTS <= 1) ? 1 : $clog2(TASK_SLOTS);
    localparam int unsigned CONTEXT_INDEX_WIDTH =
        (ACTIVE_CONTEXTS <= 1) ? 1 : $clog2(ACTIVE_CONTEXTS);
    localparam int unsigned TASK_LEVEL_WIDTH = $clog2(TASK_SLOTS + 1);
    localparam int unsigned CONTEXT_LEVEL_WIDTH = $clog2(ACTIVE_CONTEXTS + 1);

    npu_scheduler_pkg::npu_task_descriptor_t task_mem [0:TASK_SLOTS-1];
    logic [TASK_SLOTS-1:0] task_valid_q;
    logic [TASK_INDEX_WIDTH-1:0] issue_round_robin_q;
    logic [255:0] event_done_q;

    logic context_active_q [0:ACTIVE_CONTEXTS-1];
    logic [3:0] context_epoch_q [0:ACTIVE_CONTEXTS-1];
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
        context_tag_q [0:ACTIVE_CONTEXTS-1];
    logic [npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0]
        context_job_id_q [0:ACTIVE_CONTEXTS-1];
    logic context_signal_event_valid_q [0:ACTIVE_CONTEXTS-1];
    logic [npu_scheduler_pkg::NPU_EVENT_ID_WIDTH-1:0]
        context_signal_event_id_q [0:ACTIVE_CONTEXTS-1];

    logic [TASK_SLOTS-1:0] free_task_vector;
    logic free_task_valid;
    logic [TASK_INDEX_WIDTH-1:0] free_task_index;
    logic [TASK_INDEX_WIDTH-1:0] task_write_index;
    logic task_accept;
    logic task_consume;
    logic [TASK_INDEX_WIDTH-1:0] consumed_task_index;

    logic context_free_valid;
    logic [CONTEXT_INDEX_WIDTH-1:0] context_free_index;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] issue_tag;

    logic slot_dependency_met [0:TASK_SLOTS-1];
    logic slot_issue_ready [0:TASK_SLOTS-1];
    logic [4:0] slot_tile_span [0:TASK_SLOTS-1];

    logic selected_task_valid;
    logic [TASK_INDEX_WIDTH-1:0] selected_task_index;
    npu_scheduler_pkg::npu_task_descriptor_t selected_descriptor;
    logic [4:0] selected_tile_span;
    logic issue_fire;

    logic completion_context_in_range;
    logic [CONTEXT_INDEX_WIDTH-1:0] completion_context_index;
    logic completion_context_match;
    logic completion_fire;
    logic completion_release;

    npu_scheduler_pkg::npu_gemm_command_t gemm_command_input;
    npu_scheduler_pkg::npu_buffer_read_command_t activation_command_input;
    npu_scheduler_pkg::npu_buffer_read_command_t weight_command_input;
    npu_scheduler_pkg::npu_vector_command_t vector_command_input;
    npu_scheduler_pkg::npu_result_command_t result_command_input;
    npu_scheduler_pkg::npu_post_command_t post_command_input;
    npu_scheduler_pkg::npu_task_status_t status_input;

    logic gemm_fifo_input_ready;
    logic activation_fifo_input_ready;
    logic weight_fifo_input_ready;
    logic vector_fifo_input_ready;
    logic result_fifo_input_ready;
    logic post_fifo_input_ready;
    logic status_fifo_input_ready;
    logic status_fifo_input_valid;
    logic [npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH-1:0] status_fifo_input_data;
    logic [$clog2(COMMAND_FIFO_DEPTH+1)-1:0] unused_gemm_level;
    logic [$clog2(COMMAND_FIFO_DEPTH+1)-1:0] unused_activation_level;
    logic [$clog2(COMMAND_FIFO_DEPTH+1)-1:0] unused_weight_level;
    logic [$clog2(COMMAND_FIFO_DEPTH+1)-1:0] unused_vector_level;
    logic [$clog2(COMMAND_FIFO_DEPTH+1)-1:0] unused_result_level;
    logic [$clog2(COMMAND_FIFO_DEPTH+1)-1:0] unused_post_level;
    logic [$clog2(COMMAND_FIFO_DEPTH+1)-1:0] unused_status_level;

    always_comb begin
        free_task_vector = ~task_valid_q;
        free_task_valid = 1'b0;
        free_task_index = '0;
        for (integer slot = 0; slot < TASK_SLOTS; slot++) begin
            if (!free_task_valid && free_task_vector[slot]) begin
                free_task_valid = 1'b1;
                free_task_index = TASK_INDEX_WIDTH'(slot);
            end
        end
        task_write_index = free_task_valid ? free_task_index :
            consumed_task_index;
        task_ready_o = !rst_i && !clear_i &&
            (free_task_valid || task_consume);
        task_accept = task_valid_i && task_ready_o;
    end

    always_comb begin
        context_free_valid = 1'b0;
        context_free_index = '0;
        active_contexts_o = '0;
        for (integer context_index = 0;
             context_index < ACTIVE_CONTEXTS; context_index++) begin
            if (!context_active_q[context_index] && !context_free_valid) begin
                context_free_valid = 1'b1;
                context_free_index = CONTEXT_INDEX_WIDTH'(context_index);
            end
            if (context_active_q[context_index]) begin
                active_contexts_o = active_contexts_o + CONTEXT_LEVEL_WIDTH'(1);
            end
        end
        issue_tag = {
            context_epoch_q[context_free_index],
            4'(context_free_index)
        };
    end

    always_comb begin
        task_level_o = '0;
        for (integer slot = 0; slot < TASK_SLOTS; slot++) begin
            task_level_o = task_level_o +
                TASK_LEVEL_WIDTH'(task_valid_q[slot]);
            slot_tile_span[slot] = task_mem[slot].tile_span;
            slot_dependency_met[slot] =
                !task_mem[slot].wait_event_valid ||
                event_done_q[task_mem[slot].wait_event_id];
            slot_issue_ready[slot] = task_valid_q[slot] &&
                slot_dependency_met[slot] && context_free_valid &&
                gemm_fifo_input_ready &&
                activation_fifo_input_ready && weight_fifo_input_ready &&
                result_fifo_input_ready && post_fifo_input_ready &&
                ((task_mem[slot].post_route !=
                  npu_scheduler_pkg::NPU_POST_VECTOR) ||
                 vector_fifo_input_ready);
        end
    end

    always_comb begin
        integer scan_slot;
        selected_task_valid = 1'b0;
        selected_task_index = '0;
        scan_slot = 0;

        for (integer offset = 0; offset < TASK_SLOTS; offset++) begin
            scan_slot = integer'(issue_round_robin_q) + offset;
            if (scan_slot >= TASK_SLOTS) begin
                scan_slot = scan_slot - TASK_SLOTS;
            end
            if (!selected_task_valid && slot_issue_ready[scan_slot]) begin
                selected_task_valid = 1'b1;
                selected_task_index = TASK_INDEX_WIDTH'(scan_slot);
            end
        end
    end

    always_comb begin
        selected_descriptor = task_mem[selected_task_index];
        selected_tile_span = slot_tile_span[selected_task_index];
        issue_fire = selected_task_valid && !rst_i && !clear_i;
        task_consume = issue_fire;
        consumed_task_index = selected_task_index;
    end

    always_comb begin
        completion_context_in_range =
            ({1'b0, completion_tag_i[3:0]} <
             5'(ACTIVE_CONTEXTS));
        completion_context_index =
            CONTEXT_INDEX_WIDTH'(completion_tag_i[3:0]);
        completion_context_match = 1'b0;
        if (completion_context_in_range) begin
            completion_context_match =
                context_active_q[completion_context_index] &&
                (context_tag_q[completion_context_index] == completion_tag_i);
        end
        completion_ready_o = !rst_i && !clear_i && status_fifo_input_ready;
        completion_fire = completion_valid_i && completion_ready_o;
        completion_release = completion_fire && completion_context_match;
    end

    always_comb begin
        gemm_command_input = '0;
        gemm_command_input.job_id = selected_descriptor.job_id;
        gemm_command_input.tag = issue_tag;
        gemm_command_input.tile_anchor_x = selected_descriptor.tile_anchor_x;
        gemm_command_input.tile_anchor_y = selected_descriptor.tile_anchor_y;
        gemm_command_input.tile_span = selected_tile_span;
        gemm_command_input.k_blocks = selected_descriptor.k_blocks;
        gemm_command_input.matrix_size = selected_descriptor.matrix_size;
        gemm_command_input.activation_format = selected_descriptor.activation_format;
        gemm_command_input.weight_format = selected_descriptor.weight_format;
        gemm_command_input.rounding = selected_descriptor.rounding;

        activation_command_input = '0;
        activation_command_input.job_id = selected_descriptor.job_id;
        activation_command_input.tag = issue_tag;
        activation_command_input.buffer_id =
            selected_descriptor.activation_buffer_id;
        activation_command_input.base_offset =
            selected_descriptor.activation_base_offset;
        activation_command_input.matrix_size = selected_descriptor.matrix_size;
        activation_command_input.tile_anchor_x = selected_descriptor.tile_anchor_x;
        activation_command_input.tile_anchor_y = selected_descriptor.tile_anchor_y;
        activation_command_input.tile_span = selected_tile_span;
        activation_command_input.format = selected_descriptor.activation_format;
        activation_command_input.rounding = selected_descriptor.rounding;

        weight_command_input = '0;
        weight_command_input.job_id = selected_descriptor.job_id;
        weight_command_input.tag = issue_tag;
        weight_command_input.buffer_id = selected_descriptor.weight_buffer_id;
        weight_command_input.base_offset = selected_descriptor.weight_base_offset;
        weight_command_input.matrix_size = selected_descriptor.matrix_size;
        weight_command_input.tile_anchor_x = selected_descriptor.tile_anchor_x;
        weight_command_input.tile_anchor_y = selected_descriptor.tile_anchor_y;
        weight_command_input.tile_span = selected_tile_span;
        weight_command_input.format = selected_descriptor.weight_format;
        weight_command_input.rounding = selected_descriptor.rounding;

        vector_command_input = '0;
        vector_command_input.job_id = selected_descriptor.job_id;
        vector_command_input.tag = issue_tag;
        vector_command_input.matrix_size = selected_descriptor.matrix_size;
        vector_command_input.vectors_per_row = selected_tile_span;
        vector_command_input.control = selected_descriptor.vector_control;
        vector_command_input.control.tag = issue_tag;
        vector_command_input.operand_b_buffer_id =
            selected_descriptor.vector_b_buffer_id;
        vector_command_input.operand_b_base_offset =
            selected_descriptor.vector_b_base_offset;
        vector_command_input.operand_c_buffer_id =
            selected_descriptor.vector_c_buffer_id;
        vector_command_input.operand_c_base_offset =
            selected_descriptor.vector_c_base_offset;
        vector_command_input.scalar = selected_descriptor.vector_scalar;

        result_command_input = '0;
        result_command_input.job_id = selected_descriptor.job_id;
        result_command_input.tag = issue_tag;
        result_command_input.source =
            (selected_descriptor.post_route ==
             npu_scheduler_pkg::NPU_POST_VECTOR) ?
            npu_scheduler_pkg::NPU_RESULT_FROM_VECTOR :
            npu_scheduler_pkg::NPU_RESULT_FROM_GEMM;
        result_command_input.buffer_id = selected_descriptor.output_buffer_id;
        result_command_input.base_offset = selected_descriptor.output_base_offset;
        result_command_input.matrix_size = selected_descriptor.matrix_size;
        result_command_input.vectors_per_row = selected_tile_span;
        result_command_input.output_format = selected_descriptor.output_format;
        result_command_input.signal_event_valid =
            selected_descriptor.signal_event_valid;
        result_command_input.signal_event_id = selected_descriptor.signal_event_id;

        post_command_input = '0;
        post_command_input.job_id = selected_descriptor.job_id;
        post_command_input.tag = issue_tag;
        post_command_input.matrix_size = selected_descriptor.matrix_size;
        post_command_input.vectors_per_row = selected_tile_span;
        post_command_input.route = selected_descriptor.post_route;
        post_command_input.vector_control = selected_descriptor.vector_control;
        post_command_input.vector_control.tag = issue_tag;
        post_command_input.operand_b_buffer_id =
            selected_descriptor.vector_b_buffer_id;
        post_command_input.operand_b_base_offset =
            selected_descriptor.vector_b_base_offset;
        post_command_input.operand_c_buffer_id =
            selected_descriptor.vector_c_buffer_id;
        post_command_input.operand_c_base_offset =
            selected_descriptor.vector_c_base_offset;
        post_command_input.scalar = selected_descriptor.vector_scalar;
        post_command_input.destination_buffer_id =
            selected_descriptor.output_buffer_id;
        post_command_input.destination_base_offset =
            selected_descriptor.output_base_offset;
        post_command_input.destination_operand =
            selected_descriptor.feedback_operand;
        post_command_input.transpose_enable =
            selected_descriptor.feedback_transpose;
        post_command_input.destination_format =
            selected_descriptor.activation_format;
        post_command_input.destination_rounding =
            selected_descriptor.rounding;
        post_command_input.output_format = selected_descriptor.output_format;
        post_command_input.signal_event_valid =
            selected_descriptor.signal_event_valid;
        post_command_input.signal_event_id =
            selected_descriptor.signal_event_id;
    end

    always_comb begin
        status_input = '0;
        if (completion_context_match) begin
            status_input.job_id =
                context_job_id_q[completion_context_index];
            status_input.tag = completion_tag_i;
            status_input.success = completion_success_i;
            status_input.code = completion_success_i ?
                npu_scheduler_pkg::NPU_TASK_STATUS_OK :
                npu_scheduler_pkg::NPU_TASK_ERROR_COMPLETION;
        end else begin
            status_input.job_id = '0;
            status_input.tag = completion_tag_i;
            status_input.success = 1'b0;
            status_input.code =
                npu_scheduler_pkg::NPU_TASK_ERROR_COMPLETION;
        end
        status_fifo_input_valid = completion_valid_i;
        status_fifo_input_data = status_input;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            task_valid_q <= '0;
            issue_round_robin_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            if (task_consume) begin
                task_valid_q[consumed_task_index] <= 1'b0;
                if (consumed_task_index == TASK_INDEX_WIDTH'(TASK_SLOTS - 1)) begin
                    issue_round_robin_q <= '0;
                end else begin
                    issue_round_robin_q <= consumed_task_index + 1'b1;
                end
            end
            // A full queue may replace the slot issued in this cycle.  Keep
            // this assignment after retirement so the new descriptor remains valid.
            if (task_accept) begin
                task_mem[task_write_index] <=
                    npu_scheduler_pkg::npu_task_descriptor_t'(task_i);
                task_valid_q[task_write_index] <= 1'b1;
            end
            if (completion_fire && !completion_context_match) begin
                protocol_error_o <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            event_done_q <= '0;
            for (integer context_index = 0;
                 context_index < ACTIVE_CONTEXTS; context_index++) begin
                context_active_q[context_index] <= 1'b0;
                context_epoch_q[context_index] <= 4'd0;
            end
        end else if (clear_i) begin
            event_done_q <= '0;
            for (integer context_index = 0;
                 context_index < ACTIVE_CONTEXTS; context_index++) begin
                context_active_q[context_index] <= 1'b0;
                context_epoch_q[context_index] <=
                    context_epoch_q[context_index] + 4'd1;
            end
        end else begin
            if (event_clear_valid_i) begin
                event_done_q[event_clear_id_i] <= 1'b0;
            end
            if (event_set_valid_i) begin
                event_done_q[event_set_id_i] <= 1'b1;
            end
            if (issue_fire) begin
                context_active_q[context_free_index] <= 1'b1;
                context_tag_q[context_free_index] <= issue_tag;
                context_job_id_q[context_free_index] <= selected_descriptor.job_id;
                context_signal_event_valid_q[context_free_index] <=
                    selected_descriptor.signal_event_valid;
                context_signal_event_id_q[context_free_index] <=
                    selected_descriptor.signal_event_id;
            end
            if (completion_release) begin
                context_active_q[completion_context_index] <= 1'b0;
                context_epoch_q[completion_context_index] <=
                    context_epoch_q[completion_context_index] + 4'd1;
                if (completion_success_i &&
                    context_signal_event_valid_q[completion_context_index]) begin
                    event_done_q[
                        context_signal_event_id_q[completion_context_index]
                    ] <= 1'b1;
                end
            end
        end
    end

    npu_scheduler_fifo #(
        .WIDTH(npu_scheduler_pkg::NPU_GEMM_COMMAND_WIDTH),
        .DEPTH(COMMAND_FIFO_DEPTH)
    ) u_gemm_command_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(issue_fire), .input_ready_o(gemm_fifo_input_ready),
        .input_data_i(gemm_command_input),
        .output_valid_o(gemm_command_valid_o),
        .output_ready_i(gemm_command_ready_i),
        .output_data_o(gemm_command_o), .level_o(unused_gemm_level)
    );

    npu_scheduler_fifo #(
        .WIDTH(npu_scheduler_pkg::NPU_BUFFER_READ_COMMAND_WIDTH),
        .DEPTH(COMMAND_FIFO_DEPTH)
    ) u_activation_command_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(issue_fire),
        .input_ready_o(activation_fifo_input_ready),
        .input_data_i(activation_command_input),
        .output_valid_o(activation_command_valid_o),
        .output_ready_i(activation_command_ready_i),
        .output_data_o(activation_command_o),
        .level_o(unused_activation_level)
    );

    npu_scheduler_fifo #(
        .WIDTH(npu_scheduler_pkg::NPU_BUFFER_READ_COMMAND_WIDTH),
        .DEPTH(COMMAND_FIFO_DEPTH)
    ) u_weight_command_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(issue_fire),
        .input_ready_o(weight_fifo_input_ready),
        .input_data_i(weight_command_input),
        .output_valid_o(weight_command_valid_o),
        .output_ready_i(weight_command_ready_i),
        .output_data_o(weight_command_o), .level_o(unused_weight_level)
    );

    npu_scheduler_fifo #(
        .WIDTH(npu_scheduler_pkg::NPU_VECTOR_COMMAND_WIDTH),
        .DEPTH(COMMAND_FIFO_DEPTH)
    ) u_vector_command_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(issue_fire &&
            (selected_descriptor.post_route ==
             npu_scheduler_pkg::NPU_POST_VECTOR)),
        .input_ready_o(vector_fifo_input_ready),
        .input_data_i(vector_command_input),
        .output_valid_o(vector_command_valid_o),
        .output_ready_i(vector_command_ready_i),
        .output_data_o(vector_command_o), .level_o(unused_vector_level)
    );

    npu_scheduler_fifo #(
        .WIDTH(npu_scheduler_pkg::NPU_RESULT_COMMAND_WIDTH),
        .DEPTH(COMMAND_FIFO_DEPTH)
    ) u_result_command_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(issue_fire), .input_ready_o(result_fifo_input_ready),
        .input_data_i(result_command_input),
        .output_valid_o(result_command_valid_o),
        .output_ready_i(result_command_ready_i),
        .output_data_o(result_command_o), .level_o(unused_result_level)
    );

    npu_scheduler_fifo #(
        .WIDTH(npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH),
        .DEPTH(COMMAND_FIFO_DEPTH)
    ) u_post_command_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(issue_fire), .input_ready_o(post_fifo_input_ready),
        .input_data_i(post_command_input),
        .output_valid_o(post_command_valid_o),
        .output_ready_i(post_command_ready_i),
        .output_data_o(post_command_o), .level_o(unused_post_level)
    );

    npu_scheduler_fifo #(
        .WIDTH(npu_scheduler_pkg::NPU_TASK_STATUS_WIDTH),
        .DEPTH(COMMAND_FIFO_DEPTH)
    ) u_status_fifo (
        .clk_i(clk_i), .rst_i(rst_i), .clear_i(clear_i),
        .input_valid_i(status_fifo_input_valid),
        .input_ready_o(status_fifo_input_ready),
        .input_data_i(status_fifo_input_data),
        .output_valid_o(status_valid_o), .output_ready_i(status_ready_i),
        .output_data_o(status_o), .level_o(unused_status_level)
    );

    initial begin
        assert ((TASK_SLOTS > 0) && (TASK_SLOTS <= 16))
            else $error("TASK_SLOTS must be in 1..16");
        assert ((ACTIVE_CONTEXTS > 0) && (ACTIVE_CONTEXTS <= 16))
            else $error("ACTIVE_CONTEXTS must be in 1..16");
        assert (COMMAND_FIFO_DEPTH > 0)
            else $error("COMMAND_FIFO_DEPTH must be positive");
    end

    wire _unused_scheduler_fields = &{1'b0, selected_descriptor.version,
        selected_descriptor.operation, selected_descriptor.wait_event_valid,
        selected_descriptor.wait_event_id, selected_descriptor.tile_span};
    wire _unused_fifo_levels = &{1'b0, unused_gemm_level,
        unused_activation_level, unused_weight_level, unused_vector_level,
        unused_result_level, unused_post_level, unused_status_level,
        _unused_scheduler_fields};

endmodule

`default_nettype wire
