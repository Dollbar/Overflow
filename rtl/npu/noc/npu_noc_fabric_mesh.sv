`timescale 1ns/1ps
`default_nettype none

// One physical-lane 2x4 Mesh fabric. Pod endpoints use ready/valid, while all
// cardinal links are internal credit-based connections between Router Leafs.
module npu_noc_fabric_mesh #(
    parameter int unsigned PAYLOAD_BYTES = 128,
    parameter int unsigned FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH,
    parameter int unsigned VCS = npu_noc_pkg::NPU_NOC_DATA_VCS,
    parameter int unsigned FIFO_DEPTH = npu_noc_pkg::NPU_NOC_DATA_FIFO_DEPTH,
    parameter int unsigned MAX_PACKET_FLITS =
        npu_noc_pkg::NPU_NOC_DATA_PACKET_FLITS,
    parameter int unsigned AGE_THRESHOLD = npu_noc_pkg::NPU_NOC_AGE_THRESHOLD,
    parameter int unsigned PODS = npu_noc_pkg::NPU_NOC_PODS,
    parameter int unsigned PORTS = npu_noc_pkg::NPU_NOC_PORTS,
    parameter int unsigned VC_WIDTH = (VCS <= 1) ? 1 : $clog2(VCS)
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic [PODS-1:0] endpoint_tx_valid_i,
    output logic [PODS-1:0] endpoint_tx_ready_o,
    input  logic [PODS*FLIT_WIDTH-1:0] endpoint_tx_flit_i,

    output logic [PODS-1:0] endpoint_rx_valid_o,
    input  logic [PODS-1:0] endpoint_rx_ready_i,
    output logic [PODS*FLIT_WIDTH-1:0] endpoint_rx_flit_o,

    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o,
    output logic [PODS-1:0] router_busy_o,
    output logic [PODS-1:0] router_quiesced_o,
    output logic [PODS-1:0] router_protocol_error_o,
    output logic [PODS*PORTS*64-1:0] accepted_flits_o,
    output logic [PODS*PORTS*64-1:0] transmitted_flits_o,
    output logic [PODS*PORTS*64-1:0] blocked_cycles_o,
    output logic [PODS*PORTS*64-1:0] accepted_packets_o,
    output logic [PODS*PORTS*64-1:0] transmitted_packets_o,
    output logic [PODS*PORTS*64-1:0] maximum_wait_cycles_o,
    output logic [PODS*PORTS*64-1:0] credit_low_watermark_o,
    output logic [PODS*PORTS*64-1:0] invalid_route_events_o
);

    localparam int unsigned ROUTER_PORTS = PODS * PORTS;

    /* Some boundary-port slices are deliberately tied off by the generated
       topology and are retained in the regular Router interface. */
    /* verilator lint_off UNUSEDSIGNAL */
    logic [ROUTER_PORTS-1:0] router_rx_valid;
    logic [ROUTER_PORTS-1:0] router_rx_ready;
    logic [ROUTER_PORTS*VC_WIDTH-1:0] router_rx_vc;
    logic [ROUTER_PORTS*FLIT_WIDTH-1:0] router_rx_flit;
    logic [ROUTER_PORTS*VCS-1:0] router_rx_credit;
    logic [ROUTER_PORTS-1:0] router_tx_valid;
    logic [ROUTER_PORTS-1:0] router_tx_ready;
    logic [ROUTER_PORTS*VC_WIDTH-1:0] router_tx_vc;
    logic [ROUTER_PORTS*FLIT_WIDTH-1:0] router_tx_flit;
    logic [ROUTER_PORTS*VCS-1:0] router_tx_credit;
    /* verilator lint_on UNUSEDSIGNAL */

    generate
        for (genvar pod = 0; pod < PODS; pod++) begin : g_router
            localparam int unsigned COLUMN = pod % npu_noc_pkg::NPU_NOC_COLUMNS;
            localparam int unsigned ROW = pod / npu_noc_pkg::NPU_NOC_COLUMNS;
            localparam logic [PORTS-1:0] PORT_ENABLE = {
                (ROW + 1 < npu_noc_pkg::NPU_NOC_ROWS),
                (ROW > 0),
                (COLUMN + 1 < npu_noc_pkg::NPU_NOC_COLUMNS),
                (COLUMN > 0),
                1'b1
            };
            localparam int unsigned LOCAL_INDEX =
                pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_LOCAL;

            assign router_rx_valid[LOCAL_INDEX] = endpoint_tx_valid_i[pod];
            assign endpoint_tx_ready_o[pod] = router_rx_ready[LOCAL_INDEX];
            assign router_rx_vc[LOCAL_INDEX*VC_WIDTH +: VC_WIDTH] = '0;
            assign router_rx_flit[LOCAL_INDEX*FLIT_WIDTH +: FLIT_WIDTH] =
                endpoint_tx_flit_i[pod*FLIT_WIDTH +: FLIT_WIDTH];
            assign router_tx_credit[LOCAL_INDEX*VCS +: VCS] = '0;

            assign endpoint_rx_valid_o[pod] = router_tx_valid[LOCAL_INDEX];
            assign router_tx_ready[LOCAL_INDEX] = endpoint_rx_ready_i[pod];
            assign endpoint_rx_flit_o[pod*FLIT_WIDTH +: FLIT_WIDTH] =
                router_tx_flit[LOCAL_INDEX*FLIT_WIDTH +: FLIT_WIDTH];

            if (COLUMN > 0) begin : g_west
                localparam int unsigned RX_INDEX =
                    pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_WEST;
                localparam int unsigned NEIGHBOR_TX_INDEX =
                    (pod-1)*PORTS + npu_noc_pkg::NPU_NOC_PORT_EAST;
                localparam int unsigned TX_INDEX = RX_INDEX;
                localparam int unsigned NEIGHBOR_RX_INDEX = NEIGHBOR_TX_INDEX;
                assign router_rx_valid[RX_INDEX] =
                    router_tx_valid[NEIGHBOR_TX_INDEX];
                assign router_rx_vc[RX_INDEX*VC_WIDTH +: VC_WIDTH] =
                    router_tx_vc[NEIGHBOR_TX_INDEX*VC_WIDTH +: VC_WIDTH];
                assign router_rx_flit[RX_INDEX*FLIT_WIDTH +: FLIT_WIDTH] =
                    router_tx_flit[
                        NEIGHBOR_TX_INDEX*FLIT_WIDTH +: FLIT_WIDTH];
                assign router_tx_credit[TX_INDEX*VCS +: VCS] =
                    router_rx_credit[NEIGHBOR_RX_INDEX*VCS +: VCS];
            end else begin : g_no_west
                localparam int unsigned INDEX =
                    pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_WEST;
                assign router_rx_valid[INDEX] = 1'b0;
                assign router_rx_vc[INDEX*VC_WIDTH +: VC_WIDTH] = '0;
                assign router_rx_flit[INDEX*FLIT_WIDTH +: FLIT_WIDTH] = '0;
                assign router_tx_credit[INDEX*VCS +: VCS] = '0;
            end

            if (COLUMN + 1 < npu_noc_pkg::NPU_NOC_COLUMNS) begin : g_east
                localparam int unsigned RX_INDEX =
                    pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_EAST;
                localparam int unsigned NEIGHBOR_TX_INDEX =
                    (pod+1)*PORTS + npu_noc_pkg::NPU_NOC_PORT_WEST;
                localparam int unsigned TX_INDEX = RX_INDEX;
                localparam int unsigned NEIGHBOR_RX_INDEX = NEIGHBOR_TX_INDEX;
                assign router_rx_valid[RX_INDEX] =
                    router_tx_valid[NEIGHBOR_TX_INDEX];
                assign router_rx_vc[RX_INDEX*VC_WIDTH +: VC_WIDTH] =
                    router_tx_vc[NEIGHBOR_TX_INDEX*VC_WIDTH +: VC_WIDTH];
                assign router_rx_flit[RX_INDEX*FLIT_WIDTH +: FLIT_WIDTH] =
                    router_tx_flit[
                        NEIGHBOR_TX_INDEX*FLIT_WIDTH +: FLIT_WIDTH];
                assign router_tx_credit[TX_INDEX*VCS +: VCS] =
                    router_rx_credit[NEIGHBOR_RX_INDEX*VCS +: VCS];
            end else begin : g_no_east
                localparam int unsigned INDEX =
                    pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_EAST;
                assign router_rx_valid[INDEX] = 1'b0;
                assign router_rx_vc[INDEX*VC_WIDTH +: VC_WIDTH] = '0;
                assign router_rx_flit[INDEX*FLIT_WIDTH +: FLIT_WIDTH] = '0;
                assign router_tx_credit[INDEX*VCS +: VCS] = '0;
            end

            if (ROW > 0) begin : g_north
                localparam int unsigned RX_INDEX =
                    pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_NORTH;
                localparam int unsigned NEIGHBOR_TX_INDEX =
                    (pod-npu_noc_pkg::NPU_NOC_COLUMNS)*PORTS +
                    npu_noc_pkg::NPU_NOC_PORT_SOUTH;
                localparam int unsigned TX_INDEX = RX_INDEX;
                localparam int unsigned NEIGHBOR_RX_INDEX = NEIGHBOR_TX_INDEX;
                assign router_rx_valid[RX_INDEX] =
                    router_tx_valid[NEIGHBOR_TX_INDEX];
                assign router_rx_vc[RX_INDEX*VC_WIDTH +: VC_WIDTH] =
                    router_tx_vc[NEIGHBOR_TX_INDEX*VC_WIDTH +: VC_WIDTH];
                assign router_rx_flit[RX_INDEX*FLIT_WIDTH +: FLIT_WIDTH] =
                    router_tx_flit[
                        NEIGHBOR_TX_INDEX*FLIT_WIDTH +: FLIT_WIDTH];
                assign router_tx_credit[TX_INDEX*VCS +: VCS] =
                    router_rx_credit[NEIGHBOR_RX_INDEX*VCS +: VCS];
            end else begin : g_no_north
                localparam int unsigned INDEX =
                    pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_NORTH;
                assign router_rx_valid[INDEX] = 1'b0;
                assign router_rx_vc[INDEX*VC_WIDTH +: VC_WIDTH] = '0;
                assign router_rx_flit[INDEX*FLIT_WIDTH +: FLIT_WIDTH] = '0;
                assign router_tx_credit[INDEX*VCS +: VCS] = '0;
            end

            if (ROW + 1 < npu_noc_pkg::NPU_NOC_ROWS) begin : g_south
                localparam int unsigned RX_INDEX =
                    pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_SOUTH;
                localparam int unsigned NEIGHBOR_TX_INDEX =
                    (pod+npu_noc_pkg::NPU_NOC_COLUMNS)*PORTS +
                    npu_noc_pkg::NPU_NOC_PORT_NORTH;
                localparam int unsigned TX_INDEX = RX_INDEX;
                localparam int unsigned NEIGHBOR_RX_INDEX = NEIGHBOR_TX_INDEX;
                assign router_rx_valid[RX_INDEX] =
                    router_tx_valid[NEIGHBOR_TX_INDEX];
                assign router_rx_vc[RX_INDEX*VC_WIDTH +: VC_WIDTH] =
                    router_tx_vc[NEIGHBOR_TX_INDEX*VC_WIDTH +: VC_WIDTH];
                assign router_rx_flit[RX_INDEX*FLIT_WIDTH +: FLIT_WIDTH] =
                    router_tx_flit[
                        NEIGHBOR_TX_INDEX*FLIT_WIDTH +: FLIT_WIDTH];
                assign router_tx_credit[TX_INDEX*VCS +: VCS] =
                    router_rx_credit[NEIGHBOR_RX_INDEX*VCS +: VCS];
            end else begin : g_no_south
                localparam int unsigned INDEX =
                    pod*PORTS + npu_noc_pkg::NPU_NOC_PORT_SOUTH;
                assign router_rx_valid[INDEX] = 1'b0;
                assign router_rx_vc[INDEX*VC_WIDTH +: VC_WIDTH] = '0;
                assign router_rx_flit[INDEX*FLIT_WIDTH +: FLIT_WIDTH] = '0;
                assign router_tx_credit[INDEX*VCS +: VCS] = '0;
            end

            for (genvar port = 1; port < PORTS; port++) begin : g_cardinal_ready
                assign router_tx_ready[pod*PORTS + port] = 1'b0;
            end

            npu_noc_lane_router #(
                .LOCAL_POD_ID(pod),
                .PAYLOAD_BYTES(PAYLOAD_BYTES),
                .FLIT_WIDTH(FLIT_WIDTH),
                .VCS(VCS),
                .FIFO_DEPTH(FIFO_DEPTH),
                .MAX_PACKET_FLITS(MAX_PACKET_FLITS),
                .AGE_THRESHOLD(AGE_THRESHOLD)
            ) u_router (
                .clk_i,
                .rst_i,
                .clear_i,
                .quiesce_i,
                .port_enable_i(PORT_ENABLE),
                .rx_valid_i(router_rx_valid[pod*PORTS +: PORTS]),
                .rx_ready_o(router_rx_ready[pod*PORTS +: PORTS]),
                .rx_vc_i(router_rx_vc[
                    pod*PORTS*VC_WIDTH +: PORTS*VC_WIDTH]),
                .rx_flit_i(router_rx_flit[
                    pod*PORTS*FLIT_WIDTH +: PORTS*FLIT_WIDTH]),
                .rx_credit_o(router_rx_credit[
                    pod*PORTS*VCS +: PORTS*VCS]),
                .tx_valid_o(router_tx_valid[pod*PORTS +: PORTS]),
                .tx_ready_i(router_tx_ready[pod*PORTS +: PORTS]),
                .tx_vc_o(router_tx_vc[
                    pod*PORTS*VC_WIDTH +: PORTS*VC_WIDTH]),
                .tx_flit_o(router_tx_flit[
                    pod*PORTS*FLIT_WIDTH +: PORTS*FLIT_WIDTH]),
                .tx_credit_i(router_tx_credit[
                    pod*PORTS*VCS +: PORTS*VCS]),
                .busy_o(router_busy_o[pod]),
                .quiesced_o(router_quiesced_o[pod]),
                .protocol_error_o(router_protocol_error_o[pod]),
                .accepted_flits_o(accepted_flits_o[
                    pod*PORTS*64 +: PORTS*64]),
                .transmitted_flits_o(transmitted_flits_o[
                    pod*PORTS*64 +: PORTS*64]),
                .blocked_cycles_o(blocked_cycles_o[
                    pod*PORTS*64 +: PORTS*64]),
                .accepted_packets_o(accepted_packets_o[
                    pod*PORTS*64 +: PORTS*64]),
                .transmitted_packets_o(transmitted_packets_o[
                    pod*PORTS*64 +: PORTS*64]),
                .maximum_wait_cycles_o(maximum_wait_cycles_o[
                    pod*PORTS*64 +: PORTS*64]),
                .credit_low_watermark_o(credit_low_watermark_o[
                    pod*PORTS*64 +: PORTS*64]),
                .invalid_route_events_o(invalid_route_events_o[
                    pod*PORTS*64 +: PORTS*64])
            );
        end
    endgenerate

    assign busy_o = |router_busy_o;
    assign quiesced_o = quiesce_i && (&router_quiesced_o);
    assign protocol_error_o = |router_protocol_error_o;

`ifndef SYNTHESIS
    initial begin
        assert (PODS == npu_noc_pkg::NPU_NOC_PODS &&
                PORTS == npu_noc_pkg::NPU_NOC_PORTS)
            else $error("npu_noc_fabric_mesh geometry must remain 2x4/5-port");
    end
`endif

endmodule

`default_nettype wire
