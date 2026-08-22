`timescale 1ns/1ps
module tb_kdlink_baseboard32;
    localparam integer MEASURE_CYCLES = 256;
    logic clk;
    logic rst_n;
    logic [7:0] card_present;
    logic [7:0] card_reset_done;
    logic [7:0] plane_enable;
    logic [511:0] endpoint_slice_link_up;
    logic [511:0] endpoint_tx_valid;
    wire [511:0] endpoint_tx_ready;
    logic [327679:0] endpoint_tx_flit;
    wire [511:0] endpoint_rx_valid;
    logic [511:0] endpoint_rx_ready;
    wire [327679:0] endpoint_rx_flit;
    wire [7:0] card_active;
    wire [15:0] protocol_error;
    integer drive_cycle;
    integer drive_endpoint;
    integer drive_node;
    integer drive_bank;
    integer drive_plane;
    integer drive_destination;
    integer check_endpoint;
    integer check_node;
    integer check_bank;
    integer check_plane;
    integer expected_source;
    integer seen [0:511];
    integer bubbles;
    integer source_stalls;
    logic stream_started;

    kdlink_baseboard32_model u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .card_present_i(card_present), .card_reset_done_i(card_reset_done),
        .plane_enable_i(plane_enable), .endpoint_slice_link_up_i(endpoint_slice_link_up),
        .endpoint_tx_valid_i(endpoint_tx_valid), .endpoint_tx_ready_o(endpoint_tx_ready),
        .endpoint_tx_flit_i(endpoint_tx_flit), .endpoint_rx_valid_o(endpoint_rx_valid),
        .endpoint_rx_ready_i(endpoint_rx_ready), .endpoint_rx_flit_o(endpoint_rx_flit),
        .card_active_o(card_active), .protocol_error_o(protocol_error)
    );

    always #0.5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bubbles = 0;
            source_stalls = 0;
            stream_started = 1'b0;
            for (check_endpoint = 0; check_endpoint < 512; check_endpoint = check_endpoint + 1) begin
                seen[check_endpoint] = 0;
            end
        end else begin
            if (|endpoint_rx_valid) stream_started = 1'b1;
            if (|(endpoint_tx_valid & ~endpoint_tx_ready)) source_stalls = source_stalls + 1;
            if (stream_started && (|endpoint_rx_valid) && !(&endpoint_rx_valid)) bubbles = bubbles + 1;
            for (check_endpoint = 0; check_endpoint < 512; check_endpoint = check_endpoint + 1) begin
                check_node = check_endpoint / 16;
                check_bank = check_endpoint & 15;
                check_plane = check_bank >> 1;
                expected_source = (check_node - check_plane - 1 + 32) & 31;
                if (endpoint_rx_valid[check_endpoint] && (seen[check_endpoint] < MEASURE_CYCLES)) begin
                    if (endpoint_rx_flit[check_endpoint*640 +: 16] != seen[check_endpoint][15:0]) begin
                        $fatal(1, "Baseboard sequence mismatch endpoint=%0d expected=%0d observed=%0d",
                            check_endpoint, seen[check_endpoint], endpoint_rx_flit[check_endpoint*640 +: 16]);
                    end
                    if (endpoint_rx_flit[check_endpoint*640 + 16 +: 5] != expected_source[4:0] ||
                        endpoint_rx_flit[check_endpoint*640 + 21 +: 4] != check_bank[3:0]) begin
                        $fatal(1, "Baseboard source/card mapping mismatch endpoint=%0d", check_endpoint);
                    end
                    if (endpoint_rx_flit[check_endpoint*640 + 512 + 25 +: 5] != check_node[4:0] ||
                        endpoint_rx_flit[check_endpoint*640 + 512 + 30 +: 3] != check_plane[2:0]) begin
                        $fatal(1, "Baseboard route mismatch endpoint=%0d", check_endpoint);
                    end
                    seen[check_endpoint] = seen[check_endpoint] + 1;
                end
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        card_present = 8'hff;
        card_reset_done = 8'hff;
        plane_enable = 8'hff;
        endpoint_slice_link_up = {512{1'b1}};
        endpoint_tx_valid = 512'd0;
        endpoint_rx_ready = {512{1'b1}};
        for (drive_endpoint = 0; drive_endpoint < 512; drive_endpoint = drive_endpoint + 1) begin
            endpoint_tx_flit[drive_endpoint*640 +: 640] = 640'd0;
        end
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
        if (card_active != 8'hff) $fatal(1, "Not all baseboard card slots became active");

        for (drive_cycle = 0; drive_cycle < MEASURE_CYCLES; drive_cycle = drive_cycle + 1) begin
            @(negedge clk);
            endpoint_tx_valid = {512{1'b1}};
            for (drive_endpoint = 0; drive_endpoint < 512; drive_endpoint = drive_endpoint + 1) begin
                drive_node = drive_endpoint / 16;
                drive_bank = drive_endpoint & 15;
                drive_plane = drive_bank >> 1;
                drive_destination = (drive_node + drive_plane + 1) & 31;
                endpoint_tx_flit[drive_endpoint*640 +: 640] = 640'd0;
                endpoint_tx_flit[drive_endpoint*640 +: 16] = drive_cycle[15:0];
                endpoint_tx_flit[drive_endpoint*640 + 16 +: 5] = drive_node[4:0];
                endpoint_tx_flit[drive_endpoint*640 + 21 +: 4] = drive_bank[3:0];
                endpoint_tx_flit[drive_endpoint*640 + 512 + 13 +: 3] = drive_bank[2:0];
                endpoint_tx_flit[drive_endpoint*640 + 512 + 25 +: 5] = drive_destination[4:0];
                endpoint_tx_flit[drive_endpoint*640 + 512 + 30 +: 3] = drive_plane[2:0];
            end
        end
        @(negedge clk); endpoint_tx_valid = 512'd0;
        wait (seen[0] == MEASURE_CYCLES && seen[511] == MEASURE_CYCLES);
        repeat (6) @(posedge clk); #0.01;
        for (check_endpoint = 0; check_endpoint < 512; check_endpoint = check_endpoint + 1) begin
            if (seen[check_endpoint] != MEASURE_CYCLES) begin
                $fatal(1, "Baseboard final count mismatch endpoint=%0d seen=%0d",
                    check_endpoint, seen[check_endpoint]);
            end
        end
        if (bubbles != 0 || source_stalls != 0 || protocol_error != 16'd0) begin
            $fatal(1, "Baseboard nominal performance failure bubbles=%0d stalls=%0d errors=%h",
                bubbles, source_stalls, protocol_error);
        end

        @(negedge clk); card_present[3] = 1'b0;
        #0.01;
        if (card_active[3] || endpoint_tx_ready[3*64 +: 64] != 64'd0) begin
            $fatal(1, "Removed card slot still accepts traffic");
        end
        if (!endpoint_tx_ready[0]) $fatal(1, "Card removal affected unrelated slot");

        @(negedge clk); plane_enable[2] = 1'b0;
        #0.01;
        for (drive_node = 0; drive_node < 32; drive_node = drive_node + 1) begin
            if (endpoint_tx_ready[drive_node*16 + 4 +: 2] != 2'b00) begin
                $fatal(1, "Disabled plane still accepts traffic node=%0d", drive_node);
            end
        end
        if (!endpoint_tx_ready[0]) $fatal(1, "Plane failure affected unrelated plane");

        @(negedge clk); endpoint_slice_link_up[1] = 1'b0;
        #0.01;
        if (endpoint_tx_ready[1] || !endpoint_tx_ready[0]) begin
            $fatal(1, "Per-slice link isolation failed");
        end
        $display("TB_KDLINK_BASEBOARD32_PASS cards=8 npus_per_card=4 nodes=32 planes=8 slices=512 cycles=%0d flits_per_cycle=512 bubbles=0 card_isolation=1 plane_isolation=1 slice_isolation=1",
            MEASURE_CYCLES);
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "KDLink baseboard32 timeout");
    end
endmodule
