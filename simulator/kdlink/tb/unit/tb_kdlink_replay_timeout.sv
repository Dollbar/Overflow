`timescale 1ns/1ps
module tb_kdlink_replay_timeout;
    reg clk;
    reg rst_n;
    reg clear;
    reg store_start;
    reg store_valid;
    reg [607:0] store_body;
    reg store_last;
    wire store_ready;
    reg ack_valid;
    reg [11:0] ack_collective;
    reg ack_phase;
    reg [11:0] ack_sequence;
    reg nack_valid;
    reg [11:0] nack_collective;
    reg nack_phase;
    reg [11:0] nack_sequence;
    wire replay_valid;
    reg replay_ready;
    wire [607:0] replay_body;
    wire replay_last;
    wire timeout_replay;
    wire retry_exhausted;
    wire [3:0] occupancy;
    integer timeout_events;
    integer replay_flits;
    integer replay_packets;
    integer wait_cycles;
    integer slot_index;
    integer flit_index;
    integer retry_index;
    integer sweep_round;
    integer replay_packet_target;
    reg extended_exercise;

    kdlink_replay_window #(.SLOT_BITS(3), .TIMEOUT_CYCLES(16'd64)) dut (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(clear),
        .store_start_i(store_start), .store_valid_i(store_valid),
        .store_body_i(store_body), .store_last_i(store_last),
        .store_ready_o(store_ready), .ack_valid_i(ack_valid),
        .ack_collective_id_i(ack_collective), .ack_phase_i(ack_phase),
        .ack_packet_seq_i(ack_sequence), .nack_valid_i(nack_valid),
        .nack_collective_id_i(nack_collective), .nack_phase_i(nack_phase),
        .nack_packet_seq_i(nack_sequence), .replay_valid_o(replay_valid),
        .replay_ready_i(replay_ready), .replay_body_o(replay_body),
        .replay_last_o(replay_last), .timeout_replay_o(timeout_replay),
        .retry_exhausted_o(retry_exhausted), .occupancy_o(occupancy)
    );

    always #1 clk = ~clk;

    always @(posedge clk) begin
        if (rst_n && timeout_replay) timeout_events <= timeout_events + 1;
        if (rst_n && replay_valid && replay_ready) begin
            replay_flits <= replay_flits + 1;
            if (replay_body[527:525] != 3'd6 || !replay_body[531])
                $fatal(1, "timeout replay did not remap to VC6 retry traffic");
            if (!extended_exercise &&
                (replay_body[31:0] != 32'hc001cafe || !replay_last))
                $fatal(1, "timeout replay payload or packet boundary mismatch");
            if (replay_last) replay_packets <= replay_packets + 1;
        end
    end

    task automatic store_packet(input integer slot_value, input integer flit_total);
        begin
            for (flit_index = 0; flit_index < flit_total; flit_index = flit_index + 1) begin
                @(negedge clk);
                store_body = 608'd0;
                store_body[31:0] = (slot_value * 32'h9e37_79b9) ^
                    (flit_index * 32'h7f4a_7c15) ^ 32'ha5a5_5a5a;
                store_body[527:525] = slot_value[2:0];
                store_body[528] = slot_value[0];
                store_body[529] = flit_index == 0;
                store_body[530] = flit_index == flit_total-1;
                store_body[569:558] = 12'h5a5 ^ slot_value[11:0] ^
                    {slot_value[3:0], slot_value[11:4]};
                store_body[593:582] = slot_value[11:0];
                store_body[607:594] = {slot_value[6:0], flit_index[6:0]};
                store_start = flit_index == 0;
                store_valid = 1'b1;
                store_last = flit_index == flit_total-1;
                #0.01;
                if (!store_ready) $fatal(1, "replay window rejected slot=%0d flit=%0d", slot_value, flit_index);
            end
            @(negedge clk);
            store_start = 1'b0;
            store_valid = 1'b0;
            store_last = 1'b0;
        end
    endtask

    task automatic select_response(input integer slot_value);
        begin
            ack_collective = 12'h5a5 ^ slot_value[11:0] ^
                {slot_value[3:0], slot_value[11:4]};
            ack_phase = slot_value[0];
            ack_sequence = slot_value[11:0];
            nack_collective = ack_collective;
            nack_phase = ack_phase;
            nack_sequence = ack_sequence;
        end
    endtask

    task automatic nack_and_wait;
        begin
            replay_packet_target = replay_packets + 1;
            @(negedge clk); nack_valid = 1'b1; replay_ready = 1'b0;
            @(negedge clk); nack_valid = 1'b0;
            repeat (3) @(negedge clk);
            replay_ready = 1'b1;
            wait_cycles = 0;
            while ((replay_packets < replay_packet_target) && (wait_cycles < 100)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (replay_packets != replay_packet_target)
                $fatal(1, "NACK replay did not complete target=%0d got=%0d", replay_packet_target, replay_packets);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        clear = 1'b0;
        store_start = 1'b0;
        store_valid = 1'b0;
        store_body = 608'd0;
        store_last = 1'b0;
        ack_valid = 1'b0;
        ack_collective = 12'h321;
        ack_phase = 1'b1;
        ack_sequence = 12'h005;
        nack_valid = 1'b0;
        nack_collective = 12'd0;
        nack_phase = 1'b0;
        nack_sequence = 12'd0;
        replay_ready = 1'b1;
        timeout_events = 0;
        replay_flits = 0;
        replay_packets = 0;
        extended_exercise = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        @(negedge clk);
        store_body = 608'd0;
        store_body[527:525] = 3'd2;
        store_body[528] = 1'b1;
        store_body[529] = 1'b1;
        store_body[530] = 1'b1;
        store_body[569:558] = 12'h321;
        store_body[593:582] = 12'h005;
        store_body[31:0] = 32'hc001cafe;
        store_start = 1'b1;
        store_valid = 1'b1;
        store_last = 1'b1;
        if (!store_ready) $fatal(1, "replay window rejected an empty slot");
        @(negedge clk);
        store_start = 1'b0;
        store_valid = 1'b0;
        store_last = 1'b0;

        wait_cycles = 0;
        while ((replay_flits == 0) && (wait_cycles < 100)) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if (timeout_events != 1 || replay_flits != 1)
            $fatal(1, "ACK-loss timeout replay did not occur exactly once");
        @(negedge clk); ack_valid = 1'b1;
        @(negedge clk); ack_valid = 1'b0;
        repeat (4) @(posedge clk);
        if (occupancy != 0) $fatal(1, "matching ACK did not release timeout-replayed packet");
        if (retry_exhausted) $fatal(1, "single timeout unexpectedly exhausted retry budget");

        @(negedge clk); clear = 1'b1;
        @(negedge clk); clear = 1'b0;
        if (occupancy != 0 || replay_valid) $fatal(1, "replay clear did not leave an empty window");
        extended_exercise = 1'b1;
        for (slot_index = 0; slot_index < 8; slot_index = slot_index + 1)
            store_packet(slot_index, 1); // 同时占用全部槽位以覆盖 occupancy 全宽度
        if (occupancy != 8) $fatal(1, "replay window did not reach full occupancy got=%0d", occupancy);
        for (slot_index = 0; slot_index < 8; slot_index = slot_index + 1) begin
            select_response(slot_index);
            @(negedge clk); ack_valid = 1'b1;
            @(negedge clk); ack_valid = 1'b0;
        end
        repeat (2) @(posedge clk);
        if (occupancy != 0) $fatal(1, "full-window ACK sweep did not release every slot");
        for (slot_index = 0; slot_index < 8; slot_index = slot_index + 1) begin
            store_packet(slot_index, slot_index+1); // 覆盖多槽位和可变 packet flit count
            select_response(slot_index);
            nack_and_wait();
            @(negedge clk); ack_valid = 1'b1;
            @(negedge clk); ack_valid = 1'b0;
            repeat (2) @(posedge clk);
            if (occupancy != 0) $fatal(1, "NACK replay ACK release failed slot=%0d", slot_index);
        end
        for (sweep_round = 0; sweep_round < 512; sweep_round = sweep_round + 1) begin
            for (slot_index = 0; slot_index < 8; slot_index = slot_index + 1)
                store_packet((sweep_round << 3) | slot_index, 1);
            if (occupancy != 8)
                $fatal(1, "identity sweep did not fill replay window round=%0d occupancy=%0d",
                    sweep_round, occupancy);
            for (slot_index = 0; slot_index < 8; slot_index = slot_index + 1) begin
                select_response((sweep_round << 3) | slot_index);
                @(negedge clk); ack_valid = 1'b1;
                @(negedge clk); ack_valid = 1'b0;
            end
            repeat (2) @(posedge clk);
            if (occupancy != 0)
                $fatal(1, "identity sweep ACK release failed round=%0d occupancy=%0d",
                    sweep_round, occupancy);
        end
        store_packet(7, 16); // 覆盖十六 flit 上限和 flit_count 最高位
        select_response(7);
        for (retry_index = 0; retry_index < 7; retry_index = retry_index + 1)
            nack_and_wait(); // 逐次覆盖三位 retry counter 所有合法值
        @(negedge clk); nack_valid = 1'b1;
        @(posedge clk); #0.01;
        if (!retry_exhausted) $fatal(1, "eighth NACK did not report retry exhaustion");
        @(negedge clk); nack_valid = 1'b0;
        @(negedge clk); ack_valid = 1'b1;
        @(negedge clk); ack_valid = 1'b0;
        repeat (2) @(posedge clk);
        if (occupancy != 0) $fatal(1, "exhausted slot ACK release failed");
        $display("TB_KDLINK_REPLAY_TIMEOUT_PASS ack_loss=1 timeout_replay=1 vc6=1 release=1 clear=1 slots=8 max_flits=16 nack_replay=1 backpressure=1 retry_exhausted=1");
        $finish;
    end
endmodule
