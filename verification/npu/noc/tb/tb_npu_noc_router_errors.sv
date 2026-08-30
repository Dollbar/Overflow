`timescale 1ns/1ps
`default_nettype none

module tb_npu_noc_router_errors;

    import npu_noc_tb_pkg::*;

    localparam int unsigned POD_ID = 1;
    localparam int unsigned PORTS = npu_noc_pkg::NPU_NOC_PORTS;
    localparam int unsigned VCS = npu_noc_pkg::NPU_NOC_DATA_VCS;
    localparam int unsigned VC_WIDTH = $clog2(VCS);
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

    npu_noc_lane_router #(
        .LOCAL_POD_ID(POD_ID),
        .FIFO_DEPTH(4),
        .MAX_PACKET_FLITS(2),
        .AGE_THRESHOLD(4)
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

    task automatic pulse_clear;
        @(negedge clk);
        clear = 1'b1;
        @(posedge clk);
        @(negedge clk);
        clear = 1'b0;
        repeat (2) @(posedge clk);
        if (busy || protocol_error) begin
            $fatal(1, "Router clear failed to restore clean state");
        end
    endtask

    task automatic inject_local(input logic [FLIT_WIDTH-1:0] flit);
        @(negedge clk);
        rx_flit[0 +: FLIT_WIDTH] = flit;
        rx_valid[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b1;
        do @(posedge clk); while (!rx_ready[npu_noc_pkg::NPU_NOC_PORT_LOCAL]);
        @(negedge clk);
        rx_valid[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b0;
    endtask

    task automatic expect_payload(
        input int unsigned port,
        input logic [7:0] payload
    );
        integer timeout;
        timeout = 0;
        do begin
            @(posedge clk);
            timeout = timeout + 1;
        end while (!tx_valid[port] && timeout < 30);
        if (!tx_valid[port] ||
            data_payload_byte(tx_flit[
                port*FLIT_WIDTH +: FLIT_WIDTH]) != payload) begin
            $fatal(1, "error-recovery output mismatch port=%0d payload=%h",
                   port, payload);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        clear = 1'b0;
        quiesce = 1'b0;
        port_enable = 5'b1_0111;
        rx_valid = '0;
        rx_vc = '0;
        /* verilator lint_off WIDTHCONCAT */
        rx_flit = '0;
        /* verilator lint_on WIDTHCONCAT */
        tx_ready = '0;
        tx_ready[npu_noc_pkg::NPU_NOC_PORT_LOCAL] = 1'b1;
        tx_credit = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // A disabled legal direction is diagnosed and dropped so the Router
        // cannot retain an unrouteable head forever.
        port_enable[npu_noc_pkg::NPU_NOC_PORT_EAST] = 1'b0;
        inject_local(make_data_flit(
            1'b1, 1'b1, 3'd1, 3'd2, 2'd0, 8'h11));
        repeat (6) @(posedge clk);
        if (busy || !protocol_error ||
            invalid_route_events[0 +: 64] != 1 || (|tx_valid)) begin
            $fatal(1, "invalid-route recovery mismatch");
        end

        pulse_clear();
        port_enable[npu_noc_pkg::NPU_NOC_PORT_EAST] = 1'b1;

        // A destination change is malformed, but the original packet lock
        // must drain the tail only once through East.
        fork
            begin
                inject_local(make_data_flit(
                    1'b1, 1'b0, 3'd1, 3'd2, 2'd0, 8'h21));
                inject_local(make_data_flit(
                    1'b0, 1'b1, 3'd1, 3'd0, 2'd0, 8'h22));
            end
            begin
                expect_payload(npu_noc_pkg::NPU_NOC_PORT_EAST, 8'h21);
                expect_payload(npu_noc_pkg::NPU_NOC_PORT_EAST, 8'h22);
            end
        join
        if (tx_valid[npu_noc_pkg::NPU_NOC_PORT_WEST]) begin
            $fatal(1, "malformed tail was duplicated to a second output");
        end
        repeat (2) @(posedge clk);
        if (!protocol_error ||
            transmitted_flits[
                npu_noc_pkg::NPU_NOC_PORT_EAST*64 +: 64] != 2 ||
            transmitted_flits[
                npu_noc_pkg::NPU_NOC_PORT_WEST*64 +: 64] != 0) begin
            $fatal(1, "malformed packet-lock recovery mismatch");
        end

        pulse_clear();

        // A third flit exceeds MAX_PACKET_FLITS=2 but still drains through EOP.
        fork
            begin
                inject_local(make_data_flit(
                    1'b1, 1'b0, 3'd1, 3'd1, 2'd1, 8'h31));
                inject_local(make_data_flit(
                    1'b0, 1'b0, 3'd1, 3'd1, 2'd1, 8'h32));
                inject_local(make_data_flit(
                    1'b0, 1'b1, 3'd1, 3'd1, 2'd1, 8'h33));
            end
            begin
                expect_payload(npu_noc_pkg::NPU_NOC_PORT_LOCAL, 8'h31);
                expect_payload(npu_noc_pkg::NPU_NOC_PORT_LOCAL, 8'h32);
                expect_payload(npu_noc_pkg::NPU_NOC_PORT_LOCAL, 8'h33);
            end
        join
        if (!protocol_error) begin
            $fatal(1, "overlength packet was not diagnosed");
        end

        pulse_clear();

        // A returned cardinal credit above reset capacity is an error.
        @(negedge clk);
        tx_credit[npu_noc_pkg::NPU_NOC_PORT_EAST*VCS] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tx_credit[npu_noc_pkg::NPU_NOC_PORT_EAST*VCS] = 1'b0;
        @(posedge clk);
        if (!protocol_error) begin
            $fatal(1, "credit overflow was not diagnosed");
        end

        $display("PASS tb_npu_noc_router_errors");
        $finish;
    end

    wire _unused_outputs = &{1'b0, rx_credit, tx_vc, accepted_flits,
        transmitted_flits[PORTS*64-1:192], transmitted_flits[63:0],
        blocked_cycles, accepted_packets, transmitted_packets,
        maximum_wait_cycles, credit_low_watermark,
        invalid_route_events[PORTS*64-1:64], quiesced};

endmodule

`default_nettype wire
