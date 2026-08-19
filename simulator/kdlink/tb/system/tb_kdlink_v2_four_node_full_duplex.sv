`timescale 1ns/1ps
`include "collective_defs.vh"

module tb_kdlink_v2_four_node_full_duplex;
    localparam integer RANKS = 4;
    localparam integer PACKET_FLITS = 16;
    localparam integer PACKETS_PER_RANK = 64;
    localparam integer FLITS_PER_RANK = PACKET_FLITS * PACKETS_PER_RANK;
    logic coll_clk;
    logic phy_clk;
    logic rst_n;
    logic generator_valid;
    logic [511:0] generator_payload [0:RANKS-1];
    logic [15:0] generator_packet_seq;
    logic [7:0] generator_flit_seq;
    logic [15:0] generator_chunk_id;
    logic generator_sop;
    logic generator_eop;
    wire [RANKS-1:0] generated_valid;
    wire [639:0] generated_flit [0:RANKS-1];
    logic [639:0] flit_store [0:RANKS-1][0:FLITS_PER_RANK-1];
    integer generated_count [0:RANKS-1];
    logic run_active;
    integer source_index [0:RANKS-1];
    wire [RANKS-1:0] source_valid;
    wire [RANKS-1:0] source_ready;
    wire [639:0] source_flit [0:RANKS-1];
    logic credit_init_valid;
    logic [1:0] credit_init_vc;
    logic [6:0] credit_init_count;
    wire [639:0] fwd_tx_flit [0:RANKS-1];
    wire [RANKS-1:0] fwd_tx_valid;
    wire [RANKS-1:0] fwd_tx_ready;
    wire [639:0] fwd_rx_flit [0:RANKS-1];
    wire [RANKS-1:0] fwd_rx_valid;
    wire [RANKS-1:0] fwd_rx_ready;
    wire [95:0] rev_tx_word [0:RANKS-1];
    wire [RANKS-1:0] rev_tx_valid;
    wire [RANKS-1:0] rev_tx_ready;
    wire [95:0] rev_rx_word [0:RANKS-1];
    wire [RANKS-1:0] rev_rx_valid;
    wire [RANKS-1:0] rev_rx_ready;
    wire [RANKS-1:0] commit_valid;
    wire [511:0] commit_payload [0:RANKS-1];
    wire [6:0] commit_bytes [0:RANKS-1];
    wire [RANKS-1:0] retry_exhausted;
    wire [RANKS-1:0] credit_error;
    wire [RANKS-1:0] protocol_error;
    wire [RANKS-1:0] duplicate_drop;
    wire [RANKS-1:0] cdc_error;
    logic [RANKS-1:0] retry_exhausted_seen;
    logic [RANKS-1:0] credit_error_seen;
    logic [RANKS-1:0] protocol_error_seen;
    logic [RANKS-1:0] duplicate_drop_seen;
    logic [RANKS-1:0] cdc_error_seen;
    integer commit_count [0:RANKS-1];
    longint unsigned phy_cycle;
    longint unsigned first_tx_cycle;
    longint unsigned last_tx_cycle;
    longint unsigned first_rx_cycle;
    longint unsigned last_rx_cycle;
    integer tx_observed;
    integer rx_observed;
    integer tx_bubble_count;
    integer tx_backpressure_count;
    integer source_backpressure_count;
    longint unsigned tx_max_gap;
    integer generator_index;
    integer rank_integer;
    integer timeout_cycles;
    longint unsigned tx_span;
    longint unsigned rx_span;
    real tx_gbyte_s;
    real rx_gbyte_s;
    real aggregate_gbyte_s;
    real payload_utilization_percent;

    always #0.5 coll_clk = ~coll_clk;
    always #0.5 phy_clk = ~phy_clk;

    genvar rank;
    generate
        for (rank = 0; rank < RANKS; rank = rank + 1) begin : g_rank
            localparam [2:0] SOURCE_RANK = rank;
            localparam integer DEST = (rank + 1) % RANKS;
            coll_packetizer u_packetizer (
                .clk_i(coll_clk), .rst_n_i(rst_n), .valid_i(generator_valid),
                .payload_i(generator_payload[rank]), .payload_bytes_i(7'd64),
                .message_type_i(`COLL_MESSAGE_TYPE_DATA),
                .opcode_i(`COLL_OPCODE_ALL_REDUCE), .phase_i(1'b0),
                .dtype_i(`COLL_DTYPE_INT32), .vc_i(2'd0),
                .src_rank_i(SOURCE_RANK), .dst_rank_i(DEST[2:0]),
                .collective_id_i(12'h700), .chunk_id_i(generator_chunk_id),
                .packet_seq_i(generator_packet_seq),
                .flit_seq_i(generator_flit_seq), .sop_i(generator_sop),
                .eop_i(generator_eop), .retry_i(1'b0),
                .link_epoch_i(8'h44), .valid_o(generated_valid[rank]),
                .flit_o(generated_flit[rank])
            );

            assign source_valid[rank] = run_active &&
                (source_index[rank] < FLITS_PER_RANK);
            assign source_flit[rank] = (source_index[rank] < FLITS_PER_RANK) ?
                flit_store[rank][source_index[rank]] : 640'd0;

            coll_link_endpoint #(.STREAM_MODE(1'b1)) u_endpoint (
                .coll_clk_i(coll_clk), .coll_rst_n_i(rst_n),
                .phy_clk_i(phy_clk), .phy_rst_n_i(rst_n),
                .local_rank_i(SOURCE_RANK[1:0]), .link_epoch_i(8'h44),
                .credit_init_valid_i(credit_init_valid),
                .credit_init_vc_i(credit_init_vc),
                .credit_init_count_i(credit_init_count),
                .tx_vc0_valid_i(source_valid[rank]),
                .tx_vc0_ready_o(source_ready[rank]),
                .tx_vc0_flit_i(source_flit[rank]),
                .tx_vc0_packet_flits_i(5'd16),
                .tx_vc1_valid_i(1'b0), .tx_vc1_ready_o(),
                .tx_vc1_flit_i(640'd0), .tx_vc1_packet_flits_i(5'd1),
                .tx_vc2_valid_i(1'b0), .tx_vc2_ready_o(),
                .tx_vc2_flit_i(640'd0), .tx_vc2_packet_flits_i(5'd1),
                .rx_commit_valid_o(commit_valid[rank]),
                .rx_commit_ready_i(1'b1),
                .rx_commit_payload_o(commit_payload[rank]),
                .rx_commit_bytes_o(commit_bytes[rank]),
                .rx_commit_last_o(), .rx_commit_collective_id_o(),
                .rx_commit_phase_o(), .rx_commit_dtype_o(),
                .rx_commit_chunk_id_o(), .rx_commit_packet_seq_o(),
                .rx_ctrl_valid_o(), .rx_ctrl_ready_i(1'b1),
                .rx_ctrl_message_type_o(), .rx_ctrl_origin_rank_o(),
                .rx_ctrl_collective_id_o(), .rx_ctrl_signature_o(),
                .rx_ctrl_ready_mask_o(), .rx_ctrl_visited_mask_o(),
                .rx_ctrl_generation_o(), .rx_ctrl_status_o(),
                .rx_ctrl_offending_rank_o(), .rx_ctrl_length_bytes_o(),
                .rx_ctrl_opcode_o(), .rx_ctrl_dtype_o(),
                .retry_exhausted_o(retry_exhausted[rank]),
                .replay_empty_o(), .tx_credit_count_o(),
                .credit_error_o(credit_error[rank]),
                .protocol_error_o(protocol_error[rank]),
                .duplicate_drop_o(duplicate_drop[rank]),
                .cdc_error_o(cdc_error[rank]),
                .phy_fwd_tx_flit_o(fwd_tx_flit[rank]),
                .phy_fwd_tx_valid_o(fwd_tx_valid[rank]),
                .phy_fwd_tx_ready_i(fwd_tx_ready[rank]),
                .phy_fwd_rx_flit_i(fwd_rx_flit[rank]),
                .phy_fwd_rx_valid_i(fwd_rx_valid[rank]),
                .phy_fwd_rx_ready_o(fwd_rx_ready[rank]),
                .phy_rev_tx_word_o(rev_tx_word[rank]),
                .phy_rev_tx_valid_o(rev_tx_valid[rank]),
                .phy_rev_tx_ready_i(rev_tx_ready[rank]),
                .phy_rev_rx_word_i(rev_rx_word[rank]),
                .phy_rev_rx_valid_i(rev_rx_valid[rank]),
                .phy_rev_rx_ready_o(rev_rx_ready[rank])
            );

            assign fwd_rx_flit[DEST] = fwd_tx_flit[rank];
            assign fwd_rx_valid[DEST] = fwd_tx_valid[rank];
            assign fwd_tx_ready[rank] = fwd_rx_ready[DEST];
            assign rev_rx_word[rank] = rev_tx_word[DEST];
            assign rev_rx_valid[rank] = rev_tx_valid[DEST];
            assign rev_tx_ready[DEST] = rev_rx_ready[rank];
        end
    endgenerate

    always @(posedge coll_clk) begin
        if (rst_n) begin
            retry_exhausted_seen <= retry_exhausted_seen | retry_exhausted;
            credit_error_seen <= credit_error_seen | credit_error;
            protocol_error_seen <= protocol_error_seen | protocol_error;
            duplicate_drop_seen <= duplicate_drop_seen | duplicate_drop;
            cdc_error_seen <= cdc_error_seen | cdc_error;
            for (rank_integer = 0; rank_integer < RANKS;
                 rank_integer = rank_integer + 1) begin
                if (generated_valid[rank_integer]) begin
                    if (generated_count[rank_integer] >= FLITS_PER_RANK)
                        $fatal(1, "full-duplex generator overflow rank=%0d", rank_integer);
                    flit_store[rank_integer][generated_count[rank_integer]] <=
                        generated_flit[rank_integer];
                    generated_count[rank_integer] <=
                        generated_count[rank_integer] + 1;
                end
                if (source_valid[rank_integer] && source_ready[rank_integer])
                    source_index[rank_integer] <= source_index[rank_integer] + 1;
                if (source_valid[rank_integer] && !source_ready[rank_integer])
                    source_backpressure_count <= source_backpressure_count + 1;
                if (commit_valid[rank_integer]) begin
                    if (commit_bytes[rank_integer] != 7'd64)
                        $fatal(1, "full-duplex byte count mismatch rank=%0d", rank_integer);
                    if (commit_payload[rank_integer] !=
                        {16{32'h10000000 +
                            (((rank_integer + RANKS - 1) % RANKS) * 32'h01000000) +
                            commit_count[rank_integer]}})
                        $fatal(1, "full-duplex payload mismatch rank=%0d index=%0d",
                            rank_integer, commit_count[rank_integer]);
                    commit_count[rank_integer] <= commit_count[rank_integer] + 1;
                end
            end
        end
    end

    always @(posedge phy_clk or negedge rst_n) begin
        if (!rst_n) begin
            phy_cycle <= 0;
            first_tx_cycle <= 0;
            last_tx_cycle <= 0;
            first_rx_cycle <= 0;
            last_rx_cycle <= 0;
            tx_observed <= 0;
            rx_observed <= 0;
            tx_bubble_count <= 0;
            tx_backpressure_count <= 0;
            tx_max_gap <= 0;
        end else begin
            phy_cycle <= phy_cycle + 1;
            if (fwd_tx_valid[0] && fwd_tx_ready[0]) begin
                if (tx_observed == 0) first_tx_cycle <= phy_cycle;
                if (tx_observed != 0 && phy_cycle != last_tx_cycle + 1) begin
                    tx_bubble_count <= tx_bubble_count + 1;
                    if (phy_cycle - last_tx_cycle > tx_max_gap)
                        tx_max_gap <= phy_cycle - last_tx_cycle;
                end
                if (fwd_tx_flit[0] != flit_store[0][tx_observed])
                    $fatal(1, "full-duplex TX ordering mismatch index=%0d", tx_observed);
                last_tx_cycle <= phy_cycle;
                tx_observed <= tx_observed + 1;
            end
            if (fwd_tx_valid[0] && !fwd_tx_ready[0])
                tx_backpressure_count <= tx_backpressure_count + 1;
            if (fwd_rx_valid[0] && fwd_rx_ready[0]) begin
                if (rx_observed == 0) first_rx_cycle <= phy_cycle;
                if (fwd_rx_flit[0] != flit_store[RANKS-1][rx_observed])
                    $fatal(1, "full-duplex RX ordering mismatch index=%0d", rx_observed);
                last_rx_cycle <= phy_cycle;
                rx_observed <= rx_observed + 1;
            end
        end
    end

    initial begin
        coll_clk = 1'b0;
        phy_clk = 1'b0;
        rst_n = 1'b0;
        generator_valid = 1'b0;
        run_active = 1'b0;
        generator_packet_seq = 16'd0;
        generator_flit_seq = 8'd0;
        generator_chunk_id = 16'd0;
        generator_sop = 1'b0;
        generator_eop = 1'b0;
        credit_init_valid = 1'b0;
        credit_init_vc = 2'd0;
        credit_init_count = 7'd64;
        retry_exhausted_seen = '0;
        credit_error_seen = '0;
        protocol_error_seen = '0;
        duplicate_drop_seen = '0;
        cdc_error_seen = '0;
        source_backpressure_count = 0;
        for (rank_integer = 0; rank_integer < RANKS;
             rank_integer = rank_integer + 1) begin
            generator_payload[rank_integer] = 512'd0;
            generated_count[rank_integer] = 0;
            source_index[rank_integer] = 0;
            commit_count[rank_integer] = 0;
        end
        repeat (8) @(negedge coll_clk);
        rst_n = 1'b1;
        for (rank_integer = 0; rank_integer < RANKS;
             rank_integer = rank_integer + 1) begin
            @(negedge coll_clk);
            credit_init_valid = 1'b1;
            credit_init_vc = rank_integer[1:0];
        end
        @(negedge coll_clk);
        credit_init_valid = 1'b0;
        for (generator_index = 0; generator_index < FLITS_PER_RANK;
             generator_index = generator_index + 1) begin
            @(negedge coll_clk);
            generator_valid = 1'b1;
            generator_packet_seq = {4'd0, generator_index[15:4]};
            generator_flit_seq = {4'd0, generator_index[3:0]};
            generator_chunk_id = {14'd0, generator_index[5:4]};
            generator_sop = (generator_index[3:0] == 4'd0);
            generator_eop = (generator_index[3:0] == 4'd15);
            for (rank_integer = 0; rank_integer < RANKS;
                 rank_integer = rank_integer + 1)
                generator_payload[rank_integer] =
                    {16{32'h10000000 +
                        (rank_integer * 32'h01000000) + generator_index}};
        end
        @(negedge coll_clk);
        generator_valid = 1'b0;
        generator_sop = 1'b0;
        generator_eop = 1'b0;
        wait (generated_count[0] == FLITS_PER_RANK &&
              generated_count[1] == FLITS_PER_RANK &&
              generated_count[2] == FLITS_PER_RANK &&
              generated_count[3] == FLITS_PER_RANK);
        @(negedge coll_clk);
        run_active = 1'b1;
        timeout_cycles = 0;
        while ((commit_count[0] != FLITS_PER_RANK ||
                commit_count[1] != FLITS_PER_RANK ||
                commit_count[2] != FLITS_PER_RANK ||
                commit_count[3] != FLITS_PER_RANK) &&
               timeout_cycles < 200000) begin
            @(posedge coll_clk);
            timeout_cycles = timeout_cycles + 1;
        end
        run_active = 1'b0;
        if (timeout_cycles >= 200000)
            $fatal(1, "full-duplex completion timeout commits=%0d,%0d,%0d,%0d",
                commit_count[0], commit_count[1], commit_count[2], commit_count[3]);
        if (|retry_exhausted_seen || |credit_error_seen ||
            |protocol_error_seen || |duplicate_drop_seen || |cdc_error_seen)
            $fatal(1, "full-duplex reliability status retry=%h credit=%h protocol=%h duplicate=%h cdc=%h",
                retry_exhausted_seen, credit_error_seen, protocol_error_seen,
                duplicate_drop_seen, cdc_error_seen);
        if (tx_observed != FLITS_PER_RANK || rx_observed != FLITS_PER_RANK)
            $fatal(1, "full-duplex PHY count mismatch tx=%0d rx=%0d",
                tx_observed, rx_observed);
        if (tx_bubble_count != 0 || tx_backpressure_count != 0 ||
            source_backpressure_count != 0 || tx_max_gap != 0)
            $fatal(1, "full-duplex streaming failure bubbles=%0d phy_backpressure=%0d source_backpressure=%0d max_gap=%0d",
                tx_bubble_count, tx_backpressure_count,
                source_backpressure_count, tx_max_gap);
        tx_span = last_tx_cycle - first_tx_cycle + 1;
        rx_span = last_rx_cycle - first_rx_cycle + 1;
        tx_gbyte_s = (FLITS_PER_RANK * 64.0) / tx_span;
        rx_gbyte_s = (FLITS_PER_RANK * 64.0) / rx_span;
        aggregate_gbyte_s = tx_gbyte_s + rx_gbyte_s;
        payload_utilization_percent = tx_gbyte_s * 100.0 / 64.0;
        if (tx_span != {32'd0, FLITS_PER_RANK[31:0]} ||
            rx_span != {32'd0, FLITS_PER_RANK[31:0]} ||
            tx_gbyte_s != 64.0 || rx_gbyte_s != 64.0 ||
            aggregate_gbyte_s != 128.0)
            $fatal(1, "full-duplex bandwidth mismatch tx_span=%0d rx_span=%0d tx=%f rx=%f aggregate=%f",
                tx_span, rx_span, tx_gbyte_s, rx_gbyte_s, aggregate_gbyte_s);
        $display("TB_KDLINK_V2_FOUR_NODE_FULL_DUPLEX_PASS ranks=4 flits_per_rank=%0d packets_per_rank=%0d tx_span_cycles=%0d rx_span_cycles=%0d tx_payload_GBps=%0.6f rx_payload_GBps=%0.6f full_duplex_payload_GBps=%0.6f measured_payload_utilization_percent=%0.6f tx_bubbles=0 phy_backpressure=0 source_backpressure=0 logical_clock_GHz=1.000",
            FLITS_PER_RANK, PACKETS_PER_RANK, tx_span, rx_span,
            tx_gbyte_s, rx_gbyte_s, aggregate_gbyte_s,
            payload_utilization_percent);
        $finish;
    end

    initial begin
        #300000;
        $fatal(1, "KDLink-v2 four-node full-duplex timeout");
    end
endmodule
