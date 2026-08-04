`timescale 1ns/1ps
`default_nettype none

module tb_npu_noc_mesh;

    import npu_noc_tb_pkg::*;

    localparam int unsigned PODS = npu_noc_pkg::NPU_NOC_PODS;
    localparam int unsigned LANES = npu_noc_pkg::NPU_NOC_DATA_LANES;
    localparam int unsigned VCS = npu_noc_pkg::NPU_NOC_DATA_VCS;
    localparam int unsigned PORTS = npu_noc_pkg::NPU_NOC_PORTS;
    localparam int unsigned RANDOM_FLOWS = 128;

    logic clk;
    logic rst;
    logic clear;
    logic quiesce;
    logic [PODS-1:0] control_tx_valid;
    logic [PODS-1:0] control_tx_ready;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] control_tx_flit;
    logic [PODS-1:0] control_rx_valid;
    logic [PODS-1:0] control_rx_ready;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] control_rx_flit;
    logic [PODS*LANES-1:0] data_tx_valid;
    logic [PODS*LANES-1:0] data_tx_ready;
    logic [PODS*LANES*DATA_FLIT_WIDTH-1:0] data_tx_flit;
    logic [PODS*LANES-1:0] data_rx_valid;
    logic [PODS*LANES-1:0] data_rx_ready;
    logic [PODS*LANES*DATA_FLIT_WIDTH-1:0] data_rx_flit;
    logic busy;
    logic quiesced;
    logic protocol_error;
    logic [PODS-1:0] control_router_busy;
    logic [LANES*PODS-1:0] data_router_busy;
    logic [PODS-1:0] control_router_quiesced;
    logic [LANES*PODS-1:0] data_router_quiesced;
    logic [PODS-1:0] control_router_protocol_error;
    logic [LANES*PODS-1:0] data_router_protocol_error;
    logic [PODS*PORTS*64-1:0] control_accepted_flits;
    logic [PODS*PORTS*64-1:0] control_transmitted_flits;
    logic [PODS*PORTS*64-1:0] control_blocked_cycles;
    logic [PODS*PORTS*64-1:0] control_accepted_packets;
    logic [PODS*PORTS*64-1:0] control_transmitted_packets;
    logic [PODS*PORTS*64-1:0] control_maximum_wait_cycles;
    logic [PODS*PORTS*64-1:0] control_credit_low_watermark;
    logic [PODS*PORTS*64-1:0] control_invalid_route_events;
    logic [LANES*PODS*PORTS*64-1:0] data_accepted_flits;
    logic [LANES*PODS*PORTS*64-1:0] data_transmitted_flits;
    logic [LANES*PODS*PORTS*64-1:0] data_blocked_cycles;
    logic [LANES*PODS*PORTS*64-1:0] data_accepted_packets;
    logic [LANES*PODS*PORTS*64-1:0] data_transmitted_packets;
    logic [LANES*PODS*PORTS*64-1:0] data_maximum_wait_cycles;
    logic [LANES*PODS*PORTS*64-1:0] data_credit_low_watermark;
    logic [LANES*PODS*PORTS*64-1:0] data_invalid_route_events;
    integer checked_control_flits;
    integer checked_data_flits;
    logic [PODS*PODS-1:0] control_pair_seen;
    logic [VCS*LANES*PODS*PODS-1:0] data_pair_vc_seen;
    logic [63:0] cycle_count;

    npu_noc_mesh dut (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(clear),
        .quiesce_i(quiesce),
        .pod_control_tx_valid_i(control_tx_valid),
        .pod_control_tx_ready_o(control_tx_ready),
        .pod_control_tx_flit_i(control_tx_flit),
        .pod_control_rx_valid_o(control_rx_valid),
        .pod_control_rx_ready_i(control_rx_ready),
        .pod_control_rx_flit_o(control_rx_flit),
        .pod_data_tx_valid_i(data_tx_valid),
        .pod_data_tx_ready_o(data_tx_ready),
        .pod_data_tx_flit_i(data_tx_flit),
        .pod_data_rx_valid_o(data_rx_valid),
        .pod_data_rx_ready_i(data_rx_ready),
        .pod_data_rx_flit_o(data_rx_flit),
        .busy_o(busy),
        .quiesced_o(quiesced),
        .protocol_error_o(protocol_error),
        .control_router_busy_o(control_router_busy),
        .data_router_busy_o(data_router_busy),
        .control_router_quiesced_o(control_router_quiesced),
        .data_router_quiesced_o(data_router_quiesced),
        .control_router_protocol_error_o(control_router_protocol_error),
        .data_router_protocol_error_o(data_router_protocol_error),
        .control_accepted_flits_o(control_accepted_flits),
        .control_transmitted_flits_o(control_transmitted_flits),
        .control_blocked_cycles_o(control_blocked_cycles),
        .control_accepted_packets_o(control_accepted_packets),
        .control_transmitted_packets_o(control_transmitted_packets),
        .control_maximum_wait_cycles_o(control_maximum_wait_cycles),
        .control_credit_low_watermark_o(control_credit_low_watermark),
        .control_invalid_route_events_o(control_invalid_route_events),
        .data_accepted_flits_o(data_accepted_flits),
        .data_transmitted_flits_o(data_transmitted_flits),
        .data_blocked_cycles_o(data_blocked_cycles),
        .data_accepted_packets_o(data_accepted_packets),
        .data_transmitted_packets_o(data_transmitted_packets),
        .data_maximum_wait_cycles_o(data_maximum_wait_cycles),
        .data_credit_low_watermark_o(data_credit_low_watermark),
        .data_invalid_route_events_o(data_invalid_route_events)
    );

    always #0.5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= '0;
        end else begin
            cycle_count <= cycle_count + 1'b1;
        end
    end

    task automatic send_control_flit(
        input int unsigned source,
        input logic [CONTROL_FLIT_WIDTH-1:0] flit
    );
        @(negedge clk);
        control_tx_flit[source*CONTROL_FLIT_WIDTH +:
                        CONTROL_FLIT_WIDTH] = flit;
        control_tx_valid[source] = 1'b1;
        do @(posedge clk); while (!control_tx_ready[source]);
        @(negedge clk);
        control_tx_valid[source] = 1'b0;
    endtask

    task automatic expect_control_flit(
        input int unsigned destination,
        input logic [CONTROL_FLIT_WIDTH-1:0] expected
    );
        integer timeout;
        timeout = 0;
        do begin
            @(posedge clk);
            timeout = timeout + 1;
        end while (!control_rx_valid[destination] && timeout < 100);
        if (!control_rx_valid[destination] ||
            control_rx_flit[destination*CONTROL_FLIT_WIDTH +:
                            CONTROL_FLIT_WIDTH] !== expected) begin
            $fatal(1, "control delivery mismatch destination=%0d",
                   destination);
        end
        checked_control_flits = checked_control_flits + 1;
    endtask

    task automatic send_data_flit(
        input int unsigned source,
        input int unsigned lane,
        input logic [DATA_FLIT_WIDTH-1:0] flit
    );
        integer endpoint;
        endpoint = source*LANES + lane;
        @(negedge clk);
        data_tx_flit[endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] = flit;
        data_tx_valid[endpoint] = 1'b1;
        do @(posedge clk); while (!data_tx_ready[endpoint]);
        @(negedge clk);
        data_tx_valid[endpoint] = 1'b0;
    endtask

    task automatic expect_data_flit(
        input int unsigned destination,
        input int unsigned lane,
        input logic [DATA_FLIT_WIDTH-1:0] expected
    );
        integer endpoint;
        integer timeout;
        endpoint = destination*LANES + lane;
        timeout = 0;
        do begin
            @(posedge clk);
            timeout = timeout + 1;
        end while (!data_rx_valid[endpoint] && timeout < 150);
        if (!data_rx_valid[endpoint] ||
            data_rx_flit[endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] !==
            expected) begin
            $fatal(1, "data delivery mismatch destination=%0d lane=%0d",
                   destination, lane);
        end
        checked_data_flits = checked_data_flits + 1;
    endtask

    task automatic run_control_pair(
        input int unsigned source,
        input int unsigned destination
    );
        logic [CONTROL_FLIT_WIDTH-1:0] flit;
        flit = make_control_flit(1'b1, 1'b1, 3'(source), 3'(destination),
            2'((source + destination) % 4),
            {64'(source), 32'(destination), 32'hc011_c011});
        send_control_flit(source, flit);
        expect_control_flit(destination, flit);
        control_pair_seen[source*PODS + destination] = 1'b1;
    endtask

    task automatic run_data_pair(
        input int unsigned source,
        input int unsigned destination,
        input int unsigned lane,
        input int unsigned vc
    );
        logic [DATA_FLIT_WIDTH-1:0] flit;
        logic [7:0] marker;
        marker = 8'(vc*8'h40 + lane*8'h20 + source*8 + destination);
        flit = make_data_flit(1'b1, 1'b1, 3'(source), 3'(destination),
            2'(vc), marker);
        send_data_flit(source, lane, flit);
        expect_data_flit(destination, lane, flit);
        data_pair_vc_seen[
            ((vc*LANES + lane)*PODS + source)*PODS + destination] = 1'b1;
    endtask

    task automatic run_transpose_pattern;
        logic [DATA_FLIT_WIDTH-1:0] flit;
        integer destination;
        for (integer source = 0; source < PODS; source++) begin
            destination = source ^ (PODS - 1);
            flit = make_data_flit(1'b1, 1'b1, 3'(source),
                3'(destination), 2'(source % VCS), 8'he0 + 8'(source));
            send_data_flit(source, source % LANES, flit);
            expect_data_flit(destination, source % LANES, flit);
        end
    endtask

    task automatic run_uniform_random(
        input logic [31:0] seed,
        input int unsigned flow_count
    );
        logic [31:0] state;
        logic [DATA_FLIT_WIDTH-1:0] flit;
        logic [2:0] source;
        logic [2:0] destination;
        logic lane;
        logic [1:0] vc;
        logic [3:0] endpoint;
        state = (seed == 0) ? 32'h1 : seed;
        for (integer flow = 0; flow < flow_count; flow++) begin
            state = state ^ (state << 13);
            state = state ^ (state >> 17);
            state = state ^ (state << 5);
            source = state[2:0];
            destination = 3'(int'($unsigned(state[5:3])) % (PODS - 1));
            if (destination >= source) begin
                destination = destination + 1;
            end
            lane = state[6];
            vc = state[8:7];
            endpoint = {destination, lane};
            flit = make_data_flit(1'b1, 1'b1, 3'(source),
                3'(destination), 2'(vc), 8'(flow));
            if (state[9]) begin
                @(negedge clk);
                data_rx_ready[endpoint] = 1'b0;
            end
            send_data_flit(int'($unsigned(source)),
                           int'($unsigned(lane)), flit);
            if (state[9]) begin
                repeat (1 + int'($unsigned(state[11:10]))) @(posedge clk);
                @(negedge clk);
                data_rx_ready[endpoint] = 1'b1;
            end
            expect_data_flit(int'($unsigned(destination)),
                             int'($unsigned(lane)), flit);
        end
    endtask

    task automatic send_data_packet(
        input int unsigned source,
        input logic [2:0] destination,
        input int unsigned lane,
        input logic [1:0] traffic_class,
        input int unsigned length,
        input logic [7:0] marker_base
    );
        for (integer index = 0; index < length; index++) begin
            send_data_flit(source, lane, make_data_flit(
                index == 0, index == length-1, 3'(source), destination,
                traffic_class, marker_base + 8'(index)));
        end
    endtask

    task automatic expect_data_packet(
        input logic [2:0] source,
        input int unsigned destination,
        input int unsigned lane,
        input logic [1:0] traffic_class,
        input int unsigned length,
        input logic [7:0] marker_base
    );
        for (integer index = 0; index < length; index++) begin
            expect_data_flit(destination, lane, make_data_flit(
                index == 0, index == length-1, source, 3'(destination),
                traffic_class, marker_base + 8'(index)));
        end
    endtask

    // Keep valid asserted across adjacent transfers.  The regular directed
    // source task intentionally inserts an idle cycle between calls, so this
    // driver is used for the throughput contract checks below.
    task automatic send_continuous_data_packet(
        input int unsigned source,
        input logic [2:0] destination,
        input int unsigned lane,
        input logic [1:0] traffic_class,
        input int unsigned length,
        input logic [7:0] marker_base
    );
        integer endpoint;
        endpoint = source*LANES + lane;
        @(negedge clk);
        data_tx_valid[endpoint] = 1'b1;
        data_tx_flit[endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
            make_data_flit(1'b1, length == 1, 3'(source), destination,
                           traffic_class, marker_base);
        for (integer index = 0; index < length; index++) begin
            do @(posedge clk); while (!data_tx_ready[endpoint]);
            @(negedge clk);
            if (index == length-1) begin
                data_tx_valid[endpoint] = 1'b0;
            end else begin
                data_tx_flit[
                    endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
                    make_data_flit(1'b0, index == length-2,
                                   3'(source), destination, traffic_class,
                                   marker_base + 8'(index + 1));
            end
        end
    endtask

    task automatic expect_timed_data_packet(
        input logic [2:0] source,
        input int unsigned destination,
        input int unsigned lane,
        input logic [1:0] traffic_class,
        input int unsigned length,
        input logic [7:0] marker_base,
        output logic [63:0] first_cycle,
        output logic [63:0] last_cycle
    );
        integer endpoint;
        integer timeout;
        endpoint = destination*LANES + lane;
        first_cycle = '0;
        last_cycle = '0;
        for (integer index = 0; index < length; index++) begin
            timeout = 0;
            do begin
                @(posedge clk);
                timeout = timeout + 1;
            end while (!data_rx_valid[endpoint] && timeout < 250);
            if (!data_rx_valid[endpoint] ||
                data_rx_flit[endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] !==
                make_data_flit(index == 0, index == length-1, source,
                    3'(destination), traffic_class,
                    marker_base + 8'(index))) begin
                $fatal(1,
                    "timed data mismatch destination=%0d lane=%0d index=%0d",
                    destination, lane, index);
            end
            if (index == 0) begin
                first_cycle = cycle_count;
            end
            last_cycle = cycle_count;
            checked_data_flits = checked_data_flits + 1;
        end
    endtask

    task automatic expect_incast(
        input int unsigned destination,
        input int unsigned lane
    );
        integer endpoint;
        integer timeout;
        logic [PODS-1:0] source_seen;
        logic [DATA_FLIT_WIDTH-1:0] observed;
        logic [2:0] source;
        endpoint = destination*LANES + lane;
        source_seen = '0;
        source_seen[destination] = 1'b1;
        for (integer index = 0; index < PODS-1; index++) begin
            timeout = 0;
            do begin
                @(posedge clk);
                timeout = timeout + 1;
            end while (!data_rx_valid[endpoint] && timeout < 300);
            observed = data_rx_flit[
                endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH];
            source = data_source(observed);
            if (!data_rx_valid[endpoint] || source == 3'(destination) ||
                source_seen[source] || observed !== make_data_flit(
                    1'b1, 1'b1, source, 3'(destination),
                    2'(source % 4), 8'hd0 + 8'(source))) begin
                $fatal(1, "incast mismatch source=%0d seen=%h",
                       source, source_seen);
            end
            source_seen[source] = 1'b1;
            checked_data_flits = checked_data_flits + 1;
        end
        if (source_seen !== '1) begin
            $fatal(1, "incast failed to deliver every source: %h",
                   source_seen);
        end
    endtask

    initial begin
        logic [DATA_FLIT_WIDTH-1:0] stalled_flit;
        logic [DATA_FLIT_WIDTH-1:0] backpressure_flit;
        integer stalled_endpoint;
        logic [63:0] long_first;
        logic [63:0] long_last;
        logic [63:0] bisect_first_0;
        logic [63:0] bisect_first_1;
        logic [63:0] bisect_first_2;
        logic [63:0] bisect_first_3;
        logic [63:0] bisect_last_0;
        logic [63:0] bisect_last_1;
        logic [63:0] bisect_last_2;
        logic [63:0] bisect_last_3;
        logic [63:0] bisect_first;
        logic [63:0] bisect_last;
        logic [63:0] bisect_active_cycles;
        integer random_seed;
        clk = 1'b0;
        rst = 1'b1;
        clear = 1'b0;
        quiesce = 1'b0;
        control_tx_valid = '0;
        /* verilator lint_off WIDTHCONCAT */
        control_tx_flit = '0;
        data_tx_flit = '0;
        /* verilator lint_on WIDTHCONCAT */
        control_rx_ready = '1;
        data_tx_valid = '0;
        data_rx_ready = '1;
        checked_control_flits = 0;
        checked_data_flits = 0;
        control_pair_seen = '0;
        data_pair_vc_seen = '0;
        if (!$value$plusargs("NOC_SEED=%d", random_seed)) begin
            random_seed = 32'h004e_4f43;
        end

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        if (busy || quiesced || protocol_error ||
            (|control_router_protocol_error) ||
            (|data_router_protocol_error)) begin
            $fatal(1, "Mesh reset state mismatch");
        end

        // Every ordered source/destination pair, including local ejection.
        for (integer source = 0; source < PODS; source++) begin
            for (integer destination = 0; destination < PODS;
                 destination++) begin
                run_control_pair(source, destination);
                for (integer lane = 0; lane < LANES; lane++) begin
                    for (integer vc = 0; vc < VCS; vc++) begin
                        run_data_pair(source, destination, lane, vc);
                    end
                end
            end
        end

        // Packet-lock and maximum-length obligations run concurrently with
        // their scoreboard so no endpoint transfer can be missed.
        fork
            send_data_packet(0, 7, 0, 2'd1, 2, 8'h20);
            expect_data_packet(0, 7, 0, 2'd1, 2, 8'h20);
        join

        // Exercise the fixed complement transpose at RTL and then execute a
        // reproducible non-local uniform-random stream with endpoint stalls.
        run_transpose_pattern();
        run_uniform_random(32'(random_seed), RANDOM_FLOWS);
        fork
            send_data_packet(3, 4, 1, 2'd3, 31, 8'h40);
            expect_data_packet(3, 4, 1, 2'd3, 31, 8'h40);
        join
        fork
            send_data_packet(0, 7, 0, 2'd2, 32, 8'h80);
            expect_data_packet(0, 7, 0, 2'd2, 32, 8'h80);
        join

        // A maximum-size packet must sustain at least 95% of one lane after
        // the first delivered flit.  The interval test excludes only route
        // acquisition latency and includes every payload transfer gap.
        fork
            send_continuous_data_packet(0, 7, 0, 2'd0, 32, 8'ha0);
            expect_timed_data_packet(0, 7, 0, 2'd0, 32, 8'ha0,
                                     long_first, long_last);
        join
        if (((32-1)*100) < ((long_last-long_first)*95)) begin
            $fatal(1,
                "long-flow utilization below 95%%: first=%0d last=%0d",
                long_first, long_last);
        end

        // Exercise all four physical data links across the column-1/2 cut:
        // two rows times two lanes.  Aggregate utilization over their common
        // active window must reach at least 90% of 4 flits/cycle.
        fork
            send_continuous_data_packet(1, 3'd2, 0, 2'd0, 32, 8'h00);
            expect_timed_data_packet(3'd1, 2, 0, 2'd0, 32, 8'h00,
                bisect_first_0, bisect_last_0);
            send_continuous_data_packet(1, 3'd2, 1, 2'd1, 32, 8'h20);
            expect_timed_data_packet(3'd1, 2, 1, 2'd1, 32, 8'h20,
                bisect_first_1, bisect_last_1);
            send_continuous_data_packet(5, 3'd6, 0, 2'd2, 32, 8'h40);
            expect_timed_data_packet(3'd5, 6, 0, 2'd2, 32, 8'h40,
                bisect_first_2, bisect_last_2);
            send_continuous_data_packet(5, 3'd6, 1, 2'd3, 32, 8'h60);
            expect_timed_data_packet(3'd5, 6, 1, 2'd3, 32, 8'h60,
                bisect_first_3, bisect_last_3);
        join
        bisect_first = bisect_first_0;
        if (bisect_first_1 < bisect_first) bisect_first = bisect_first_1;
        if (bisect_first_2 < bisect_first) bisect_first = bisect_first_2;
        if (bisect_first_3 < bisect_first) bisect_first = bisect_first_3;
        bisect_last = bisect_last_0;
        if (bisect_last_1 > bisect_last) bisect_last = bisect_last_1;
        if (bisect_last_2 > bisect_last) bisect_last = bisect_last_2;
        if (bisect_last_3 > bisect_last) bisect_last = bisect_last_3;
        bisect_active_cycles = bisect_last - bisect_first + 1'b1;
        if ((4*32*100) < (bisect_active_cycles*4*90)) begin
            $fatal(1,
                "bisection utilization below 90%%: active_cycles=%0d",
                bisect_active_cycles);
        end
        $display("PERF long=%0d/%0d flits/cycle bisection=%0d/%0d",
                 31, long_last-long_first, 4*32,
                 bisect_active_cycles*4);

        // Seven simultaneous sources target one endpoint on the same physical
        // lane.  Delivery order is arbitration-dependent, so the scoreboard
        // checks the complete source set without imposing an illegal order.
        fork
            send_data_flit(1, 0, make_data_flit(
                1'b1, 1'b1, 3'd1, 3'd0, 2'd1, 8'hd1));
            send_data_flit(2, 0, make_data_flit(
                1'b1, 1'b1, 3'd2, 3'd0, 2'd2, 8'hd2));
            send_data_flit(3, 0, make_data_flit(
                1'b1, 1'b1, 3'd3, 3'd0, 2'd3, 8'hd3));
            send_data_flit(4, 0, make_data_flit(
                1'b1, 1'b1, 3'd4, 3'd0, 2'd0, 8'hd4));
            send_data_flit(5, 0, make_data_flit(
                1'b1, 1'b1, 3'd5, 3'd0, 2'd1, 8'hd5));
            send_data_flit(6, 0, make_data_flit(
                1'b1, 1'b1, 3'd6, 3'd0, 2'd2, 8'hd6));
            send_data_flit(7, 0, make_data_flit(
                1'b1, 1'b1, 3'd7, 3'd0, 2'd3, 8'hd7));
            expect_incast(0, 0);
        join

        // Hold a multi-hop ejection under endpoint backpressure and prove the
        // destination payload remains stable until ready returns.
        stalled_endpoint = 7*LANES;
        backpressure_flit = make_data_flit(
            1'b1, 1'b1, 3'd0, 3'd7, 2'd0, 8'hee);
        @(negedge clk);
        data_rx_ready[stalled_endpoint] = 1'b0;
        send_data_flit(0, 0, backpressure_flit);
        wait (data_rx_valid[stalled_endpoint]);
        stalled_flit = data_rx_flit[
            stalled_endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH];
        repeat (4) begin
            @(posedge clk);
            if (!data_rx_valid[stalled_endpoint] ||
                data_rx_flit[stalled_endpoint*DATA_FLIT_WIDTH +:
                             DATA_FLIT_WIDTH] !== stalled_flit) begin
                $fatal(1, "Mesh ejection changed under backpressure");
            end
        end
        @(negedge clk);
        data_rx_ready[stalled_endpoint] = 1'b1;
        expect_data_flit(7, 0, backpressure_flit);

        // Quiesce rejects a new local SOP and reports only after every Router
        // has drained and all cardinal credits have returned.
        @(negedge clk);
        quiesce = 1'b1;
        control_tx_flit[0 +: CONTROL_FLIT_WIDTH] = make_control_flit(
            1'b1, 1'b1, 3'd0, 3'd7, 2'd0, 128'hdead);
        control_tx_valid[0] = 1'b1;
        repeat (8) @(posedge clk);
        if (control_tx_ready[0]) begin
            $fatal(1, "Mesh admitted a new Local SOP while quiescing");
        end
        @(negedge clk);
        control_tx_valid[0] = 1'b0;
        repeat (4) @(posedge clk);
        if (!quiesced || busy || protocol_error ||
            !(&control_router_quiesced) || !(&data_router_quiesced)) begin
            $fatal(1, "Mesh failed clean quiesce");
        end

        if (control_pair_seen !== '1 || data_pair_vc_seen !== '1) begin
            $fatal(1, "all-pairs/lane/VC functional coverage incomplete");
        end
        if ((|control_invalid_route_events) ||
            (|data_invalid_route_events) ||
            (control_accepted_packets == '0) ||
            (data_accepted_packets == '0) ||
            (control_transmitted_packets == '0) ||
            (data_transmitted_packets == '0)) begin
            $fatal(1, "Mesh extended telemetry mismatch");
        end
        if (data_blocked_cycles[
                (0*PODS*PORTS + 7*PORTS +
                 npu_noc_pkg::NPU_NOC_PORT_LOCAL)*64 +: 64] == 0) begin
            $fatal(1, "Mesh telemetry missed destination backpressure");
        end
        if ((checked_control_flits != PODS*PODS) ||
            (checked_data_flits !=
             VCS*LANES*PODS*PODS + 2 + 31 + 32 + 32 + 4*32 + 7 +
             PODS + RANDOM_FLOWS + 1)) begin
            $fatal(1, "Mesh checked-flit count mismatch control=%0d data=%0d",
                   checked_control_flits, checked_data_flits);
        end

        $display("PASS tb_npu_noc_mesh control=%0d data=%0d all_pairs=%0d",
                 checked_control_flits, checked_data_flits,
                 PODS*PODS*(1+LANES*VCS));
        $finish;
    end

    // Consume telemetry fields not explicitly inspected by this directed TB.
    wire _unused_telemetry = &{1'b0, control_router_busy, data_router_busy,
        control_accepted_flits, control_transmitted_flits,
        control_blocked_cycles, data_accepted_flits,
        data_transmitted_flits, data_blocked_cycles,
        control_accepted_packets, control_transmitted_packets,
        control_maximum_wait_cycles, control_credit_low_watermark,
        data_accepted_packets, data_transmitted_packets,
        data_maximum_wait_cycles, data_credit_low_watermark};

endmodule

`default_nettype wire
