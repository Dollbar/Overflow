`timescale 1ns/1ps
`default_nettype none

module tb_npu_noc_cdc_mesh;

    import npu_noc_tb_pkg::*;

    localparam int unsigned PODS = npu_noc_pkg::NPU_NOC_PODS;
    localparam int unsigned LANES = npu_noc_pkg::NPU_NOC_DATA_LANES;
    localparam int unsigned VCS = npu_noc_pkg::NPU_NOC_DATA_VCS;

    logic [PODS-1:0] pod_clk;
    logic noc_clk;
    logic async_rst;
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
    logic [PODS-1:0] pod_rst;
    logic noc_rst;
    logic [PODS-1:0] pod_quiesce;
    logic busy;
    logic quiesced;
    logic protocol_error;
    logic [PODS-1:0] pod_cdc_busy;
    logic [PODS-1:0] noc_cdc_busy;
    integer checked_control_flits;
    integer checked_data_flits;
    logic [PODS*PODS-1:0] control_pair_seen;
    logic [VCS*LANES*PODS*PODS-1:0] data_pair_vc_seen;

    /* The detailed per-Router telemetry ports are separately checked by the
       Mesh TB.  This smoke test owns the complete CDC+Mesh composition. */
    /* verilator lint_off PINCONNECTEMPTY */
    npu_noc_cdc_mesh dut (
        .pod_clk_i(pod_clk),
        .noc_clk_i(noc_clk),
        .async_rst_i(async_rst),
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
        .pod_rst_o(pod_rst),
        .noc_rst_o(noc_rst),
        .pod_quiesce_o(pod_quiesce),
        .busy_o(busy),
        .quiesced_o(quiesced),
        .protocol_error_o(protocol_error),
        .pod_cdc_busy_o(pod_cdc_busy),
        .noc_cdc_busy_o(noc_cdc_busy),
        .control_router_busy_o(),
        .data_router_busy_o(),
        .control_router_protocol_error_o(),
        .data_router_protocol_error_o(),
        .control_accepted_flits_o(),
        .control_transmitted_flits_o(),
        .control_blocked_cycles_o(),
        .control_accepted_packets_o(),
        .control_transmitted_packets_o(),
        .control_maximum_wait_cycles_o(),
        .control_credit_low_watermark_o(),
        .control_invalid_route_events_o(),
        .data_accepted_flits_o(),
        .data_transmitted_flits_o(),
        .data_blocked_cycles_o(),
        .data_accepted_packets_o(),
        .data_transmitted_packets_o(),
        .data_maximum_wait_cycles_o(),
        .data_credit_low_watermark_o(),
        .data_invalid_route_events_o()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #1.00 pod_clk[0] = ~pod_clk[0];
    always #0.83 pod_clk[1] = ~pod_clk[1];
    always #1.17 pod_clk[2] = ~pod_clk[2];
    always #0.91 pod_clk[3] = ~pod_clk[3];
    always #1.31 pod_clk[4] = ~pod_clk[4];
    always #0.73 pod_clk[5] = ~pod_clk[5];
    always #1.07 pod_clk[6] = ~pod_clk[6];
    always #1.43 pod_clk[7] = ~pod_clk[7];
    always #0.5 noc_clk = ~noc_clk;

    task automatic send_control(
        input int unsigned source,
        input logic [CONTROL_FLIT_WIDTH-1:0] flit
    );
        @(negedge pod_clk[source]);
        control_tx_flit[source*CONTROL_FLIT_WIDTH +:
                        CONTROL_FLIT_WIDTH] = flit;
        control_tx_valid[source] = 1'b1;
        do @(posedge pod_clk[source]); while (!control_tx_ready[source]);
        @(negedge pod_clk[source]);
        control_tx_valid[source] = 1'b0;
    endtask

    task automatic expect_control(
        input int unsigned destination,
        input logic [CONTROL_FLIT_WIDTH-1:0] expected
    );
        integer timeout;
        timeout = 0;
        do begin
            @(posedge pod_clk[destination]);
            timeout = timeout + 1;
        end while (!control_rx_valid[destination] && timeout < 200);
        if (!control_rx_valid[destination] ||
            control_rx_flit[destination*CONTROL_FLIT_WIDTH +:
                            CONTROL_FLIT_WIDTH] !== expected) begin
            $fatal(1, "CDC Mesh control delivery mismatch");
        end
        checked_control_flits = checked_control_flits + 1;
    endtask

    task automatic send_data(
        input int unsigned source,
        input int unsigned lane,
        input logic [DATA_FLIT_WIDTH-1:0] flit
    );
        integer endpoint;
        endpoint = source*LANES + lane;
        @(negedge pod_clk[source]);
        data_tx_flit[endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] = flit;
        data_tx_valid[endpoint] = 1'b1;
        do @(posedge pod_clk[source]); while (!data_tx_ready[endpoint]);
        @(negedge pod_clk[source]);
        data_tx_valid[endpoint] = 1'b0;
    endtask

    task automatic expect_data(
        input int unsigned destination,
        input int unsigned lane,
        input logic [DATA_FLIT_WIDTH-1:0] expected
    );
        integer endpoint;
        integer timeout;
        endpoint = destination*LANES + lane;
        timeout = 0;
        do begin
            @(posedge pod_clk[destination]);
            timeout = timeout + 1;
        end while (!data_rx_valid[endpoint] && timeout < 250);
        if (!data_rx_valid[endpoint] ||
            data_rx_flit[endpoint*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] !==
            expected) begin
            $fatal(1, "CDC Mesh data delivery mismatch endpoint=%0d",
                   endpoint);
        end
        checked_data_flits = checked_data_flits + 1;
    endtask

    initial begin
        logic [CONTROL_FLIT_WIDTH-1:0] control_forward;
        logic [CONTROL_FLIT_WIDTH-1:0] control_reverse;
        logic [DATA_FLIT_WIDTH-1:0] data_forward;
        logic [DATA_FLIT_WIDTH-1:0] data_reverse;
        integer timeout;
        pod_clk = '0;
        noc_clk = 1'b0;
        async_rst = 1'b1;
        clear = 1'b0;
        quiesce = 1'b0;
        control_tx_valid = '0;
        control_tx_flit = '0;
        control_rx_ready = '1;
        data_tx_valid = '0;
        /* verilator lint_off WIDTHCONCAT */
        data_tx_flit = '0;
        /* verilator lint_on WIDTHCONCAT */
        data_rx_ready = '1;
        checked_control_flits = 0;
        checked_data_flits = 0;
        control_pair_seen = '0;
        data_pair_vc_seen = '0;

        #7.3;
        async_rst = 1'b0;
        wait (!noc_rst && !(|pod_rst));
        repeat (4) @(posedge noc_clk);
        if (busy || protocol_error) begin
            $fatal(1, "CDC Mesh reset state mismatch");
        end

        control_forward = make_control_flit(
            1'b1, 1'b1, 3'd0, 3'd7, 2'd1, 128'h0123);
        control_reverse = make_control_flit(
            1'b1, 1'b1, 3'd7, 3'd0, 2'd2, 128'h4567);
        data_forward = make_data_flit(
            1'b1, 1'b1, 3'd0, 3'd7, 2'd0, 8'ha5);
        data_reverse = make_data_flit(
            1'b1, 1'b1, 3'd7, 3'd0, 2'd3, 8'h5a);
        fork
            send_control(0, control_forward);
            expect_control(7, control_forward);
            send_control(7, control_reverse);
            expect_control(0, control_reverse);
            send_data(0, 0, data_forward);
            expect_data(7, 0, data_forward);
            send_data(7, 1, data_reverse);
            expect_data(0, 1, data_reverse);
        join

        // Traverse every Pod pair through both CDC directions, both physical
        // data lanes, and all four VCs while all eight Pod clocks are distinct.
        for (integer source = 0; source < PODS; source++) begin
            for (integer destination = 0; destination < PODS;
                 destination++) begin
                control_forward = make_control_flit(
                    1'b1, 1'b1, 3'(source), 3'(destination),
                    2'((source + destination) % 4),
                    {64'(source), 32'(destination), 32'hcdc0_cdc0});
                fork
                    send_control(source, control_forward);
                    expect_control(destination, control_forward);
                join
                control_pair_seen[source*PODS + destination] = 1'b1;
                for (integer lane = 0; lane < LANES; lane++) begin
                    for (integer vc = 0; vc < VCS; vc++) begin
                        data_forward = make_data_flit(
                            1'b1, 1'b1, 3'(source), 3'(destination),
                            2'(vc), 8'(source*32 + destination*4 +
                                      lane*2 + (vc & 1)));
                        fork
                            send_data(source, lane, data_forward);
                            expect_data(destination, lane, data_forward);
                        join
                        data_pair_vc_seen[
                            ((vc*LANES + lane)*PODS + source)*PODS +
                            destination] = 1'b1;
                    end
                end
            end
        end

        @(negedge pod_clk[0]);
        quiesce = 1'b1;
        timeout = 0;
        do begin
            @(posedge noc_clk);
            timeout = timeout + 1;
        end while (!quiesced && timeout < 100);
        if (!quiesced || busy || protocol_error ||
            (pod_quiesce !== '1) || (|pod_cdc_busy) || (|noc_cdc_busy)) begin
            $fatal(1, "CDC Mesh failed stable drain/quiesce");
        end
        if (control_pair_seen !== '1 || data_pair_vc_seen !== '1 ||
            checked_control_flits != 2 + PODS*PODS ||
            checked_data_flits != 2 + VCS*LANES*PODS*PODS) begin
            $fatal(1, "CDC Mesh functional coverage matrix incomplete");
        end

        $display("PASS tb_npu_noc_cdc_mesh control=%0d data=%0d matrix=%0d",
                 checked_control_flits, checked_data_flits,
                 PODS*PODS*(1 + LANES*VCS));
        $finish;
    end

endmodule

`default_nettype wire
