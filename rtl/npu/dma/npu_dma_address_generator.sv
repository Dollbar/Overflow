`timescale 1ns/1ps
`default_nettype none

module npu_dma_address_generator #(
    parameter logic [npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH:0]
        HBM_CAPACITY_BYTES = 36'd24000000000,
    parameter logic [npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH:0]
        SRAM_CAPACITY_BYTES = 25'd16777216,
    parameter logic [npu_dma_pkg::NPU_DMA_BEAT_COUNT_WIDTH-1:0]
        MAX_COMMAND_BEATS = 18'd131072
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic command_valid_i,
    output logic command_ready_o,
    input  logic [npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0] command_i,

    output logic beat_valid_o,
    input  logic beat_ready_i,
    output logic [1:0] beat_operation_o,
    output logic [npu_dma_pkg::NPU_DMA_COMMAND_ID_WIDTH-1:0]
                 beat_command_id_o,
    output logic [npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
                 beat_hbm_address_o,
    output logic [npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH-1:0]
                 beat_sram_address_o,
    output logic [1:0] beat_qos_o,
    output logic beat_first_o,
    output logic beat_last_o,

    output logic sequence_done_valid_o,
    input  logic sequence_done_ready_i,
    output logic [npu_dma_pkg::NPU_DMA_COMMAND_ID_WIDTH-1:0]
                 sequence_done_command_id_o,
    output logic sequence_done_error_o,
    output logic [2:0] sequence_done_error_code_o,
    output logic [npu_dma_pkg::NPU_DMA_BEAT_COUNT_WIDTH-1:0]
                 sequence_done_beats_o,

    output logic busy_o,
    output logic protocol_error_o
);

    localparam int unsigned HBM_ADDRESS_WIDTH =
        npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH;
    localparam int unsigned SRAM_ADDRESS_WIDTH =
        npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH;
    localparam int unsigned HBM_WORD_ADDRESS_WIDTH = HBM_ADDRESS_WIDTH - 7;
    localparam int unsigned SRAM_WORD_ADDRESS_WIDTH = SRAM_ADDRESS_WIDTH - 7;
    localparam int unsigned X_COUNT_WIDTH =
        npu_dma_pkg::NPU_DMA_X_COUNT_WIDTH;
    localparam int unsigned YZ_COUNT_WIDTH =
        npu_dma_pkg::NPU_DMA_YZ_COUNT_WIDTH;
    localparam int unsigned BEAT_COUNT_WIDTH =
        npu_dma_pkg::NPU_DMA_BEAT_COUNT_WIDTH;
    localparam logic [HBM_ADDRESS_WIDTH:0] HBM_LAST_BEAT_ADDRESS =
        HBM_CAPACITY_BYTES - 36'd128;
    localparam logic [SRAM_ADDRESS_WIDTH:0] SRAM_LAST_BEAT_ADDRESS =
        SRAM_CAPACITY_BYTES - 25'd128;
    localparam logic [HBM_WORD_ADDRESS_WIDTH:0] HBM_LAST_BEAT_WORD =
        (HBM_WORD_ADDRESS_WIDTH + 1)'((HBM_CAPACITY_BYTES >> 7) - 1'b1);
    localparam logic [SRAM_WORD_ADDRESS_WIDTH:0] SRAM_LAST_BEAT_WORD =
        (SRAM_WORD_ADDRESS_WIDTH + 1)'((SRAM_CAPACITY_BYTES >> 7) - 1'b1);

    npu_dma_pkg::npu_dma_command_t command;
    logic active_q;
    logic done_valid_q;
    logic done_error_q;
    npu_dma_pkg::npu_dma_error_e done_error_code_q;
    logic [npu_dma_pkg::NPU_DMA_COMMAND_ID_WIDTH-1:0] command_id_q;
    npu_dma_pkg::npu_dma_operation_e operation_q;
    logic [1:0] qos_q;
    logic [X_COUNT_WIDTH-1:0] x_count_q;
    logic [YZ_COUNT_WIDTH-1:0] y_count_q;
    logic [X_COUNT_WIDTH-1:0] x_remaining_q;
    logic [YZ_COUNT_WIDTH-1:0] y_remaining_q;
    logic [YZ_COUNT_WIDTH-1:0] z_remaining_q;
    logic x_last_q;
    logic y_last_q;
    logic z_last_q;
    logic x_single_q;
    logic y_single_q;
    logic [HBM_WORD_ADDRESS_WIDTH-1:0] hbm_y_stride_q;
    logic [HBM_WORD_ADDRESS_WIDTH-1:0] hbm_z_stride_q;
    logic [SRAM_WORD_ADDRESS_WIDTH-1:0] sram_y_stride_q;
    logic [SRAM_WORD_ADDRESS_WIDTH-1:0] sram_z_stride_q;
    logic [HBM_WORD_ADDRESS_WIDTH:0] hbm_plane_base_q;
    logic [HBM_WORD_ADDRESS_WIDTH:0] hbm_row_base_q;
    logic [HBM_WORD_ADDRESS_WIDTH:0] hbm_address_q;
    logic [SRAM_WORD_ADDRESS_WIDTH:0] sram_plane_base_q;
    logic [SRAM_WORD_ADDRESS_WIDTH:0] sram_row_base_q;
    logic [SRAM_WORD_ADDRESS_WIDTH:0] sram_address_q;
    logic [BEAT_COUNT_WIDTH-1:0] beats_emitted_q;

    logic command_legal;
    npu_dma_pkg::npu_dma_error_e command_error_code;
    logic current_last;
    logic beat_fire;
    logic command_accept;
    logic [HBM_WORD_ADDRESS_WIDTH:0] hbm_contiguous_address;
    logic [HBM_WORD_ADDRESS_WIDTH:0] hbm_next_row_address;
    logic [HBM_WORD_ADDRESS_WIDTH:0] hbm_next_plane_address;
    logic [HBM_WORD_ADDRESS_WIDTH:0] next_hbm_address;
    logic [SRAM_WORD_ADDRESS_WIDTH:0] sram_contiguous_address;
    logic [SRAM_WORD_ADDRESS_WIDTH:0] sram_next_row_address;
    logic [SRAM_WORD_ADDRESS_WIDTH:0] sram_next_plane_address;
    logic [SRAM_WORD_ADDRESS_WIDTH:0] next_sram_address;
    logic current_address_legal;

    assign command = command_i;
    assign command_ready_o = !rst_i && !clear_i && !active_q &&
                             !done_valid_q;
    assign command_accept = command_valid_i && !active_q && !done_valid_q;
    assign current_address_legal =
        (hbm_address_q <= HBM_LAST_BEAT_WORD) &&
        (sram_address_q <= SRAM_LAST_BEAT_WORD);
    assign beat_valid_o = active_q && current_address_legal;
    assign beat_operation_o = operation_q;
    assign beat_command_id_o = command_id_q;
    assign beat_hbm_address_o = {
        hbm_address_q[HBM_WORD_ADDRESS_WIDTH-1:0], 7'd0};
    assign beat_sram_address_o = {
        sram_address_q[SRAM_WORD_ADDRESS_WIDTH-1:0], 7'd0};
    assign beat_qos_o = qos_q;
    assign beat_first_o = active_q && (beats_emitted_q == '0);
    assign current_last = x_last_q && y_last_q && z_last_q;
    assign beat_last_o = active_q && current_last;
    assign beat_fire = beat_valid_o && beat_ready_i;
    assign sequence_done_valid_o = done_valid_q;
    assign sequence_done_command_id_o = command_id_q;
    assign sequence_done_error_o = done_error_q;
    assign sequence_done_error_code_o = done_error_code_q;
    assign sequence_done_beats_o = beats_emitted_q;
    assign busy_o = active_q || done_valid_q;

    always_comb begin
        command_legal = 1'b1;
        command_error_code = npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR;
        if ((command.version != npu_dma_pkg::NPU_DMA_COMMAND_VERSION) ||
            ((command.operation != npu_dma_pkg::NPU_DMA_HBM_TO_SRAM) &&
             (command.operation != npu_dma_pkg::NPU_DMA_SRAM_TO_HBM)) ||
            (command.x_beat_count == '0) || (command.y_count == '0) ||
            (command.z_count == '0) ||
            (command.x_beat_count > MAX_COMMAND_BEATS)) begin
            command_legal = 1'b0;
        end else if ((command.hbm_base_address[6:0] != 7'd0) ||
                     (command.sram_base_address[6:0] != 7'd0) ||
                     (command.hbm_y_stride[6:0] != 7'd0) ||
                     (command.hbm_z_stride[6:0] != 7'd0) ||
                     (command.sram_y_stride[6:0] != 7'd0) ||
                     (command.sram_z_stride[6:0] != 7'd0) ||
                     ({1'b0, command.hbm_base_address} >
                      HBM_LAST_BEAT_ADDRESS) ||
                     ({1'b0, command.sram_base_address} >
                      SRAM_LAST_BEAT_ADDRESS)) begin
            command_legal = 1'b0;
            command_error_code = npu_dma_pkg::NPU_DMA_ERROR_ADDRESS;
        end
    end

    always_comb begin
        next_hbm_address = hbm_contiguous_address;
        next_sram_address = sram_contiguous_address;
        if (x_last_q) begin
            if (y_last_q) begin
                next_hbm_address = hbm_next_plane_address;
                next_sram_address = sram_next_plane_address;
            end else begin
                next_hbm_address = hbm_next_row_address;
                next_sram_address = sram_next_row_address;
            end
        end
    end

    npu_dma_carry_select_adder #(
        .WIDTH(HBM_WORD_ADDRESS_WIDTH + 1)
    ) u_hbm_contiguous_adder (
        .a_i(hbm_address_q),
        .b_i({{HBM_WORD_ADDRESS_WIDTH{1'b0}}, 1'b1}),
        .cin_i(1'b0),
        .sum_o(hbm_contiguous_address)
    );

    npu_dma_carry_select_adder #(
        .WIDTH(HBM_WORD_ADDRESS_WIDTH + 1)
    ) u_hbm_row_adder (
        .a_i(hbm_row_base_q),
        .b_i({1'b0, hbm_y_stride_q}),
        .cin_i(1'b0),
        .sum_o(hbm_next_row_address)
    );

    npu_dma_carry_select_adder #(
        .WIDTH(HBM_WORD_ADDRESS_WIDTH + 1)
    ) u_hbm_plane_adder (
        .a_i(hbm_plane_base_q),
        .b_i({1'b0, hbm_z_stride_q}),
        .cin_i(1'b0),
        .sum_o(hbm_next_plane_address)
    );

    npu_dma_carry_select_adder #(
        .WIDTH(SRAM_WORD_ADDRESS_WIDTH + 1)
    ) u_sram_contiguous_adder (
        .a_i(sram_address_q),
        .b_i({{SRAM_WORD_ADDRESS_WIDTH{1'b0}}, 1'b1}),
        .cin_i(1'b0),
        .sum_o(sram_contiguous_address)
    );

    npu_dma_carry_select_adder #(
        .WIDTH(SRAM_WORD_ADDRESS_WIDTH + 1)
    ) u_sram_row_adder (
        .a_i(sram_row_base_q),
        .b_i({1'b0, sram_y_stride_q}),
        .cin_i(1'b0),
        .sum_o(sram_next_row_address)
    );

    npu_dma_carry_select_adder #(
        .WIDTH(SRAM_WORD_ADDRESS_WIDTH + 1)
    ) u_sram_plane_adder (
        .a_i(sram_plane_base_q),
        .b_i({1'b0, sram_z_stride_q}),
        .cin_i(1'b0),
        .sum_o(sram_next_plane_address)
    );

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            active_q <= 1'b0;
            done_valid_q <= 1'b0;
            done_error_q <= 1'b0;
            done_error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_OK;
            command_id_q <= '0;
            operation_q <= npu_dma_pkg::NPU_DMA_HBM_TO_SRAM;
            qos_q <= '0;
            x_count_q <= '0;
            y_count_q <= '0;
            x_remaining_q <= '0;
            y_remaining_q <= '0;
            z_remaining_q <= '0;
            x_last_q <= 1'b0;
            y_last_q <= 1'b0;
            z_last_q <= 1'b0;
            x_single_q <= 1'b0;
            y_single_q <= 1'b0;
            hbm_y_stride_q <= '0;
            hbm_z_stride_q <= '0;
            sram_y_stride_q <= '0;
            sram_z_stride_q <= '0;
            hbm_plane_base_q <= '0;
            hbm_row_base_q <= '0;
            hbm_address_q <= '0;
            sram_plane_base_q <= '0;
            sram_row_base_q <= '0;
            sram_address_q <= '0;
            beats_emitted_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            if (done_valid_q && sequence_done_ready_i) begin
                done_valid_q <= 1'b0;
            end

            if (command_accept) begin
                command_id_q <= command.command_id;
                operation_q <= command.operation;
                qos_q <= command.qos;
                x_count_q <= command.x_beat_count;
                y_count_q <= command.y_count;
                x_remaining_q <= command.x_beat_count;
                y_remaining_q <= command.y_count;
                z_remaining_q <= command.z_count;
                x_last_q <= command.x_beat_count == 18'd1;
                y_last_q <= command.y_count == 16'd1;
                z_last_q <= command.z_count == 16'd1;
                x_single_q <= command.x_beat_count == 18'd1;
                y_single_q <= command.y_count == 16'd1;
                hbm_y_stride_q <= command.hbm_y_stride[
                    HBM_ADDRESS_WIDTH-1:7];
                hbm_z_stride_q <= command.hbm_z_stride[
                    HBM_ADDRESS_WIDTH-1:7];
                sram_y_stride_q <= command.sram_y_stride[
                    SRAM_ADDRESS_WIDTH-1:7];
                sram_z_stride_q <= command.sram_z_stride[
                    SRAM_ADDRESS_WIDTH-1:7];
                hbm_plane_base_q <= {1'b0, command.hbm_base_address[
                    HBM_ADDRESS_WIDTH-1:7]};
                hbm_row_base_q <= {1'b0, command.hbm_base_address[
                    HBM_ADDRESS_WIDTH-1:7]};
                hbm_address_q <= {1'b0, command.hbm_base_address[
                    HBM_ADDRESS_WIDTH-1:7]};
                sram_plane_base_q <= {1'b0, command.sram_base_address[
                    SRAM_ADDRESS_WIDTH-1:7]};
                sram_row_base_q <= {1'b0, command.sram_base_address[
                    SRAM_ADDRESS_WIDTH-1:7]};
                sram_address_q <= {1'b0, command.sram_base_address[
                    SRAM_ADDRESS_WIDTH-1:7]};
                beats_emitted_q <= '0;
                done_error_q <= !command_legal;
                done_error_code_q <= command_legal ?
                    npu_dma_pkg::NPU_DMA_ERROR_OK : command_error_code;
                if (command_legal) begin
                    active_q <= 1'b1;
                end else begin
                    active_q <= 1'b0;
                    done_valid_q <= 1'b1;
                    protocol_error_o <= 1'b1;
                end
            end else if (active_q && !current_address_legal) begin
                active_q <= 1'b0;
                done_valid_q <= 1'b1;
                done_error_q <= 1'b1;
                done_error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_ADDRESS;
                protocol_error_o <= 1'b1;
            end else if (beat_fire) begin
                beats_emitted_q <= beats_emitted_q + 18'd1;
                if (current_last) begin
                    active_q <= 1'b0;
                    done_valid_q <= 1'b1;
                    done_error_q <= 1'b0;
                    done_error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_OK;
                end else if (beats_emitted_q == (MAX_COMMAND_BEATS - 18'd1)) begin
                    active_q <= 1'b0;
                    done_valid_q <= 1'b1;
                    done_error_q <= 1'b1;
                    done_error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR;
                    protocol_error_o <= 1'b1;
                end else begin
                    hbm_address_q <= next_hbm_address;
                    sram_address_q <= next_sram_address;
                    if (x_last_q) begin
                        x_remaining_q <= x_count_q;
                        x_last_q <= x_single_q;
                        if (y_last_q) begin
                            y_remaining_q <= y_count_q;
                            y_last_q <= y_single_q;
                            z_remaining_q <= z_remaining_q - 16'd1;
                            z_last_q <= z_remaining_q == 16'd2;
                            hbm_plane_base_q <= next_hbm_address;
                            hbm_row_base_q <= next_hbm_address;
                            sram_plane_base_q <= next_sram_address;
                            sram_row_base_q <= next_sram_address;
                        end else begin
                            y_remaining_q <= y_remaining_q - 16'd1;
                            y_last_q <= y_remaining_q == 16'd2;
                            hbm_row_base_q <= next_hbm_address;
                            sram_row_base_q <= next_sram_address;
                        end
                    end else begin
                        x_remaining_q <= x_remaining_q - 18'd1;
                        x_last_q <= x_remaining_q == 18'd2;
                    end
                end
            end
        end
    end

    initial begin
        if ((HBM_CAPACITY_BYTES < 36'd128) ||
            (SRAM_CAPACITY_BYTES < 25'd128) ||
            (MAX_COMMAND_BEATS == '0)) begin
            $error("npu_dma_address_generator parameters are invalid");
        end
    end

endmodule

`default_nettype wire
