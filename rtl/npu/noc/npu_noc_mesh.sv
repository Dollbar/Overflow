`timescale 1ns/1ps
`default_nettype none

// Complete synchronous NoC core: one control fabric and two independent data
// fabrics. CDC and client semantics remain outside this clock-domain module.
module npu_noc_mesh #(
    parameter int unsigned PODS = npu_noc_pkg::NPU_NOC_PODS,
    parameter int unsigned DATA_LANES = npu_noc_pkg::NPU_NOC_DATA_LANES,
    parameter int unsigned PORTS = npu_noc_pkg::NPU_NOC_PORTS,
    parameter int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH,
    parameter int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic [PODS-1:0] pod_control_tx_valid_i,
    output logic [PODS-1:0] pod_control_tx_ready_o,
    input  logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_tx_flit_i,
    output logic [PODS-1:0] pod_control_rx_valid_o,
    input  logic [PODS-1:0] pod_control_rx_ready_i,
    output logic [PODS*CONTROL_FLIT_WIDTH-1:0] pod_control_rx_flit_o,

    input  logic [PODS*DATA_LANES-1:0] pod_data_tx_valid_i,
    output logic [PODS*DATA_LANES-1:0] pod_data_tx_ready_o,
    input  logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_tx_flit_i,
    output logic [PODS*DATA_LANES-1:0] pod_data_rx_valid_o,
    input  logic [PODS*DATA_LANES-1:0] pod_data_rx_ready_i,
    output logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_rx_flit_o,

    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o,
    output logic [PODS-1:0] control_router_busy_o,
    output logic [DATA_LANES*PODS-1:0] data_router_busy_o,
    output logic [PODS-1:0] control_router_quiesced_o,
    output logic [DATA_LANES*PODS-1:0] data_router_quiesced_o,
    output logic [PODS-1:0] control_router_protocol_error_o,
    output logic [DATA_LANES*PODS-1:0] data_router_protocol_error_o,
    output logic [PODS*PORTS*64-1:0] control_accepted_flits_o,
    output logic [PODS*PORTS*64-1:0] control_transmitted_flits_o,
    output logic [PODS*PORTS*64-1:0] control_blocked_cycles_o,
    output logic [PODS*PORTS*64-1:0] control_accepted_packets_o,
    output logic [PODS*PORTS*64-1:0] control_transmitted_packets_o,
    output logic [PODS*PORTS*64-1:0] control_maximum_wait_cycles_o,
    output logic [PODS*PORTS*64-1:0] control_credit_low_watermark_o,
    output logic [PODS*PORTS*64-1:0] control_invalid_route_events_o,
    output logic [DATA_LANES*PODS*PORTS*64-1:0] data_accepted_flits_o,
    output logic [DATA_LANES*PODS*PORTS*64-1:0] data_transmitted_flits_o,
    output logic [DATA_LANES*PODS*PORTS*64-1:0] data_blocked_cycles_o,
    output logic [DATA_LANES*PODS*PORTS*64-1:0] data_accepted_packets_o,
    output logic [DATA_LANES*PODS*PORTS*64-1:0] data_transmitted_packets_o,
    output logic [DATA_LANES*PODS*PORTS*64-1:0] data_maximum_wait_cycles_o,
    output logic [DATA_LANES*PODS*PORTS*64-1:0] data_credit_low_watermark_o,
    output logic [DATA_LANES*PODS*PORTS*64-1:0] data_invalid_route_events_o
);

    logic control_busy;
    logic control_quiesced;
    logic control_protocol_error;
    logic [DATA_LANES-1:0] data_busy;
    logic [DATA_LANES-1:0] data_quiesced;
    logic [DATA_LANES-1:0] data_protocol_error;

    npu_noc_fabric_mesh #(
        .PAYLOAD_BYTES(npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_BYTES),
        .FLIT_WIDTH(CONTROL_FLIT_WIDTH),
        .VCS(npu_noc_pkg::NPU_NOC_CONTROL_VCS),
        .FIFO_DEPTH(npu_noc_pkg::NPU_NOC_CONTROL_FIFO_DEPTH),
        .MAX_PACKET_FLITS(npu_noc_pkg::NPU_NOC_CONTROL_PACKET_FLITS)
    ) u_control_fabric (
        .clk_i,
        .rst_i,
        .clear_i,
        .quiesce_i,
        .endpoint_tx_valid_i(pod_control_tx_valid_i),
        .endpoint_tx_ready_o(pod_control_tx_ready_o),
        .endpoint_tx_flit_i(pod_control_tx_flit_i),
        .endpoint_rx_valid_o(pod_control_rx_valid_o),
        .endpoint_rx_ready_i(pod_control_rx_ready_i),
        .endpoint_rx_flit_o(pod_control_rx_flit_o),
        .busy_o(control_busy),
        .quiesced_o(control_quiesced),
        .protocol_error_o(control_protocol_error),
        .router_busy_o(control_router_busy_o),
        .router_quiesced_o(control_router_quiesced_o),
        .router_protocol_error_o(control_router_protocol_error_o),
        .accepted_flits_o(control_accepted_flits_o),
        .transmitted_flits_o(control_transmitted_flits_o),
        .blocked_cycles_o(control_blocked_cycles_o),
        .accepted_packets_o(control_accepted_packets_o),
        .transmitted_packets_o(control_transmitted_packets_o),
        .maximum_wait_cycles_o(control_maximum_wait_cycles_o),
        .credit_low_watermark_o(control_credit_low_watermark_o),
        .invalid_route_events_o(control_invalid_route_events_o)
    );

    generate
        for (genvar lane = 0; lane < DATA_LANES; lane++) begin : g_data_fabric
            logic [PODS-1:0] lane_tx_valid;
            logic [PODS-1:0] lane_tx_ready;
            logic [PODS*DATA_FLIT_WIDTH-1:0] lane_tx_flit;
            logic [PODS-1:0] lane_rx_valid;
            logic [PODS-1:0] lane_rx_ready;
            logic [PODS*DATA_FLIT_WIDTH-1:0] lane_rx_flit;

            for (genvar pod = 0; pod < PODS; pod++) begin : g_endpoint_order
                localparam int unsigned ENDPOINT = pod*DATA_LANES + lane;
                assign lane_tx_valid[pod] = pod_data_tx_valid_i[ENDPOINT];
                assign pod_data_tx_ready_o[ENDPOINT] = lane_tx_ready[pod];
                assign lane_tx_flit[pod*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
                    pod_data_tx_flit_i[
                        ENDPOINT*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH];
                assign pod_data_rx_valid_o[ENDPOINT] = lane_rx_valid[pod];
                assign lane_rx_ready[pod] = pod_data_rx_ready_i[ENDPOINT];
                assign pod_data_rx_flit_o[
                    ENDPOINT*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
                    lane_rx_flit[pod*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH];
            end

            npu_noc_fabric_mesh #(
                .PAYLOAD_BYTES(npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES),
                .FLIT_WIDTH(DATA_FLIT_WIDTH),
                .VCS(npu_noc_pkg::NPU_NOC_DATA_VCS),
                .FIFO_DEPTH(npu_noc_pkg::NPU_NOC_DATA_FIFO_DEPTH),
                .MAX_PACKET_FLITS(npu_noc_pkg::NPU_NOC_DATA_PACKET_FLITS)
            ) u_data_fabric (
                .clk_i,
                .rst_i,
                .clear_i,
                .quiesce_i,
                .endpoint_tx_valid_i(lane_tx_valid),
                .endpoint_tx_ready_o(lane_tx_ready),
                .endpoint_tx_flit_i(lane_tx_flit),
                .endpoint_rx_valid_o(lane_rx_valid),
                .endpoint_rx_ready_i(lane_rx_ready),
                .endpoint_rx_flit_o(lane_rx_flit),
                .busy_o(data_busy[lane]),
                .quiesced_o(data_quiesced[lane]),
                .protocol_error_o(data_protocol_error[lane]),
                .router_busy_o(data_router_busy_o[lane*PODS +: PODS]),
                .router_quiesced_o(data_router_quiesced_o[
                    lane*PODS +: PODS]),
                .router_protocol_error_o(data_router_protocol_error_o[
                    lane*PODS +: PODS]),
                .accepted_flits_o(data_accepted_flits_o[
                    lane*PODS*PORTS*64 +: PODS*PORTS*64]),
                .transmitted_flits_o(data_transmitted_flits_o[
                    lane*PODS*PORTS*64 +: PODS*PORTS*64]),
                .blocked_cycles_o(data_blocked_cycles_o[
                    lane*PODS*PORTS*64 +: PODS*PORTS*64]),
                .accepted_packets_o(data_accepted_packets_o[
                    lane*PODS*PORTS*64 +: PODS*PORTS*64]),
                .transmitted_packets_o(data_transmitted_packets_o[
                    lane*PODS*PORTS*64 +: PODS*PORTS*64]),
                .maximum_wait_cycles_o(data_maximum_wait_cycles_o[
                    lane*PODS*PORTS*64 +: PODS*PORTS*64]),
                .credit_low_watermark_o(data_credit_low_watermark_o[
                    lane*PODS*PORTS*64 +: PODS*PORTS*64]),
                .invalid_route_events_o(data_invalid_route_events_o[
                    lane*PODS*PORTS*64 +: PODS*PORTS*64])
            );
        end
    endgenerate

    assign busy_o = control_busy || (|data_busy);
    assign quiesced_o = quiesce_i && control_quiesced && (&data_quiesced);
    assign protocol_error_o = control_protocol_error ||
        (|data_protocol_error);

endmodule

`default_nettype wire
