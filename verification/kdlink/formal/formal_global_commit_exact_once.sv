module formal_global_commit_exact_once;
    (* gclk *) reg clk;
    reg past_valid;
    reg [4:0] cycle_q;
    reg [2:0] delivery_count_q;
    reg [2:0] ack_count_q;
    wire rst_n;
    wire commit_valid;
    wire route_reset;
    wire commit_ready;
    wire commit_fire;
    wire deliver_valid;
    wire ack_valid;
    wire duplicate_seen;
    wire [63:0] transaction_id;
    wire [7:0] destination_domain;
    initial begin
        past_valid = 1'b0;
        cycle_q = 5'd0;
        delivery_count_q = 3'd0;
        ack_count_q = 3'd0;
    end
    assign rst_n = past_valid;
    assign commit_valid = (cycle_q >= 5'd2) && (cycle_q <= 5'd12);
    assign route_reset = cycle_q == 5'd3;
    assign transaction_id = (cycle_q < 5'd4) ? 64'h1234_5678_9abc_def0 : 64'h2234_5678_9abc_def0;
    assign destination_domain = (cycle_q < 5'd4) ? 8'd255 : 8'd254;
    assign commit_fire = commit_valid && commit_ready;
    kdlink_global_commit_tracker #(
        .REPLAY_GRACE_CYCLES(12'd8)
    ) u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .route_reset_i(route_reset),
        .commit_valid_i(commit_valid), .commit_ready_o(commit_ready),
        .source_domain_i(8'd3), .destination_domain_i(destination_domain),
        .source_node_i(5'd17), .destination_node_i(5'd4),
        .topology_epoch_i((cycle_q < 5'd4) ? 8'd7 : 8'd8),
        .global_transaction_id_i(transaction_id),
        .deliver_valid_o(deliver_valid), .deliver_transaction_id_o(),
        .global_ack_valid_o(ack_valid), .global_ack_source_domain_o(),
        .global_ack_destination_domain_o(), .global_ack_source_node_o(),
        .global_ack_destination_node_o(), .global_ack_topology_epoch_o(),
        .global_ack_transaction_id_o(), .global_ack_status_o(),
        .duplicate_seen_o(duplicate_seen)
    );
    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            cycle_q <= 5'd0;
            delivery_count_q <= 3'd0;
            ack_count_q <= 3'd0;
        end else begin
            cycle_q <= cycle_q + 5'd1;
            if (deliver_valid) delivery_count_q <= delivery_count_q + 3'd1;
            if (ack_valid) ack_count_q <= ack_count_q + 3'd1;
            assert (!deliver_valid || ack_valid);
            assert (delivery_count_q <= 3'd2);
            if ((cycle_q >= 5'd5) && (cycle_q <= 5'd11)) begin
                assert (delivery_count_q == 3'd1);
                assert (!commit_ready);
            end
            if (cycle_q == 5'd6) begin
                assert (duplicate_seen);
                assert (ack_count_q == 3'd2);
            end
            if (cycle_q == 5'd16) begin
                assert (delivery_count_q == 3'd2);
                assert (ack_count_q == 3'd3);
            end
        end
    end
endmodule
