`include "kdlink_defs.vh"
module formal_rx_exact_once;
    (* gclk *) reg clk;
    reg past_valid;
    reg [4:0] cycle_q;
    reg [1:0] commit_count_q;
    reg [2:0] ack_count_q;
    reg duplicate_seen_q;
    wire rst_n;
    wire flit_valid;
    reg [95:0] header_d;
    wire commit_valid;
    wire commit_last;
    wire response_valid;
    wire [3:0] response_type;
    wire duplicate;
    wire protocol_error;

    initial begin
        past_valid = 1'b0;
        cycle_q = 5'd0;
        commit_count_q = 2'd0;
        ack_count_q = 3'd0;
        duplicate_seen_q = 1'b0;
    end
    assign rst_n = past_valid;
    assign flit_valid = (cycle_q == 5'd2) || (cycle_q == 5'd8);

    always @(*) begin
        header_d = 96'd0;
        header_d[3:0] = `KDL_SCHEMA_VERSION;
        header_d[7:4] = `KDL_MESSAGE_TYPE_DATA;
        header_d[10:8] = `KDL_OPCODE_ALL_REDUCE;
        header_d[12:11] = `KDL_DTYPE_INT32;
        header_d[15:13] = (cycle_q == 5'd8) ?
            `KDL_VC_ROLE_REPLAY : `KDL_VC_ROLE_COLLECTIVE;
        header_d[17] = 1'b1;
        header_d[18] = 1'b1;
        header_d[19] = (cycle_q == 5'd8);
        header_d[24:20] = 5'd0;
        header_d[29:25] = 5'd1;
        header_d[32:30] = 3'd0;
        header_d[37:33] = 5'd30;
        header_d[45:38] = 8'h2a;
        header_d[57:46] = 12'h123;
        header_d[69:58] = 12'd0;
        header_d[81:70] = 12'd3;
        header_d[87:82] = 6'd0;
        header_d[94:88] = 7'd64;
    end

    kdlink_rx_commit #(
        .CONTEXT_BITS(1), .RESPONSE_BITS(3), .INITIAL_CREDIT_TOTAL(16'd4)
    ) u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .local_node_i(5'd1),
        .link_epoch_i(8'h2a), .link_reinitialize_i(1'b0),
        .flit_valid_i(flit_valid), .crc_good_i(1'b1), .header_i(header_d),
        .payload_i(512'h55), .payload_bytes_i(7'd64), .flit_ready_o(),
        .commit_valid_o(commit_valid), .commit_ready_i(1'b1),
        .commit_header_o(), .commit_payload_o(), .commit_payload_bytes_o(),
        .commit_last_o(commit_last), .response_valid_o(response_valid),
        .response_ready_i(1'b1), .response_type_o(response_type),
        .response_vc_o(), .response_plane_o(), .response_phase_o(),
        .response_dst_node_o(), .response_collective_id_o(),
        .response_packet_seq_o(), .response_credit_total_o(),
        .response_status_o(), .duplicate_o(duplicate),
        .protocol_error_o(protocol_error)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            cycle_q <= 5'd0;
            commit_count_q <= 2'd0;
            ack_count_q <= 3'd0;
            duplicate_seen_q <= 1'b0;
        end else begin
            cycle_q <= cycle_q + 1'b1;
            if (commit_valid && commit_last)
                commit_count_q <= commit_count_q + 1'b1;
            if (response_valid && response_type == `KDL_REVERSE_TYPE_ACK)
                ack_count_q <= ack_count_q + 1'b1;
            if (duplicate) duplicate_seen_q <= 1'b1;
            if ($past(past_valid)) begin
                assert (commit_count_q <= 2'd1);
                assert (!protocol_error);
                if (cycle_q >= 5'd14 && cycle_q <= 5'd20) begin
                    assert (commit_count_q == 2'd1);
                    assert (duplicate_seen_q);
                    assert (ack_count_q == 3'd2);
                end
            end
        end
    end
endmodule
