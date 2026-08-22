module formal_replay_progress;
    (* gclk *) reg clk;
    reg past_valid;
    reg [4:0] cycle_q;
    reg replay_seen_q;
    wire rst_n;
    wire store_valid;
    wire ack_valid;
    reg [607:0] store_body_d;
    wire store_ready;
    wire replay_valid;
    wire [607:0] replay_body;
    wire replay_last;
    wire timeout_replay;
    wire retry_exhausted;
    wire [1:0] occupancy;

    initial begin
        past_valid = 1'b0;
        cycle_q = 5'd0;
        replay_seen_q = 1'b0;
    end
    assign rst_n = past_valid;
    assign store_valid = cycle_q == 5'd2;
    assign ack_valid = cycle_q == 5'd14;

    always @(*) begin
        store_body_d = 608'd0;
        store_body_d[515:512] = 4'd2;
        store_body_d[519:516] = 4'd0;
        store_body_d[522:520] = 3'd2;
        store_body_d[527:525] = 3'd2;
        store_body_d[529] = 1'b1;
        store_body_d[530] = 1'b1;
        store_body_d[536:532] = 5'd0;
        store_body_d[541:537] = 5'd1;
        store_body_d[549:545] = 5'd31;
        store_body_d[557:550] = 8'h2a;
        store_body_d[569:558] = 12'h321;
        store_body_d[593:582] = 12'd0;
        store_body_d[607:600] = 8'd64;
        store_body_d[31:0] = 32'h1234_5678;
    end

    kdlink_replay_window #(.SLOT_BITS(1), .TIMEOUT_CYCLES(16'd3)) u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(1'b0),
        .store_start_i(store_valid), .store_valid_i(store_valid),
        .store_body_i(store_body_d), .store_last_i(store_valid),
        .store_ready_o(store_ready), .ack_valid_i(ack_valid),
        .ack_collective_id_i(12'h321), .ack_phase_i(1'b0),
        .ack_packet_seq_i(12'd0), .nack_valid_i(1'b0),
        .nack_collective_id_i(12'd0), .nack_phase_i(1'b0),
        .nack_packet_seq_i(12'd0), .replay_valid_o(replay_valid),
        .replay_ready_i(1'b1), .replay_body_o(replay_body),
        .replay_last_o(replay_last), .timeout_replay_o(timeout_replay),
        .retry_exhausted_o(retry_exhausted), .occupancy_o(occupancy)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            cycle_q <= 5'd0;
            replay_seen_q <= 1'b0;
        end else begin
            cycle_q <= cycle_q + 1'b1;
            if (replay_valid && replay_last) replay_seen_q <= 1'b1;
            if ($past(past_valid)) begin
                assert (occupancy <= 2'd1);
                assert (!retry_exhausted);
                if (replay_valid) begin
                    assert (replay_body[531]);
                    assert (replay_body[527:525] == 3'd6);
                    assert (replay_body[511:0] == store_body_d[511:0]);
                end
                if (cycle_q >= 5'd12) assert (replay_seen_q);
                if (cycle_q >= 5'd16) assert (occupancy == 2'd0);
            end
        end
    end
endmodule
