`include "kdlink_defs.vh"

package kdlink_tb_pkg;
    localparam int unsigned KDLINK_PAYLOAD_WIDTH = `KDL_PAYLOAD_WIDTH;
    localparam int unsigned KDLINK_HEADER_NO_CRC_WIDTH = 96;
    localparam int unsigned KDLINK_FLIT_WIDTH = `KDL_FLIT_WIDTH;

    typedef logic [KDLINK_PAYLOAD_WIDTH-1:0] kdlink_payload_t;
    typedef logic [KDLINK_HEADER_NO_CRC_WIDTH-1:0] kdlink_header_t;
    typedef logic [KDLINK_FLIT_WIDTH-1:0] kdlink_flit_t;

    typedef struct packed {
        logic reserved;
        logic [6:0] payload_bytes;
        logic [5:0] flit_seq;
        logic [11:0] packet_seq;
        logic [11:0] chunk_id;
        logic [11:0] collective_id;
        logic [7:0] link_epoch;
        logic [4:0] hop_limit;
        logic [2:0] plane_id;
        logic [4:0] dst_node;
        logic [4:0] src_node;
        logic retry;
        logic eop;
        logic sop;
        logic phase;
        logic [2:0] vc;
        logic [1:0] dtype;
        logic [2:0] opcode;
        logic [3:0] message_type;
        logic [3:0] version;
    } kdlink_header_fields_t;

    typedef struct packed {
        logic [345:0] reserved;
        logic [2:0] logical_vc;
        logic [31:0] group_id;
        logic [63:0] global_transaction_id;
        logic [11:0] expected_packet_sequence;
        logic [4:0] packet_flit_count;
        logic [2:0] route_policy;
        logic [1:0] slice_mask;
        logic [2:0] logical_plane;
        logic [7:0] domain_hop_limit;
        logic [7:0] topology_epoch;
        logic [4:0] destination_node;
        logic [4:0] source_node;
        logic [7:0] destination_domain;
        logic [7:0] source_domain;
    } kdlink_route_context_fields_t;

    typedef struct packed {
        logic [320:0] reserved;
        logic [2:0] route_depth;
        logic [2:0] logical_vc;
        logic [31:0] group_id;
        logic [63:0] global_transaction_id;
        logic [11:0] expected_packet_sequence;
        logic [4:0] packet_flit_count;
        logic [2:0] route_policy;
        logic [1:0] slice_mask;
        logic [2:0] logical_plane;
        logic [7:0] domain_hop_limit;
        logic [15:0] topology_epoch;
        logic [4:0] destination_node;
        logic [4:0] source_node;
        logic [14:0] destination_domain;
        logic [14:0] source_domain;
    } kdlink_scale_route_context_fields_t;

    typedef struct packed {
        logic [411:0] reserved;
        logic [1:0] status;
        logic [63:0] global_transaction_id;
        logic [7:0] topology_epoch;
        logic [4:0] destination_node;
        logic [4:0] source_node;
        logic [7:0] destination_domain;
        logic [7:0] source_domain;
    } kdlink_global_commit_fields_t;

    typedef struct packed {
        logic [389:0] reserved;
        logic [1:0] status;
        logic [63:0] global_transaction_id;
        logic [15:0] topology_epoch;
        logic [4:0] destination_node;
        logic [4:0] source_node;
        logic [14:0] destination_domain;
        logic [14:0] source_domain;
    } kdlink_scale_global_commit_fields_t;

    function automatic kdlink_header_t kdlink_encode_header(
        input kdlink_header_fields_t fields
    );
        kdlink_encode_header = fields;
    endfunction

    function automatic kdlink_header_fields_t kdlink_decode_header(
        input kdlink_header_t header
    );
        kdlink_decode_header = kdlink_header_fields_t'(header);
    endfunction

    function automatic kdlink_payload_t kdlink_encode_route_context(
        input kdlink_route_context_fields_t fields
    );
        kdlink_encode_route_context = fields;
    endfunction

    function automatic kdlink_route_context_fields_t kdlink_decode_route_context(
        input kdlink_payload_t payload
    );
        kdlink_decode_route_context = kdlink_route_context_fields_t'(payload);
    endfunction

    function automatic kdlink_payload_t kdlink_encode_scale_route_context(
        input kdlink_scale_route_context_fields_t fields
    );
        kdlink_encode_scale_route_context = fields;
    endfunction

    function automatic kdlink_scale_route_context_fields_t kdlink_decode_scale_route_context(
        input kdlink_payload_t payload
    );
        kdlink_decode_scale_route_context = kdlink_scale_route_context_fields_t'(payload);
    endfunction

    function automatic kdlink_payload_t kdlink_encode_global_commit(
        input kdlink_global_commit_fields_t fields
    );
        kdlink_encode_global_commit = fields;
    endfunction

    function automatic kdlink_global_commit_fields_t kdlink_decode_global_commit(
        input kdlink_payload_t payload
    );
        kdlink_decode_global_commit = kdlink_global_commit_fields_t'(payload);
    endfunction

    function automatic kdlink_payload_t kdlink_encode_scale_global_commit(
        input kdlink_scale_global_commit_fields_t fields
    );
        kdlink_encode_scale_global_commit = fields;
    endfunction

    function automatic kdlink_scale_global_commit_fields_t kdlink_decode_scale_global_commit(
        input kdlink_payload_t payload
    );
        kdlink_decode_scale_global_commit = kdlink_scale_global_commit_fields_t'(payload);
    endfunction

    function automatic logic [31:0] kdlink_crc32(
        input kdlink_header_t header,
        input kdlink_payload_t payload,
        input logic [6:0] payload_bytes
    );
        logic [31:0] crc;
        logic [7:0] data_byte;
        int byte_index;
        int bit_index;
        int unsigned byte_count;
        begin
            crc = 32'hffff_ffff;
            byte_count = {25'd0, payload_bytes};
            for (byte_index = 0; byte_index < 12 + byte_count; byte_index++) begin
                if (byte_index < 12) data_byte = header[byte_index*8 +: 8];
                else data_byte = payload[(byte_index-12)*8 +: 8];
                crc = crc ^ {24'd0, data_byte};
                for (bit_index = 0; bit_index < 8; bit_index++) begin
                    if (crc[0]) crc = (crc >> 1) ^ 32'hedb8_8320;
                    else crc = crc >> 1;
                end
            end
            kdlink_crc32 = crc ^ 32'hffff_ffff;
        end
    endfunction

    function automatic kdlink_flit_t kdlink_pack_flit(
        input kdlink_header_t header,
        input kdlink_payload_t payload
    );
        logic [31:0] crc;
        begin
            crc = kdlink_crc32(header, payload, header[94:88]);
            kdlink_pack_flit = {crc, header, payload};
        end
    endfunction

    function automatic bit kdlink_header_is_route_context(
        input kdlink_header_fields_t fields,
        input bit allow_route_context,
        input bit allow_scale
    );
        kdlink_header_is_route_context =
            (fields.message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT) &&
            (((fields.version == `KDL_ROUTE_SCHEMA) && allow_route_context) ||
             ((fields.version == `KDL_SCALE_SCHEMA) && allow_scale));
    endfunction

    function automatic bit kdlink_header_is_global_commit(
        input kdlink_header_fields_t fields,
        input bit allow_route_context,
        input bit allow_scale
    );
        kdlink_header_is_global_commit =
            (fields.message_type == `KDL_MESSAGE_TYPE_GLOBAL_COMMIT) &&
            (((fields.version == `KDL_SCHEMA_VERSION) && allow_route_context) ||
             ((fields.version == `KDL_SCALE_SCHEMA) && allow_scale));
    endfunction

    function automatic bit kdlink_header_is_valid_for_capabilities(
        input kdlink_header_t header,
        input bit allow_route_context,
        input bit allow_scale
    );
        kdlink_header_fields_t fields;
        bit route_context;
        bit global_commit;
        bit version_valid;
        bit message_valid;
        bit vc_valid;
        begin
            fields = kdlink_decode_header(header);
            route_context = kdlink_header_is_route_context(
                fields, allow_route_context, allow_scale
            );
            global_commit = kdlink_header_is_global_commit(
                fields, allow_route_context, allow_scale
            );
            version_valid = (fields.version == `KDL_SCHEMA_VERSION) ||
                route_context || global_commit;
            message_valid = (fields.message_type <= `KDL_MESSAGE_TYPE_FAULT) ||
                route_context || global_commit;
            vc_valid = 1'b1;
            if (route_context) begin
                vc_valid = fields.sop && fields.eop && (fields.flit_seq == 6'd0) &&
                    (fields.payload_bytes == 7'd64) &&
                    (fields.retry ? (fields.vc == `KDL_VC_ROLE_REPLAY) :
                                    (fields.vc <= `KDL_VC_ROLE_CONTROL));
            end else if (global_commit) begin
                vc_valid = fields.sop && fields.eop && (fields.flit_seq == 6'd0) &&
                    (fields.payload_bytes == 7'd64) &&
                    (fields.retry ? (fields.vc == `KDL_VC_ROLE_REPLAY) :
                                    (fields.vc == `KDL_VC_ROLE_CONTROL));
            end else if (fields.retry) begin
                vc_valid = (fields.vc == `KDL_VC_ROLE_REPLAY);
            end else if (fields.message_type == `KDL_MESSAGE_TYPE_DATA) begin
                vc_valid = (fields.opcode <= `KDL_OPCODE_POINT_TO_POINT) &&
                    (fields.vc <= `KDL_VC_ROLE_POINT_TO_POINT);
            end else if ((fields.message_type >= `KDL_MESSAGE_TYPE_COLL_SETUP) &&
                         (fields.message_type <= `KDL_MESSAGE_TYPE_COLL_ABORT)) begin
                vc_valid = (fields.vc == `KDL_VC_ROLE_CONTROL);
            end else if (fields.message_type >= `KDL_MESSAGE_TYPE_KEEPALIVE) begin
                vc_valid = (fields.vc == `KDL_VC_ROLE_MANAGEMENT);
            end
            kdlink_header_is_valid_for_capabilities = version_valid && message_valid &&
                vc_valid && (fields.reserved == 1'b0) &&
                (fields.payload_bytes <= 7'd64);
        end
    endfunction

    function automatic bit kdlink_header_is_valid(input kdlink_header_t header);
        kdlink_header_is_valid = kdlink_header_is_valid_for_capabilities(
            header, 1'b0, 1'b0
        );
    endfunction

    function automatic bit kdlink_route_context_is_valid(
        input kdlink_route_context_fields_t fields
    );
        kdlink_route_context_is_valid = (fields.domain_hop_limit != 8'd0) &&
            (fields.slice_mask != 2'd0) && (fields.route_policy == 3'd0) &&
            (fields.packet_flit_count >= 5'd1) &&
            (fields.packet_flit_count <= 5'd16) &&
            (fields.logical_vc <= `KDL_VC_ROLE_CONTROL) && (fields.reserved == '0);
    endfunction

    function automatic bit kdlink_scale_route_context_is_valid(
        input kdlink_scale_route_context_fields_t fields
    );
        kdlink_scale_route_context_is_valid = (fields.domain_hop_limit != 8'd0) &&
            (fields.slice_mask != 2'd0) && (fields.route_policy == 3'd0) &&
            (fields.packet_flit_count >= 5'd1) &&
            (fields.packet_flit_count <= 5'd16) &&
            (fields.logical_vc <= `KDL_VC_ROLE_CONTROL) &&
            (fields.route_depth >= 3'd1) && (fields.route_depth <= 3'd5) &&
            (fields.reserved == '0);
    endfunction

    function automatic bit kdlink_global_commit_is_valid(
        input kdlink_global_commit_fields_t fields
    );
        kdlink_global_commit_is_valid = (fields.status != 2'b11) &&
            (fields.reserved == '0);
    endfunction

    function automatic bit kdlink_scale_global_commit_is_valid(
        input kdlink_scale_global_commit_fields_t fields
    );
        kdlink_scale_global_commit_is_valid = (fields.status != 2'b11) &&
            (fields.reserved == '0);
    endfunction

    function automatic bit kdlink_control_payload_is_valid(
        input kdlink_header_t header,
        input kdlink_payload_t payload,
        input bit allow_route_context,
        input bit allow_scale
    );
        kdlink_header_fields_t fields;
        kdlink_route_context_fields_t route_fields;
        kdlink_scale_route_context_fields_t scale_route_fields;
        kdlink_global_commit_fields_t commit_fields;
        kdlink_scale_global_commit_fields_t scale_commit_fields;
        begin
            fields = kdlink_decode_header(header);
            kdlink_control_payload_is_valid = 1'b1;
            if (kdlink_header_is_route_context(fields, allow_route_context, allow_scale)) begin
                if (fields.version == `KDL_ROUTE_SCHEMA) begin
                    route_fields = kdlink_decode_route_context(payload);
                    kdlink_control_payload_is_valid = kdlink_route_context_is_valid(route_fields) &&
                        (route_fields.source_node == fields.src_node) &&
                        (route_fields.destination_node == fields.dst_node) &&
                        (route_fields.logical_plane == fields.plane_id) &&
                        (fields.retry || (route_fields.logical_vc == fields.vc));
                end else begin
                    scale_route_fields = kdlink_decode_scale_route_context(payload);
                    kdlink_control_payload_is_valid =
                        kdlink_scale_route_context_is_valid(scale_route_fields) &&
                        (scale_route_fields.source_node == fields.src_node) &&
                        (scale_route_fields.destination_node == fields.dst_node) &&
                        (scale_route_fields.logical_plane == fields.plane_id) &&
                        (fields.retry || (scale_route_fields.logical_vc == fields.vc));
                end
            end else if (kdlink_header_is_global_commit(fields, allow_route_context, allow_scale)) begin
                if (fields.version == `KDL_SCALE_SCHEMA) begin
                    scale_commit_fields = kdlink_decode_scale_global_commit(payload);
                    kdlink_control_payload_is_valid =
                        kdlink_scale_global_commit_is_valid(scale_commit_fields) &&
                        (scale_commit_fields.source_node == fields.src_node) &&
                        (scale_commit_fields.destination_node == fields.dst_node);
                end else begin
                    commit_fields = kdlink_decode_global_commit(payload);
                    kdlink_control_payload_is_valid =
                        kdlink_global_commit_is_valid(commit_fields) &&
                        (commit_fields.source_node == fields.src_node) &&
                        (commit_fields.destination_node == fields.dst_node);
                end
            end
        end
    endfunction
endpackage
