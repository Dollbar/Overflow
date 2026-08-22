`timescale 1ns/1ps
module tb_kdlink_reliable_nic8_fabric;
    localparam integer TEST_FLITS = 32;
    reg clk;
    reg rst_n;
    reg start_a;
    reg [511:0] descriptor_a;
    reg [15:0] source_valid_a;
    wire [15:0] source_ready_a;
    reg [8191:0] source_data_a;
    reg [111:0] source_bytes_a;
    reg [15:0] source_eop_a;
    wire [15:0] result_valid_b;
    wire [1535:0] result_header_b;
    wire [8191:0] result_data_b;
    wire [111:0] result_bytes_b;
    wire [15:0] forward_tx_valid_a;
    wire [10239:0] forward_tx_flit_a;
    wire [15:0] reverse_tx_valid_a;
    wire [2047:0] reverse_tx_word_a;
    wire [15:0] forward_tx_valid_b;
    wire [10239:0] forward_tx_flit_b;
    wire [15:0] reverse_tx_valid_b;
    wire [2047:0] reverse_tx_word_b;
    wire [15:0] link_up_a;
    wire [15:0] link_up_b;
    wire [7:0] reliability_error_a;
    wire [7:0] reliability_error_b;
    wire [7:0] mapping_error_a;
    wire [7:0] mapping_error_b;
    reg [15:0] forward_rx_valid_a;
    reg [10239:0] forward_rx_flit_a;
    reg [15:0] forward_rx_valid_b;
    reg [10239:0] forward_rx_flit_b;
    wire [63:0] switch_ingress_ready;
    reg [63:0] switch_ingress_valid;
    reg [40959:0] switch_ingress_flit;
    wire [63:0] switch_egress_valid;
    wire [40959:0] switch_egress_flit;
    wire [1:0] switch_protocol_error;
    integer drive_index;
    integer result_count0;
    integer result_count1;
    integer result_count [0:15];
    integer result_total;
    integer result_bank_index;
    integer physical_count;
    integer switch_count;
    integer physical_bubbles;
    integer switch_bubbles;
    reg physical_started;
    reg switch_started;
    reg [4:0] local_node_a;
    reg [4:0] peer_node_a;
    reg [4:0] local_node_b;
    reg [4:0] peer_node_b;
    reg [7:0] link_epoch;
    reg [7:0] link_enable;
    reg [15:0] configured_slice_mask;
    reg [15:0] slice_fault;
    reg [15:0] result_ready_b;
    reg [79:0] source_dst_a;
    integer soak_index;

    always #0.5 clk = ~clk;

    always @(*) begin
        switch_ingress_valid = 64'd0;
        switch_ingress_flit = 40960'd0;
        switch_ingress_valid[0] = forward_tx_valid_a[0];
        switch_ingress_valid[32] = forward_tx_valid_a[1];
        switch_ingress_flit[0 +: 640] = forward_tx_flit_a[0 +: 640];
        switch_ingress_flit[32*640 +: 640] = forward_tx_flit_a[640 +: 640];
        forward_rx_valid_a = 16'd0;
        forward_rx_flit_a = 10240'd0;
        forward_rx_valid_b = 16'd0;
        forward_rx_flit_b = 10240'd0;
        forward_rx_valid_b[0] = switch_egress_valid[1];
        forward_rx_valid_b[1] = switch_egress_valid[33];
        forward_rx_flit_b[0 +: 640] = switch_egress_flit[1*640 +: 640];
        forward_rx_flit_b[640 +: 640] = switch_egress_flit[33*640 +: 640];
        for (result_bank_index = 2; result_bank_index < 16; result_bank_index = result_bank_index + 1) begin
            forward_rx_valid_b[result_bank_index] = forward_tx_valid_a[result_bank_index];
            forward_rx_flit_b[result_bank_index*640 +: 640] = forward_tx_flit_a[result_bank_index*640 +: 640];
        end
    end

    kdlink_reliable_nic8 #(
        .NUM_RELIABLE_PLANES(8), .INITIAL_CREDITS(16'd64),
        .REPLAY_SLOT_BITS(9), .REPLAY_TIMEOUT_CYCLES(16'd2048),
        .KEEPALIVE_CYCLES(128), .LINK_TIMEOUT_CYCLES(1024)
    ) u_node_a (
        .core_clk_i(clk), .core_rst_n_i(rst_n), .phy_clk_i(clk), .phy_rst_n_i(rst_n),
        .local_node_i(local_node_a), .peer_node_i(peer_node_a), .link_epoch_i(link_epoch),
        .link_enable_i(link_enable), .configured_slice_mask_i(configured_slice_mask), .slice_fault_i(slice_fault),
        .start_i(start_a), .start_ready_o(), .descriptor_i(descriptor_a), .phase_i(1'b0),
        .finish_i(1'b0), .active_o(), .descriptor_error_o(),
        .source_valid_i(source_valid_a), .source_ready_o(source_ready_a),
        .source_data_i(source_data_a), .source_bytes_i(source_bytes_a),
        .source_eop_i(source_eop_a), .source_dst_i(source_dst_a),
        .result_valid_o(), .result_ready_i(16'hffff), .result_header_o(),
        .result_data_o(), .result_bytes_o(),
        .phy_forward_tx_valid_o(forward_tx_valid_a), .phy_forward_tx_flit_o(forward_tx_flit_a),
        .phy_forward_rx_valid_i(forward_rx_valid_a), .phy_forward_rx_flit_i(forward_rx_flit_a),
        .phy_reverse_tx_valid_o(reverse_tx_valid_a), .phy_reverse_tx_word_o(reverse_tx_word_a),
        .phy_reverse_rx_valid_i(reverse_tx_valid_b), .phy_reverse_rx_word_i(reverse_tx_word_b),
        .logical_link_up_o(link_up_a), .active_slice_mask_o(), .epoch_recovery_required_o(),
        .reliability_error_o(reliability_error_a), .mapping_error_o(mapping_error_a)
    );

    kdlink_reliable_nic8 #(
        .NUM_RELIABLE_PLANES(8), .INITIAL_CREDITS(16'd64),
        .REPLAY_SLOT_BITS(9), .REPLAY_TIMEOUT_CYCLES(16'd2048),
        .KEEPALIVE_CYCLES(128), .LINK_TIMEOUT_CYCLES(1024)
    ) u_node_b (
        .core_clk_i(clk), .core_rst_n_i(rst_n), .phy_clk_i(clk), .phy_rst_n_i(rst_n),
        .local_node_i(local_node_b), .peer_node_i(peer_node_b), .link_epoch_i(link_epoch),
        .link_enable_i(link_enable), .configured_slice_mask_i(configured_slice_mask), .slice_fault_i(slice_fault),
        .start_i(1'b0), .start_ready_o(), .descriptor_i(512'd0), .phase_i(1'b0),
        .finish_i(1'b0), .active_o(), .descriptor_error_o(),
        .source_valid_i(16'd0), .source_ready_o(), .source_data_i(8192'd0),
        .source_bytes_i(112'd0), .source_eop_i(16'd0), .source_dst_i(80'd0),
        .result_valid_o(result_valid_b), .result_ready_i(result_ready_b),
        .result_header_o(result_header_b), .result_data_o(result_data_b),
        .result_bytes_o(result_bytes_b),
        .phy_forward_tx_valid_o(forward_tx_valid_b), .phy_forward_tx_flit_o(forward_tx_flit_b),
        .phy_forward_rx_valid_i(forward_rx_valid_b), .phy_forward_rx_flit_i(forward_rx_flit_b),
        .phy_reverse_tx_valid_o(reverse_tx_valid_b), .phy_reverse_tx_word_o(reverse_tx_word_b),
        .phy_reverse_rx_valid_i(reverse_tx_valid_a), .phy_reverse_rx_word_i(reverse_tx_word_a),
        .logical_link_up_o(link_up_b), .active_slice_mask_o(), .epoch_recovery_required_o(),
        .reliability_error_o(reliability_error_b), .mapping_error_o(mapping_error_b)
    );

    kdlink_switch32 u_switch (
        .clk_i(clk), .rst_n_i(rst_n),
        .ingress_valid_i(switch_ingress_valid), .ingress_ready_o(switch_ingress_ready),
        .ingress_flit_i(switch_ingress_flit), .egress_valid_o(switch_egress_valid),
        .egress_ready_i(64'hffff_ffff_ffff_ffff), .egress_flit_o(switch_egress_flit),
        .escape_pending_o(), .protocol_error_o(switch_protocol_error)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if ((forward_tx_valid_a[0] && !switch_ingress_ready[0]) ||
                (forward_tx_valid_a[1] && !switch_ingress_ready[32]))
                $fatal(1, "switch backpressured an unpaced physical slice");
            if (|forward_tx_valid_a[1:0]) begin
                if (forward_tx_valid_a[1:0] != 2'b11) $fatal(1, "bonded physical slices lost alignment");
                if (physical_started && (physical_count < TEST_FLITS) && (forward_tx_valid_a[1:0] != 2'b11))
                    physical_bubbles <= physical_bubbles + 1;
                physical_started <= 1'b1;
                physical_count <= physical_count + 1;
            end else if (physical_started && (physical_count < TEST_FLITS)) begin
                physical_bubbles <= physical_bubbles + 1;
            end
            if (switch_egress_valid[1] || switch_egress_valid[33]) begin
                if (!(switch_egress_valid[1] && switch_egress_valid[33])) $fatal(1, "switch slices lost alignment");
                switch_started <= 1'b1;
                switch_count <= switch_count + 1;
            end else if (switch_started && (switch_count < TEST_FLITS)) begin
                switch_bubbles <= switch_bubbles + 1;
            end
            if (result_valid_b[0]) begin
                if (result_data_b[31:0] != result_count0*16) $fatal(1, "slice-zero result payload mismatch");
                if (result_header_b[29:25] != 5'd1 || result_header_b[24:20] != 5'd0)
                    $fatal(1, "slice-zero routed identity mismatch");
                if (result_header_b[37:33] != 5'd30) $fatal(1, "slice-zero hop limit was not decremented");
                if (result_bytes_b[6:0] != 7'd64) $fatal(1, "slice-zero byte count mismatch");
                result_count0 <= result_count0 + 1;
                result_count[0] <= result_count[0] + 1;
            end
            if (result_valid_b[1]) begin
                if (result_data_b[512 +: 32] != result_count1*16+1) $fatal(1, "slice-one result payload mismatch");
                if (result_header_b[96+29 -: 5] != 5'd1 || result_header_b[96+24 -: 5] != 5'd0)
                    $fatal(1, "slice-one routed identity mismatch");
                if (result_header_b[96+37 -: 5] != 5'd30) $fatal(1, "slice-one hop limit was not decremented");
                if (result_bytes_b[7 +: 7] != 7'd64) $fatal(1, "slice-one byte count mismatch");
                result_count1 <= result_count1 + 1;
                result_count[1] <= result_count[1] + 1;
            end
            for (result_bank_index = 2; result_bank_index < 16; result_bank_index = result_bank_index + 1) begin
                if (result_valid_b[result_bank_index]) begin
                    if (result_data_b[result_bank_index*512 +: 32] != result_count[result_bank_index]*16 + result_bank_index)
                        $fatal(1, "direct plane result payload mismatch bank=%0d", result_bank_index);
                    if (result_header_b[result_bank_index*96 + 29 -: 5] != 5'd1 ||
                        result_header_b[result_bank_index*96 + 24 -: 5] != 5'd0)
                        $fatal(1, "direct plane routed identity mismatch bank=%0d", result_bank_index);
                    if (result_header_b[result_bank_index*96 + 37 -: 5] != 5'd30)
                        $fatal(1, "direct plane hop limit mismatch bank=%0d", result_bank_index);
                    if (result_bytes_b[result_bank_index*7 +: 7] != 7'd64)
                        $fatal(1, "direct plane byte count mismatch bank=%0d", result_bank_index);
                    result_count[result_bank_index] <= result_count[result_bank_index] + 1;
                end
            end
            result_total <= result_total + $countones(result_valid_b);
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start_a = 1'b0;
        descriptor_a = 512'd0;
        source_valid_a = 16'd0;
        source_data_a = 8192'd0;
        source_bytes_a = {16{7'd64}};
        source_eop_a = 16'd0;
        result_count0 = 0;
        result_count1 = 0;
        result_total = 0;
        for (result_bank_index = 0; result_bank_index < 16; result_bank_index = result_bank_index + 1)
            result_count[result_bank_index] = 0;
        physical_count = 0;
        switch_count = 0;
        physical_bubbles = 0;
        switch_bubbles = 0;
        physical_started = 1'b0;
        switch_started = 1'b0;
        local_node_a = 5'd0;
        peer_node_a = 5'd1;
        local_node_b = 5'd1;
        peer_node_b = 5'd0;
        link_epoch = 8'h51;
        link_enable = 8'hff;
        configured_slice_mask = 16'hffff;
        slice_fault = 16'd0;
        result_ready_b = 16'hffff;
        source_dst_a = 80'd0;
        repeat (12) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        wait (link_up_a == 16'hffff && link_up_b == 16'hffff);
        descriptor_a[2:0] = 3'd2;
        descriptor_a[9:5] = 5'd0;
        descriptor_a[15:10] = 6'd32;
        descriptor_a[19:18] = 2'd1;
        descriptor_a[24:21] = 4'd2;
        descriptor_a[36:25] = 12'h431;
        descriptor_a[56:49] = 8'hff;
        descriptor_a[58:57] = 2'b11;
        descriptor_a[223:192] = TEST_FLITS*64*2;
        @(negedge clk); start_a = 1'b1;
        @(negedge clk); start_a = 1'b0;
        for (drive_index = 0; drive_index < TEST_FLITS; drive_index = drive_index + 1) begin
            @(negedge clk);
            if (source_ready_a != 16'hffff) $fatal(1, "reliable NIC source unexpectedly backpressured ready=%h", source_ready_a);
            source_valid_a = 16'hffff;
            source_eop_a = 16'hffff;
            source_data_a = 8192'd0;
            for (result_bank_index = 0; result_bank_index < 16; result_bank_index = result_bank_index + 1)
                source_data_a[result_bank_index*512 +: 512] = {16{(drive_index*16 + result_bank_index)}};
        end
        @(negedge clk); source_valid_a = 16'd0; source_eop_a = 16'd0;
        wait (result_total == TEST_FLITS*16);
        repeat (16) @(posedge clk);
        if (physical_count != TEST_FLITS || switch_count != TEST_FLITS ||
            physical_bubbles != 0 || switch_bubbles != 0)
            $fatal(1, "integrated throughput mismatch physical=%0d switch=%0d bubbles=%0d/%0d",
                physical_count, switch_count, physical_bubbles, switch_bubbles);
        if (|forward_tx_valid_b || |reliability_error_a || |reliability_error_b ||
            |mapping_error_a || |mapping_error_b || |switch_protocol_error)
            $fatal(1, "integrated path reported an unexpected protocol error");
        @(negedge clk); rst_n = 1'b0;
        for (soak_index = 0; soak_index < 32; soak_index = soak_index + 1) begin
            @(negedge clk);
            local_node_a = soak_index[4:0];
            peer_node_a = ~soak_index[4:0];
            local_node_b = ~soak_index[4:0];
            peer_node_b = soak_index[4:0];
            link_epoch = 8'h5a ^ soak_index[7:0];
            link_enable = 8'ha5 ^ soak_index[7:0];
            configured_slice_mask = 16'ha55a ^ {2{soak_index[7:0]}};
            slice_fault = ~configured_slice_mask;
            result_ready_b = 16'h3cc3 ^ {2{soak_index[7:0]}};
            source_valid_a = 16'h6996 ^ {2{soak_index[7:0]}};
            source_eop_a = ~source_valid_a;
            source_dst_a = {16{soak_index[4:0]}};
        end
        @(negedge clk); source_valid_a = 16'd0; source_eop_a = 16'd0;
        rst_n = 1'b1;
        repeat (8) @(posedge clk);
        for (result_bank_index = 0; result_bank_index < 16; result_bank_index = result_bank_index + 1)
            if (result_count[result_bank_index] != TEST_FLITS)
                $fatal(1, "result count mismatch bank=%0d count=%0d", result_bank_index, result_count[result_bank_index]);
        $display("TB_KDLINK_RELIABLE_NIC8_FABRIC_PASS planes=8 slices=16 flits=%0d physical_bubbles=0 switch_bubbles=0 exact_once=1", TEST_FLITS*16);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "reliable NIC8 fabric integration timeout results=%0d/%0d links=%h/%h errors=%h/%h/%h",
            result_count0, result_count1, link_up_a, link_up_b,
            reliability_error_a, reliability_error_b, switch_protocol_error);
    end
endmodule
