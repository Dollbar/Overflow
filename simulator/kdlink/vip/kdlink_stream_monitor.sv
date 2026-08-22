module kdlink_stream_monitor (
    input logic clk_i,
    input logic rst_n_i,
    kdlink_stream_if.monitor stream,
    output logic [31:0] accepted_flits_o,
    output logic [31:0] completed_packets_o,
    output logic [31:0] crc_errors_o,
    output logic [31:0] protocol_errors_o
);
    import kdlink_tb_pkg::*;

    logic [95:0] observed_header;
    logic [511:0] observed_payload;
    logic [31:0] observed_crc;
    logic [31:0] expected_crc;

    always_comb begin
        observed_payload = stream.flit[511:0];
        observed_header = stream.flit[607:512];
        observed_crc = stream.flit[639:608];
        expected_crc = kdlink_crc32(
            observed_header,
            observed_payload,
            observed_header[94:88]
        );
    end

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            accepted_flits_o <= 32'd0;
            completed_packets_o <= 32'd0;
            crc_errors_o <= 32'd0;
            protocol_errors_o <= 32'd0;
        end else if (stream.valid && stream.ready) begin
            accepted_flits_o <= accepted_flits_o + 32'd1;
            if (observed_header[18]) completed_packets_o <= completed_packets_o + 32'd1;
            if (observed_crc != expected_crc) crc_errors_o <= crc_errors_o + 32'd1;
            if (!kdlink_header_is_valid(observed_header)) begin
                protocol_errors_o <= protocol_errors_o + 32'd1;
            end
        end
    end
endmodule
