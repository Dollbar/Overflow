`timescale 1ns/1ps
`include "kdlink_defs.vh"
module tb_kdlink_rx_commit_stress;
    reg clk;
    reg rst_n;
    reg [4:0] local_node;
    reg [7:0] link_epoch;
    reg link_reinitialize;
    reg flit_valid;
    reg crc_good;
    reg [95:0] header;
    reg [511:0] payload;
    reg [6:0] payload_bytes;
    wire flit_ready;
    wire commit_valid;
    reg commit_ready;
    wire [95:0] commit_header;
    wire [511:0] commit_payload;
    wire [6:0] commit_payload_bytes;
    wire commit_last;
    wire response_valid;
    reg response_ready;
    wire [3:0] response_type;
    wire [2:0] response_vc;
    wire [2:0] response_plane;
    wire response_phase;
    wire [4:0] response_dst_node;
    wire [11:0] response_collective_id;
    wire [11:0] response_packet_seq;
    wire [15:0] response_credit_total;
    wire [7:0] response_status;
    wire duplicate;
    wire protocol_error;
    integer packet_index;
    integer flit_index;
    integer commit_count;
    integer response_count;
    integer duplicate_count;
    integer timeout_count;
    integer response_before_collision;

    kdlink_rx_commit u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .local_node_i(local_node),
        .link_epoch_i(link_epoch), .link_reinitialize_i(link_reinitialize),
        .flit_valid_i(flit_valid), .crc_good_i(crc_good), .header_i(header),
        .payload_i(payload), .payload_bytes_i(payload_bytes),
        .flit_ready_o(flit_ready), .commit_valid_o(commit_valid),
        .commit_ready_i(commit_ready), .commit_header_o(commit_header),
        .commit_payload_o(commit_payload),
        .commit_payload_bytes_o(commit_payload_bytes), .commit_last_o(commit_last),
        .response_valid_o(response_valid), .response_ready_i(response_ready),
        .response_type_o(response_type), .response_vc_o(response_vc),
        .response_plane_o(response_plane), .response_phase_o(response_phase),
        .response_dst_node_o(response_dst_node),
        .response_collective_id_o(response_collective_id),
        .response_packet_seq_o(response_packet_seq),
        .response_credit_total_o(response_credit_total),
        .response_status_o(response_status), .duplicate_o(duplicate),
        .protocol_error_o(protocol_error)
    );

    always #0.5 clk = ~clk;

    function automatic [11:0] collective_pattern(input integer value);
        collective_pattern = value[11:0] ^ {value[5:0], ~value[5:0]};
    endfunction

    task automatic build_flit(input integer packet_value,
                              input integer flit_value,
                              input bit sop_value,
                              input bit eop_value);
        begin
            payload_bytes = {1'b0, packet_value[5:0]} + 7'd1;
            header = 96'd0;
            header[3:0] = `KDL_SCHEMA_VERSION;
            header[7:4] = `KDL_MESSAGE_TYPE_DATA;
            header[10:8] = packet_value[2:0];
            header[12:11] = packet_value[1:0];
            case (packet_value[2:0])
                3'd0, 3'd1, 3'd2, 3'd3, 3'd4: header[15:13] = packet_value[2:0];
                default: header[15:13] = {1'b0, packet_value[1:0]};
            endcase
            header[16] = packet_value[0];
            header[17] = sop_value;
            header[18] = eop_value;
            header[19] = 1'b0;
            header[24:20] = packet_value[4:0];
            header[29:25] = local_node;
            header[32:30] = packet_value[2:0];
            header[37:33] = packet_value[4:0] | 5'd1;
            header[45:38] = link_epoch;
            header[57:46] = collective_pattern(packet_value);
            header[69:58] = packet_value[11:0] ^ {~packet_value[5:0], packet_value[5:0]};
            header[81:70] = packet_value[11:0];
            header[87:82] = flit_value[5:0];
            header[94:88] = payload_bytes;
            payload = {16{(packet_value * 32'h9e37_79b9) ^
                (flit_value * 32'h7f4a_7c15) ^ 32'ha5c3_69f0}};
        end
    endtask

    task automatic send_flit(input bit crc_value);
        begin
            @(negedge clk);
            crc_good = crc_value;
            flit_valid = 1'b1;
            while (!flit_ready) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            flit_valid = 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            commit_count <= 0;
            response_count <= 0;
            duplicate_count <= 0;
        end else begin
            if (commit_valid && commit_ready) begin
                if (commit_header[29:25] != local_node ||
                    commit_header[45:38] != link_epoch ||
                    commit_payload_bytes > 7'd64)
                    $fatal(1, "commit metadata corruption count=%0d", commit_count);
                commit_count <= commit_count + 1;
            end
            if (response_valid && response_ready) begin
                if (response_type > 4'd2 ||
                    $isunknown({response_vc, response_plane, response_phase,
                        response_dst_node, response_collective_id,
                        response_packet_seq, response_credit_total,
                        response_status}))
                    $fatal(1, "response metadata corruption count=%0d", response_count);
                response_count <= response_count + 1;
            end
            if (duplicate) duplicate_count <= duplicate_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        local_node = 5'd31;
        link_epoch = 8'ha5;
        link_reinitialize = 1'b0;
        flit_valid = 1'b0;
        crc_good = 1'b1;
        header = 96'd0;
        payload = 512'd0;
        payload_bytes = 7'd0;
        commit_ready = 1'b0;
        response_ready = 1'b0;
        commit_count = 0;
        response_count = 0;
        duplicate_count = 0;
        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        for (packet_index = 0; packet_index < 64; packet_index = packet_index + 1) begin
            build_flit(packet_index, 0, 1'b1, 1'b1);
            send_flit(1'b1);
        end
        #0.01;
        if (flit_ready || commit_count != 0)
            $fatal(1, "context capacity did not backpressure at 64 packets ready=%b", flit_ready);
        @(negedge clk); commit_ready = 1'b1;
        repeat (80) @(posedge clk);
        if (commit_count != 63 || !response_valid)
            $fatal(1, "response capacity did not stall final commit commits=%0d", commit_count);
        @(negedge clk); response_ready = 1'b1;
        timeout_count = 0;
        while ((commit_count < 64 || response_count < 64) && timeout_count < 500) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (commit_count != 64 || response_count != 64)
            $fatal(1, "full queue drain mismatch commits=%0d responses=%0d",
                commit_count, response_count);

        build_flit(7, 0, 1'b1, 1'b1); // 重放已 commit 的完整 identity
        send_flit(1'b1);
        repeat (8) @(posedge clk);
        if (duplicate_count == 0 || commit_count != 64)
            $fatal(1, "history duplicate was not suppressed");

        build_flit(100, 0, 1'b1, 1'b1);
        send_flit(1'b0); // 注入 CRC 错误并生成 status 0x30 NACK
        build_flit(101, 0, 1'b1, 1'b1);
        header[3:0] = 4'hf;
        send_flit(1'b1); // 注入合法 CRC 但非法 header 并生成 status 0x33 NACK
        repeat (8) @(posedge clk);
        if (!protocol_error || commit_count != 64)
            $fatal(1, "CRC/header rejection did not preserve commit count");

        build_flit(200, 0, 1'b1, 1'b0);
        send_flit(1'b1);
        for (flit_index = 1; flit_index < 16; flit_index = flit_index + 1) begin
            build_flit(200, flit_index, 1'b0, flit_index == 15);
            send_flit(1'b1);
        end
        timeout_count = 0;
        while (commit_count < 80 && timeout_count < 200) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (commit_count != 80) $fatal(1, "16-flit commit did not drain count=%0d", commit_count);

        build_flit(300, 0, 1'b1, 1'b0);
        send_flit(1'b1);
        build_flit(300, 3, 1'b0, 1'b0);
        send_flit(1'b1); // 注入 flit sequence 跳变并进入 drain-bad
        build_flit(300, 4, 1'b0, 1'b1);
        send_flit(1'b1); // 用 EOP 结束 bad-packet drain

        @(negedge clk); link_reinitialize = 1'b1; commit_ready = 1'b0; response_ready = 1'b0;
        @(negedge clk); link_reinitialize = 1'b0;
        response_before_collision = response_count;
        build_flit(400, 0, 1'b1, 1'b1);
        send_flit(1'b1); // 暂存一个完整 packet，等待与输入 credit 事件同拍出队
        build_flit(401, 0, 1'b1, 1'b0);
        @(negedge clk); commit_ready = 1'b1; flit_valid = 1'b1;
        #0.01;
        if (u_dut.response_push_count != 2 || u_dut.response_pop || !u_dut.input_event_valid || !u_dut.output_event_valid) $fatal(1, "two-response push without pop was not formed");
        @(posedge clk);
        if (!flit_ready || !commit_valid) $fatal(1, "two-response push setup did not overlap input and output events");
        @(negedge clk); flit_valid = 1'b0; commit_ready = 1'b0;
        #0.01;
        if (u_dut.response_count_q != 2) $fatal(1, "two-response push without pop count mismatch count=%0d", u_dut.response_count_q);
        build_flit(401, 1, 1'b0, 1'b1);
        send_flit(1'b1); // 完成第二个 packet，使其成为下一次同拍出队对象
        @(negedge clk); commit_ready = 1'b1;
        #0.01;
        if (!commit_valid || commit_last) $fatal(1, "multi-flit commit did not present its non-final flit first");
        @(posedge clk);
        @(negedge clk); commit_ready = 1'b0;
        build_flit(402, 0, 1'b1, 1'b0);
        @(negedge clk); commit_ready = 1'b1; response_ready = 1'b1; flit_valid = 1'b1;
        #0.01;
        if (u_dut.response_push_count != 2 || !u_dut.response_pop || !u_dut.input_event_valid || !u_dut.output_event_valid) $fatal(1, "two-response push with pop was not formed push=%0d input=%b output=%b pop=%b contexts=%0d", u_dut.response_push_count, u_dut.input_event_valid, u_dut.output_event_valid, u_dut.response_pop, u_dut.context_count_q);
        @(posedge clk);
        if (!flit_ready || !commit_valid || !response_valid) $fatal(1, "two-response push with pop setup did not overlap all events");
        @(negedge clk); flit_valid = 1'b0; commit_ready = 1'b0; response_ready = 1'b0;
        #0.01;
        if (u_dut.response_count_q != 3) $fatal(1, "two-response push with pop count mismatch count=%0d push=%0d input=%b output=%b pop=%b contexts=%0d", u_dut.response_count_q, u_dut.response_push_count, u_dut.input_event_valid, u_dut.output_event_valid, u_dut.response_pop, u_dut.context_count_q);
        @(negedge clk); response_ready = 1'b1;
        timeout_count = 0;
        while (response_count < response_before_collision + 4 && timeout_count < 20) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (response_count != response_before_collision + 4) $fatal(1, "overlapped response events did not drain exactly four responses before=%0d after=%0d", response_before_collision, response_count);

        @(negedge clk); link_reinitialize = 1'b1; local_node = 5'd0; link_epoch = 8'h5a;
        @(negedge clk); link_reinitialize = 1'b0; commit_ready = 1'b1; response_ready = 1'b1;
        for (packet_index = 0; packet_index < 4096; packet_index = packet_index + 1) begin
            build_flit(packet_index, 0, 1'b1, 1'b1);
            header[15:13] = 3'd0; // 将全序号空间累计到同一 VC 以覆盖十六位 cumulative credit
            send_flit(1'b1);
        end
        timeout_count = 0;
        while (commit_count < 4179 && timeout_count < 500) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (commit_count != 4179 || protocol_error)
            $fatal(1, "link reinitialize recovery failed commits=%0d error=%b",
                commit_count, protocol_error);
        repeat (20) @(posedge clk);
        $display("TB_KDLINK_RX_COMMIT_STRESS_PASS contexts=64 responses=full packets=4179 sequence_space=4096 max_flits=16 duplicate=1 crc_nack=1 protocol_nack=1 overlapped_response_push=2 drain_bad=1 reinitialize=1");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "KDLink RX commit stress timeout commits=%0d responses=%0d",
            commit_count, response_count);
    end
endmodule
