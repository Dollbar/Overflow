`timescale 1ns/1ps
`default_nettype none

// Compatibility loader for the current 128-bit compute-local write boundary.
// One 128-byte data beat and one 128-byte scale beat are read from Pod-shared
// SRAM, then emitted as one to eight bank writes without crossing the NoC.
module npu_pod_local_loader #(
    parameter int unsigned SRAM_ADDRESS_WIDTH = 24,
    parameter int unsigned SRAM_DATA_WIDTH = 1024,
    parameter int unsigned LOCAL_WORD_WIDTH = 128,
    parameter int unsigned LOCAL_BANKS = 16,
    parameter int unsigned LOCAL_BUFFER_COUNT = 4,
    parameter int unsigned LOCAL_VECTOR_DEPTH = 8192,
    parameter int unsigned BANK_INDEX_WIDTH =
        (LOCAL_BANKS <= 1) ? 1 : $clog2(LOCAL_BANKS)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic command_valid_i,
    output logic command_ready_o,
    input  logic [npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_WIDTH-1:0]
                 command_i,

    output logic shared_read_request_valid_o,
    input  logic shared_read_request_ready_i,
    output logic [SRAM_ADDRESS_WIDTH-1:0] shared_read_request_address_o,
    input  logic shared_read_response_valid_i,
    output logic shared_read_response_ready_o,
    input  logic [SRAM_DATA_WIDTH-1:0] shared_read_response_data_i,

    output logic tensor_write_valid_o,
    input  logic tensor_write_ready_i,
    output logic tensor_write_weight_o,
    output logic [3:0] tensor_write_buffer_id_o,
    output logic [BANK_INDEX_WIDTH-1:0] tensor_write_bank_o,
    output logic [31:0] tensor_write_offset_o,
    output logic [LOCAL_WORD_WIDTH-1:0] tensor_write_data_o,
    output logic [LOCAL_WORD_WIDTH-1:0] tensor_write_scale_o,

    output logic vector_write_valid_o,
    input  logic vector_write_ready_i,
    output logic vector_write_c_o,
    output logic [3:0] vector_write_buffer_id_o,
    output logic [BANK_INDEX_WIDTH-1:0] vector_write_bank_o,
    output logic [31:0] vector_write_offset_o,
    output logic [LOCAL_WORD_WIDTH-1:0] vector_write_data_o,
    output logic [7:0] vector_write_scale_o,

    output logic completion_valid_o,
    input  logic completion_ready_i,
    output logic [npu_pod_pkg::NPU_POD_LOCAL_COMPLETION_WIDTH-1:0]
                 completion_o,
    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o
);

    localparam int unsigned WORDS_PER_BEAT =
        SRAM_DATA_WIDTH / LOCAL_WORD_WIDTH;
    localparam logic [SRAM_ADDRESS_WIDTH:0] LAST_BEAT_ADDRESS =
        (SRAM_ADDRESS_WIDTH+1)'((1 << SRAM_ADDRESS_WIDTH) -
                               (SRAM_DATA_WIDTH / 8));

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_DATA_REQUEST,
        STATE_DATA_RESPONSE,
        STATE_SCALE_REQUEST,
        STATE_SCALE_RESPONSE,
        STATE_WRITE,
        STATE_COMPLETE
    } state_e;

    state_e state_q;
    npu_pod_pkg::npu_pod_local_transfer_t command_fields;
    // Version and transfer_id are consumed at admission; the retained packed
    // command intentionally keeps the frozen wire shape intact.
    /* verilator lint_off UNUSEDSIGNAL */
    npu_pod_pkg::npu_pod_local_transfer_t active_command_q;
    /* verilator lint_on UNUSEDSIGNAL */
    npu_pod_pkg::npu_pod_local_completion_t completion_q;
    logic [SRAM_DATA_WIDTH-1:0] data_beat_q;
    logic [SRAM_DATA_WIDTH-1:0] scale_beat_q;
    logic [$clog2(WORDS_PER_BEAT)-1:0] word_index_q;
    logic command_fire;
    logic local_write_fire;
    logic command_valid_fields;
    npu_pod_pkg::npu_pod_local_error_e command_error;

    assign command_fields = command_i;

    always_comb begin
        command_valid_fields = 1'b1;
        command_error = npu_pod_pkg::NPU_POD_LOCAL_OK;
        if (command_fields.version !=
            npu_pod_pkg::NPU_POD_LOCAL_TRANSFER_VERSION) begin
            command_valid_fields = 1'b0;
            command_error = npu_pod_pkg::NPU_POD_LOCAL_ERROR_VERSION;
        end else if ((command_fields.word_count == 4'd0) ||
                     (command_fields.word_count > 4'(WORDS_PER_BEAT))) begin
            command_valid_fields = 1'b0;
            command_error = npu_pod_pkg::NPU_POD_LOCAL_ERROR_WORD_COUNT;
        end else if (({1'b0, command_fields.bank_start} +
                      {1'b0, command_fields.word_count}) >
                     5'(LOCAL_BANKS)) begin
            command_valid_fields = 1'b0;
            command_error = npu_pod_pkg::NPU_POD_LOCAL_ERROR_BANK_RANGE;
        end else if ((command_fields.data_sram_address[6:0] != 7'd0) ||
                     (command_fields.scale_sram_address[6:0] != 7'd0)) begin
            command_valid_fields = 1'b0;
            command_error = npu_pod_pkg::NPU_POD_LOCAL_ERROR_ALIGNMENT;
        end else if (({1'b0, command_fields.data_sram_address} >
                      LAST_BEAT_ADDRESS) ||
                     ({1'b0, command_fields.scale_sram_address} >
                      LAST_BEAT_ADDRESS)) begin
            command_valid_fields = 1'b0;
            command_error = npu_pod_pkg::NPU_POD_LOCAL_ERROR_SRAM_RANGE;
        end else if ((command_fields.buffer_id >= 4'(LOCAL_BUFFER_COUNT)) ||
                     (command_fields.local_offset[3:0] != 4'd0) ||
                     ((command_fields.local_offset >> 4) >=
                      LOCAL_VECTOR_DEPTH)) begin
            command_valid_fields = 1'b0;
            command_error = npu_pod_pkg::NPU_POD_LOCAL_ERROR_OFFSET;
        end
    end

    always_comb begin
        command_ready_o = !rst_i && !clear_i && !quiesce_i &&
                          (state_q == STATE_IDLE);
        shared_read_request_valid_o = 1'b0;
        shared_read_request_address_o = '0;
        shared_read_response_ready_o = 1'b0;
        tensor_write_valid_o = 1'b0;
        tensor_write_weight_o =
            active_command_q.target ==
            npu_pod_pkg::NPU_POD_TARGET_TENSOR_WEIGHT;
        tensor_write_buffer_id_o = active_command_q.buffer_id;
        tensor_write_bank_o = BANK_INDEX_WIDTH'(
            active_command_q.bank_start + word_index_q);
        tensor_write_offset_o = active_command_q.local_offset;
        tensor_write_data_o = data_beat_q[
            word_index_q*LOCAL_WORD_WIDTH +: LOCAL_WORD_WIDTH];
        tensor_write_scale_o = scale_beat_q[
            word_index_q*LOCAL_WORD_WIDTH +: LOCAL_WORD_WIDTH];
        vector_write_valid_o = 1'b0;
        vector_write_c_o =
            active_command_q.target ==
            npu_pod_pkg::NPU_POD_TARGET_VECTOR_C;
        vector_write_buffer_id_o = active_command_q.buffer_id;
        vector_write_bank_o = BANK_INDEX_WIDTH'(
            active_command_q.bank_start + word_index_q);
        vector_write_offset_o = active_command_q.local_offset;
        vector_write_data_o = data_beat_q[
            word_index_q*LOCAL_WORD_WIDTH +: LOCAL_WORD_WIDTH];
        vector_write_scale_o = scale_beat_q[word_index_q*8 +: 8];
        completion_valid_o = state_q == STATE_COMPLETE;
        completion_o = completion_q;

        case (state_q)
            STATE_DATA_REQUEST: begin
                shared_read_request_valid_o = 1'b1;
                shared_read_request_address_o =
                    active_command_q.data_sram_address;
            end
            STATE_DATA_RESPONSE: begin
                shared_read_response_ready_o = 1'b1;
            end
            STATE_SCALE_REQUEST: begin
                shared_read_request_valid_o = 1'b1;
                shared_read_request_address_o =
                    active_command_q.scale_sram_address;
            end
            STATE_SCALE_RESPONSE: begin
                shared_read_response_ready_o = 1'b1;
            end
            STATE_WRITE: begin
                if ((active_command_q.target ==
                     npu_pod_pkg::NPU_POD_TARGET_TENSOR_ACTIVATION) ||
                    (active_command_q.target ==
                     npu_pod_pkg::NPU_POD_TARGET_TENSOR_WEIGHT)) begin
                    tensor_write_valid_o = 1'b1;
                end else begin
                    vector_write_valid_o = 1'b1;
                end
            end
            default: begin
            end
        endcase
    end

    assign command_fire = command_valid_i && command_ready_o;
    assign local_write_fire =
        (tensor_write_valid_o && tensor_write_ready_i) ||
        (vector_write_valid_o && vector_write_ready_i);
    assign busy_o = state_q != STATE_IDLE;
    assign quiesced_o = quiesce_i && (state_q == STATE_IDLE);

    always_ff @(posedge clk_i) begin
        if (rst_i || clear_i) begin
            state_q <= STATE_IDLE;
            active_command_q <= '0;
            completion_q <= '0;
            data_beat_q <= '0;
            scale_beat_q <= '0;
            word_index_q <= '0;
            protocol_error_o <= 1'b0;
        end else begin
            case (state_q)
                STATE_IDLE: begin
                    if (command_fire) begin
                        active_command_q <= command_fields;
                        completion_q.transfer_id <= command_fields.transfer_id;
                        completion_q.success <= command_valid_fields;
                        completion_q.error_code <= command_error;
                        word_index_q <= '0;
                        if (command_valid_fields) begin
                            state_q <= STATE_DATA_REQUEST;
                        end else begin
                            protocol_error_o <= 1'b1;
                            state_q <= STATE_COMPLETE;
                        end
                    end
                end
                STATE_DATA_REQUEST: begin
                    if (shared_read_request_valid_o &&
                        shared_read_request_ready_i) begin
                        state_q <= STATE_DATA_RESPONSE;
                    end
                end
                STATE_DATA_RESPONSE: begin
                    if (shared_read_response_valid_i &&
                        shared_read_response_ready_o) begin
                        data_beat_q <= shared_read_response_data_i;
                        state_q <= STATE_SCALE_REQUEST;
                    end
                end
                STATE_SCALE_REQUEST: begin
                    if (shared_read_request_valid_o &&
                        shared_read_request_ready_i) begin
                        state_q <= STATE_SCALE_RESPONSE;
                    end
                end
                STATE_SCALE_RESPONSE: begin
                    if (shared_read_response_valid_i &&
                        shared_read_response_ready_o) begin
                        scale_beat_q <= shared_read_response_data_i;
                        state_q <= STATE_WRITE;
                    end
                end
                STATE_WRITE: begin
                    if (local_write_fire) begin
                        if (word_index_q + 1'b1 ==
                            active_command_q.word_count) begin
                            state_q <= STATE_COMPLETE;
                        end else begin
                            word_index_q <= word_index_q + 1'b1;
                        end
                    end
                end
                STATE_COMPLETE: begin
                    if (completion_valid_o && completion_ready_i) begin
                        state_q <= STATE_IDLE;
                    end
                end
                default: begin
                    state_q <= STATE_IDLE;
                    protocol_error_o <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
