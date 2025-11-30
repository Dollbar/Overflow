`timescale 1ns/1ps

module tb_kdlink_v2_vip_stream;
    import kdlink_v2_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic [31:0] accepted_flits;
    logic [31:0] completed_packets;
    logic [31:0] crc_errors;
    logic [31:0] protocol_errors;
    logic [95:0] header;
    logic [511:0] payload;
    logic [639:0] flit;
    kdlink_v2_header_fields_t fields;

    kdlink_v2_stream_if stream(clk);
    kdlink_v2_stream_monitor u_monitor (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .stream(stream),
        .accepted_flits_o(accepted_flits),
        .completed_packets_o(completed_packets),
        .crc_errors_o(crc_errors),
        .protocol_errors_o(protocol_errors)
    );

    always #0.5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        stream.ready = 1'b0;
        stream.drive_idle();
        fields = '0;
        payload = 512'd0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        fields.version = `KDL2_SCHEMA_VERSION;
        fields.message_type = `KDL2_MESSAGE_TYPE_DATA;
        fields.opcode = `KDL2_OPCODE_ALL_REDUCE;
        fields.dtype = `KDL2_DTYPE_INT32;
        fields.vc = `KDL2_VC_ROLE_COLLECTIVE;
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
        header = kdlink_v2_encode_header(fields);
        flit = kdlink_v2_pack_flit(header, payload);

        fork
            stream.send(flit);
            begin
                repeat (3) @(posedge clk);
                stream.ready = 1'b1;
            end
        join
        @(posedge clk);
        #0.1;
        if (accepted_flits != 32'd1) $fatal(1, "VIP did not observe the valid-ready transfer");
        if (completed_packets != 32'd1) $fatal(1, "VIP did not decode EOP");
        if (crc_errors != 32'd0) $fatal(1, "VIP rejected a valid CRC");
        if (protocol_errors != 32'd0) $fatal(1, "VIP rejected a valid header");

        flit[639] = ~flit[639];
        stream.send(flit);
        @(posedge clk);
        #0.1;
        if (accepted_flits != 32'd2) $fatal(1, "VIP did not observe the second transfer");
        if (crc_errors != 32'd1) $fatal(1, "VIP did not detect the injected CRC error");
        if (protocol_errors != 32'd0) $fatal(1, "CRC corruption changed header classification");
        $display("TB_KDLINK_V2_VIP_STREAM_PASS");
        $finish;
    end
endmodule
