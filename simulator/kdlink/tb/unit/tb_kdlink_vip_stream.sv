`timescale 1ns/1ps

module tb_kdlink_vip_stream;
    import kdlink_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic [31:0] accepted_flits;
    logic [31:0] completed_packets;
    logic [31:0] crc_errors;
    logic [31:0] protocol_errors;
    logic [31:0] payload_errors;
    logic [31:0] sequence_errors;
    logic [95:0] header;
    logic [511:0] payload;
    logic [639:0] flit;
    kdlink_header_fields_t fields;
    kdlink_route_context_fields_t route_fields;
    kdlink_scale_route_context_fields_t scale_route_fields;
    kdlink_global_commit_fields_t commit_fields;
    kdlink_scale_global_commit_fields_t scale_commit_fields;

    kdlink_stream_if stream(clk);
    kdlink_stream_monitor #(
        .ALLOW_ROUTE_CONTEXT(1'b1),
        .ALLOW_SCALE(1'b1)
    ) u_monitor (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .stream(stream),
        .accepted_flits_o(accepted_flits),
        .completed_packets_o(completed_packets),
        .crc_errors_o(crc_errors),
        .protocol_errors_o(protocol_errors),
        .payload_errors_o(payload_errors),
        .sequence_errors_o(sequence_errors)
    );

    always #0.5 clk = ~clk;

    task automatic send_fields;
        begin
            header = kdlink_encode_header(fields);
            flit = kdlink_pack_flit(header, payload);
            stream.send(flit);
        end
    endtask

    task automatic check_counters(
        input logic [31:0] expected_flits,
        input logic [31:0] expected_packets,
        input logic [31:0] expected_crc_errors,
        input logic [31:0] expected_protocol_errors,
        input logic [31:0] expected_payload_errors,
        input logic [31:0] expected_sequence_errors
    );
        begin
            @(posedge clk);
            #0.1;
            if (accepted_flits != expected_flits ||
                completed_packets != expected_packets ||
                crc_errors != expected_crc_errors ||
                protocol_errors != expected_protocol_errors ||
                payload_errors != expected_payload_errors ||
                sequence_errors != expected_sequence_errors) begin
                $fatal(1,
                    "VIP counters mismatch got=%0d/%0d/%0d/%0d/%0d/%0d expected=%0d/%0d/%0d/%0d/%0d/%0d",
                    accepted_flits, completed_packets, crc_errors, protocol_errors,
                    payload_errors, sequence_errors, expected_flits, expected_packets,
                    expected_crc_errors, expected_protocol_errors,
                    expected_payload_errors, expected_sequence_errors
                );
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        stream.ready = 1'b0;
        stream.drive_idle();
        fields = '0;
        route_fields = '0;
        scale_route_fields = '0;
        commit_fields = '0;
        scale_commit_fields = '0;
        payload = 512'd0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        fields.version = `KDL_SCHEMA_VERSION;
        fields.message_type = `KDL_MESSAGE_TYPE_DATA;
        fields.opcode = `KDL_OPCODE_ALL_REDUCE;
        fields.dtype = `KDL_DTYPE_INT32;
        fields.vc = `KDL_VC_ROLE_COLLECTIVE;
        fields.sop = 1'b1;
        fields.eop = 1'b1;
        fields.src_node = 5'd3;
        fields.dst_node = 5'd4;
        fields.plane_id = 3'd2;
        fields.hop_limit = 5'd8;
        fields.link_epoch = 8'h21;
        fields.collective_id = 12'h456;
        fields.chunk_id = 12'h012;
        fields.packet_seq = 12'h345;
        fields.payload_bytes = 7'd64;
        payload = {16{32'h1234_5678}};
        header = kdlink_encode_header(fields);
        flit = kdlink_pack_flit(header, payload);

        fork
            stream.send(flit);
            begin
                repeat (3) @(posedge clk);
                stream.ready = 1'b1;
            end
        join
        check_counters(1, 1, 0, 0, 0, 0);

        flit[639] = ~flit[639];
        stream.send(flit);
        check_counters(2, 2, 1, 0, 0, 0);

        route_fields.source_domain = 8'h12;
        route_fields.destination_domain = 8'h34;
        route_fields.source_node = 5'd3;
        route_fields.destination_node = 5'd4;
        route_fields.topology_epoch = 8'h56;
        route_fields.domain_hop_limit = 8'd3;
        route_fields.logical_plane = 3'd2;
        route_fields.slice_mask = 2'b11;
        route_fields.packet_flit_count = 5'd2;
        route_fields.expected_packet_sequence = 12'h401;
        route_fields.global_transaction_id = 64'h0123_4567_89ab_cdef;
        route_fields.group_id = 32'h1020_3040;
        route_fields.logical_vc = `KDL_VC_ROLE_COLLECTIVE;
        payload = kdlink_encode_route_context(route_fields);
        if (kdlink_decode_route_context(payload) != route_fields ||
            !kdlink_route_context_is_valid(route_fields)) begin
            $fatal(1, "schema-3 Route Context package round trip failed");
        end
        fields = '0;
        fields.version = `KDL_ROUTE_SCHEMA;
        fields.message_type = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
        fields.vc = `KDL_VC_ROLE_COLLECTIVE;
        fields.sop = 1'b1;
        fields.eop = 1'b1;
        fields.src_node = 5'd3;
        fields.dst_node = 5'd4;
        fields.plane_id = 3'd2;
        fields.payload_bytes = 7'd64;
        header = kdlink_encode_header(fields);
        if (kdlink_header_is_valid(header) ||
            !kdlink_header_is_valid_for_capabilities(header, 1'b1, 1'b0)) begin
            $fatal(1, "schema-3 capability gate failed");
        end
        send_fields();

        fields = '0;
        fields.version = `KDL_SCHEMA_VERSION;
        fields.message_type = `KDL_MESSAGE_TYPE_DATA;
        fields.opcode = `KDL_OPCODE_ALL_REDUCE;
        fields.dtype = `KDL_DTYPE_FP16;
        fields.vc = `KDL_VC_ROLE_COLLECTIVE;
        fields.sop = 1'b1;
        fields.src_node = 5'd3;
        fields.dst_node = 5'd4;
        fields.plane_id = 3'd2;
        fields.packet_seq = 12'h401;
        fields.collective_id = 12'h221;
        fields.chunk_id = 12'h031;
        fields.payload_bytes = 7'd64;
        payload = {8{64'h55aa_0123_4567_89ab}};
        send_fields();
        fields.sop = 1'b0;
        fields.eop = 1'b1;
        fields.flit_seq = 6'd1;
        payload = {8{64'haa55_fedc_ba98_7654}};
        send_fields();
        check_counters(5, 4, 1, 0, 0, 0);

        scale_route_fields.source_domain = 15'h0123;
        scale_route_fields.destination_domain = 15'h4567;
        scale_route_fields.source_node = 5'd7;
        scale_route_fields.destination_node = 5'd19;
        scale_route_fields.topology_epoch = 16'h789a;
        scale_route_fields.domain_hop_limit = 8'd5;
        scale_route_fields.logical_plane = 3'd6;
        scale_route_fields.slice_mask = 2'b01;
        scale_route_fields.packet_flit_count = 5'd1;
        scale_route_fields.expected_packet_sequence = 12'h402;
        scale_route_fields.global_transaction_id = 64'h7654_3210_fedc_ba98;
        scale_route_fields.group_id = 32'h5566_7788;
        scale_route_fields.logical_vc = `KDL_VC_ROLE_POINT_TO_POINT;
        scale_route_fields.route_depth = 3'd5;
        payload = kdlink_encode_scale_route_context(scale_route_fields);
        if (kdlink_decode_scale_route_context(payload) != scale_route_fields ||
            !kdlink_scale_route_context_is_valid(scale_route_fields)) begin
            $fatal(1, "schema-4 Route Context package round trip failed");
        end
        fields = '0;
        fields.version = `KDL_SCALE_SCHEMA;
        fields.message_type = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
        fields.vc = `KDL_VC_ROLE_POINT_TO_POINT;
        fields.sop = 1'b1;
        fields.eop = 1'b1;
        fields.src_node = 5'd7;
        fields.dst_node = 5'd19;
        fields.plane_id = 3'd6;
        fields.payload_bytes = 7'd64;
        header = kdlink_encode_header(fields);
        if (kdlink_header_is_valid_for_capabilities(header, 1'b1, 1'b0) ||
            !kdlink_header_is_valid_for_capabilities(header, 1'b1, 1'b1)) begin
            $fatal(1, "schema-4 capability gate failed");
        end
        send_fields();

        fields = '0;
        fields.version = `KDL_SCHEMA_VERSION;
        fields.message_type = `KDL_MESSAGE_TYPE_DATA;
        fields.opcode = `KDL_OPCODE_POINT_TO_POINT;
        fields.dtype = `KDL_DTYPE_INT32;
        fields.vc = `KDL_VC_ROLE_POINT_TO_POINT;
        fields.sop = 1'b1;
        fields.eop = 1'b1;
        fields.src_node = 5'd7;
        fields.dst_node = 5'd19;
        fields.plane_id = 3'd6;
        fields.packet_seq = 12'h402;
        fields.payload_bytes = 7'd32;
        payload = {16{32'h89ab_cdef}};
        send_fields();
        check_counters(7, 6, 1, 0, 0, 0);

        scale_commit_fields.source_domain = 15'h4567;
        scale_commit_fields.destination_domain = 15'h0123;
        scale_commit_fields.source_node = 5'd19;
        scale_commit_fields.destination_node = 5'd7;
        scale_commit_fields.topology_epoch = 16'h789a;
        scale_commit_fields.global_transaction_id = 64'h7654_3210_fedc_ba98;
        scale_commit_fields.status = 2'd2;
        payload = kdlink_encode_scale_global_commit(scale_commit_fields);
        if (kdlink_decode_scale_global_commit(payload) != scale_commit_fields ||
            !kdlink_scale_global_commit_is_valid(scale_commit_fields)) begin
            $fatal(1, "schema-4 Global Commit package round trip failed");
        end
        fields = '0;
        fields.version = `KDL_SCALE_SCHEMA;
        fields.message_type = `KDL_MESSAGE_TYPE_GLOBAL_COMMIT;
        fields.vc = `KDL_VC_ROLE_CONTROL;
        fields.sop = 1'b1;
        fields.eop = 1'b1;
        fields.src_node = 5'd19;
        fields.dst_node = 5'd7;
        fields.payload_bytes = 7'd64;
        send_fields();
        check_counters(8, 7, 1, 0, 0, 0);

        scale_commit_fields.reserved[389] = 1'b1;
        payload = kdlink_encode_scale_global_commit(scale_commit_fields);
        send_fields();
        check_counters(9, 8, 1, 1, 1, 0);

        fields = '0;
        fields.version = `KDL_SCHEMA_VERSION;
        fields.message_type = `KDL_MESSAGE_TYPE_DATA;
        fields.opcode = `KDL_OPCODE_ALL_GATHER;
        fields.dtype = `KDL_DTYPE_BF16;
        fields.vc = `KDL_VC_ROLE_COLLECTIVE;
        fields.sop = 1'b1;
        fields.src_node = 5'd1;
        fields.dst_node = 5'd2;
        fields.packet_seq = 12'h500;
        fields.payload_bytes = 7'd64;
        payload = {16{32'h1357_9bdf}};
        send_fields();
        fields.sop = 1'b0;
        fields.eop = 1'b1;
        fields.flit_seq = 6'd2;
        send_fields();
        check_counters(11, 9, 1, 2, 1, 1);

        commit_fields.source_domain = 8'h34;
        commit_fields.destination_domain = 8'h12;
        commit_fields.source_node = 5'd4;
        commit_fields.destination_node = 5'd3;
        commit_fields.topology_epoch = 8'h56;
        commit_fields.global_transaction_id = 64'h0123_4567_89ab_cdef;
        commit_fields.status = 2'd1;
        payload = kdlink_encode_global_commit(commit_fields);
        if (kdlink_decode_global_commit(payload) != commit_fields ||
            !kdlink_global_commit_is_valid(commit_fields)) begin
            $fatal(1, "schema-2 Global Commit package round trip failed");
        end
        fields = '0;
        fields.version = `KDL_SCHEMA_VERSION;
        fields.message_type = `KDL_MESSAGE_TYPE_GLOBAL_COMMIT;
        fields.vc = `KDL_VC_ROLE_CONTROL;
        fields.sop = 1'b1;
        fields.eop = 1'b1;
        fields.src_node = 5'd4;
        fields.dst_node = 5'd3;
        fields.payload_bytes = 7'd64;
        send_fields();
        check_counters(12, 10, 1, 2, 1, 1);

        scale_route_fields.reserved = '0;
        scale_route_fields.source_node = 5'd5;
        scale_route_fields.destination_node = 5'd6;
        scale_route_fields.logical_plane = 3'd1;
        scale_route_fields.logical_vc = `KDL_VC_ROLE_COLLECTIVE;
        scale_route_fields.packet_flit_count = 5'd2;
        scale_route_fields.expected_packet_sequence = 12'h600;
        payload = kdlink_encode_scale_route_context(scale_route_fields);
        fields = '0;
        fields.version = `KDL_SCALE_SCHEMA;
        fields.message_type = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
        fields.vc = `KDL_VC_ROLE_COLLECTIVE;
        fields.sop = 1'b1;
        fields.eop = 1'b1;
        fields.src_node = 5'd5;
        fields.dst_node = 5'd6;
        fields.plane_id = 3'd1;
        fields.payload_bytes = 7'd64;
        send_fields();

        fields = '0;
        fields.version = `KDL_SCHEMA_VERSION;
        fields.message_type = `KDL_MESSAGE_TYPE_DATA;
        fields.opcode = `KDL_OPCODE_ALL_REDUCE;
        fields.dtype = `KDL_DTYPE_FP32;
        fields.vc = `KDL_VC_ROLE_COLLECTIVE;
        fields.sop = 1'b1;
        fields.eop = 1'b1;
        fields.src_node = 5'd5;
        fields.dst_node = 5'd6;
        fields.plane_id = 3'd1;
        fields.packet_seq = 12'h600;
        fields.payload_bytes = 7'd64;
        payload = {16{32'h2468_ace0}};
        send_fields();
        check_counters(14, 12, 1, 3, 1, 2);

        fields.reserved = 1'b1;
        send_fields();
        check_counters(15, 13, 1, 4, 1, 2);

        $display("TB_KDLINK_VIP_STREAM_PASS");
        $finish;
    end
endmodule
