`include "kdlink_defs.vh"
module formal_route_pair_order;
    (* gclk *) reg clk;
    reg past_valid;
    reg [4:0] cycle_q;
    reg matching_ack_seen_q;
    reg completion_seen_q;
    reg [639:0] ingress_flit_d;
    wire rst_n;
    wire ingress_valid;
    wire ingress_ready;
    wire tx_valid;
    wire [95:0] tx_header;
    wire [511:0] tx_payload;
    wire [6:0] tx_payload_bytes;
    wire waiting_for_ack;
    wire pair_complete;
    wire protocol_error;
    wire ack_valid;
    wire [11:0] ack_collective;
    wire [11:0] ack_sequence;

    initial begin
        past_valid = 1'b0;
        cycle_q = 5'd0;
        matching_ack_seen_q = 1'b0;
        completion_seen_q = 1'b0;
    end
    assign rst_n = past_valid;
    assign ingress_valid = (cycle_q == 5'd2) || ((cycle_q >= 5'd3) && (cycle_q <= 5'd12));
    assign ack_valid = (cycle_q == 5'd6) || (cycle_q == 5'd8);
    assign ack_collective = (cycle_q == 5'd6) ? 12'h321 : 12'h620;
    assign ack_sequence = (cycle_q == 5'd6) ? 12'd77 : 12'd100;

    always @(*) begin
        ingress_flit_d = 640'd0;
        if (cycle_q == 5'd2) begin
            ingress_flit_d[515:512] = `KDL_ROUTE_SCHEMA;
            ingress_flit_d[519:516] = `KDL_MESSAGE_TYPE_ROUTE_CONTEXT;
            ingress_flit_d[527:525] = `KDL_VC_ROLE_POINT_TO_POINT;
            ingress_flit_d[528] = 1'b0;
            ingress_flit_d[529] = 1'b1;
            ingress_flit_d[530] = 1'b1;
            ingress_flit_d[536:532] = 5'd3;
            ingress_flit_d[541:537] = 5'd29;
            ingress_flit_d[544:542] = 3'd2;
            ingress_flit_d[569:558] = 12'h620;
            ingress_flit_d[593:582] = 12'd100;
            ingress_flit_d[606:600] = 7'd64;
            ingress_flit_d[7:0] = 8'd0;
            ingress_flit_d[15:8] = 8'd1;
            ingress_flit_d[20:16] = 5'd3;
            ingress_flit_d[25:21] = 5'd29;
            ingress_flit_d[33:26] = 8'd7;
            ingress_flit_d[41:34] = 8'd1;
            ingress_flit_d[44:42] = 3'd2;
            ingress_flit_d[46:45] = 2'b11;
            ingress_flit_d[54:50] = 5'd1;
            ingress_flit_d[66:55] = 12'd102;
            ingress_flit_d[130:67] = 64'h1234_5678_9abc_def0;
            ingress_flit_d[162:131] = 32'h1020_3040;
            ingress_flit_d[165:163] = `KDL_VC_ROLE_POINT_TO_POINT;
        end else begin
            ingress_flit_d[515:512] = `KDL_SCHEMA_VERSION;
            ingress_flit_d[519:516] = `KDL_MESSAGE_TYPE_DATA;
            ingress_flit_d[527:525] = `KDL_VC_ROLE_POINT_TO_POINT;
            ingress_flit_d[529] = 1'b1;
            ingress_flit_d[530] = 1'b1;
            ingress_flit_d[536:532] = 5'd3;
            ingress_flit_d[541:537] = 5'd29;
            ingress_flit_d[544:542] = 3'd2;
            ingress_flit_d[569:558] = 12'h620;
            ingress_flit_d[593:582] = 12'd102;
            ingress_flit_d[606:600] = 7'd64;
            ingress_flit_d[31:0] = 32'hcafe_3201;
        end
    end

    kdlink_route_pair_tx u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .ingress_valid_i(ingress_valid),
        .ingress_ready_o(ingress_ready), .ingress_flit_i(ingress_flit_d),
        .tx_valid_o(tx_valid), .tx_ready_i(1'b1), .tx_header_o(tx_header),
        .tx_payload_o(tx_payload), .tx_payload_bytes_o(tx_payload_bytes),
        .ack_valid_i(ack_valid), .ack_phase_i(1'b0),
        .ack_collective_id_i(ack_collective), .ack_packet_seq_i(ack_sequence),
        .waiting_for_ack_o(waiting_for_ack), .pair_complete_o(pair_complete),
        .protocol_error_o(protocol_error)
    );

    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) begin
            cycle_q <= 5'd0;
            matching_ack_seen_q <= 1'b0;
            completion_seen_q <= 1'b0;
        end else begin
            cycle_q <= cycle_q + 1'b1;
            if (ack_valid && ack_collective == 12'h620 && ack_sequence == 12'd100)
                matching_ack_seen_q <= 1'b1;
            if (pair_complete) completion_seen_q <= 1'b1;
            if ($past(past_valid)) begin
                if (waiting_for_ack) begin
                    assert (!ingress_ready);
                    assert (!tx_valid);
                end
                if (tx_valid && tx_header[3:0] == `KDL_SCHEMA_VERSION)
                    assert (matching_ack_seen_q);
                if (pair_complete) begin
                    assert (matching_ack_seen_q);
                    assert (tx_header[81:70] == 12'd102);
                end
                if (completion_seen_q) assert (matching_ack_seen_q);
            end
        end
    end
endmodule
