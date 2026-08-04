`timescale 1ns/1ps
`default_nettype none

module formal_npu_noc_router_invariants;

    localparam int unsigned PORTS = 5;
    localparam int unsigned VCS = 4;
    localparam int unsigned VC_WIDTH = 2;
    localparam int unsigned FLIT_WIDTH = 23;

    wire clk = $global_clock;
    (* anyseq *) logic rst;
    (* anyseq *) logic local_rx_valid;
    (* anyseq *) logic [FLIT_WIDTH-1:0] local_rx_flit;
    (* anyseq *) logic local_tx_ready;
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
    logic past_valid_q;
    logic [5:0] accepted_ghost_q;
    logic [5:0] transmitted_ghost_q;

    initial past_valid_q = 1'b0;

    always_comb begin
        rx_valid = '0;
        rx_valid[0] = local_rx_valid;
        rx_vc = '0;
        rx_flit = '0;
        rx_flit[0 +: FLIT_WIDTH] = local_rx_flit;
        tx_ready = '0;
        tx_ready[0] = local_tx_ready;
        tx_credit = '0;
        for (integer port = 1; port < PORTS; port++) begin
            for (integer vc = 0; vc < VCS; vc++) begin
                tx_credit[port*VCS + vc] = tx_valid[port] &&
                    (tx_vc[port*VC_WIDTH +: VC_WIDTH] == VC_WIDTH'(vc));
            end
        end
    end

    npu_noc_lane_router #(
        .LOCAL_POD_ID(1),
        .PAYLOAD_BYTES(1),
        .FLIT_WIDTH(FLIT_WIDTH),
        .VCS(VCS),
        .FIFO_DEPTH(2),
        .MAX_PACKET_FLITS(2),
        .AGE_THRESHOLD(2)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),
        .clear_i(1'b0),
        .quiesce_i(1'b0),
        .port_enable_i(5'b1_1111),
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
        .busy_o(),
        .quiesced_o(),
        .protocol_error_o(),
        .accepted_flits_o(),
        .transmitted_flits_o(),
        .blocked_cycles_o(),
        .accepted_packets_o(),
        .transmitted_packets_o(),
        .maximum_wait_cycles_o(),
        .credit_low_watermark_o(),
        .invalid_route_events_o()
    );

    always_ff @(posedge clk) begin
        past_valid_q <= 1'b1;
        if (!past_valid_q) begin
            assume (rst);
        end else begin
            assume (!rst);
        end
        if (past_valid_q && $past(local_rx_valid && !rx_ready[0])) begin
            assume (local_rx_valid);
            assume (local_rx_flit == $past(local_rx_flit));
        end
        if (past_valid_q && $past(tx_valid[0] && !local_tx_ready)) begin
            assert (tx_valid[0]);
            assert (tx_flit[0 +: FLIT_WIDTH] ==
                    $past(tx_flit[0 +: FLIT_WIDTH]));
        end
        if (rst) begin
            accepted_ghost_q <= '0;
            transmitted_ghost_q <= '0;
        end else begin
            if (local_rx_valid && rx_ready[0]) begin
                accepted_ghost_q <= accepted_ghost_q + 1'b1;
            end
            transmitted_ghost_q <= transmitted_ghost_q +
                6'($countones({tx_valid[PORTS-1:1],
                               tx_valid[0] && local_tx_ready}));
            assert (transmitted_ghost_q <= accepted_ghost_q);
        end
    end

    wire _unused_rx_credit = &{1'b0, rx_credit};

endmodule

`default_nettype wire
