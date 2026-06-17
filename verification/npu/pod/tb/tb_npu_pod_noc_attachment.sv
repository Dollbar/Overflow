`timescale 1ns/1ps
`default_nettype none

module tb_npu_pod_noc_attachment;

    localparam int unsigned POD_ID = 3;
    localparam int unsigned DATA_LANES =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_LANES;
    localparam int unsigned CONTROL_BYTES =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_BYTES;
    localparam int unsigned DATA_BYTES =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES;
    localparam int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH;
    localparam int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH;

    logic clk;
    logic rst;
    logic clear;
    logic quiesce;

    logic pod_control_tx_valid;
    logic pod_control_tx_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] pod_control_tx_flit;
    logic noc_control_tx_valid;
    logic noc_control_tx_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] noc_control_tx_flit;
    logic [DATA_LANES-1:0] pod_data_tx_valid;
    logic [DATA_LANES-1:0] pod_data_tx_ready;
    logic [DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_tx_flit;
    logic [DATA_LANES-1:0] noc_data_tx_valid;
    logic [DATA_LANES-1:0] noc_data_tx_ready;
    logic [DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_tx_flit;

    logic noc_control_rx_valid;
    logic noc_control_rx_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] noc_control_rx_flit;
    logic pod_control_rx_valid;
    logic pod_control_rx_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] pod_control_rx_flit;
    logic [DATA_LANES-1:0] noc_data_rx_valid;
    logic [DATA_LANES-1:0] noc_data_rx_ready;
    logic [DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_rx_flit;
    logic [DATA_LANES-1:0] pod_data_rx_valid;
    logic [DATA_LANES-1:0] pod_data_rx_ready;
    logic [DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_rx_flit;

    logic busy;
    logic quiesced;
    logic protocol_error;
    logic control_tx_busy;
    logic [DATA_LANES-1:0] data_tx_busy;
    logic control_rx_busy;
    logic [DATA_LANES-1:0] data_rx_busy;

    logic [CONTROL_FLIT_WIDTH-1:0] expected_control_flit;
    logic [DATA_FLIT_WIDTH-1:0] expected_data_flit_0;
    logic [DATA_FLIT_WIDTH-1:0] expected_data_flit_1;
    integer checked_flits;

    function automatic [CONTROL_FLIT_WIDTH-1:0] make_control_flit(
        input logic [3:0] version,
        input logic sop,
        input logic eop,
        input logic [2:0] source,
        input logic [2:0] destination,
        input logic [1:0] traffic_class,
        input logic [CONTROL_BYTES-1:0] keep,
        input logic [CONTROL_BYTES*8-1:0] payload
    );
        make_control_flit = {version, sop, eop, source, destination,
                             traffic_class, keep, payload};
    endfunction

    function automatic [DATA_FLIT_WIDTH-1:0] make_data_flit(
        input logic [3:0] version,
        input logic sop,
        input logic eop,
        input logic [2:0] source,
        input logic [2:0] destination,
        input logic [1:0] traffic_class,
        input logic [DATA_BYTES-1:0] keep,
        input logic [DATA_BYTES*8-1:0] payload
    );
        make_data_flit = {version, sop, eop, source, destination,
                          traffic_class, keep, payload};
    endfunction

    npu_pod_noc_attachment #(
        .POD_ID(POD_ID)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(clear),
        .quiesce_i(quiesce),
        .pod_control_tx_valid_i(pod_control_tx_valid),
        .pod_control_tx_ready_o(pod_control_tx_ready),
        .pod_control_tx_flit_i(pod_control_tx_flit),
        .noc_control_tx_valid_o(noc_control_tx_valid),
        .noc_control_tx_ready_i(noc_control_tx_ready),
        .noc_control_tx_flit_o(noc_control_tx_flit),
        .pod_data_tx_valid_i(pod_data_tx_valid),
        .pod_data_tx_ready_o(pod_data_tx_ready),
        .pod_data_tx_flit_i(pod_data_tx_flit),
        .noc_data_tx_valid_o(noc_data_tx_valid),
        .noc_data_tx_ready_i(noc_data_tx_ready),
        .noc_data_tx_flit_o(noc_data_tx_flit),
        .noc_control_rx_valid_i(noc_control_rx_valid),
        .noc_control_rx_ready_o(noc_control_rx_ready),
        .noc_control_rx_flit_i(noc_control_rx_flit),
        .pod_control_rx_valid_o(pod_control_rx_valid),
        .pod_control_rx_ready_i(pod_control_rx_ready),
        .pod_control_rx_flit_o(pod_control_rx_flit),
        .noc_data_rx_valid_i(noc_data_rx_valid),
        .noc_data_rx_ready_o(noc_data_rx_ready),
        .noc_data_rx_flit_i(noc_data_rx_flit),
        .pod_data_rx_valid_o(pod_data_rx_valid),
        .pod_data_rx_ready_i(pod_data_rx_ready),
        .pod_data_rx_flit_o(pod_data_rx_flit),
        .busy_o(busy),
        .quiesced_o(quiesced),
        .protocol_error_o(protocol_error),
        .control_tx_busy_o(control_tx_busy),
        .data_tx_busy_o(data_tx_busy),
        .control_rx_busy_o(control_rx_busy),
        .data_rx_busy_o(data_rx_busy)
    );

    always #0.5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        clear = 1'b0;
        quiesce = 1'b0;
        pod_control_tx_valid = 1'b0;
        pod_control_tx_flit = '0;
        noc_control_tx_ready = 1'b0;
        pod_data_tx_valid = '0;
        pod_data_tx_flit = '0;
        noc_data_tx_ready = '0;
        noc_control_rx_valid = 1'b0;
        noc_control_rx_flit = '0;
        pod_control_rx_ready = 1'b0;
        noc_data_rx_valid = '0;
        noc_data_rx_flit = '0;
        pod_data_rx_ready = '0;
        checked_flits = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        if (!quiesced || busy || protocol_error ||
            !pod_control_tx_ready || !(&pod_data_tx_ready) ||
            !noc_control_rx_ready || !(&noc_data_rx_ready) ||
            pod_control_rx_valid || (|pod_data_rx_valid) ||
            (pod_data_rx_flit !== '0) ||
            control_tx_busy || (|data_tx_busy) || control_rx_busy ||
            (|data_rx_busy)) begin
            $fatal(1, "NoC attachment reset state mismatch");
        end

        // Hold one control flit across router backpressure and check stability.
        expected_control_flit = make_control_flit(
            4'd1, 1'b1, 1'b1, 3'd3, 3'd6, 2'd0,
            {CONTROL_BYTES{1'b1}}, 128'h0123456789abcdef_fedcba9876543210);
        @(negedge clk);
        pod_control_tx_flit = expected_control_flit;
        pod_control_tx_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pod_control_tx_valid = 1'b0;
        repeat (3) begin
            @(posedge clk);
            if (!noc_control_tx_valid ||
                (noc_control_tx_flit !== expected_control_flit)) begin
                $fatal(1, "control TX changed under backpressure");
            end
        end
        @(negedge clk);
        noc_control_tx_ready = 1'b1;
        @(posedge clk);
        checked_flits = checked_flits + 1;
        @(negedge clk);
        noc_control_tx_ready = 1'b0;

        // Accept both independent data lanes in the same cycle.
        expected_data_flit_0 = make_data_flit(
            4'd1, 1'b1, 1'b1, 3'd3, 3'd4, 2'd1,
            {DATA_BYTES{1'b1}}, {DATA_BYTES{8'h5a}});
        expected_data_flit_1 = make_data_flit(
            4'd1, 1'b1, 1'b1, 3'd3, 3'd7, 2'd2,
            {DATA_BYTES{1'b1}}, {DATA_BYTES{8'ha5}});
        @(negedge clk);
        pod_data_tx_flit[0 +: DATA_FLIT_WIDTH] = expected_data_flit_0;
        pod_data_tx_flit[DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
            expected_data_flit_1;
        pod_data_tx_valid = 2'b11;
        noc_data_tx_ready = 2'b11;
        @(posedge clk);
        @(negedge clk);
        pod_data_tx_valid = '0;
        @(posedge clk);
        if ((noc_data_tx_valid != 2'b11) ||
            (noc_data_tx_flit[0 +: DATA_FLIT_WIDTH] !==
             expected_data_flit_0) ||
            (noc_data_tx_flit[DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] !==
             expected_data_flit_1)) begin
            $fatal(1, "parallel data TX mismatch");
        end
        checked_flits = checked_flits + 2;
        @(negedge clk);
        noc_data_tx_ready = '0;

        // Check one router-to-Pod control delivery and local backpressure.
        expected_control_flit = make_control_flit(
            4'd1, 1'b1, 1'b1, 3'd5, 3'd3, 2'd3,
            {CONTROL_BYTES{1'b1}}, 128'hdeadcafe_00112233_44556677_8899aabb);
        @(negedge clk);
        noc_control_rx_flit = expected_control_flit;
        noc_control_rx_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        noc_control_rx_valid = 1'b0;
        repeat (2) begin
            @(posedge clk);
            if (!pod_control_rx_valid ||
                (pod_control_rx_flit !== expected_control_flit)) begin
                $fatal(1, "control RX changed under backpressure");
            end
        end
        @(negedge clk);
        pod_control_rx_ready = 1'b1;
        @(posedge clk);
        checked_flits = checked_flits + 1;
        @(negedge clk);
        pod_control_rx_ready = 1'b0;

        // Check one full-width router-to-Pod data delivery.
        expected_data_flit_0 = make_data_flit(
            4'd1, 1'b1, 1'b1, 3'd6, 3'd3, 2'd2,
            {DATA_BYTES{1'b1}}, {DATA_BYTES{8'hc3}});
        @(negedge clk);
        noc_data_rx_flit[0 +: DATA_FLIT_WIDTH] = expected_data_flit_0;
        noc_data_rx_valid[0] = 1'b1;
        pod_data_rx_ready[0] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        noc_data_rx_valid[0] = 1'b0;
        @(posedge clk);
        if (!pod_data_rx_valid[0] ||
            (pod_data_rx_flit[0 +: DATA_FLIT_WIDTH] !==
             expected_data_flit_0)) begin
            $fatal(1, "data RX payload mismatch");
        end
        checked_flits = checked_flits + 1;
        @(negedge clk);
        pod_data_rx_ready[0] = 1'b0;

        // Quiesce after a packet head: its tail remains admissible, while a
        // subsequent packet is blocked until quiesce is released.
        expected_data_flit_0 = make_data_flit(
            4'd1, 1'b1, 1'b0, 3'd3, 3'd0, 2'd1,
            {DATA_BYTES{1'b1}}, {DATA_BYTES{8'h11}});
        @(negedge clk);
        pod_data_tx_flit[0 +: DATA_FLIT_WIDTH] = expected_data_flit_0;
        pod_data_tx_valid[0] = 1'b1;
        noc_data_tx_ready[0] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        quiesce = 1'b1;
        expected_data_flit_0 = make_data_flit(
            4'd1, 1'b0, 1'b1, 3'd3, 3'd0, 2'd1,
            {DATA_BYTES{1'b1}}, {DATA_BYTES{8'h22}});
        pod_data_tx_flit[0 +: DATA_FLIT_WIDTH] = expected_data_flit_0;
        @(posedge clk);
        if (!pod_data_tx_ready[0]) begin
            $fatal(1, "quiesce blocked the tail of an admitted packet");
        end
        @(negedge clk);
        expected_data_flit_0 = make_data_flit(
            4'd1, 1'b1, 1'b1, 3'd3, 3'd1, 2'd1,
            {DATA_BYTES{1'b1}}, {DATA_BYTES{8'h33}});
        pod_data_tx_flit[0 +: DATA_FLIT_WIDTH] = expected_data_flit_0;
        @(posedge clk);
        if (pod_data_tx_ready[0]) begin
            $fatal(1, "quiesce admitted a new packet");
        end
        @(negedge clk);
        pod_data_tx_valid[0] = 1'b0;
        repeat (2) @(posedge clk);
        if (!quiesced) begin
            $fatal(1, "NoC attachment failed to drain during quiesce");
        end
        checked_flits = checked_flits + 2;

        // Release quiesce, inject a wrong local source, and require a sticky
        // diagnostic without suppressing the flit.
        @(negedge clk);
        quiesce = 1'b0;
        expected_control_flit = make_control_flit(
            4'd1, 1'b1, 1'b1, 3'd2, 3'd6, 2'd0,
            {CONTROL_BYTES{1'b1}}, 128'hbad0bad1_bad2bad3_bad4bad5_bad6bad7);
        pod_control_tx_flit = expected_control_flit;
        pod_control_tx_valid = 1'b1;
        noc_control_tx_ready = 1'b1;
        @(posedge clk);
        @(negedge clk);
        pod_control_tx_valid = 1'b0;
        @(posedge clk);
        if (!noc_control_tx_valid || !protocol_error) begin
            $fatal(1, "malformed endpoint metadata was not forwarded/diagnosed");
        end
        checked_flits = checked_flits + 1;

        // Clear discards local state and clears the sticky diagnostic.
        @(negedge clk);
        clear = 1'b1;
        noc_control_tx_ready = 1'b0;
        @(posedge clk);
        @(negedge clk);
        clear = 1'b0;
        @(posedge clk);
        if (busy || !quiesced || protocol_error) begin
            $fatal(1, "clear did not restore the NoC attachment idle state");
        end

        $display("[RTL_SIM PASS] npu_pod_noc_attachment checked_flits=%0d",
                 checked_flits);
        $finish;
    end

    initial begin
        #500;
        $fatal(1, "npu_pod_noc_attachment timeout");
    end

endmodule

`default_nettype wire
