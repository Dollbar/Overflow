`timescale 1ns/1ps
`default_nettype none

module npu_dma_channel_mover #(
    parameter int unsigned LOCAL_TAG_WIDTH = 8,
    parameter int unsigned DATA_BYTES = 128,
    parameter int unsigned DATA_WIDTH = DATA_BYTES * 8
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,

    input  logic command_valid_i,
    output logic command_ready_o,
    input  logic [npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-1:0] command_i,

    output logic hbm_request_valid_o,
    input  logic hbm_request_ready_i,
    output logic hbm_request_write_o,
    output logic [npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
                 hbm_request_address_o,
    output logic [DATA_WIDTH-1:0] hbm_request_write_data_o,
    output logic [DATA_BYTES-1:0] hbm_request_byte_enable_o,
    output logic [1:0] hbm_request_qos_o,
    input  logic [LOCAL_TAG_WIDTH-1:0] hbm_request_local_tag_i,

    input  logic hbm_response_valid_i,
    output logic hbm_response_ready_o,
    input  logic hbm_response_write_i,
    input  logic [LOCAL_TAG_WIDTH-1:0] hbm_response_local_tag_i,
    input  logic [DATA_WIDTH-1:0] hbm_response_read_data_i,
    input  logic [1:0] hbm_response_status_i,

    output logic sram_read_request_valid_o,
    input  logic sram_read_request_ready_i,
    output logic [npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH-1:0]
                 sram_read_request_address_o,
    input  logic sram_read_response_valid_i,
    output logic sram_read_response_ready_o,
    input  logic [DATA_WIDTH-1:0] sram_read_response_data_i,

    output logic sram_write_valid_o,
    input  logic sram_write_ready_i,
    output logic [npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH-1:0]
                 sram_write_address_o,
    output logic [DATA_WIDTH-1:0] sram_write_data_o,
    output logic [DATA_BYTES-1:0] sram_write_byte_enable_o,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_dma_pkg::NPU_DMA_COMPLETION_WIDTH-1:0]
                 completion_o,

    output logic busy_o,
    output logic [LOCAL_TAG_WIDTH:0] outstanding_o,
    output logic protocol_error_o
);

    localparam int unsigned SRAM_ADDRESS_WIDTH =
        npu_dma_pkg::NPU_DMA_SRAM_ADDRESS_WIDTH;
    localparam int unsigned TAG_BANK_WIDTH = 4;
    localparam int unsigned TAG_BANKS = 1 << TAG_BANK_WIDTH;

    npu_dma_pkg::npu_dma_completion_t completion_q;
    logic [1:0] command_operation;
    logic [npu_dma_pkg::NPU_DMA_COMMAND_ID_WIDTH-1:0] command_input_id;
    logic command_active_q;
    logic [1:0] operation_q;
    logic [npu_dma_pkg::NPU_DMA_COMMAND_ID_WIDTH-1:0] command_id_q;
    logic generator_done_q;
    logic generator_error_q;
    npu_dma_pkg::npu_dma_error_e error_code_q;
    logic corrected_ecc_seen_q;
    logic [npu_dma_pkg::NPU_DMA_BEAT_COUNT_WIDTH-1:0]
        beats_completed_q;
    logic completion_valid_q;
    logic mover_protocol_error_q;

    logic generator_command_ready;
    logic generator_beat_valid;
    logic generator_beat_ready;
    logic [1:0] generator_beat_operation;
    logic [npu_dma_pkg::NPU_DMA_COMMAND_ID_WIDTH-1:0]
        generator_beat_command_id;
    logic [npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
        generator_beat_hbm_address;
    logic [SRAM_ADDRESS_WIDTH-1:0] generator_beat_sram_address;
    logic [1:0] generator_beat_qos;
    logic generator_beat_first;
    logic generator_beat_last;
    logic generator_done_valid;
    logic [npu_dma_pkg::NPU_DMA_COMMAND_ID_WIDTH-1:0]
        generator_done_command_id;
    logic generator_done_error;
    logic [2:0] generator_done_error_code;
    logic [npu_dma_pkg::NPU_DMA_BEAT_COUNT_WIDTH-1:0]
        generator_done_beats;
    logic generator_busy;
    logic generator_protocol_error;

    logic read_pending_q;
    logic [npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
        read_pending_hbm_address_q;
    logic read_pending_last_q;
    logic [1:0] read_pending_qos_q;
    logic write_buffer_valid_q;
    logic [npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
        write_buffer_hbm_address_q;
    logic [DATA_WIDTH-1:0] write_buffer_data_q;
    logic write_buffer_last_q;
    logic [1:0] write_buffer_qos_q;
    logic hbm_read_buffer_valid_q;
    logic [npu_dma_pkg::NPU_DMA_HBM_ADDRESS_WIDTH-1:0]
        hbm_read_buffer_address_q;
    logic [SRAM_ADDRESS_WIDTH-1:0] hbm_read_buffer_sram_address_q;
    logic hbm_read_buffer_last_q;
    logic [1:0] hbm_read_buffer_qos_q;
    logic response_buffer_valid_q;
    logic response_buffer_write_q;
    logic [TAG_BANK_WIDTH-1:0] response_buffer_tag_bank_q;
    logic [DATA_WIDTH-1:0] response_buffer_read_data_q;
    logic [1:0] response_buffer_status_q;

    logic [TAG_BANKS-1:0] allocate_bank_entry_valid;
    logic [TAG_BANKS-1:0] release_bank_entry_valid;
    logic [TAG_BANKS-1:0] release_bank_last;
    logic [TAG_BANKS*SRAM_ADDRESS_WIDTH-1:0] release_bank_sram_address;
    logic allocate_tag_valid;
    logic [LOCAL_TAG_WIDTH-1:0] allocate_tag_buffered;
    logic allocate_last;
    logic allocate_last_buffered;
    logic release_tag_valid;
    logic release_tag_last;
    logic [SRAM_ADDRESS_WIDTH-1:0] release_tag_sram_address;
    logic [LOCAL_TAG_WIDTH:0] outstanding_q;
    logic final_response_seen_q;
    logic generator_any_beat_q;
    logic [npu_dma_pkg::NPU_DMA_BEAT_COUNT_WIDTH-1:0]
        generated_beats_q;

    logic command_fire;
    logic generator_beat_fire;
    logic sram_read_request_fire;
    logic sram_read_response_fire;
    logic write_buffer_fire;
    logic hbm_read_buffer_capture;
    logic hbm_read_buffer_send;
    logic hbm_read_buffer_available;
    logic hbm_request_fire;
    logic response_tag_known;
    logic response_operation_matches;
    logic response_status_success;
    logic response_requires_sram_write;
    logic response_processing_ready;
    logic hbm_response_input_fire;
    logic hbm_response_capture_fire;
    logic hbm_response_fire;
    logic hbm_response_known_fire;
    logic sram_write_fire;
    logic write_buffer_available;
    logic read_pending_available;
    logic completion_condition;

    assign command_operation = command_i[
        npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-5 -: 2];
    assign command_input_id = command_i[
        npu_dma_pkg::NPU_DMA_COMMAND_WIDTH-7 -:
        npu_dma_pkg::NPU_DMA_COMMAND_ID_WIDTH];
    assign command_ready_o = generator_command_ready && !command_active_q &&
                             !completion_valid_q;
    assign command_fire = command_valid_i && command_ready_o;

    npu_dma_address_generator u_address_generator (
        .clk_i,
        .rst_i,
        .clear_i,
        .command_valid_i(command_valid_i && !command_active_q &&
                         !completion_valid_q),
        .command_ready_o(generator_command_ready),
        .command_i,
        .beat_valid_o(generator_beat_valid),
        .beat_ready_i(generator_beat_ready),
        .beat_operation_o(generator_beat_operation),
        .beat_command_id_o(generator_beat_command_id),
        .beat_hbm_address_o(generator_beat_hbm_address),
        .beat_sram_address_o(generator_beat_sram_address),
        .beat_qos_o(generator_beat_qos),
        .beat_first_o(generator_beat_first),
        .beat_last_o(generator_beat_last),
        .sequence_done_valid_o(generator_done_valid),
        .sequence_done_ready_i(1'b1),
        .sequence_done_command_id_o(generator_done_command_id),
        .sequence_done_error_o(generator_done_error),
        .sequence_done_error_code_o(generator_done_error_code),
        .sequence_done_beats_o(generator_done_beats),
        .busy_o(generator_busy),
        .protocol_error_o(generator_protocol_error)
    );

    assign write_buffer_fire = write_buffer_valid_q &&
                               hbm_request_ready_i &&
                               (operation_q == npu_dma_pkg::NPU_DMA_SRAM_TO_HBM);
    assign write_buffer_available = !write_buffer_valid_q ||
                                    write_buffer_fire;
    assign sram_read_response_ready_o = !read_pending_q ? 1'b1 :
                                        write_buffer_available;
    assign sram_read_response_fire = sram_read_response_valid_i &&
                                     sram_read_response_ready_o;
    assign read_pending_available = !read_pending_q ||
                                    (sram_read_response_fire && read_pending_q);

    assign sram_read_request_valid_o = generator_beat_valid &&
        (generator_beat_operation == npu_dma_pkg::NPU_DMA_SRAM_TO_HBM) &&
        read_pending_available;
    assign sram_read_request_address_o = generator_beat_sram_address;
    assign sram_read_request_fire = sram_read_request_valid_o &&
                                    sram_read_request_ready_i;

    always_comb begin
        hbm_request_valid_o = 1'b0;
        hbm_request_write_o = 1'b0;
        hbm_request_address_o = '0;
        hbm_request_write_data_o = '0;
        hbm_request_byte_enable_o = {DATA_BYTES{1'b1}};
        hbm_request_qos_o = '0;
        generator_beat_ready = 1'b0;
        if (command_active_q &&
            (operation_q == npu_dma_pkg::NPU_DMA_HBM_TO_SRAM)) begin
            hbm_request_valid_o = hbm_read_buffer_valid_q;
            hbm_request_address_o = hbm_read_buffer_address_q;
            hbm_request_qos_o = hbm_read_buffer_qos_q;
            generator_beat_ready = hbm_read_buffer_available;
        end else if (command_active_q &&
                     (operation_q == npu_dma_pkg::NPU_DMA_SRAM_TO_HBM)) begin
            hbm_request_valid_o = write_buffer_valid_q;
            hbm_request_write_o = 1'b1;
            hbm_request_address_o = write_buffer_hbm_address_q;
            hbm_request_write_data_o = write_buffer_data_q;
            hbm_request_qos_o = write_buffer_qos_q;
            generator_beat_ready = sram_read_request_ready_i &&
                                   read_pending_available;
        end
    end

    assign generator_beat_fire = generator_beat_valid &&
                                 generator_beat_ready;
    assign hbm_request_fire = hbm_request_valid_o && hbm_request_ready_i;
    assign hbm_read_buffer_capture = generator_beat_fire &&
        (generator_beat_operation == npu_dma_pkg::NPU_DMA_HBM_TO_SRAM);
    assign hbm_read_buffer_send = hbm_request_fire &&
        (operation_q == npu_dma_pkg::NPU_DMA_HBM_TO_SRAM);
    assign hbm_read_buffer_available = !hbm_read_buffer_valid_q ||
                                       hbm_read_buffer_send;

    generate
        for (genvar tag_bit = 0; tag_bit < LOCAL_TAG_WIDTH;
             tag_bit++) begin : g_allocate_tag_buffer
            npu_dma_hbm_wide_control_buffer u_control_buffer (
                .data_i(hbm_request_local_tag_i[tag_bit]),
                .data_o(allocate_tag_buffered[tag_bit])
            );
        end
    endgenerate
    assign allocate_last =
        (operation_q == npu_dma_pkg::NPU_DMA_HBM_TO_SRAM) ?
        hbm_read_buffer_last_q : write_buffer_last_q;
    npu_dma_hbm_wide_control_buffer u_allocate_last_control_buffer (
        .data_i(allocate_last),
        .data_o(allocate_last_buffered)
    );

    generate
        for (genvar bank = 0; bank < TAG_BANKS; bank++) begin : g_tag_bank
            npu_dma_tag_metadata_bank u_tag_bank (
                .clk_i,
                .rst_i,
                .clear_i,
                .allocate_valid_i(hbm_request_fire &&
                    (allocate_tag_buffered[7:4] == TAG_BANK_WIDTH'(bank))),
                .allocate_row_i(allocate_tag_buffered[3:0]),
                .allocate_last_i(allocate_last_buffered),
                .allocate_address_i(
                    (operation_q == npu_dma_pkg::NPU_DMA_HBM_TO_SRAM) ?
                    hbm_read_buffer_sram_address_q : '0),
                .allocate_entry_valid_o(allocate_bank_entry_valid[bank]),
                .release_row_capture_i(hbm_response_capture_fire),
                .release_row_input_i(hbm_response_local_tag_i[3:0]),
                .release_valid_i(hbm_response_fire &&
                    (response_buffer_tag_bank_q == TAG_BANK_WIDTH'(bank))),
                .release_entry_valid_o(release_bank_entry_valid[bank]),
                .release_last_o(release_bank_last[bank]),
                .release_address_o(release_bank_sram_address[
                    bank*SRAM_ADDRESS_WIDTH +: SRAM_ADDRESS_WIDTH])
            );
        end
    endgenerate

    assign allocate_tag_valid =
        allocate_bank_entry_valid[allocate_tag_buffered[7:4]];
    assign release_tag_valid =
        release_bank_entry_valid[response_buffer_tag_bank_q];
    assign release_tag_last =
        release_bank_last[response_buffer_tag_bank_q];
    assign release_tag_sram_address = release_bank_sram_address[
        response_buffer_tag_bank_q*SRAM_ADDRESS_WIDTH +:
        SRAM_ADDRESS_WIDTH];

    assign response_tag_known = release_tag_valid;
    assign response_operation_matches =
        response_buffer_write_q ==
        (operation_q == npu_dma_pkg::NPU_DMA_SRAM_TO_HBM);
    assign response_status_success = (response_buffer_status_q == 2'd0) ||
                                     (response_buffer_status_q == 2'd1);
    assign sram_write_valid_o = response_buffer_valid_q &&
                                response_tag_known &&
                                response_operation_matches &&
                                !response_buffer_write_q &&
                                response_status_success;
    assign sram_write_address_o = release_tag_sram_address;
    assign sram_write_data_o = response_buffer_read_data_q;
    assign sram_write_byte_enable_o = {DATA_BYTES{1'b1}};
    assign response_requires_sram_write = response_buffer_valid_q &&
        !response_buffer_write_q &&
        (operation_q == npu_dma_pkg::NPU_DMA_HBM_TO_SRAM) &&
        response_status_success;
    assign response_processing_ready = response_requires_sram_write ?
                                           sram_write_ready_i : 1'b1;
    assign hbm_response_ready_o = !response_buffer_valid_q ||
                                  response_processing_ready;
    assign hbm_response_input_fire = hbm_response_valid_i &&
                                     hbm_response_ready_o;
    npu_dma_hbm_wide_control_buffer u_response_capture_control_buffer (
        .data_i(hbm_response_input_fire),
        .data_o(hbm_response_capture_fire)
    );
    assign hbm_response_fire = response_buffer_valid_q &&
                               response_processing_ready;
    assign hbm_response_known_fire = hbm_response_fire && response_tag_known;
    assign sram_write_fire = sram_write_valid_o && sram_write_ready_i;

    assign completion_condition = command_active_q && generator_done_q &&
                                  (outstanding_q == '0) && !read_pending_q &&
                                  !hbm_read_buffer_valid_q &&
                                  !write_buffer_valid_q && !completion_valid_q &&
                                  (generator_error_q || final_response_seen_q);
    assign completion_valid_o = completion_valid_q;
    assign completion_o = completion_q;
    assign outstanding_o = outstanding_q;
    assign busy_o = command_active_q || generator_busy || read_pending_q ||
                    hbm_read_buffer_valid_q || write_buffer_valid_q ||
                    response_buffer_valid_q ||
                    (outstanding_q != '0) || completion_valid_q;
    assign protocol_error_o = generator_protocol_error ||
                              mover_protocol_error_q;

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            command_active_q <= 1'b0;
            operation_q <= npu_dma_pkg::NPU_DMA_HBM_TO_SRAM;
            command_id_q <= '0;
            generator_done_q <= 1'b0;
            generator_error_q <= 1'b0;
            error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_OK;
            corrected_ecc_seen_q <= 1'b0;
            beats_completed_q <= '0;
            completion_valid_q <= 1'b0;
            completion_q <= '0;
            mover_protocol_error_q <= 1'b0;
            read_pending_q <= 1'b0;
            read_pending_hbm_address_q <= '0;
            read_pending_last_q <= 1'b0;
            read_pending_qos_q <= '0;
            write_buffer_valid_q <= 1'b0;
            write_buffer_hbm_address_q <= '0;
            write_buffer_data_q <= '0;
            write_buffer_last_q <= 1'b0;
            write_buffer_qos_q <= '0;
            hbm_read_buffer_valid_q <= 1'b0;
            hbm_read_buffer_address_q <= '0;
            hbm_read_buffer_sram_address_q <= '0;
            hbm_read_buffer_last_q <= 1'b0;
            hbm_read_buffer_qos_q <= '0;
            response_buffer_valid_q <= 1'b0;
            response_buffer_write_q <= 1'b0;
            response_buffer_tag_bank_q <= '0;
            response_buffer_read_data_q <= '0;
            response_buffer_status_q <= '0;
            outstanding_q <= '0;
            final_response_seen_q <= 1'b0;
            generator_any_beat_q <= 1'b0;
            generated_beats_q <= '0;
        end else begin
            case ({hbm_read_buffer_capture, hbm_read_buffer_send})
                2'b10: hbm_read_buffer_valid_q <= 1'b1;
                2'b01: hbm_read_buffer_valid_q <= 1'b0;
                2'b11: hbm_read_buffer_valid_q <= 1'b1;
                default: hbm_read_buffer_valid_q <= hbm_read_buffer_valid_q;
            endcase
            if (hbm_read_buffer_capture) begin
                hbm_read_buffer_address_q <= generator_beat_hbm_address;
                hbm_read_buffer_sram_address_q <=
                    generator_beat_sram_address;
                hbm_read_buffer_last_q <= generator_beat_last;
                hbm_read_buffer_qos_q <= generator_beat_qos;
            end

            case ({hbm_response_input_fire, hbm_response_fire})
                2'b10: response_buffer_valid_q <= 1'b1;
                2'b01: response_buffer_valid_q <= 1'b0;
                2'b11: response_buffer_valid_q <= 1'b1;
                default: response_buffer_valid_q <= response_buffer_valid_q;
            endcase
            if (hbm_response_capture_fire) begin
                response_buffer_write_q <= hbm_response_write_i;
                response_buffer_tag_bank_q <= hbm_response_local_tag_i[7:4];
                response_buffer_read_data_q <= hbm_response_read_data_i;
                response_buffer_status_q <= hbm_response_status_i;
            end

            if (completion_valid_q && completion_ready_i) begin
                completion_valid_q <= 1'b0;
                command_active_q <= 1'b0;
            end

            if (command_fire) begin
                command_active_q <= 1'b1;
                operation_q <= command_operation;
                command_id_q <= command_input_id;
                generator_done_q <= 1'b0;
                generator_error_q <= 1'b0;
                error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_OK;
                corrected_ecc_seen_q <= 1'b0;
                beats_completed_q <= '0;
                final_response_seen_q <= 1'b0;
                generator_any_beat_q <= 1'b0;
                generated_beats_q <= '0;
            end

            if (generator_beat_valid &&
                ((generator_beat_command_id != command_id_q) ||
                 (generator_beat_first != !generator_any_beat_q))) begin
                mover_protocol_error_q <= 1'b1;
                generator_error_q <= 1'b1;
                error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_INTERNAL;
            end
            if (generator_beat_fire) begin
                generator_any_beat_q <= 1'b1;
                generated_beats_q <= generated_beats_q + 18'd1;
            end

            if (generator_done_valid) begin
                generator_done_q <= 1'b1;
                if ((generator_done_command_id != command_id_q) ||
                    (generator_done_beats != generated_beats_q)) begin
                    generator_error_q <= 1'b1;
                    error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_INTERNAL;
                    mover_protocol_error_q <= 1'b1;
                end else if (generator_done_error && !generator_error_q) begin
                    generator_error_q <= 1'b1;
                    case (generator_done_error_code)
                        npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR:
                            error_code_q <=
                                npu_dma_pkg::NPU_DMA_ERROR_DESCRIPTOR;
                        npu_dma_pkg::NPU_DMA_ERROR_ADDRESS:
                            error_code_q <=
                                npu_dma_pkg::NPU_DMA_ERROR_ADDRESS;
                        default:
                            error_code_q <=
                                npu_dma_pkg::NPU_DMA_ERROR_INTERNAL;
                    endcase
                end
            end

            case ({sram_read_request_fire,
                   (sram_read_response_fire && read_pending_q)})
                2'b10: read_pending_q <= 1'b1;
                2'b01: read_pending_q <= 1'b0;
                default: read_pending_q <= read_pending_q;
            endcase
            if (sram_read_request_fire) begin
                read_pending_hbm_address_q <= generator_beat_hbm_address;
                read_pending_last_q <= generator_beat_last;
                read_pending_qos_q <= generator_beat_qos;
            end
            if (sram_read_response_fire && !read_pending_q) begin
                mover_protocol_error_q <= 1'b1;
                if (command_active_q && !generator_error_q) begin
                    generator_error_q <= 1'b1;
                    error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_SRAM;
                end
            end

            if (write_buffer_fire) begin
                write_buffer_valid_q <= 1'b0;
            end
            if (sram_read_response_fire && read_pending_q) begin
                write_buffer_valid_q <= 1'b1;
                write_buffer_hbm_address_q <= read_pending_hbm_address_q;
                write_buffer_data_q <= sram_read_response_data_i;
                write_buffer_last_q <= read_pending_last_q;
                write_buffer_qos_q <= read_pending_qos_q;
            end

            if (hbm_request_fire) begin
                if (allocate_tag_valid) begin
                    mover_protocol_error_q <= 1'b1;
                    generator_error_q <= 1'b1;
                    error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_INTERNAL;
                end
            end

            if (hbm_response_known_fire) begin
                if (release_tag_last) begin
                    final_response_seen_q <= 1'b1;
                end
                if (!response_operation_matches) begin
                    mover_protocol_error_q <= 1'b1;
                    generator_error_q <= 1'b1;
                    error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_INTERNAL;
                end else begin
                    if (response_buffer_status_q == 2'd1) begin
                        corrected_ecc_seen_q <= 1'b1;
                    end else if ((response_buffer_status_q == 2'd2) &&
                                 !generator_error_q) begin
                        generator_error_q <= 1'b1;
                        error_code_q <=
                            npu_dma_pkg::NPU_DMA_ERROR_HBM_UNCORRECTABLE;
                    end else if ((response_buffer_status_q == 2'd3) &&
                                 !generator_error_q) begin
                        generator_error_q <= 1'b1;
                        error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_HBM_DATA;
                    end
                    if (response_status_success &&
                        (response_buffer_write_q || sram_write_fire)) begin
                        beats_completed_q <= beats_completed_q + 18'd1;
                    end
                end
            end else if (hbm_response_fire) begin
                mover_protocol_error_q <= 1'b1;
                if (command_active_q && !generator_error_q) begin
                    generator_error_q <= 1'b1;
                    error_code_q <= npu_dma_pkg::NPU_DMA_ERROR_INTERNAL;
                end
            end

            case ({hbm_request_fire, hbm_response_known_fire})
                2'b10: outstanding_q <= outstanding_q + 9'd1;
                2'b01: begin
                    if (outstanding_q == '0) begin
                        mover_protocol_error_q <= 1'b1;
                    end else begin
                        outstanding_q <= outstanding_q - 9'd1;
                    end
                end
                default: outstanding_q <= outstanding_q;
            endcase

            if (completion_condition) begin
                completion_valid_q <= 1'b1;
                completion_q.command_id <= command_id_q;
                completion_q.success <= !generator_error_q;
                completion_q.error_code <= generator_error_q ?
                    error_code_q : npu_dma_pkg::NPU_DMA_ERROR_OK;
                completion_q.corrected_ecc_seen <= corrected_ecc_seen_q;
                completion_q.beats_completed <= beats_completed_q;
            end
        end
    end

    initial begin
        if ((LOCAL_TAG_WIDTH != 8) || (DATA_BYTES != 128) ||
            (DATA_WIDTH != 1024)) begin
            $error("npu_dma_channel_mover violates DMA v0.1 geometry");
        end
    end

endmodule

`default_nettype wire
