`include "kdlink_v2_defs.vh"
module kdlink_v2_rx_commit #(
    parameter integer CONTEXT_BITS = 6,
    parameter integer RESPONSE_BITS = 6
) (
    input wire clk_i,
    input wire rst_n_i,
    input wire [4:0] local_node_i,
    input wire [7:0] link_epoch_i,
    input wire flit_valid_i,
    input wire crc_good_i,
    input wire [95:0] header_i,
    input wire [511:0] payload_i,
    input wire [6:0] payload_bytes_i,
    output wire flit_ready_o,
    output wire commit_valid_o,
    input wire commit_ready_i,
    output wire [95:0] commit_header_o,
    output wire [511:0] commit_payload_o,
    output wire [6:0] commit_payload_bytes_o,
    output wire commit_last_o,
    output wire response_valid_o,
    input wire response_ready_i,
    output wire [3:0] response_type_o,
    output wire [2:0] response_vc_o,
    output wire [2:0] response_plane_o,
    output wire response_phase_o,
    output wire [4:0] response_dst_node_o,
    output wire [11:0] response_collective_id_o,
    output wire [11:0] response_packet_seq_o,
    output wire [15:0] response_credit_total_o,
    output wire [7:0] response_status_o,
    output reg duplicate_o,
    output reg protocol_error_o
);
    localparam integer RESPONSE_WIDTH = 64;
    localparam integer CONTEXT_COUNT = (1 << CONTEXT_BITS);
    localparam integer RESPONSE_DEPTH = (1 << RESPONSE_BITS);
    localparam [RESPONSE_BITS:0] RESPONSE_CAPACITY =
        {1'b1, {RESPONSE_BITS{1'b0}}};
    reg [95:0] header_mem [0:CONTEXT_COUNT-1][0:15];
    reg [511:0] payload_mem [0:CONTEXT_COUNT-1][0:15];
    reg [6:0] bytes_mem [0:CONTEXT_COUNT-1][0:15];
    reg [4:0] slot_flits_q [0:CONTEXT_COUNT-1];
    reg [15:0] slot_credit_total_q [0:CONTEXT_COUNT-1];
    reg [CONTEXT_BITS-1:0] head_q;
    reg [CONTEXT_BITS-1:0] tail_q;
    reg [CONTEXT_BITS:0] context_count_q;
    reg rx_active_q;
    reg drain_bad_q;
    reg rx_duplicate_q;
    reg [CONTEXT_BITS-1:0] rx_slot_q;
    reg [3:0] rx_flit_index_q;
    reg [5:0] expected_flit_seq_q;
    reg [95:0] rx_header_q;
    reg [3:0] output_flit_index_q;
    reg [15:0] credit_total_q [0:7];

    reg history_valid_q [0:511];
    reg [11:0] history_collective_q [0:511];
    reg history_phase_q [0:511];
    reg [11:0] history_sequence_q [0:511];
    reg [4:0] history_source_q [0:511];
    reg [7:0] history_epoch_q [0:511];

    reg [RESPONSE_WIDTH-1:0] response_mem [0:RESPONSE_DEPTH-1];
    reg [RESPONSE_BITS-1:0] response_read_q;
    reg [RESPONSE_BITS-1:0] response_write_q;
    reg [RESPONSE_BITS:0] response_count_q;
    reg input_event_valid;
    reg [RESPONSE_WIDTH-1:0] input_event_data;
    reg output_event_valid;
    reg [RESPONSE_WIDTH-1:0] output_event_data;
    reg [1:0] response_push_count;
    wire response_pop;
    wire [RESPONSE_WIDTH-1:0] response_head;

    wire input_fire;
    wire output_fire;
    wire output_last;
    wire context_full;
    wire response_space;
    wire header_sop;
    wire header_eop;
    wire [2:0] header_vc;
    wire [3:0] header_message_type;
    wire header_retry;
    wire [4:0] header_source;
    wire [4:0] header_destination;
    wire [2:0] header_plane;
    wire [11:0] header_collective;
    wire [11:0] header_sequence;
    wire [5:0] header_flit_sequence;
    wire header_phase;
    wire [7:0] header_epoch;
    wire identity_match;
    wire header_legal;
    wire flit_error;
    wire history_match;
    wire enqueue_event;
    wire dequeue_event;
    wire [15:0] incremented_credit_total;
    integer reset_index;

    assign header_sop = header_i[17];
    assign header_eop = header_i[18];
    assign header_vc = header_i[15:13];
    assign header_message_type = header_i[7:4];
    assign header_retry = header_i[19];
    assign header_source = header_i[24:20];
    assign header_destination = header_i[29:25];
    assign header_plane = header_i[32:30];
    assign header_epoch = header_i[45:38];
    assign header_collective = header_i[57:46];
    assign header_sequence = header_i[81:70];
    assign header_flit_sequence = header_i[87:82];
    assign header_phase = header_i[16];
    assign incremented_credit_total = credit_total_q[header_vc] + 16'd1;
    assign context_full = context_count_q[CONTEXT_BITS];
    assign response_space = response_count_q < (RESPONSE_CAPACITY - 1'b1);
    assign flit_ready_o = response_space &&
        (drain_bad_q || rx_active_q || !context_full || dequeue_event);
    assign input_fire = flit_valid_i && flit_ready_o;
    assign identity_match = (header_i[57:46] == rx_header_q[57:46]) &&
        (header_i[16] == rx_header_q[16]) &&
        (header_i[12:11] == rx_header_q[12:11]) &&
        (header_i[69:58] == rx_header_q[69:58]) &&
        (header_i[81:70] == rx_header_q[81:70]) &&
        (header_i[24:20] == rx_header_q[24:20]) &&
        (header_i[45:38] == rx_header_q[45:38]);
    assign header_legal = (header_i[3:0] == `KDL2_SCHEMA_VERSION) &&
        (header_i[7:4] <= `KDL2_MESSAGE_TYPE_FAULT) &&
        (header_i[94:88] == payload_bytes_i) && (payload_bytes_i <= 7'd64) &&
        (header_destination == local_node_i) && (header_epoch == link_epoch_i) &&
        !header_i[95] &&
        (((header_message_type == `KDL2_MESSAGE_TYPE_DATA) &&
          ((!header_retry && (header_vc <= `KDL2_VC_ROLE_POINT_TO_POINT)) ||
           (header_retry && (header_vc == `KDL2_VC_ROLE_REPLAY)))) ||
         ((header_message_type >= `KDL2_MESSAGE_TYPE_COLL_SETUP) &&
          (header_message_type <= `KDL2_MESSAGE_TYPE_COLL_ABORT) &&
          (header_vc == `KDL2_VC_ROLE_CONTROL)) ||
         ((header_message_type >= `KDL2_MESSAGE_TYPE_KEEPALIVE) &&
          (header_vc == `KDL2_VC_ROLE_MANAGEMENT)));
    assign flit_error = !crc_good_i || !header_legal ||
        (!rx_active_q && !header_sop) ||
        (rx_active_q && (header_sop || !identity_match ||
            (header_flit_sequence != expected_flit_seq_q))) ||
        (rx_active_q && (rx_flit_index_q == 4'd15) && !header_eop);
    assign history_match = history_valid_q[header_sequence[8:0]] &&
        (history_collective_q[header_sequence[8:0]] == header_collective) &&
        (history_phase_q[header_sequence[8:0]] == header_phase) &&
        (history_sequence_q[header_sequence[8:0]] == header_sequence) &&
        (history_source_q[header_sequence[8:0]] == header_source) &&
        (history_epoch_q[header_sequence[8:0]] == header_epoch);
    assign output_last = (context_count_q != 0) &&
        ({1'b0, output_flit_index_q} == (slot_flits_q[head_q] - 5'd1));
    assign commit_valid_o = (context_count_q != 0) && response_space;
    assign commit_header_o = header_mem[head_q][output_flit_index_q];
    assign commit_payload_o = payload_mem[head_q][output_flit_index_q];
    assign commit_payload_bytes_o = bytes_mem[head_q][output_flit_index_q];
    assign commit_last_o = commit_valid_o && output_last;
    assign output_fire = commit_valid_o && commit_ready_i;
    assign dequeue_event = output_fire && output_last;
    assign enqueue_event = input_fire && !drain_bad_q && !flit_error && header_eop &&
        !(rx_duplicate_q || (!rx_active_q && history_match));

    assign response_valid_o = response_count_q != 0;
    assign response_pop = response_valid_o && response_ready_i;
    assign response_head = response_mem[response_read_q];
    assign response_type_o = response_head[3:0];
    assign response_vc_o = response_head[6:4];
    assign response_plane_o = response_head[9:7];
    assign response_phase_o = response_head[10];
    assign response_dst_node_o = response_head[15:11];
    assign response_collective_id_o = response_head[27:16];
    assign response_packet_seq_o = response_head[39:28];
    assign response_credit_total_o = response_head[55:40];
    assign response_status_o = response_head[63:56];

    always @(*) begin
        input_event_valid = 1'b0;
        input_event_data = {RESPONSE_WIDTH{1'b0}};
        if (input_fire) begin
            if (drain_bad_q) begin
                input_event_valid = 1'b1;
                input_event_data = {8'd0, incremented_credit_total,
                    header_sequence, header_collective, header_source,
                    header_phase, header_plane, header_vc,
                    4'd0};
            end else if (flit_error) begin
                input_event_valid = 1'b1;
                input_event_data = {crc_good_i ? 8'h33 : 8'h30,
                    incremented_credit_total,
                    rx_active_q ? rx_header_q[81:70] : header_sequence,
                    rx_active_q ? rx_header_q[57:46] : header_collective,
                    rx_active_q ? rx_header_q[24:20] : header_source,
                    rx_active_q ? rx_header_q[16] : header_phase,
                    rx_active_q ? rx_header_q[32:30] : header_plane,
                    rx_active_q ? rx_header_q[15:13] : header_vc,
                    4'd2};
            end else if (header_eop &&
                (rx_duplicate_q || (!rx_active_q && history_match))) begin
                input_event_valid = 1'b1;
                input_event_data = {8'd0, incremented_credit_total,
                    header_sequence, header_collective, header_source,
                    header_phase, header_plane, header_vc,
                    4'd1};
            end else if (!header_eop) begin
                input_event_valid = 1'b1;
                input_event_data = {8'd0, incremented_credit_total,
                    header_sequence, header_collective, header_source,
                    header_phase, header_plane, header_vc,
                    4'd0};
            end
        end

        output_event_valid = dequeue_event;
        output_event_data = {8'd0, slot_credit_total_q[head_q],
            header_mem[head_q][0][81:70], header_mem[head_q][0][57:46],
            header_mem[head_q][0][24:20], header_mem[head_q][0][16],
            header_mem[head_q][0][32:30], header_mem[head_q][0][15:13],
            4'd1};
        response_push_count = {1'b0, input_event_valid} +
            {1'b0, output_event_valid};
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            head_q <= {CONTEXT_BITS{1'b0}};
            tail_q <= {CONTEXT_BITS{1'b0}};
            context_count_q <= {(CONTEXT_BITS+1){1'b0}};
            rx_active_q <= 1'b0;
            drain_bad_q <= 1'b0;
            rx_duplicate_q <= 1'b0;
            rx_slot_q <= {CONTEXT_BITS{1'b0}};
            rx_flit_index_q <= 4'd0;
            expected_flit_seq_q <= 6'd0;
            rx_header_q <= 96'd0;
            output_flit_index_q <= 4'd0;
            response_read_q <= {RESPONSE_BITS{1'b0}};
            response_write_q <= {RESPONSE_BITS{1'b0}};
            response_count_q <= {(RESPONSE_BITS+1){1'b0}};
            duplicate_o <= 1'b0;
            protocol_error_o <= 1'b0;
            for (reset_index = 0; reset_index < 8; reset_index = reset_index + 1)
                credit_total_q[reset_index] <= 16'd0;
            for (reset_index = 0; reset_index < CONTEXT_COUNT; reset_index = reset_index + 1) begin
                slot_flits_q[reset_index] <= 5'd0;
                slot_credit_total_q[reset_index] <= 16'd0;
            end
            for (reset_index = 0; reset_index < 512; reset_index = reset_index + 1) begin
                history_valid_q[reset_index] <= 1'b0;
                history_collective_q[reset_index] <= 12'd0;
                history_phase_q[reset_index] <= 1'b0;
                history_sequence_q[reset_index] <= 12'd0;
                history_source_q[reset_index] <= 5'd0;
                history_epoch_q[reset_index] <= 8'd0;
            end
        end else begin
            duplicate_o <= 1'b0;
            if (flit_valid_i && !flit_ready_o) protocol_error_o <= 1'b1;

            case ({enqueue_event, dequeue_event})
                2'b10: context_count_q <= context_count_q + 1'b1;
                2'b01: context_count_q <= context_count_q - 1'b1;
                default: context_count_q <= context_count_q;
            endcase
            if (enqueue_event) tail_q <= tail_q + 1'b1;
            if (dequeue_event) begin
                head_q <= head_q + 1'b1;
                history_valid_q[header_mem[head_q][0][78:70]] <= 1'b1;
                history_collective_q[header_mem[head_q][0][78:70]] <=
                    header_mem[head_q][0][57:46];
                history_phase_q[header_mem[head_q][0][78:70]] <=
                    header_mem[head_q][0][16];
                history_sequence_q[header_mem[head_q][0][78:70]] <=
                    header_mem[head_q][0][81:70];
                history_source_q[header_mem[head_q][0][78:70]] <=
                    header_mem[head_q][0][24:20];
                history_epoch_q[header_mem[head_q][0][78:70]] <=
                    header_mem[head_q][0][45:38];
            end

            if (output_fire) begin
                if (output_last) output_flit_index_q <= 4'd0;
                else output_flit_index_q <= output_flit_index_q + 1'b1;
            end

            if (input_fire) begin
                credit_total_q[header_vc] <= incremented_credit_total;
                if (drain_bad_q) begin
                    if (header_eop) drain_bad_q <= 1'b0;
                end else if (flit_error) begin
                    if (crc_good_i) protocol_error_o <= 1'b1;
                    rx_active_q <= 1'b0;
                    drain_bad_q <= !header_eop;
                end else if (!rx_active_q) begin
                    rx_slot_q <= tail_q;
                    rx_header_q <= header_i;
                    rx_duplicate_q <= history_match;
                    rx_flit_index_q <= 4'd1;
                    expected_flit_seq_q <= 6'd1;
                    header_mem[tail_q][0] <= header_i;
                    payload_mem[tail_q][0] <= payload_i;
                    bytes_mem[tail_q][0] <= payload_bytes_i;
                    slot_flits_q[tail_q] <= 5'd1;
                    slot_credit_total_q[tail_q] <= incremented_credit_total;
                    if (header_eop) begin
                        rx_active_q <= 1'b0;
                        if (history_match) duplicate_o <= 1'b1;
                    end else begin
                        rx_active_q <= 1'b1;
                    end
                end else begin
                    header_mem[rx_slot_q][rx_flit_index_q] <= header_i;
                    payload_mem[rx_slot_q][rx_flit_index_q] <= payload_i;
                    bytes_mem[rx_slot_q][rx_flit_index_q] <= payload_bytes_i;
                    slot_flits_q[rx_slot_q] <= {1'b0, rx_flit_index_q} + 5'd1;
                    slot_credit_total_q[rx_slot_q] <= incremented_credit_total;
                    if (header_eop) begin
                        rx_active_q <= 1'b0;
                        if (rx_duplicate_q) duplicate_o <= 1'b1;
                    end else begin
                        rx_flit_index_q <= rx_flit_index_q + 1'b1;
                        expected_flit_seq_q <= expected_flit_seq_q + 1'b1;
                    end
                end
            end

            case ({response_push_count, response_pop})
                3'b000: response_count_q <= response_count_q;
                3'b001: begin
                    response_read_q <= response_read_q + 1'b1;
                    response_count_q <= response_count_q - 1'b1;
                end
                3'b010: response_count_q <= response_count_q + 1'b1;
                3'b011: response_read_q <= response_read_q + 1'b1;
                3'b100: response_count_q <= response_count_q +
                    {{(RESPONSE_BITS-1){1'b0}}, 2'd2};
                3'b101: begin
                    response_read_q <= response_read_q + 1'b1;
                    response_count_q <= response_count_q + 1'b1;
                end
                default: response_count_q <= response_count_q;
            endcase
            if (response_push_count != 0) begin
                if (input_event_valid) begin
                    response_mem[response_write_q] <= input_event_data;
                    if (output_event_valid)
                        response_mem[response_write_q + 1'b1] <= output_event_data;
                end else begin
                    response_mem[response_write_q] <= output_event_data;
                end
                response_write_q <= response_write_q +
                    {{(RESPONSE_BITS-2){1'b0}}, response_push_count};
            end
        end
    end
endmodule
