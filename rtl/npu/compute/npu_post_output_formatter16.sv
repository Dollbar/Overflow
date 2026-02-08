`timescale 1ns/1ps
`default_nettype none

// Formats sixteen independent post-result lanes at the external boundary.
// FP32 traffic is passed through one-deep elastic stages. MX traffic pairs
// adjacent 16-lane beats, selects one E8M0 scale, and then emits both encoded
// beats on consecutive cycles. Every lane therefore sustains one beat/cycle.
module npu_post_output_formatter16 #(
    parameter int unsigned CHANNELS = 16
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic [CHANNELS-1:0] input_valid_i,
    output logic [CHANNELS-1:0] input_ready_o,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 input_result_i,
    input  logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 input_command_i,

    output logic [CHANNELS-1:0] output_valid_o,
    input  logic [CHANNELS-1:0] output_ready_i,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH-1:0]
                 output_result_o,
    output logic [CHANNELS*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH-1:0]
                 output_command_o,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_o,
    output logic completion_success_o,
    output logic busy_o,
    output logic protocol_error_o
);

    npu_scheduler_pkg::npu_post_result_beat_t first_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t scale_first_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t scale_second_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t reduce_first_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t reduce_second_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t pair_first_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t pair_second_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t quantize_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t scaled_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_result_beat_t output_beat_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t first_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t scale_first_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t scale_second_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t reduce_first_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t reduce_second_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t pair_first_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t pair_second_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t quantize_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t scaled_command_q [0:CHANNELS-1];
    npu_scheduler_pkg::npu_post_command_t output_command_q [0:CHANNELS-1];
    logic [CHANNELS-1:0] first_valid_q;
    logic [CHANNELS-1:0] scale_pair_valid_q;
    logic [CHANNELS-1:0] reduce_pair_valid_q;
    logic [CHANNELS-1:0] pair_valid_q;
    logic [CHANNELS-1:0] pair_second_q;
    logic [CHANNELS-1:0] quantize_valid_q;
    logic [CHANNELS-1:0] scaled_valid_q;
    logic [CHANNELS-1:0] output_valid_q;
    mxfp_pkg::mxfp_scale_t pair_scale_q [0:CHANNELS-1];
    mxfp_pkg::mxfp_scale_t quantize_scale_q [0:CHANNELS-1];
    mxfp_pkg::mxfp_scale_t scaled_scale_q [0:CHANNELS-1];
    logic [7:0] scale_group_max_q [0:CHANNELS-1][0:7];
    logic [7:0] scale_group_special_q [0:CHANNELS-1];
    logic [7:0] scale_reduce_max_q [0:CHANNELS-1][0:1];
    logic [7:0] scale_reduce_special_q [0:CHANNELS-1];
    logic completion_valid_q;
    logic [npu_scheduler_pkg::NPU_TAG_WIDTH-1:0] completion_tag_q;
    logic [CHANNELS-1:0] output_fire;
    logic [CHANNELS-1:0] output_last_fire;
    logic [CHANNELS-1:0] pair_protocol_error;
    logic [5:0] output_last_count;

    generate
        for (genvar channel = 0; channel < CHANNELS; channel++) begin : g_lane
            npu_scheduler_pkg::npu_post_result_beat_t input_beat;
            npu_scheduler_pkg::npu_post_command_t input_command;
            npu_scheduler_pkg::npu_post_result_beat_t quantized_beat;
            npu_scheduler_pkg::npu_post_command_t quantized_command;
            npu_scheduler_pkg::npu_post_result_beat_t scaled_beat;
            logic input_needs_quantization;
            logic input_fire;
            logic quantize_output;
            logic quantize_to_scaled;
            logic pair_select_fire;
            logic quantize_slot_available;
            logic scaled_slot_available;
            logic scale_transfer;
            logic reduce_transfer;
            logic scale_slot_available;
            logic reduce_slot_available;
            logic pair_slot_available;
            logic output_slot_available;
            logic output_completion_available;
            logic output_effective_ready;
            logic [1023:0] scale_block_data;
            logic [7:0] scale_group_max [0:7];
            logic [7:0] scale_group_special;
            logic [7:0] scale_reduce_level1 [0:3];
            logic [7:0] scale_reduce_level2 [0:1];
            logic [7:0] scale_maximum;
            logic [4:0] scale_element_max_exponent;
            logic scale_format_valid;
            mxfp_pkg::mxfp_scale_t reduced_scale;
            logic [511:0] quantize_data;
            mxfp_pkg::mxfp_format_e quantize_format;
            mxfp_pkg::mxfp_scale_t quantize_scale;
            logic [7:0] quantized_lane [0:15];
            logic [127:0] quantized_vector;
            logic [15:0] quantized_overflow;
            logic [15:0] quantized_inexact;
            logic [31:0] scaled_lane [0:15];
            logic [511:0] scaled_vector;

            always_comb begin
                input_beat = npu_scheduler_pkg::npu_post_result_beat_t'(
                    input_result_i[
                        channel*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_RESULT_WIDTH]);
                input_command = npu_scheduler_pkg::npu_post_command_t'(
                    input_command_i[
                        channel*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                        npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH]);
                input_needs_quantization =
                    (input_command.output_format ==
                     npu_scheduler_pkg::NPU_OUTPUT_MX) &&
                    (input_beat.payload_kind ==
                     npu_scheduler_pkg::NPU_PAYLOAD_FP32_VECTOR);
                output_completion_available =
                    !output_beat_q[channel].last ||
                    !completion_valid_q || completion_ready_i;
                output_effective_ready = output_ready_i[channel] &&
                    output_completion_available;
                output_slot_available = !output_valid_q[channel] ||
                    output_effective_ready;
                input_ready_o[channel] = 1'b0;
                quantize_output = scaled_valid_q[channel] &&
                    output_slot_available;
                scaled_slot_available = !scaled_valid_q[channel] ||
                    quantize_output;
                quantize_to_scaled = quantize_valid_q[channel] &&
                    scaled_slot_available;
                quantize_slot_available = !quantize_valid_q[channel] ||
                    quantize_to_scaled;
                pair_select_fire = pair_valid_q[channel] &&
                    quantize_slot_available;
                pair_slot_available = !pair_valid_q[channel] ||
                    (pair_select_fire && pair_second_q[channel]);
                reduce_transfer = reduce_pair_valid_q[channel] &&
                    pair_slot_available;
                reduce_slot_available = !reduce_pair_valid_q[channel] ||
                    reduce_transfer;
                scale_transfer = scale_pair_valid_q[channel] &&
                    reduce_slot_available;
                scale_slot_available = !scale_pair_valid_q[channel] ||
                    scale_transfer;
                if (!rst_i && !clear_i) begin
                    if (first_valid_q[channel]) begin
                        input_ready_o[channel] = scale_slot_available;
                    end else if (input_needs_quantization) begin
                        input_ready_o[channel] = 1'b1;
                    end else begin
                        input_ready_o[channel] =
                            !scale_pair_valid_q[channel] &&
                            !reduce_pair_valid_q[channel] &&
                            !pair_valid_q[channel] &&
                            !quantize_valid_q[channel] &&
                            !scaled_valid_q[channel] &&
                            output_slot_available;
                    end
                end
                input_fire = input_valid_i[channel] && input_ready_o[channel];
                pair_protocol_error[channel] = input_fire &&
                    ((!first_valid_q[channel] &&
                      input_needs_quantization && input_beat.last) ||
                     (first_valid_q[channel] &&
                      ((input_command.output_format !=
                        npu_scheduler_pkg::NPU_OUTPUT_MX) ||
                       (input_beat.payload_kind !=
                        npu_scheduler_pkg::NPU_PAYLOAD_FP32_VECTOR) ||
                       (input_beat.job_id != first_beat_q[channel].job_id) ||
                       (input_beat.tag != first_beat_q[channel].tag) ||
                       (input_beat.row != first_beat_q[channel].row) ||
                       (input_beat.segment !=
                        (first_beat_q[channel].segment + 5'd1)) ||
                       first_beat_q[channel].last ||
                       (input_command.output_mx_format !=
                        first_command_q[channel].output_mx_format))));

                scale_block_data = {input_beat.data,
                                    first_beat_q[channel].data};
                for (integer group = 0; group < 8; group++) begin
                    scale_group_special[group] =
                        (scale_block_data[(group*4+0)*32+23 +: 8] == 8'hff) ||
                        (scale_block_data[(group*4+1)*32+23 +: 8] == 8'hff) ||
                        (scale_block_data[(group*4+2)*32+23 +: 8] == 8'hff) ||
                        (scale_block_data[(group*4+3)*32+23 +: 8] == 8'hff);
                end

                for (integer node = 0; node < 4; node++) begin
                    scale_reduce_level1[node] =
                        (scale_group_max_q[channel][node*2] >
                         scale_group_max_q[channel][node*2+1]) ?
                        scale_group_max_q[channel][node*2] :
                        scale_group_max_q[channel][node*2+1];
                end
                for (integer node = 0; node < 2; node++) begin
                    scale_reduce_level2[node] =
                        (scale_reduce_level1[node*2] >
                         scale_reduce_level1[node*2+1]) ?
                        scale_reduce_level1[node*2] :
                        scale_reduce_level1[node*2+1];
                end
                scale_maximum =
                    (scale_reduce_max_q[channel][0] >
                     scale_reduce_max_q[channel][1]) ?
                    scale_reduce_max_q[channel][0] :
                    scale_reduce_max_q[channel][1];
                unique case (
                    reduce_first_command_q[channel].output_mx_format)
                    mxfp_pkg::MXFP4_E2M1: begin
                        scale_format_valid = 1'b1;
                        scale_element_max_exponent = 5'd2;
                    end
                    mxfp_pkg::MXFP8_E4M3: begin
                        scale_format_valid = 1'b1;
                        scale_element_max_exponent = 5'd8;
                    end
                    default: begin
                        scale_format_valid = 1'b0;
                        scale_element_max_exponent = 5'd0;
                    end
                endcase
                if (!scale_format_valid ||
                    (|scale_reduce_special_q[channel])) begin
                    reduced_scale = mxfp_pkg::MX_E8M0_NAN;
                end else if (scale_maximum >
                             {3'd0, scale_element_max_exponent}) begin
                    reduced_scale = scale_maximum -
                        {3'd0, scale_element_max_exponent};
                end else begin
                    reduced_scale = 8'd0;
                end
                scaled_beat = quantize_beat_q[channel];
                scaled_beat.data = scaled_vector;
                quantize_data = scaled_beat_q[channel].data;
                quantize_format =
                    scaled_command_q[channel].output_mx_format;
                quantize_scale = scaled_scale_q[channel];
                quantized_beat = scaled_beat_q[channel];
                quantized_command = scaled_command_q[channel];

                quantized_vector = '0;
                for (integer lane = 0; lane < 16; lane++) begin
                    if (quantize_format == mxfp_pkg::MXFP4_E2M1) begin
                        quantized_vector[lane*4 +: 4] =
                            quantized_lane[lane][3:0];
                    end else begin
                        quantized_vector[lane*8 +: 8] =
                            quantized_lane[lane];
                    end
                end
                quantized_beat.data = '0;
                quantized_beat.data[127:0] = quantized_vector;
                quantized_beat.payload_kind =
                    npu_scheduler_pkg::NPU_PAYLOAD_MX_VECTOR;
                quantized_beat.mx_format = quantize_format;
                quantized_beat.mx_scale = quantize_scale;

                output_valid_o[channel] = output_valid_q[channel] &&
                    output_completion_available;
                output_result_o[
                    channel*npu_scheduler_pkg::NPU_POST_RESULT_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_RESULT_WIDTH] =
                    output_beat_q[channel];
                output_command_o[
                    channel*npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH +:
                    npu_scheduler_pkg::NPU_POST_COMMAND_WIDTH] =
                    output_command_q[channel];
                output_fire[channel] = output_valid_o[channel] &&
                    output_ready_i[channel];
                output_last_fire[channel] = output_fire[channel] &&
                    output_beat_q[channel].last;
            end

            for (genvar group = 0; group < 8; group++) begin : g_scale_group
                logic [7:0] maximum01;
                logic [7:0] maximum23;
                logic [7:0] exponent0;
                logic [7:0] exponent1;
                logic [7:0] exponent2;
                logic [7:0] exponent3;

                assign exponent0 = scale_block_data[
                    (group*4+0)*32+23 +: 8];
                assign exponent1 = scale_block_data[
                    (group*4+1)*32+23 +: 8];
                assign exponent2 = scale_block_data[
                    (group*4+2)*32+23 +: 8];
                assign exponent3 = scale_block_data[
                    (group*4+3)*32+23 +: 8];
                assign maximum01 = (exponent0 > exponent1) ?
                    exponent0 : exponent1;
                assign maximum23 = (exponent2 > exponent3) ?
                    exponent2 : exponent3;
                assign scale_group_max[group] = (maximum01 > maximum23) ?
                    maximum01 : maximum23;
            end

            for (genvar lane = 0; lane < 16; lane++) begin : g_quantize
                mxfp_apply_scale_lane u_apply_scale (
                    .data_i(quantize_beat_q[channel].data[
                        lane*32 +: 32]),
                    .scale_i(quantize_scale_q[channel]),
                    .data_o(scaled_lane[lane])
                );
                assign scaled_vector[lane*32 +: 32] = scaled_lane[lane];

                mxfp_quantize_lane u_quantize_lane (
                    .data_i(quantize_data[lane*32 +: 32]),
                    .format_i(quantize_format),
                    .scale_i(8'd127),
                    .data_o(quantized_lane[lane]),
                    .overflow_o(quantized_overflow[lane]),
                    .inexact_o(quantized_inexact[lane])
                );
            end

            always_ff @(posedge clk_i) begin
                if (rst_i || clear_i) begin
                    first_beat_q[channel] <= '0;
                    scale_first_beat_q[channel] <= '0;
                    scale_second_beat_q[channel] <= '0;
                    reduce_first_beat_q[channel] <= '0;
                    reduce_second_beat_q[channel] <= '0;
                    pair_first_beat_q[channel] <= '0;
                    pair_second_beat_q[channel] <= '0;
                    quantize_beat_q[channel] <= '0;
                    scaled_beat_q[channel] <= '0;
                    output_beat_q[channel] <= '0;
                    first_command_q[channel] <= '0;
                    scale_first_command_q[channel] <= '0;
                    scale_second_command_q[channel] <= '0;
                    reduce_first_command_q[channel] <= '0;
                    reduce_second_command_q[channel] <= '0;
                    pair_first_command_q[channel] <= '0;
                    pair_second_command_q[channel] <= '0;
                    quantize_command_q[channel] <= '0;
                    scaled_command_q[channel] <= '0;
                    output_command_q[channel] <= '0;
                    first_valid_q[channel] <= 1'b0;
                    scale_pair_valid_q[channel] <= 1'b0;
                    reduce_pair_valid_q[channel] <= 1'b0;
                    pair_valid_q[channel] <= 1'b0;
                    pair_second_q[channel] <= 1'b0;
                    quantize_valid_q[channel] <= 1'b0;
                    scaled_valid_q[channel] <= 1'b0;
                    output_valid_q[channel] <= 1'b0;
                    pair_scale_q[channel] <= '0;
                    quantize_scale_q[channel] <= '0;
                    scaled_scale_q[channel] <= '0;
                    scale_group_special_q[channel] <= '0;
                    scale_reduce_special_q[channel] <= '0;
                    for (integer group = 0; group < 8; group++) begin
                        scale_group_max_q[channel][group] <= '0;
                    end
                    for (integer node = 0; node < 2; node++) begin
                        scale_reduce_max_q[channel][node] <= '0;
                    end
                end else begin
                    if (output_fire[channel]) begin
                        output_valid_q[channel] <= 1'b0;
                    end
                    if (quantize_output) begin
                        output_beat_q[channel] <= quantized_beat;
                        output_command_q[channel] <= quantized_command;
                        output_valid_q[channel] <= 1'b1;
                        scaled_valid_q[channel] <= 1'b0;
                    end
                    if (quantize_to_scaled) begin
                        scaled_beat_q[channel] <= scaled_beat;
                        scaled_command_q[channel] <=
                            quantize_command_q[channel];
                        scaled_scale_q[channel] <= quantize_scale_q[channel];
                        scaled_valid_q[channel] <= 1'b1;
                        quantize_valid_q[channel] <= 1'b0;
                    end
                    if (pair_select_fire) begin
                        quantize_beat_q[channel] <= pair_second_q[channel] ?
                            pair_second_beat_q[channel] :
                            pair_first_beat_q[channel];
                        quantize_command_q[channel] <=
                            pair_second_q[channel] ?
                            pair_second_command_q[channel] :
                            pair_first_command_q[channel];
                        quantize_scale_q[channel] <= pair_scale_q[channel];
                        quantize_valid_q[channel] <= 1'b1;
                        if (pair_second_q[channel]) begin
                            pair_valid_q[channel] <= 1'b0;
                            pair_second_q[channel] <= 1'b0;
                        end else begin
                            pair_second_q[channel] <= 1'b1;
                        end
                    end
                    if (scale_transfer) begin
                        reduce_first_beat_q[channel] <=
                            scale_first_beat_q[channel];
                        reduce_second_beat_q[channel] <=
                            scale_second_beat_q[channel];
                        reduce_first_command_q[channel] <=
                            scale_first_command_q[channel];
                        reduce_second_command_q[channel] <=
                            scale_second_command_q[channel];
                        for (integer node = 0; node < 2; node++) begin
                            scale_reduce_max_q[channel][node] <=
                                scale_reduce_level2[node];
                        end
                        scale_reduce_special_q[channel] <=
                            scale_group_special_q[channel];
                        reduce_pair_valid_q[channel] <= 1'b1;
                        scale_pair_valid_q[channel] <= 1'b0;
                    end
                    if (reduce_transfer) begin
                        pair_first_beat_q[channel] <=
                            reduce_first_beat_q[channel];
                        pair_second_beat_q[channel] <=
                            reduce_second_beat_q[channel];
                        pair_first_command_q[channel] <=
                            reduce_first_command_q[channel];
                        pair_second_command_q[channel] <=
                            reduce_second_command_q[channel];
                        pair_scale_q[channel] <= reduced_scale;
                        pair_valid_q[channel] <= 1'b1;
                        pair_second_q[channel] <= 1'b0;
                        if (!scale_transfer) begin
                            reduce_pair_valid_q[channel] <= 1'b0;
                        end
                    end
                    if (input_fire) begin
                        if (first_valid_q[channel]) begin
                            scale_first_beat_q[channel] <=
                                first_beat_q[channel];
                            scale_second_beat_q[channel] <= input_beat;
                            scale_first_command_q[channel] <=
                                first_command_q[channel];
                            scale_second_command_q[channel] <= input_command;
                            for (integer group = 0; group < 8; group++) begin
                                scale_group_max_q[channel][group] <=
                                    scale_group_max[group];
                            end
                            scale_group_special_q[channel] <=
                                scale_group_special;
                            scale_pair_valid_q[channel] <= 1'b1;
                            first_valid_q[channel] <= 1'b0;
                        end else if (input_needs_quantization) begin
                            first_beat_q[channel] <= input_beat;
                            first_command_q[channel] <= input_command;
                            first_valid_q[channel] <= 1'b1;
                        end else begin
                            output_beat_q[channel] <= input_beat;
                            output_command_q[channel] <= input_command;
                            output_valid_q[channel] <= 1'b1;
                        end
                    end
                end
            end

            wire _unused_quantize_status = &{1'b0, quantized_overflow,
                                              quantized_inexact};
        end
    endgenerate

    always_comb begin
        output_last_count = '0;
        for (integer channel = 0; channel < CHANNELS; channel++) begin
            output_last_count = output_last_count +
                6'(output_last_fire[channel]);
        end
        completion_valid_o = completion_valid_q;
        completion_tag_o = completion_tag_q;
        completion_success_o = 1'b1;
        busy_o = (|first_valid_q) || (|scale_pair_valid_q) ||
            (|reduce_pair_valid_q) || (|pair_valid_q) ||
            (|quantize_valid_q) || (|scaled_valid_q) ||
            (|output_valid_q) || completion_valid_q;
    end

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            completion_valid_q <= 1'b0;
            completion_tag_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            if (completion_valid_q && completion_ready_i) begin
                completion_valid_q <= 1'b0;
            end
            if (|pair_protocol_error) begin
                protocol_error_o <= 1'b1;
            end
            if (output_last_count != 6'd0) begin
                completion_valid_q <= 1'b1;
                for (integer channel = 0; channel < CHANNELS; channel++) begin
                    if (output_last_fire[channel]) begin
                        completion_tag_q <= output_beat_q[channel].tag;
                    end
                end
                if (output_last_count != 6'd1) begin
                    protocol_error_o <= 1'b1;
                end
            end
        end
    end

    initial begin
        assert ((CHANNELS > 0) && (CHANNELS <= 16))
            else $error("npu_post_output_formatter16 CHANNELS must be 1..16");
    end

endmodule

`default_nettype wire
