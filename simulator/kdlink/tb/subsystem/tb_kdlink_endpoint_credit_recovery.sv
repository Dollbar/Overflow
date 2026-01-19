`timescale 1ns/1ps
`include "collective_defs.vh"

module tb_kdlink_endpoint_credit_recovery;
    logic coll_clk;
    logic phy_clk;
    logic rst_n;
    logic credit_init_valid;
    logic [1:0] credit_init_vc;
    logic [6:0] credit_init_count;
    logic data_source_valid;
    logic [511:0] data_source_payload;
    logic [15:0] data_source_sequence;
    wire data_packet_valid;
    wire [639:0] data_packet_flit;
    logic ctrl_source_valid;
    logic [511:0] ctrl_source_payload;
    wire ctrl_packet_valid;
    wire [639:0] ctrl_packet_flit;
    wire a_tx_vc0_ready;
    wire a_tx_vc2_ready;
    wire [639:0] a_fwd_tx_flit;
    wire a_fwd_tx_valid;
    wire a_fwd_tx_ready;
    wire [95:0] a_rev_tx_word;
    wire a_rev_tx_valid;
    wire a_rev_tx_ready;
    wire [639:0] b_fwd_tx_flit;
    wire b_fwd_tx_valid;
    wire b_fwd_tx_ready;
    wire [95:0] b_rev_tx_word;
    wire b_rev_tx_valid;
    wire b_rev_tx_ready;
    wire [639:0] b_fwd_rx_flit;
    wire b_fwd_rx_valid;
    wire b_fwd_rx_ready;
    wire [95:0] a_rev_rx_word;
    wire a_rev_rx_valid;
    wire a_rev_rx_ready;
    logic fault_first_forward;
    logic inject_bad_reverse;
    logic [95:0] bad_reverse_word;
    wire b_commit_valid;
    wire [511:0] b_commit_payload;
    wire b_commit_last;
    wire b_ctrl_valid;
    wire [3:0] b_ctrl_message;
    wire [11:0] b_ctrl_collective;
    wire [31:0] b_ctrl_signature;
    wire [27:0] a_credits;
    wire a_retry_exhausted;
    wire a_replay_empty;
    wire a_credit_error;
    wire a_protocol_error;
    wire b_protocol_error;
    integer commit_count;
    integer replay_seen;
    integer zero_credit_seen;
    integer recovered_credit_seen;
    integer reverse_crc_seen;
    integer ctrl_seen;
    integer timeout_count;
    integer source_backpressure;
    integer forward_count;
    logic [511:0] committed_payload0;
    logic [511:0] committed_payload1;

    always #0.5 coll_clk = ~coll_clk;
    always #0.8 phy_clk = ~phy_clk;

    coll_packetizer u_data_packetizer (
        .clk_i(coll_clk), .rst_n_i(rst_n), .valid_i(data_source_valid),
        .payload_i(data_source_payload), .payload_bytes_i(7'd64),
        .message_type_i(`COLL_MESSAGE_TYPE_DATA),
        .opcode_i(`COLL_OPCODE_REDUCE_SCATTER), .phase_i(1'b0),
        .dtype_i(`COLL_DTYPE_INT32), .vc_i(2'd0), .src_rank_i(3'd0),
        .dst_rank_i(3'd1), .collective_id_i(12'h123), .chunk_id_i(16'd0),
        .packet_seq_i(data_source_sequence), .flit_seq_i(8'd0),
        .sop_i(1'b1), .eop_i(1'b1), .retry_i(1'b0),
        .link_epoch_i(8'h2a), .valid_o(data_packet_valid),
        .flit_o(data_packet_flit)
    );

    coll_packetizer u_ctrl_packetizer (
        .clk_i(coll_clk), .rst_n_i(rst_n), .valid_i(ctrl_source_valid),
        .payload_i(ctrl_source_payload), .payload_bytes_i(7'd16),
        .message_type_i(`COLL_MESSAGE_TYPE_COLL_SETUP),
        .opcode_i(`COLL_OPCODE_ALL_REDUCE), .phase_i(1'b0),
        .dtype_i(`COLL_DTYPE_FP16), .vc_i(2'd2), .src_rank_i(3'd0),
        .dst_rank_i(3'd1), .collective_id_i(12'h321), .chunk_id_i(16'd0),
        .packet_seq_i(16'd0), .flit_seq_i(8'd0), .sop_i(1'b1),
        .eop_i(1'b1), .retry_i(1'b0), .link_epoch_i(8'h2a),
        .valid_o(ctrl_packet_valid), .flit_o(ctrl_packet_flit)
    );

    assign b_fwd_rx_flit = fault_first_forward ?
        (a_fwd_tx_flit ^ 640'd1) : a_fwd_tx_flit;
    assign b_fwd_rx_valid = a_fwd_tx_valid;
    assign a_fwd_tx_ready = b_fwd_rx_ready;
    assign a_rev_rx_word = inject_bad_reverse ? bad_reverse_word : b_rev_tx_word;
    assign a_rev_rx_valid = inject_bad_reverse ? 1'b1 : b_rev_tx_valid;
    assign b_rev_tx_ready = inject_bad_reverse ? 1'b0 : a_rev_rx_ready;
    assign b_fwd_tx_ready = 1'b1;
    assign a_rev_tx_ready = 1'b1;

    coll_link_endpoint #(.STREAM_MODE(1'b0)) u_endpoint_a (
        .coll_clk_i(coll_clk), .coll_rst_n_i(rst_n), .phy_clk_i(phy_clk),
        .phy_rst_n_i(rst_n), .local_rank_i(2'd0), .link_epoch_i(8'h2a),
        .credit_init_valid_i(credit_init_valid),
        .credit_init_vc_i(credit_init_vc),
        .credit_init_count_i(credit_init_count),
        .tx_vc0_valid_i(data_packet_valid), .tx_vc0_ready_o(a_tx_vc0_ready),
        .tx_vc0_flit_i(data_packet_flit), .tx_vc0_packet_flits_i(5'd1),
        .tx_vc1_valid_i(1'b0), .tx_vc1_ready_o(), .tx_vc1_flit_i(640'd0),
        .tx_vc1_packet_flits_i(5'd1), .tx_vc2_valid_i(ctrl_packet_valid),
        .tx_vc2_ready_o(a_tx_vc2_ready), .tx_vc2_flit_i(ctrl_packet_flit),
        .tx_vc2_packet_flits_i(5'd1), .rx_commit_valid_o(),
        .rx_commit_ready_i(1'b1), .rx_commit_payload_o(),
        .rx_commit_bytes_o(), .rx_commit_last_o(),
        .rx_commit_collective_id_o(), .rx_commit_phase_o(),
        .rx_commit_dtype_o(), .rx_commit_chunk_id_o(),
        .rx_commit_packet_seq_o(), .rx_ctrl_valid_o(),
        .rx_ctrl_ready_i(1'b1), .rx_ctrl_message_type_o(),
        .rx_ctrl_origin_rank_o(), .rx_ctrl_collective_id_o(),
        .rx_ctrl_signature_o(), .rx_ctrl_ready_mask_o(),
        .rx_ctrl_visited_mask_o(), .rx_ctrl_generation_o(),
        .rx_ctrl_status_o(), .rx_ctrl_offending_rank_o(),
        .rx_ctrl_length_bytes_o(), .rx_ctrl_opcode_o(), .rx_ctrl_dtype_o(),
        .retry_exhausted_o(a_retry_exhausted), .replay_empty_o(a_replay_empty),
        .tx_credit_count_o(a_credits), .credit_error_o(a_credit_error),
        .protocol_error_o(a_protocol_error), .duplicate_drop_o(),
        .cdc_error_o(), .phy_fwd_tx_flit_o(a_fwd_tx_flit),
        .phy_fwd_tx_valid_o(a_fwd_tx_valid),
        .phy_fwd_tx_ready_i(a_fwd_tx_ready), .phy_fwd_rx_flit_i(640'd0),
        .phy_fwd_rx_valid_i(1'b0), .phy_fwd_rx_ready_o(),
        .phy_rev_tx_word_o(a_rev_tx_word), .phy_rev_tx_valid_o(a_rev_tx_valid),
        .phy_rev_tx_ready_i(a_rev_tx_ready), .phy_rev_rx_word_i(a_rev_rx_word),
        .phy_rev_rx_valid_i(a_rev_rx_valid), .phy_rev_rx_ready_o(a_rev_rx_ready)
    );

    coll_link_endpoint #(.STREAM_MODE(1'b0)) u_endpoint_b (
        .coll_clk_i(coll_clk), .coll_rst_n_i(rst_n), .phy_clk_i(phy_clk),
        .phy_rst_n_i(rst_n), .local_rank_i(2'd1), .link_epoch_i(8'h2a),
        .credit_init_valid_i(1'b0), .credit_init_vc_i(2'd0),
        .credit_init_count_i(7'd0), .tx_vc0_valid_i(1'b0),
        .tx_vc0_ready_o(), .tx_vc0_flit_i(640'd0),
        .tx_vc0_packet_flits_i(5'd1), .tx_vc1_valid_i(1'b0),
        .tx_vc1_ready_o(), .tx_vc1_flit_i(640'd0),
        .tx_vc1_packet_flits_i(5'd1), .tx_vc2_valid_i(1'b0),
        .tx_vc2_ready_o(), .tx_vc2_flit_i(640'd0),
        .tx_vc2_packet_flits_i(5'd1), .rx_commit_valid_o(b_commit_valid),
        .rx_commit_ready_i(1'b1), .rx_commit_payload_o(b_commit_payload),
        .rx_commit_bytes_o(), .rx_commit_last_o(b_commit_last),
        .rx_commit_collective_id_o(), .rx_commit_phase_o(),
        .rx_commit_dtype_o(), .rx_commit_chunk_id_o(),
        .rx_commit_packet_seq_o(), .rx_ctrl_valid_o(b_ctrl_valid),
        .rx_ctrl_ready_i(1'b1), .rx_ctrl_message_type_o(b_ctrl_message),
        .rx_ctrl_origin_rank_o(), .rx_ctrl_collective_id_o(b_ctrl_collective),
        .rx_ctrl_signature_o(b_ctrl_signature), .rx_ctrl_ready_mask_o(),
        .rx_ctrl_visited_mask_o(), .rx_ctrl_generation_o(),
        .rx_ctrl_status_o(), .rx_ctrl_offending_rank_o(),
        .rx_ctrl_length_bytes_o(), .rx_ctrl_opcode_o(), .rx_ctrl_dtype_o(),
        .retry_exhausted_o(), .replay_empty_o(), .tx_credit_count_o(),
        .credit_error_o(), .protocol_error_o(b_protocol_error),
        .duplicate_drop_o(), .cdc_error_o(),
        .phy_fwd_tx_flit_o(b_fwd_tx_flit),
        .phy_fwd_tx_valid_o(b_fwd_tx_valid),
        .phy_fwd_tx_ready_i(b_fwd_tx_ready),
        .phy_fwd_rx_flit_i(b_fwd_rx_flit),
        .phy_fwd_rx_valid_i(b_fwd_rx_valid),
        .phy_fwd_rx_ready_o(b_fwd_rx_ready),
        .phy_rev_tx_word_o(b_rev_tx_word), .phy_rev_tx_valid_o(b_rev_tx_valid),
        .phy_rev_tx_ready_i(b_rev_tx_ready), .phy_rev_rx_word_i(a_rev_tx_word),
        .phy_rev_rx_valid_i(a_rev_tx_valid), .phy_rev_rx_ready_o()
    );

    always @(posedge phy_clk) begin
        if (rst_n && fault_first_forward && a_fwd_tx_valid && a_fwd_tx_ready)
            fault_first_forward <= 1'b0;
        if (rst_n && a_fwd_tx_valid && a_fwd_tx_ready) begin
            forward_count <= forward_count + 1;
            if (a_fwd_tx_flit[595]) replay_seen <= replay_seen + 1;
        end
    end

    always @(posedge coll_clk) begin
        if (rst_n && a_credits[6:0] == 7'd0) zero_credit_seen <= 1;
        if (rst_n && zero_credit_seen != 0 && a_credits[6:0] != 7'd0)
            recovered_credit_seen <= 1;
        if (rst_n && a_protocol_error) reverse_crc_seen <= 1;
        if (rst_n && data_packet_valid && !a_tx_vc0_ready)
            source_backpressure <= source_backpressure + 1;
        if (rst_n && ctrl_packet_valid && !a_tx_vc2_ready)
            source_backpressure <= source_backpressure + 1;
        if (rst_n && b_commit_valid && b_commit_last) begin
            if (commit_count == 0) committed_payload0 <= b_commit_payload;
            if (commit_count == 1) committed_payload1 <= b_commit_payload;
            commit_count <= commit_count + 1;
        end
        if (rst_n && b_ctrl_valid &&
            b_ctrl_message == `COLL_MESSAGE_TYPE_COLL_SETUP &&
            b_ctrl_collective == 12'h321 &&
            b_ctrl_signature == 32'h89abcdef) ctrl_seen <= 1;
    end

    initial begin
        coll_clk = 1'b0;
        phy_clk = 1'b0;
        rst_n = 1'b0;
        credit_init_valid = 1'b0;
        credit_init_vc = 2'd0;
        credit_init_count = 7'd0;
        data_source_valid = 1'b0;
        data_source_payload = 512'd0;
        data_source_sequence = 16'd0;
        ctrl_source_valid = 1'b0;
        ctrl_source_payload = 512'd0;
        fault_first_forward = 1'b1;
        inject_bad_reverse = 1'b0;
        bad_reverse_word = 96'd0;
        commit_count = 0;
        replay_seen = 0;
        zero_credit_seen = 0;
        recovered_credit_seen = 0;
        reverse_crc_seen = 0;
        ctrl_seen = 0;
        source_backpressure = 0;
        forward_count = 0;
        committed_payload0 = 512'd0;
        committed_payload1 = 512'd0;
        repeat (8) @(posedge coll_clk);
        @(negedge coll_clk);
        rst_n = 1'b1;
        credit_init_valid = 1'b1;
        credit_init_vc = 2'd0;
        credit_init_count = 7'd1;
        @(negedge coll_clk); credit_init_vc = 2'd1; credit_init_count = 7'd64;
        @(negedge coll_clk); credit_init_vc = 2'd2; credit_init_count = 7'd64;
        @(negedge coll_clk); credit_init_vc = 2'd3; credit_init_count = 7'd64;
        @(negedge coll_clk); credit_init_valid = 1'b0;
        @(negedge phy_clk); inject_bad_reverse = 1'b1;
        repeat (3) @(negedge phy_clk);
        inject_bad_reverse = 1'b0;
        @(negedge coll_clk);
        data_source_payload = {16{32'h01020304}};
        data_source_sequence = 16'd1;
        data_source_valid = 1'b1;
        @(negedge coll_clk);
        data_source_payload = {16{32'ha5a55a5a}};
        data_source_sequence = 16'd2;
        @(negedge coll_clk);
        data_source_valid = 1'b0;
        timeout_count = 0;
        while (commit_count < 2 && timeout_count < 8000) begin
            @(posedge coll_clk);
            timeout_count = timeout_count + 1;
        end
        if (commit_count != 2 || replay_seen != 1 || zero_credit_seen == 0 ||
            recovered_credit_seen == 0 || reverse_crc_seen == 0 ||
            a_retry_exhausted || a_credit_error || source_backpressure != 0) begin
            $fatal(1, "endpoint recovery failure commit=%0d replay=%0d zero=%0d recovered=%0d reverse_crc=%0d credit_error=%b backpressure=%0d credits=%h",
                commit_count, replay_seen, zero_credit_seen, recovered_credit_seen,
                reverse_crc_seen, a_credit_error, source_backpressure, a_credits);
        end
        if (!((committed_payload0 == {16{32'h01020304}} &&
               committed_payload1 == {16{32'ha5a55a5a}}) ||
              (committed_payload1 == {16{32'h01020304}} &&
               committed_payload0 == {16{32'ha5a55a5a}})))
            $fatal(1, "endpoint committed payload mismatch");
        ctrl_source_payload = 512'd0;
        ctrl_source_payload[31:0] = 32'h89abcdef;
        ctrl_source_payload[35:32] = 4'b0001;
        ctrl_source_payload[39:36] = 4'b0001;
        ctrl_source_payload[95:64] = 32'd4096;
        ctrl_source_payload[98:96] = `COLL_OPCODE_ALL_REDUCE;
        ctrl_source_payload[100:99] = `COLL_DTYPE_FP16;
        @(negedge coll_clk); ctrl_source_valid = 1'b1;
        @(negedge coll_clk); ctrl_source_valid = 1'b0;
        timeout_count = 0;
        while (ctrl_seen == 0 && timeout_count < 4000) begin
            @(posedge coll_clk);
            timeout_count = timeout_count + 1;
        end
        if (ctrl_seen == 0 || b_protocol_error)
            $fatal(1, "endpoint control VC failure seen=%0d protocol=%b", ctrl_seen, b_protocol_error);
        $display("TB_KDLINK_ENDPOINT_CREDIT_RECOVERY_PASS credit_exhausted=1 credit_recovered=1 crc_fault=1 nack=1 replay=1 commits=2 control_vc=1 async_clocks=1 forward_flits=%0d replay_empty=%b",
            forward_count, a_replay_empty);
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "KDLink endpoint credit recovery timeout");
    end
endmodule
