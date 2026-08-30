`timescale 1ns/1ps
`default_nettype none

module tb_npu_noc_pod_cdc;

    import npu_noc_tb_pkg::*;

    localparam int unsigned LANES = npu_noc_pkg::NPU_NOC_DATA_LANES;

    logic pod_clk;
    logic noc_clk;
    logic async_rst;
    logic pod_rst;
    logic noc_rst;
    real pod_half_period;
    real noc_half_period;

    logic pod_control_tx_valid;
    logic pod_control_tx_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] pod_control_tx_flit;
    logic noc_control_tx_valid;
    logic noc_control_tx_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] noc_control_tx_flit;
    logic [LANES-1:0] pod_data_tx_valid;
    logic [LANES-1:0] pod_data_tx_ready;
    logic [LANES*DATA_FLIT_WIDTH-1:0] pod_data_tx_flit;
    logic [LANES-1:0] noc_data_tx_valid;
    logic [LANES-1:0] noc_data_tx_ready;
    logic [LANES*DATA_FLIT_WIDTH-1:0] noc_data_tx_flit;
    logic noc_control_rx_valid;
    logic noc_control_rx_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] noc_control_rx_flit;
    logic pod_control_rx_valid;
    logic pod_control_rx_ready;
    logic [CONTROL_FLIT_WIDTH-1:0] pod_control_rx_flit;
    logic [LANES-1:0] noc_data_rx_valid;
    logic [LANES-1:0] noc_data_rx_ready;
    logic [LANES*DATA_FLIT_WIDTH-1:0] noc_data_rx_flit;
    logic [LANES-1:0] pod_data_rx_valid;
    logic [LANES-1:0] pod_data_rx_ready;
    logic [LANES*DATA_FLIT_WIDTH-1:0] pod_data_rx_flit;
    logic pod_busy;
    logic noc_busy;
    logic pod_quiesced;
    logic noc_quiesced;
    logic protocol_error;
    logic backpressure_seen;
    integer checked_flits;

    npu_noc_reset_sync u_pod_reset (
        .clk_i(pod_clk),
        .async_rst_i(async_rst),
        .sync_rst_o(pod_rst)
    );

    npu_noc_reset_sync u_noc_reset (
        .clk_i(noc_clk),
        .async_rst_i(async_rst),
        .sync_rst_o(noc_rst)
    );

    npu_noc_pod_cdc dut (
        .pod_clk_i(pod_clk),
        .pod_rst_i(pod_rst),
        .noc_clk_i(noc_clk),
        .noc_rst_i(noc_rst),
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
        .pod_busy_o(pod_busy),
        .noc_busy_o(noc_busy),
        .pod_quiesced_o(pod_quiesced),
        .noc_quiesced_o(noc_quiesced),
        .protocol_error_o(protocol_error)
    );

    initial begin
        pod_half_period = 1.0;
        forever begin
            #(pod_half_period) pod_clk = ~pod_clk;
        end
    end

    initial begin
        noc_half_period = 0.5;
        forever begin
            #(noc_half_period) noc_clk = ~noc_clk;
        end
    end

    always @(posedge pod_clk) begin
        if (!pod_rst && pod_control_tx_valid && !pod_control_tx_ready) begin
            backpressure_seen <= 1'b1;
        end
    end

    task automatic reset_phase(
        input real new_pod_half_period,
        input real new_noc_half_period
    );
        async_rst = 1'b1;
        repeat (3) @(posedge pod_clk);
        repeat (3) @(posedge noc_clk);
        pod_half_period = new_pod_half_period;
        noc_half_period = new_noc_half_period;
        #0.17;
        async_rst = 1'b0;
        wait (!pod_rst && !noc_rst);
        repeat (3) @(posedge noc_clk);
        if (pod_busy || noc_busy || !pod_quiesced || !noc_quiesced ||
            protocol_error) begin
            $fatal(1, "CDC reset state mismatch");
        end
    endtask

    task automatic send_pod_control(input int unsigned count);
        for (integer index = 0; index < count; index++) begin
            @(negedge pod_clk);
            pod_control_tx_flit = make_control_flit(
                1'b1, 1'b1, 3'd2, 3'd7, 2'(index),
                {96'h0, 32'(index)});
            pod_control_tx_valid = 1'b1;
            do @(posedge pod_clk); while (!pod_control_tx_ready);
            @(negedge pod_clk);
            pod_control_tx_valid = 1'b0;
        end
    endtask

    task automatic receive_noc_control(
        input int unsigned count,
        input int unsigned initial_stall
    );
        noc_control_tx_ready = 1'b0;
        repeat (initial_stall) @(posedge noc_clk);
        @(negedge noc_clk);
        noc_control_tx_ready = 1'b1;
        for (integer index = 0; index < count; index++) begin
            do @(posedge noc_clk); while (!noc_control_tx_valid);
            if (noc_control_tx_flit !== make_control_flit(
                    1'b1, 1'b1, 3'd2, 3'd7, 2'(index),
                    {96'h0, 32'(index)})) begin
                $fatal(1, "Pod-to-NoC control CDC mismatch index=%0d", index);
            end
            checked_flits = checked_flits + 1;
        end
        @(negedge noc_clk);
        noc_control_tx_ready = 1'b0;
    endtask

    task automatic send_noc_control(input int unsigned count);
        for (integer index = 0; index < count; index++) begin
            @(negedge noc_clk);
            noc_control_rx_flit = make_control_flit(
                1'b1, 1'b1, 3'd7, 3'd2, 2'(index),
                {64'hfeed_face, 32'(index), 32'h55aa_55aa});
            noc_control_rx_valid = 1'b1;
            do @(posedge noc_clk); while (!noc_control_rx_ready);
            @(negedge noc_clk);
            noc_control_rx_valid = 1'b0;
        end
    endtask

    task automatic receive_pod_control(input int unsigned count);
        pod_control_rx_ready = 1'b1;
        for (integer index = 0; index < count; index++) begin
            do @(posedge pod_clk); while (!pod_control_rx_valid);
            if (pod_control_rx_flit !== make_control_flit(
                    1'b1, 1'b1, 3'd7, 3'd2, 2'(index),
                    {64'hfeed_face, 32'(index), 32'h55aa_55aa})) begin
                $fatal(1, "NoC-to-Pod control CDC mismatch index=%0d", index);
            end
            checked_flits = checked_flits + 1;
        end
        @(negedge pod_clk);
        pod_control_rx_ready = 1'b0;
    endtask

    task automatic send_pod_data(
        input int unsigned lane,
        input int unsigned count
    );
        for (integer index = 0; index < count; index++) begin
            @(negedge pod_clk);
            pod_data_tx_flit[lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
                make_data_flit(1'b1, 1'b1, 3'd2, 3'd6, 2'(lane),
                               8'(index + lane*8'h80));
            pod_data_tx_valid[lane] = 1'b1;
            do @(posedge pod_clk); while (!pod_data_tx_ready[lane]);
            @(negedge pod_clk);
            pod_data_tx_valid[lane] = 1'b0;
        end
    endtask

    task automatic receive_noc_data(
        input int unsigned lane,
        input int unsigned count
    );
        noc_data_tx_ready[lane] = 1'b1;
        for (integer index = 0; index < count; index++) begin
            do @(posedge noc_clk); while (!noc_data_tx_valid[lane]);
            if (noc_data_tx_flit[
                    lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] !==
                make_data_flit(1'b1, 1'b1, 3'd2, 3'd6, 2'(lane),
                               8'(index + lane*8'h80))) begin
                $fatal(1, "Pod-to-NoC data CDC mismatch lane=%0d index=%0d",
                       lane, index);
            end
            checked_flits = checked_flits + 1;
        end
        @(negedge noc_clk);
        noc_data_tx_ready[lane] = 1'b0;
    endtask

    task automatic send_noc_data(
        input int unsigned lane,
        input int unsigned count
    );
        for (integer index = 0; index < count; index++) begin
            @(negedge noc_clk);
            noc_data_rx_flit[lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
                make_data_flit(1'b1, 1'b1, 3'd6, 3'd2, 2'(lane + 2),
                               8'(index + lane*8'h40));
            noc_data_rx_valid[lane] = 1'b1;
            do @(posedge noc_clk); while (!noc_data_rx_ready[lane]);
            @(negedge noc_clk);
            noc_data_rx_valid[lane] = 1'b0;
        end
    endtask

    task automatic receive_pod_data(
        input int unsigned lane,
        input int unsigned count
    );
        pod_data_rx_ready[lane] = 1'b1;
        for (integer index = 0; index < count; index++) begin
            do @(posedge pod_clk); while (!pod_data_rx_valid[lane]);
            if (pod_data_rx_flit[
                    lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] !==
                make_data_flit(1'b1, 1'b1, 3'd6, 3'd2, 2'(lane + 2),
                               8'(index + lane*8'h40))) begin
                $fatal(1, "NoC-to-Pod data CDC mismatch lane=%0d index=%0d",
                       lane, index);
            end
            checked_flits = checked_flits + 1;
        end
        @(negedge pod_clk);
        pod_data_rx_ready[lane] = 1'b0;
    endtask

    task automatic run_ratio_phase(
        input real new_pod_half_period,
        input real new_noc_half_period,
        input int unsigned phase_id
    );
        reset_phase(new_pod_half_period, new_noc_half_period);
        fork
            send_pod_control(12);
            receive_noc_control(12, 24);
            send_noc_control(20);
            receive_pod_control(20);
            send_pod_data(0, 40);
            receive_noc_data(0, 40);
            send_pod_data(1, 40);
            receive_noc_data(1, 40);
            send_noc_data(0, 40);
            receive_pod_data(0, 40);
            send_noc_data(1, 40);
            receive_pod_data(1, 40);
        join
        repeat (8) @(posedge pod_clk);
        repeat (8) @(posedge noc_clk);
        if (pod_busy || noc_busy || !pod_quiesced || !noc_quiesced ||
            protocol_error) begin
            $fatal(1, "CDC phase %0d failed to drain", phase_id);
        end
    endtask

    initial begin
        pod_clk = 1'b0;
        noc_clk = 1'b0;
        pod_half_period = 1.0;
        noc_half_period = 0.5;
        async_rst = 1'b1;
        pod_control_tx_valid = 1'b0;
        pod_control_tx_flit = '0;
        noc_control_tx_ready = 1'b0;
        pod_data_tx_valid = '0;
        /* verilator lint_off WIDTHCONCAT */
        pod_data_tx_flit = '0;
        noc_data_rx_flit = '0;
        /* verilator lint_on WIDTHCONCAT */
        noc_data_tx_ready = '0;
        noc_control_rx_valid = 1'b0;
        noc_control_rx_flit = '0;
        pod_control_rx_ready = 1'b0;
        noc_data_rx_valid = '0;
        pod_data_rx_ready = '0;
        checked_flits = 0;
        backpressure_seen = 1'b0;

        run_ratio_phase(1.0, 1.0, 0);  // equal frequency, phase offset
        run_ratio_phase(1.0, 0.5, 1);  // proposed Pod:NoC 1:2
        run_ratio_phase(0.5, 1.0, 2);  // reverse 2:1 stress
        run_ratio_phase(0.7, 1.1, 3);  // unrelated phase/rational ratio

        if (!backpressure_seen || checked_flits != 4*(12 + 20 + 4*40)) begin
            $fatal(1, "CDC coverage/count mismatch seen=%0b checked=%0d",
                   backpressure_seen, checked_flits);
        end

        // Assert reset away from both active edges and require immediate local
        // reset assertion followed by independent synchronized release.
        #0.13;
        async_rst = 1'b1;
        #0.01;
        if (!pod_rst || !noc_rst) begin
            $fatal(1, "CDC reset did not assert asynchronously");
        end
        #0.19;
        async_rst = 1'b0;
        wait (!pod_rst && !noc_rst);

        $display("PASS tb_npu_noc_pod_cdc checked_flits=%0d ratios=4",
                 checked_flits);
        $finish;
    end

endmodule

`default_nettype wire
