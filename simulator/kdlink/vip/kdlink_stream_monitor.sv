module kdlink_stream_monitor #(
    parameter bit ALLOW_ROUTE_CONTEXT = 1'b0,
    parameter bit ALLOW_SCALE = 1'b0
) (
    input logic clk_i,
    input logic rst_n_i,
    kdlink_stream_if.monitor stream,
    output logic [31:0] accepted_flits_o,
    output logic [31:0] completed_packets_o,
    output logic [31:0] crc_errors_o,
    output logic [31:0] protocol_errors_o,
    output logic [31:0] payload_errors_o,
    output logic [31:0] sequence_errors_o
);
    import kdlink_tb_pkg::*;

    logic [95:0] observed_header;
    logic [511:0] observed_payload;
    logic [31:0] observed_crc;
    logic [31:0] expected_crc;
    kdlink_header_fields_t observed_fields;
    kdlink_route_context_fields_t route_fields;
    kdlink_scale_route_context_fields_t scale_route_fields;

    logic header_valid_now;
    logic payload_valid_now;
    logic route_context_now;
    logic global_commit_now;
    logic sequence_error_now;
    logic trusted_transfer_now;

    logic packet_open_q;
    logic context_pending_q;
    logic context_length_active_q;
    logic [5:0] next_flit_seq_q;
    logic [4:0] packet_flit_count_q;
    logic [4:0] expected_packet_flit_count_q;
    logic [11:0] packet_seq_q;
    logic [11:0] collective_id_q;
    logic [11:0] chunk_id_q;
    logic [4:0] source_node_q;
    logic [4:0] destination_node_q;
    logic [2:0] plane_id_q;
    logic [3:0] message_type_q;
    logic [2:0] opcode_q;
    logic [1:0] dtype_q;
    logic phase_q;
    logic [2:0] vc_q;

    logic [11:0] context_packet_seq_q;
    logic [4:0] context_packet_flit_count_q;
    logic [4:0] context_source_node_q;
    logic [4:0] context_destination_node_q;
    logic [2:0] context_plane_id_q;
    logic [2:0] context_logical_vc_q;

    always_comb begin
        observed_payload = stream.flit[511:0];
        observed_header = stream.flit[607:512];
        observed_crc = stream.flit[639:608];
        observed_fields = kdlink_decode_header(observed_header);
        route_fields = kdlink_decode_route_context(observed_payload);
        scale_route_fields = kdlink_decode_scale_route_context(observed_payload);
        expected_crc = kdlink_crc32(
            observed_header,
            observed_payload,
            observed_fields.payload_bytes
        );
        route_context_now = kdlink_header_is_route_context(
            observed_fields, ALLOW_ROUTE_CONTEXT, ALLOW_SCALE
        );
        global_commit_now = kdlink_header_is_global_commit(
            observed_fields, ALLOW_ROUTE_CONTEXT, ALLOW_SCALE
        );
        header_valid_now = kdlink_header_is_valid_for_capabilities(
            observed_header, ALLOW_ROUTE_CONTEXT, ALLOW_SCALE
        );
        payload_valid_now = kdlink_control_payload_is_valid(
            observed_header, observed_payload, ALLOW_ROUTE_CONTEXT, ALLOW_SCALE
        );
        trusted_transfer_now = (observed_crc == expected_crc) && header_valid_now &&
            payload_valid_now;

        sequence_error_now = 1'b0;
        if (header_valid_now && payload_valid_now) begin
            if (route_context_now || global_commit_now) begin
                if (packet_open_q || context_pending_q) sequence_error_now = 1'b1;
            end else if (packet_open_q) begin
                if (observed_fields.sop ||
                    (observed_fields.flit_seq != next_flit_seq_q) ||
                    (observed_fields.packet_seq != packet_seq_q) ||
                    (observed_fields.collective_id != collective_id_q) ||
                    (observed_fields.chunk_id != chunk_id_q) ||
                    (observed_fields.src_node != source_node_q) ||
                    (observed_fields.dst_node != destination_node_q) ||
                    (observed_fields.plane_id != plane_id_q) ||
                    (observed_fields.message_type != message_type_q) ||
                    (observed_fields.opcode != opcode_q) ||
                    (observed_fields.dtype != dtype_q) ||
                    (observed_fields.phase != phase_q) ||
                    (observed_fields.vc != vc_q)) begin
                    sequence_error_now = 1'b1;
                end
                if (!observed_fields.eop && (packet_flit_count_q >= 5'd16)) begin
                    sequence_error_now = 1'b1;
                end
                if (context_length_active_q && observed_fields.eop &&
                    ((packet_flit_count_q + 5'd1) != expected_packet_flit_count_q)) begin
                    sequence_error_now = 1'b1;
                end
                if (context_length_active_q && !observed_fields.eop &&
                    ((packet_flit_count_q + 5'd1) >= expected_packet_flit_count_q)) begin
                    sequence_error_now = 1'b1;
                end
            end else begin
                if (!observed_fields.sop || (observed_fields.flit_seq != 6'd0)) begin
                    sequence_error_now = 1'b1;
                end
                if (context_pending_q &&
                    ((observed_fields.packet_seq != context_packet_seq_q) ||
                     (observed_fields.src_node != context_source_node_q) ||
                     (observed_fields.dst_node != context_destination_node_q) ||
                     (observed_fields.plane_id != context_plane_id_q) ||
                     (!observed_fields.retry &&
                      (observed_fields.vc != context_logical_vc_q)) ||
                     (observed_fields.retry &&
                      (observed_fields.vc != `KDL_VC_ROLE_REPLAY)))) begin
                    sequence_error_now = 1'b1;
                end
                if (context_pending_q && observed_fields.eop &&
                    (context_packet_flit_count_q != 5'd1)) begin
                    sequence_error_now = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            accepted_flits_o <= 32'd0;
            completed_packets_o <= 32'd0;
            crc_errors_o <= 32'd0;
            protocol_errors_o <= 32'd0;
            payload_errors_o <= 32'd0;
            sequence_errors_o <= 32'd0;
            packet_open_q <= 1'b0;
            context_pending_q <= 1'b0;
            context_length_active_q <= 1'b0;
            next_flit_seq_q <= 6'd0;
            packet_flit_count_q <= 5'd0;
            expected_packet_flit_count_q <= 5'd0;
            packet_seq_q <= 12'd0;
            collective_id_q <= 12'd0;
            chunk_id_q <= 12'd0;
            source_node_q <= 5'd0;
            destination_node_q <= 5'd0;
            plane_id_q <= 3'd0;
            message_type_q <= 4'd0;
            opcode_q <= 3'd0;
            dtype_q <= 2'd0;
            phase_q <= 1'b0;
            vc_q <= 3'd0;
            context_packet_seq_q <= 12'd0;
            context_packet_flit_count_q <= 5'd0;
            context_source_node_q <= 5'd0;
            context_destination_node_q <= 5'd0;
            context_plane_id_q <= 3'd0;
            context_logical_vc_q <= 3'd0;
        end else if (stream.valid && stream.ready) begin
            accepted_flits_o <= accepted_flits_o + 32'd1;
            if (observed_fields.eop) completed_packets_o <= completed_packets_o + 32'd1;
            if (observed_crc != expected_crc) crc_errors_o <= crc_errors_o + 32'd1;
            if (!header_valid_now || !payload_valid_now || sequence_error_now) begin
                protocol_errors_o <= protocol_errors_o + 32'd1;
            end
            if (header_valid_now && !payload_valid_now) begin
                payload_errors_o <= payload_errors_o + 32'd1;
            end
            if (sequence_error_now) sequence_errors_o <= sequence_errors_o + 32'd1;

            if (trusted_transfer_now && !sequence_error_now) begin
                if (route_context_now) begin
                    context_pending_q <= 1'b1;
                    if (observed_fields.version == `KDL_ROUTE_SCHEMA) begin
                        context_packet_seq_q <= route_fields.expected_packet_sequence;
                        context_packet_flit_count_q <= route_fields.packet_flit_count;
                        context_source_node_q <= route_fields.source_node;
                        context_destination_node_q <= route_fields.destination_node;
                        context_plane_id_q <= route_fields.logical_plane;
                        context_logical_vc_q <= route_fields.logical_vc;
                    end else begin
                        context_packet_seq_q <= scale_route_fields.expected_packet_sequence;
                        context_packet_flit_count_q <= scale_route_fields.packet_flit_count;
                        context_source_node_q <= scale_route_fields.source_node;
                        context_destination_node_q <= scale_route_fields.destination_node;
                        context_plane_id_q <= scale_route_fields.logical_plane;
                        context_logical_vc_q <= scale_route_fields.logical_vc;
                    end
                end else if (!global_commit_now) begin
                    if (packet_open_q) begin
                        if (observed_fields.eop) begin
                            packet_open_q <= 1'b0;
                            context_length_active_q <= 1'b0;
                        end else begin
                            next_flit_seq_q <= next_flit_seq_q + 6'd1;
                            packet_flit_count_q <= packet_flit_count_q + 5'd1;
                        end
                    end else begin
                        context_pending_q <= 1'b0;
                        if (!observed_fields.eop) begin
                            packet_open_q <= 1'b1;
                            context_length_active_q <= context_pending_q;
                            next_flit_seq_q <= 6'd1;
                            packet_flit_count_q <= 5'd1;
                            expected_packet_flit_count_q <= context_packet_flit_count_q;
                            packet_seq_q <= observed_fields.packet_seq;
                            collective_id_q <= observed_fields.collective_id;
                            chunk_id_q <= observed_fields.chunk_id;
                            source_node_q <= observed_fields.src_node;
                            destination_node_q <= observed_fields.dst_node;
                            plane_id_q <= observed_fields.plane_id;
                            message_type_q <= observed_fields.message_type;
                            opcode_q <= observed_fields.opcode;
                            dtype_q <= observed_fields.dtype;
                            phase_q <= observed_fields.phase;
                            vc_q <= observed_fields.vc;
                        end else begin
                            context_length_active_q <= 1'b0;
                        end
                    end
                end
            end else if (trusted_transfer_now && sequence_error_now && observed_fields.eop) begin
                packet_open_q <= 1'b0;
                context_pending_q <= 1'b0;
                context_length_active_q <= 1'b0;
            end
        end
    end
endmodule
