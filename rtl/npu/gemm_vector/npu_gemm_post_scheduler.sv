`timescale 1ns/1ps
`default_nettype none

// Tag-indexed GEMM post scheduler. All destinations share one parallel result
// plane; route selection never serializes independent physical-row lanes.
module npu_gemm_post_scheduler #(
    parameter int unsigned CONTEXTS = 16,
    parameter int unsigned RESULT_CHANNELS = 16
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic post_command_valid_i,
    output logic post_command_ready_o,
    input  logic [npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 post_command_i,

    input  logic [RESULT_CHANNELS-1:0] gemm_valid_i,
    output logic [RESULT_CHANNELS-1:0] gemm_ready_o,
    input  logic [RESULT_CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 gemm_result_i,

    output logic [RESULT_CHANNELS-1:0] external_valid_o,
    input  logic [RESULT_CHANNELS-1:0] external_ready_i,
    output logic [RESULT_CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 external_result_o,
    output logic [RESULT_CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 external_command_o,

    output logic [RESULT_CHANNELS-1:0] vector_valid_o,
    input  logic [RESULT_CHANNELS-1:0] vector_ready_i,
    output logic [RESULT_CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 vector_result_o,
    output logic [RESULT_CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 vector_command_o,

    input  logic vector_completion_valid_i,
    output logic vector_completion_ready_o,
    input  logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
                 vector_completion_tag_i,
    input  logic vector_completion_success_i,

    output logic [RESULT_CHANNELS-1:0] feedback_valid_o,
    input  logic [RESULT_CHANNELS-1:0] feedback_ready_i,
    output logic [RESULT_CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 feedback_result_o,
    output logic [RESULT_CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 feedback_command_o,

    input  logic feedback_completion_valid_i,
    output logic feedback_completion_ready_o,
    input  logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
                 feedback_completion_tag_i,
    input  logic feedback_completion_success_i,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0]
                 completion_tag_o,
    output logic completion_success_o,

    output logic busy_o,
    output logic protocol_error_o
);

    localparam int unsigned CONTEXT_INDEX_WIDTH =
        (CONTEXTS <= 1) ? 1 : $clog2(CONTEXTS);

    npu_scheduler_pkg::npu_post_command_t command_input;
    npu_scheduler_pkg::npu_post_command_t
        context_command_mem [0:CONTEXTS-1];
    logic [CONTEXTS-1:0] context_valid_q;
    logic [20:0] expected_count_mem [0:CONTEXTS-1];
    logic [20:0] accepted_count_q [0:CONTEXTS-1];
    logic [CONTEXTS-1:0] dispatch_done_q;

    logic command_index_in_range;
    logic [CONTEXT_INDEX_WIDTH-1:0] command_index;
    logic command_fire;
    logic completion_slot_available;

    logic [RESULT_CHANNELS-1:0] lane_match;
    logic [RESULT_CHANNELS-1:0] lane_fire;
    logic [RESULT_CHANNELS*CONTEXT_INDEX_WIDTH-1:0] lane_context_index;
    logic [CONTEXTS*6-1:0] context_increment;
    logic [CONTEXTS-1:0] context_dispatch_complete;
    logic [CONTEXTS-1:0] context_terminal_complete;
    logic [5:0] terminal_completion_count;

    logic vector_completion_index_in_range;
    logic [CONTEXT_INDEX_WIDTH-1:0] vector_completion_index;
    logic vector_completion_match;
    logic vector_completion_fire;
    logic feedback_completion_index_in_range;
    logic [CONTEXT_INDEX_WIDTH-1:0] feedback_completion_index;
    logic feedback_completion_match;
    logic feedback_completion_fire;

    logic completion_valid_q;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_q;
    logic completion_success_q;

    always_comb begin
        command_input =
            npu_scheduler_pkg::npu_post_command_t'(post_command_i);
        command_index_in_range =
            ({1'b0, command_input.tag[3:0]} < 5'(CONTEXTS));
        command_index = CONTEXT_INDEX_WIDTH'(command_input.tag[3:0]);
        post_command_ready_o = !rst_i && !clear_i &&
            command_index_in_range && !context_valid_q[command_index];
        command_fire = post_command_valid_i && post_command_ready_o;

        completion_slot_available = !completion_valid_q || completion_ready_i;
        completion_valid_o = completion_valid_q;
        completion_tag_o = completion_tag_q;
        completion_success_o = completion_success_q;
        busy_o = (|context_valid_q) || completion_valid_q;
    end

    always_comb begin
        gemm_ready_o = '0;
        external_valid_o = '0;
        external_result_o = {
            RESULT_CHANNELS{
                npu_scheduler_pkg::NPU_POST_RESULT_WIDTH'(0)
            }
        };
        external_command_o = '0;
        vector_valid_o = '0;
        vector_result_o = {
            RESULT_CHANNELS{
                npu_scheduler_pkg::NPU_POST_RESULT_WIDTH'(0)
            }
        };
        vector_command_o = '0;
        feedback_valid_o = '0;
        feedback_result_o = {
            RESULT_CHANNELS{
                npu_scheduler_pkg::NPU_POST_RESULT_WIDTH'(0)
            }
        };
        feedback_command_o = '0;
        lane_match = '0;
        lane_fire = '0;
        lane_context_index = '0;
        context_increment = '0;
        context_dispatch_complete = '0;
        context_terminal_complete = '0;
        terminal_completion_count = '0;

        for (integer lane = 0; lane < RESULT_CHANNELS; lane++) begin
            logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] lane_tag;
            logic [npu_scheduler_pkg::NPU_JOB_ID_WIDTH-1:0] lane_job_id;
            logic [CONTEXT_INDEX_WIDTH-1:0] lane_index;
            logic lane_index_in_range;
            logic destination_ready;
            npu_scheduler_pkg::npu_post_result_beat_t lane_beat;
            npu_scheduler_pkg::npu_post_command_t lane_command;

            lane_beat = npu_scheduler_pkg::npu_post_result_beat_t'(
                gemm_result_i[
                    lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
                ]
            );
            lane_tag = lane_beat.tag;
            lane_job_id = lane_beat.job_id;
            lane_index = CONTEXT_INDEX_WIDTH'(lane_tag[3:0]);
            lane_index_in_range =
                ({1'b0, lane_tag[3:0]} < 5'(CONTEXTS));
            lane_command = context_command_mem[lane_index];
            lane_context_index[
                lane*CONTEXT_INDEX_WIDTH +: CONTEXT_INDEX_WIDTH
            ] = lane_index;
            lane_match[lane] = lane_index_in_range &&
                context_valid_q[lane_index] &&
                (lane_command.tag == lane_tag) &&
                (lane_command.job_id == lane_job_id);
            destination_ready = 1'b0;

            if (lane_match[lane]) begin
                unique case (lane_command.route)
                    npu_scheduler_pkg::NPU_POST_EXTERNAL: begin
                        external_valid_o[lane] = gemm_valid_i[lane];
                        external_result_o[
                            lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
                        ] = lane_beat;
                        external_command_o[
                            lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH
                        ] = lane_command;
                        destination_ready = external_ready_i[lane] &&
                            completion_slot_available;
                    end
                    npu_scheduler_pkg::NPU_POST_VECTOR: begin
                        vector_valid_o[lane] = gemm_valid_i[lane];
                        vector_result_o[
                            lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
                        ] = lane_beat;
                        vector_command_o[
                            lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH
                        ] = lane_command;
                        destination_ready = vector_ready_i[lane];
                    end
                    npu_scheduler_pkg::NPU_POST_GEMM: begin
                        feedback_valid_o[lane] = gemm_valid_i[lane];
                        feedback_result_o[
                            lane*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_RESULT_WIDTH
                        ] = lane_beat;
                        feedback_command_o[
                            lane*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                            npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH
                        ] = lane_command;
                        destination_ready = feedback_ready_i[lane] &&
                            completion_slot_available;
                    end
                    default: destination_ready = 1'b0;
                endcase
                gemm_ready_o[lane] = !rst_i && !clear_i && destination_ready;
            end
            lane_fire[lane] = gemm_valid_i[lane] && gemm_ready_o[lane];
        end

        for (integer ctx = 0; ctx < CONTEXTS; ctx++) begin
            for (integer lane = 0; lane < RESULT_CHANNELS; lane++) begin
                if (lane_fire[lane] &&
                    (lane_context_index[
                        lane*CONTEXT_INDEX_WIDTH +: CONTEXT_INDEX_WIDTH
                     ] == CONTEXT_INDEX_WIDTH'(ctx))) begin
                    context_increment[ctx*6 +: 6] =
                        context_increment[ctx*6 +: 6] + 6'd1;
                end
            end
            context_dispatch_complete[ctx] =
                context_valid_q[ctx] &&
                (context_increment[ctx*6 +: 6] != 6'd0) &&
                ((accepted_count_q[ctx] +
                  21'(context_increment[ctx*6 +: 6])) ==
                 expected_count_mem[ctx]);
            context_terminal_complete[ctx] =
                context_dispatch_complete[ctx] &&
                (context_command_mem[ctx].route ==
                 npu_scheduler_pkg::NPU_POST_EXTERNAL);
            if (context_terminal_complete[ctx]) begin
                terminal_completion_count = terminal_completion_count + 6'd1;
            end
        end
    end

    always_comb begin
        vector_completion_index_in_range =
            ({1'b0, vector_completion_tag_i[3:0]} < 5'(CONTEXTS));
        vector_completion_index = CONTEXT_INDEX_WIDTH'(
            vector_completion_tag_i[3:0]
        );
        vector_completion_match = vector_completion_index_in_range &&
            context_valid_q[vector_completion_index] &&
            dispatch_done_q[vector_completion_index] &&
            (context_command_mem[vector_completion_index].tag ==
             vector_completion_tag_i) &&
            (context_command_mem[vector_completion_index].route ==
             npu_scheduler_pkg::NPU_POST_VECTOR);
        vector_completion_ready_o = !rst_i && !clear_i &&
            vector_completion_match && completion_slot_available;
        vector_completion_fire = vector_completion_valid_i &&
            vector_completion_ready_o;

        feedback_completion_index_in_range =
            ({1'b0, feedback_completion_tag_i[3:0]} < 5'(CONTEXTS));
        feedback_completion_index = CONTEXT_INDEX_WIDTH'(
            feedback_completion_tag_i[3:0]
        );
        feedback_completion_match = feedback_completion_index_in_range &&
            context_valid_q[feedback_completion_index] &&
            dispatch_done_q[feedback_completion_index] &&
            (context_command_mem[feedback_completion_index].tag ==
             feedback_completion_tag_i) &&
            (context_command_mem[feedback_completion_index].route ==
             npu_scheduler_pkg::NPU_POST_GEMM);
        feedback_completion_ready_o = !rst_i && !clear_i &&
            feedback_completion_match && completion_slot_available &&
            !vector_completion_fire;
        feedback_completion_fire = feedback_completion_valid_i &&
            feedback_completion_ready_o;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            context_valid_q <= '0;
            dispatch_done_q <= '0;
            completion_valid_q <= 1'b0;
            completion_tag_q <= '0;
            completion_success_q <= 1'b0;
            protocol_error_o <= 1'b0;
            for (integer ctx = 0; ctx < CONTEXTS; ctx++) begin
                context_command_mem[ctx] <= '0;
                expected_count_mem[ctx] <= '0;
                accepted_count_q[ctx] <= '0;
            end
        end else begin
            if (completion_valid_q && completion_ready_i) begin
                completion_valid_q <= 1'b0;
            end

            if (command_fire) begin
                context_command_mem[command_index] <= command_input;
                context_valid_q[command_index] <= 1'b1;
                expected_count_mem[command_index] <=
                    command_input.matrix_size * command_input.vectors_per_row;
                accepted_count_q[command_index] <= '0;
                dispatch_done_q[command_index] <= 1'b0;
            end

            if (|(gemm_valid_i & ~lane_match)) begin
                protocol_error_o <= 1'b1;
            end
            if (terminal_completion_count > 6'd1) begin
                protocol_error_o <= 1'b1;
            end

            for (integer ctx = 0; ctx < CONTEXTS; ctx++) begin
                if (context_increment[ctx*6 +: 6] != 6'd0) begin
                    accepted_count_q[ctx] <= accepted_count_q[ctx] +
                        21'(context_increment[ctx*6 +: 6]);
                    if ((accepted_count_q[ctx] +
                         21'(context_increment[ctx*6 +: 6])) >
                        expected_count_mem[ctx]) begin
                        protocol_error_o <= 1'b1;
                    end
                    if (context_dispatch_complete[ctx]) begin
                        if ((context_command_mem[ctx].route ==
                             npu_scheduler_pkg::NPU_POST_VECTOR) ||
                            (context_command_mem[ctx].route ==
                             npu_scheduler_pkg::NPU_POST_GEMM)) begin
                            dispatch_done_q[ctx] <= 1'b1;
                        end else begin
                            context_valid_q[ctx] <= 1'b0;
                            completion_valid_q <= 1'b1;
                            completion_tag_q <=
                                context_command_mem[ctx].tag;
                            completion_success_q <= 1'b1;
                        end
                    end
                end
            end

            if (vector_completion_valid_i && !vector_completion_match) begin
                protocol_error_o <= 1'b1;
            end
            if (vector_completion_fire) begin
                context_valid_q[vector_completion_index] <= 1'b0;
                dispatch_done_q[vector_completion_index] <= 1'b0;
                completion_valid_q <= 1'b1;
                completion_tag_q <= vector_completion_tag_i;
                completion_success_q <= vector_completion_success_i;
                if (!vector_completion_success_i) begin
                    protocol_error_o <= 1'b1;
                end
            end

            if (feedback_completion_valid_i &&
                !feedback_completion_match) begin
                protocol_error_o <= 1'b1;
            end
            if (feedback_completion_fire) begin
                context_valid_q[feedback_completion_index] <= 1'b0;
                dispatch_done_q[feedback_completion_index] <= 1'b0;
                completion_valid_q <= 1'b1;
                completion_tag_q <= feedback_completion_tag_i;
                completion_success_q <= feedback_completion_success_i;
                if (!feedback_completion_success_i) begin
                    protocol_error_o <= 1'b1;
                end
            end
        end
    end

    initial begin
        assert ((CONTEXTS > 0) && (CONTEXTS <= 16))
            else $error("npu_gemm_post_scheduler CONTEXTS must be in 1..16");
        assert (RESULT_CHANNELS > 0)
            else $error("npu_gemm_post_scheduler RESULT_CHANNELS must be positive");
    end

endmodule

`default_nettype wire
