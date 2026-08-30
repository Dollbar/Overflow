`timescale 1ns/1ps
`default_nettype none

module tb_npu_noc_lane_router;

    import npu_noc_tb_pkg::*;

    localparam int unsigned POD_ID = 1;
    localparam int unsigned PORTS = npu_noc_pkg::NPU_NOC_PORTS;
    localparam int unsigned VCS = npu_noc_pkg::NPU_NOC_DATA_VCS;
    localparam int unsigned VC_WIDTH = $clog2(VCS);
    localparam int unsigned FIFO_DEPTH = 4;
    localparam int unsigned FLIT_WIDTH = DATA_FLIT_WIDTH;

    logic clk;
    logic rst;
    logic clear;
    logic quiesce;
    logic [PORTS-1:0] port_enable;
    logic [PORTS-1:0] rx_valid;
    logic [PORTS-1:0] rx_ready;
    logic [PORTS*VC_WIDTH-1:0] rx_vc;
    logic [PORTS*FLIT_WIDTH-1:0] rx_flit;
    logic [PORTS*VCS-1:0] rx_credit;
    logic [PORTS-1:0] tx_valid;
    logic [PORTS-1:0] tx_ready;
    logic [PORTS*VC_WIDTH-1:0] tx_vc;
    logic [PORTS*FLIT_WIDTH-1:0] tx_flit;
    logic [PORTS*VCS-1:0] tx_credit;
    logic busy;
    logic quiesced;
    logic protocol_error;
    logic [PORTS*64-1:0] accepted_flits;
    logic [PORTS*64-1:0] transmitted_flits;
    logic [PORTS*64-1:0] blocked_cycles;
    logic [PORTS*64-1:0] accepted_packets;
    logic [PORTS*64-1:0] transmitted_packets;
    logic [PORTS*64-1:0] maximum_wait_cycles;
    logic [PORTS*64-1:0] credit_low_watermark;
    logic [PORTS*64-1:0] invalid_route_events;
    npu_noc_router_coverage_t coverage;
    integer checked_flits;

    npu_noc_lane_router #(
        .LOCAL_POD_ID(POD_ID),
        .FIFO_DEPTH(FIFO_DEPTH),
        .AGE_THRESHOLD(8)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(clear),
        .quiesce_i(quiesce),
        .port_enable_i(port_enable),
        .rx_valid_i(rx_valid),
        .rx_ready_o(rx_ready),
        .rx_vc_i(rx_vc),
        .rx_flit_i(rx_flit),
        .rx_credit_o(rx_credit),
        .tx_valid_o(tx_valid),
        .tx_ready_i(tx_ready),
        .tx_vc_o(tx_vc),
        .tx_flit_o(tx_flit),
        .tx_credit_i(tx_credit),
        .busy_o(busy),
        .quiesced_o(quiesced),
        .protocol_error_o(protocol_error),
        .accepted_flits_o(accepted_flits),
        .transmitted_flits_o(transmitted_flits),
        .blocked_cycles_o(blocked_cycles),
        .accepted_packets_o(accepted_packets),
        .transmitted_packets_o(transmitted_packets),
        .maximum_wait_cycles_o(maximum_wait_cycles),
        .credit_low_watermark_o(credit_low_watermark),
        .invalid_route_events_o(invalid_route_events)
    );

    always #0.5 clk = ~clk;

    task automatic inject_local(input logic [FLIT_WIDTH-1:0] flit);
        @(negedge clk);
        rx_flit[0 +: FLIT_WIDTH] = flit;
        rx_valid[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b1;
        do @(posedge clk); while (!rx_ready[npu_noc_pkg::NPU_NOC_PORT_LOCAL]);
        @(negedge clk);
        rx_valid[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b0;
    endtask

    task automatic inject_cardinal(
        input int unsigned port,
        input logic [VC_WIDTH-1:0] vc,
        input logic [FLIT_WIDTH-1:0] flit
    );
        @(negedge clk);
        rx_vc[port*VC_WIDTH +: VC_WIDTH] = vc;
        rx_flit[port*FLIT_WIDTH +: FLIT_WIDTH] = flit;
        rx_valid[port] = 1'b1;
        @(posedge clk);
        if (!rx_ready[port]) begin
            $fatal(1, "cardinal injection violated credit contract port=%0d", port);
        end
        @(negedge clk);
        rx_valid[port] = 1'b0;
    endtask

    task automatic capture_output(
        input int unsigned port,
        input logic [VC_WIDTH-1:0] expected_vc,
        output logic [7:0] observed_payload
    );
        integer timeout;
        timeout = 0;
        do begin
            @(posedge clk);
            timeout = timeout + 1;
        end while (!tx_valid[port] && timeout < 40);
        if (!tx_valid[port]) begin
            $fatal(1, "timeout waiting for output port=%0d", port);
        end
        observed_payload = data_payload_byte(tx_flit[
            port*FLIT_WIDTH +: FLIT_WIDTH]);
        if (tx_vc[port*VC_WIDTH +: VC_WIDTH] !== expected_vc) begin
            $fatal(1, "output VC mismatch port=%0d expected=%0d actual=%0d",
                   port, expected_vc,
                   tx_vc[port*VC_WIDTH +: VC_WIDTH]);
        end
        coverage.traffic_class_seen[expected_vc] = 1'b1;
        coverage.output_port_seen[port] = 1'b1;
        checked_flits = checked_flits + 1;
    endtask

    task automatic expect_output(
        input int unsigned port,
        input logic [VC_WIDTH-1:0] expected_vc,
        input logic [7:0] expected_payload
    );
        logic [7:0] observed_payload;
        capture_output(port, expected_vc, observed_payload);
        if (observed_payload !== expected_payload) begin
            $fatal(1, "output mismatch port=%0d expected=%h actual=%h",
                   port, expected_payload, observed_payload);
        end
    endtask

    task automatic return_credit(
        input int unsigned port,
        input logic [VC_WIDTH-1:0] vc
    );
        @(negedge clk);
        tx_credit[port*VCS + int'($unsigned(vc))] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tx_credit[port*VCS + int'($unsigned(vc))] = 1'b0;
        coverage.credit_return_seen = 1'b1;
    endtask

    task automatic route_single(
        input logic [2:0] destination,
        input logic [1:0] traffic_class,
        input int unsigned expected_port,
        input logic [7:0] payload
    );
        inject_local(make_data_flit(1'b1, 1'b1, POD_ID[2:0], destination,
                                    traffic_class, payload));
        expect_output(expected_port, traffic_class, payload);
        if (expected_port != npu_noc_pkg::NPU_NOC_PORT_LOCAL) begin
            return_credit(expected_port, traffic_class);
        end
    endtask

    initial begin
        logic [FLIT_WIDTH-1:0] stalled_flit;
        logic [7:0] first_arbitrated_payload;
        clk = 1'b0;
        rst = 1'b1;
        clear = 1'b0;
        quiesce = 1'b0;
        // Pod 1 is on the top row: Local, West, East, and South exist.
        port_enable = 5'b1_0111;
        rx_valid = '0;
        rx_vc = '0;
        /* verilator lint_off WIDTHCONCAT */
        rx_flit = '0;
        /* verilator lint_on WIDTHCONCAT */
        tx_ready = '0;
        tx_ready[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b1;
        tx_credit = '0;
        coverage = '0;
        checked_flits = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        if (busy || quiesced || protocol_error) begin
            $fatal(1, "router reset state mismatch");
        end

        route_single(3'd1, 2'd0, npu_noc_pkg::NPU_NOC_PORT_LOCAL, 8'h10);
        route_single(3'd0, 2'd1, npu_noc_pkg::NPU_NOC_PORT_WEST, 8'h21);
        route_single(3'd2, 2'd2, npu_noc_pkg::NPU_NOC_PORT_EAST, 8'h32);
        route_single(3'd5, 2'd3, npu_noc_pkg::NPU_NOC_PORT_SOUTH, 8'h43);

        // A cardinal flit returns one input-buffer credit when delivered local.
        inject_cardinal(npu_noc_pkg::NPU_NOC_PORT_WEST, 2'd2,
            make_data_flit(1'b1, 1'b1, 3'd0, 3'd1, 2'd2, 8'h54));
        expect_output(npu_noc_pkg::NPU_NOC_PORT_LOCAL, 2'd2, 8'h54);
        if (!rx_credit[npu_noc_pkg::NPU_NOC_PORT_WEST*VCS + 2]) begin
            $fatal(1, "missing cardinal input credit return");
        end

        // Local ready/valid must keep the selected flit stable while stalled.
        @(negedge clk);
        tx_ready[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b0;
        inject_cardinal(npu_noc_pkg::NPU_NOC_PORT_WEST, 2'd1,
            make_data_flit(1'b1, 1'b1, 3'd0, 3'd1, 2'd1, 8'h65));
        wait (tx_valid[npu_noc_pkg::NPU_NOC_PORT_LOCAL]);
        stalled_flit = tx_flit[
            npu_noc_pkg::NPU_NOC_PORT_LOCAL*FLIT_WIDTH +: FLIT_WIDTH];
        repeat (3) begin
            @(posedge clk);
            if (!tx_valid[npu_noc_pkg::NPU_NOC_PORT_LOCAL] ||
                tx_flit[npu_noc_pkg::NPU_NOC_PORT_LOCAL*FLIT_WIDTH +:
                        FLIT_WIDTH] !== stalled_flit) begin
                $fatal(1, "local output changed while stalled");
            end
        end
        coverage.local_backpressure_seen = 1'b1;
        @(negedge clk);
        tx_ready[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b1;
        expect_output(npu_noc_pkg::NPU_NOC_PORT_LOCAL, 2'd1, 8'h65);

        // Exhaust East/VC1 credits. The fifth flit remains blocked until a
        // credit is returned, proving no internal ready shortcut exists.
        for (integer index = 0; index < FIFO_DEPTH; index++) begin
            inject_local(make_data_flit(1'b1, 1'b1, 3'd1, 3'd2, 2'd1,
                                        8'h80 + 8'(index)));
            expect_output(npu_noc_pkg::NPU_NOC_PORT_EAST, 2'd1,
                          8'h80 + 8'(index));
        end
        inject_local(make_data_flit(1'b1, 1'b1, 3'd1, 3'd2, 2'd1, 8'h90));
        repeat (3) begin
            @(posedge clk);
            if (tx_valid[npu_noc_pkg::NPU_NOC_PORT_EAST]) begin
                $fatal(1, "router transmitted with exhausted credit");
            end
        end
        coverage.credit_exhaustion_seen = 1'b1;
        return_credit(npu_noc_pkg::NPU_NOC_PORT_EAST, 2'd1);
        expect_output(npu_noc_pkg::NPU_NOC_PORT_EAST, 2'd1, 8'h90);
        for (integer index = 0; index < FIFO_DEPTH; index++) begin
            return_credit(npu_noc_pkg::NPU_NOC_PORT_EAST, 2'd1);
        end

        // Two independent input ports contend for East. Both must make
        // progress and preserve their single-flit packet contents.
        @(negedge clk);
        rx_flit[0 +: FLIT_WIDTH] = make_data_flit(
            1'b1, 1'b1, 3'd1, 3'd2, 2'd0, 8'ha1);
        rx_valid[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b1;
        rx_vc[npu_noc_pkg::NPU_NOC_PORT_WEST*VC_WIDTH +: VC_WIDTH] = 2'd0;
        rx_flit[npu_noc_pkg::NPU_NOC_PORT_WEST*FLIT_WIDTH +:
                FLIT_WIDTH] = make_data_flit(
                    1'b1, 1'b1, 3'd0, 3'd2, 2'd0, 8'ha2);
        rx_valid[npu_noc_pkg::NPU_NOC_PORT_WEST] = 1'b1;
        @(posedge clk);
        if (!rx_ready[npu_noc_pkg::NPU_NOC_PORT_LOCAL] ||
            !rx_ready[npu_noc_pkg::NPU_NOC_PORT_WEST]) begin
            $fatal(1, "failed to inject simultaneous arbitration contenders");
        end
        @(negedge clk);
        rx_valid[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b0;
        rx_valid[npu_noc_pkg::NPU_NOC_PORT_WEST] = 1'b0;
        capture_output(npu_noc_pkg::NPU_NOC_PORT_EAST, 2'd0,
                       first_arbitrated_payload);
        if ((first_arbitrated_payload != 8'ha1) &&
            (first_arbitrated_payload != 8'ha2)) begin
            $fatal(1, "unexpected arbitration payload=%h",
                   first_arbitrated_payload);
        end
        expect_output(npu_noc_pkg::NPU_NOC_PORT_EAST, 2'd0,
            (first_arbitrated_payload == 8'ha1) ? 8'ha2 : 8'ha1);
        return_credit(npu_noc_pkg::NPU_NOC_PORT_EAST, 2'd0);
        return_credit(npu_noc_pkg::NPU_NOC_PORT_EAST, 2'd0);
        coverage.arbitration_seen = 1'b1;

        quiesce = 1'b1;
        repeat (5) @(posedge clk);
        if (!quiesced || busy || protocol_error) begin
            $fatal(1, "router failed to quiesce cleanly");
        end
        if ((coverage.traffic_class_seen !== 4'hf) ||
            ((coverage.output_port_seen & port_enable) !== port_enable) ||
            !coverage.local_backpressure_seen ||
            !coverage.credit_exhaustion_seen ||
            !coverage.credit_return_seen || !coverage.arbitration_seen) begin
            $fatal(1, "directed coverage contract incomplete: %h", coverage);
        end
        if ((accepted_flits[0 +: 64] == 0) ||
            (transmitted_flits[
                npu_noc_pkg::NPU_NOC_PORT_EAST*64 +: 64] == 0) ||
            (blocked_cycles[
                npu_noc_pkg::NPU_NOC_PORT_EAST*64 +: 64] == 0)) begin
            $fatal(1, "router telemetry did not record exercised traffic");
        end
        if ((accepted_packets[0 +: 64] == 0) ||
            (transmitted_packets[
                npu_noc_pkg::NPU_NOC_PORT_EAST*64 +: 64] == 0) ||
            (credit_low_watermark[
                npu_noc_pkg::NPU_NOC_PORT_EAST*64 +: 64] != 0) ||
            (|invalid_route_events)) begin
            $fatal(1, "extended router telemetry mismatch");
        end

        $display("PASS tb_npu_noc_lane_router checked_flits=%0d coverage=%h",
                 checked_flits, coverage);
        $finish;
    end

    wire _unused_telemetry = &{1'b0, accepted_flits[PORTS*64-1:64],
        transmitted_flits[PORTS*64-1:192], transmitted_flits[127:0],
        blocked_cycles[PORTS*64-1:192], blocked_cycles[127:0]};
    wire _unused_extended_telemetry = &{1'b0,
        accepted_packets[PORTS*64-1:64],
        transmitted_packets[PORTS*64-1:192], transmitted_packets[127:0],
        maximum_wait_cycles, credit_low_watermark[PORTS*64-1:192],
        credit_low_watermark[127:0]};

endmodule

`default_nettype wire
