`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_global_commit_codec;
    reg [7:0] source_domain;
    reg [7:0] destination_domain;
    reg [4:0] source_node;
    reg [4:0] destination_node;
    reg [7:0] topology_epoch;
    reg [63:0] transaction_id;
    reg [1:0] status;
    wire [511:0] encoded_payload;
    reg [511:0] decoder_payload;
    wire [7:0] decoded_source_domain;
    wire [7:0] decoded_destination_domain;
    wire [4:0] decoded_source_node;
    wire [4:0] decoded_destination_node;
    wire [7:0] decoded_topology_epoch;
    wire [63:0] decoded_transaction_id;
    wire [1:0] decoded_status;
    wire decoded_valid;
    reg [95:0] header;
    wire baseline_header_valid;
    wire extended_header_valid;
    wire [7:0] baseline_header_error;
    wire [7:0] extended_header_error;
    integer status_index;
    kdlink_global_commit_codec u_encoder (
        .source_domain_i(source_domain),
        .destination_domain_i(destination_domain),
        .source_node_i(source_node),
        .destination_node_i(destination_node),
        .topology_epoch_i(topology_epoch),
        .global_transaction_id_i(transaction_id),
        .status_i(status),
        .payload_o(encoded_payload)
    );
    kdlink_global_commit_decoder u_decoder (
        .payload_i(decoder_payload),
        .source_domain_o(decoded_source_domain),
        .destination_domain_o(decoded_destination_domain),
        .source_node_o(decoded_source_node),
        .destination_node_o(decoded_destination_node),
        .topology_epoch_o(decoded_topology_epoch),
        .global_transaction_id_o(decoded_transaction_id),
        .status_o(decoded_status),
        .payload_valid_o(decoded_valid)
    );
    kdlink_header_checker #(.ALLOW_ROUTE_CONTEXT(1'b0)) u_baseline_checker (
        .header_i(header),
        .local_node_i(5'd4),
        .endpoint_check_i(1'b1),
        .valid_o(baseline_header_valid),
        .error_o(baseline_header_error)
    );
    kdlink_header_checker #(.ALLOW_ROUTE_CONTEXT(1'b1)) u_extended_checker (
        .header_i(header),
        .local_node_i(5'd4),
        .endpoint_check_i(1'b1),
        .valid_o(extended_header_valid),
        .error_o(extended_header_error)
    );
    initial begin
        source_domain = 8'ha5;
        destination_domain = 8'h5a;
        source_node = 5'd17;
        destination_node = 5'd4;
        topology_epoch = 8'hc3;
        transaction_id = 64'h0123_4567_89ab_cdef;
        status = `KDL_GLOBAL_STATUS_COMMITTED;
        decoder_payload = 512'd0;
        header = 96'd0;
        header[3:0] = `KDL_SCHEMA_VERSION;
        header[7:4] = `KDL_MESSAGE_TYPE_GLOBAL_COMMIT;
        header[15:13] = `KDL_VC_ROLE_CONTROL;
        header[17] = 1'b1;
        header[18] = 1'b1;
        header[29:25] = 5'd4;
        header[94:88] = 7'd64;
        #0.1;
        if (!extended_header_valid || baseline_header_valid || !baseline_header_error[1]) $fatal(1, "global commit header extension isolation failed");
        header[19] = 1'b1;
        header[15:13] = `KDL_VC_ROLE_REPLAY;
        #0.1;
        if (!extended_header_valid) $fatal(1, "replayed global commit header was rejected");
        header[15:13] = `KDL_VC_ROLE_CONTROL;
        #0.1;
        if (extended_header_valid || !extended_header_error[7]) $fatal(1, "replayed global commit used a non-replay VC");
        header[19] = 1'b0;
        header[15:13] = `KDL_VC_ROLE_CONTROL;
        header[18] = 1'b0;
        #0.1;
        if (extended_header_valid || !extended_header_error[7]) $fatal(1, "multi-flit global commit header was accepted");
        header[18] = 1'b1;
        for (status_index = 0; status_index < 3; status_index = status_index + 1) begin
            status = status_index[1:0];
            #0.1;
            decoder_payload = encoded_payload;
            #0.1;
            if (!decoded_valid || decoded_status != status) $fatal(1, "legal global commit status was rejected");
            if ({decoded_transaction_id, decoded_topology_epoch, decoded_destination_node, decoded_source_node, decoded_destination_domain, decoded_source_domain} != {transaction_id, topology_epoch, destination_node, source_node, destination_domain, source_domain}) $fatal(1, "global commit codec round trip failed");
        end
        status = 2'b11;
        #0.1;
        decoder_payload = encoded_payload;
        #0.1;
        if (decoded_valid) $fatal(1, "reserved global commit status was accepted");
        status = `KDL_GLOBAL_STATUS_COMMITTED;
        #0.1;
        decoder_payload = encoded_payload;
        decoder_payload[511] = 1'b1;
        #0.1;
        if (decoded_valid) $fatal(1, "nonzero global commit reserved bit was accepted");
        $display("TB_KDLINK_GLOBAL_COMMIT_CODEC_PASS");
        $finish;
    end
endmodule
