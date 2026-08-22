`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_reliable_reset_recovery;
    localparam integer RECOVERY_PACKETS = 32;
    logic clk;
    logic rst_n;
    logic [7:0] link_epoch;
    logic a_tx_valid;
    wire a_tx_ready;
    logic [95:0] a_tx_header;
    logic [511:0] a_tx_payload;
    wire a_commit_valid;
    wire [95:0] a_commit_header;
    wire [511:0] a_commit_payload;
    wire b_commit_valid;
    wire [95:0] b_commit_header;
    wire [511:0] b_commit_payload;
    wire b_commit_last;
    wire a_forward_valid;
    wire [639:0] a_forward_flit;
    wire b_forward_valid;
    wire [639:0] b_forward_flit;
    wire a_reverse_valid;
    wire [127:0] a_reverse_word;
    wire b_reverse_valid;
    wire [127:0] b_reverse_word;
    wire [9:0] a_replay_occupancy;
    wire [9:0] b_replay_occupancy;
    wire a_link_up;
    wire b_link_up;
    wire a_retry_exhausted;
    wire b_retry_exhausted;
    wire a_credit_error;
    wire b_credit_error;
    wire a_reverse_error;
    wire b_reverse_error;
    wire a_protocol_error;
    wire b_protocol_error;
    wire a_cdc_error;
    wire b_cdc_error;
    integer test_phase;
    integer commit_count;
    integer source_index;
    integer timeout_count;
    integer pre_reset_occupancy;
    bit [RECOVERY_PACKETS-1:0] sequence_seen;

    always #0.5 clk = ~clk;

    kdlink_reliable_endpoint #(
        .INITIAL_CREDITS(64), .REPLAY_SLOT_BITS(9),
        .REPLAY_TIMEOUT_CYCLES(16'd1024)
    ) u_endpoint_a (
        .core_clk_i(clk), .core_rst_n_i(rst_n), .phy_clk_i(clk),
        .phy_rst_n_i(rst_n), .local_node_i(5'd0), .peer_node_i(5'd1),
        .local_slice_i(1'b0), .link_enable_i(1'b1),
        .tx_service_grant_i(1'b1), .reverse_service_grant_i(1'b1),
        .link_epoch_i(link_epoch), .tx_valid_i(a_tx_valid),
        .tx_ready_o(a_tx_ready), .tx_header_i(a_tx_header),
        .tx_payload_i(a_tx_payload), .tx_payload_bytes_i(7'd64),
        .rx_commit_valid_o(a_commit_valid), .rx_commit_ready_i(1'b1),
        .rx_commit_header_o(a_commit_header),
        .rx_commit_payload_o(a_commit_payload), .rx_commit_payload_bytes_o(),
        .rx_commit_last_o(), .phy_forward_tx_valid_o(a_forward_valid),
        .phy_forward_tx_flit_o(a_forward_flit),
        .phy_forward_rx_valid_i(b_forward_valid),
        .phy_forward_rx_flit_i(b_forward_flit),
        .phy_reverse_tx_valid_o(a_reverse_valid),
        .phy_reverse_tx_word_o(a_reverse_word),
        .phy_reverse_rx_valid_i(b_reverse_valid),
        .phy_reverse_rx_word_i(b_reverse_word), .tx_credit_count_o(),
        .replay_occupancy_o(a_replay_occupancy), .link_up_o(a_link_up),
        .link_state_o(), .replay_timeout_o(), .tx_service_request_o(),
        .reverse_service_request_o(), .retry_exhausted_o(a_retry_exhausted),
        .duplicate_drop_o(), .credit_error_o(a_credit_error),
        .reverse_error_o(a_reverse_error), .protocol_error_o(a_protocol_error),
        .cdc_error_o(a_cdc_error)
    );

    kdlink_reliable_endpoint #(
        .INITIAL_CREDITS(64), .REPLAY_SLOT_BITS(9),
        .REPLAY_TIMEOUT_CYCLES(16'd1024)
    ) u_endpoint_b (
        .core_clk_i(clk), .core_rst_n_i(rst_n), .phy_clk_i(clk),
        .phy_rst_n_i(rst_n), .local_node_i(5'd1), .peer_node_i(5'd0),
        .local_slice_i(1'b0), .link_enable_i(1'b1),
        .tx_service_grant_i(1'b1), .reverse_service_grant_i(1'b1),
        .link_epoch_i(link_epoch), .tx_valid_i(1'b0), .tx_ready_o(),
        .tx_header_i(96'd0), .tx_payload_i(512'd0),
        .tx_payload_bytes_i(7'd64), .rx_commit_valid_o(b_commit_valid),
        .rx_commit_ready_i(1'b1), .rx_commit_header_o(b_commit_header),
        .rx_commit_payload_o(b_commit_payload), .rx_commit_payload_bytes_o(),
        .rx_commit_last_o(b_commit_last),
        .phy_forward_tx_valid_o(b_forward_valid),
        .phy_forward_tx_flit_o(b_forward_flit),
        .phy_forward_rx_valid_i(a_forward_valid),
        .phy_forward_rx_flit_i(a_forward_flit),
        .phy_reverse_tx_valid_o(b_reverse_valid),
        .phy_reverse_tx_word_o(b_reverse_word),
        .phy_reverse_rx_valid_i(a_reverse_valid),
        .phy_reverse_rx_word_i(a_reverse_word), .tx_credit_count_o(),
        .replay_occupancy_o(b_replay_occupancy), .link_up_o(b_link_up),
        .link_state_o(), .replay_timeout_o(), .tx_service_request_o(),
        .reverse_service_request_o(), .retry_exhausted_o(b_retry_exhausted),
        .duplicate_drop_o(), .credit_error_o(b_credit_error),
        .reverse_error_o(b_reverse_error), .protocol_error_o(b_protocol_error),
        .cdc_error_o(b_cdc_error)
    );

    task automatic build_packet(input integer sequence_value);
        begin
            a_tx_header = 96'd0;
            a_tx_header[3:0] = `KDL_SCHEMA_VERSION;
            a_tx_header[7:4] = `KDL_MESSAGE_TYPE_DATA;
            a_tx_header[10:8] = `KDL_OPCODE_ALL_REDUCE;
            a_tx_header[12:11] = `KDL_DTYPE_INT32;
            a_tx_header[15:13] = `KDL_VC_ROLE_COLLECTIVE;
            a_tx_header[17] = 1'b1;
            a_tx_header[18] = 1'b1;
            a_tx_header[24:20] = 5'd0;
            a_tx_header[29:25] = 5'd1;
            a_tx_header[32:30] = 3'd0;
            a_tx_header[37:33] = 5'd31;
            a_tx_header[45:38] = link_epoch;
            a_tx_header[57:46] = 12'h700;
            a_tx_header[69:58] = sequence_value[11:0];
            a_tx_header[81:70] = sequence_value[11:0];
            a_tx_header[87:82] = 6'd0;
            a_tx_payload = 512'd0;
            a_tx_payload[31:0] = sequence_value;
            a_tx_payload[63:32] = 32'h5253_5452;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            commit_count <= 0;
            sequence_seen <= '0;
        end else if (test_phase == 2 && b_commit_valid && b_commit_last) begin
            if (b_commit_header[37:33] != 5'd30 ||
                b_commit_header[81:70] >= 12'd32 ||
                b_commit_payload[31:0] != {20'd0, b_commit_header[81:70]} ||
                b_commit_payload[63:32] != 32'h5253_5452)
                $fatal(1, "post-reset payload or header mismatch sequence=%0d",
                    b_commit_header[81:70]);
            if (sequence_seen[b_commit_header[74:70]])
                $fatal(1, "post-reset duplicate commit sequence=%0d",
                    b_commit_header[81:70]);
            sequence_seen[b_commit_header[74:70]] <= 1'b1;
            commit_count <= commit_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        link_epoch = 8'h30;
        a_tx_valid = 1'b0;
        a_tx_header = 96'd0;
        a_tx_payload = 512'd0;
        test_phase = 0;
        commit_count = 0;
        sequence_seen = '0;
        repeat (8) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait (a_link_up && b_link_up);

        test_phase = 1;
        for (source_index = 0; source_index < 16; source_index = source_index + 1) begin
            @(negedge clk);
            build_packet(source_index);
            a_tx_valid = 1'b1;
            if (!a_tx_ready) $fatal(1, "pre-reset source backpressured");
        end
        @(negedge clk); a_tx_valid = 1'b0;
        if (a_replay_occupancy == 0)
            $fatal(1, "reset was not applied with packets in flight");
        pre_reset_occupancy = {22'd0, a_replay_occupancy};
        rst_n = 1'b0;
        link_epoch = 8'h31;
        repeat (8) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait (a_link_up && b_link_up);

        test_phase = 2;
        for (source_index = 0; source_index < RECOVERY_PACKETS;
             source_index = source_index + 1) begin
            @(negedge clk);
            build_packet(source_index);
            a_tx_valid = 1'b1;
            if (!a_tx_ready) $fatal(1, "post-reset source backpressured");
        end
        @(negedge clk); a_tx_valid = 1'b0;
        timeout_count = 0;
        while ((commit_count < RECOVERY_PACKETS || a_replay_occupancy != 0) &&
               timeout_count < 5000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (commit_count != RECOVERY_PACKETS || a_replay_occupancy != 0 ||
            b_replay_occupancy != 0 || a_retry_exhausted || b_retry_exhausted ||
            a_credit_error || b_credit_error || a_reverse_error || b_reverse_error ||
            a_protocol_error || b_protocol_error || a_cdc_error || b_cdc_error)
            $fatal(1, "reset recovery failure commits=%0d occupancy=%0d/%0d",
                commit_count, a_replay_occupancy, b_replay_occupancy);
        $display("TB_KDLINK_RELIABLE_RESET_RECOVERY_PASS in_flight_before_reset=%0d new_epoch=%0h post_reset_packets=%0d exact_once=1",
            pre_reset_occupancy, link_epoch, RECOVERY_PACKETS);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "KDLink reliable reset recovery timeout");
    end
endmodule
