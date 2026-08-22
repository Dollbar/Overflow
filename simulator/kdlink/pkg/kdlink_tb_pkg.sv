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

    function automatic bit kdlink_header_is_valid(input kdlink_header_t header);
        kdlink_header_fields_t fields;
        begin
            fields = kdlink_decode_header(header);
            kdlink_header_is_valid =
                (fields.version == `KDL_SCHEMA_VERSION) &&
                (fields.reserved == 1'b0) &&
                (fields.payload_bytes <= 7'd64);
        end
    endfunction
endpackage
