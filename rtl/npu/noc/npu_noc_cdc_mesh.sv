`timescale 1ns/1ps
`default_nettype none

// Eight independently clocked Pod attachments, their paired CDC FIFOs, and
// the synchronous control/two-lane data Mesh. Client payloads remain opaque.
module npu_noc_cdc_mesh #(
    parameter int unsigned PODS = npu_noc_pkg::NPU_NOC_PODS,
    parameter int unsigned DATA_LANES = npu_noc_pkg::NPU_NOC_DATA_LANES,
    parameter int unsigned PORTS = npu_noc_pkg::NPU_NOC_PORTS,
    parameter int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH,
    parameter int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH
) (
    input  logic [PODS-1:0] pod_clk_i,
    input  logic noc_clk_i,
    input  logic async_rst_i,
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

    output logic [PODS-1:0] pod_rst_o,
    output logic noc_rst_o,
    output logic [PODS-1:0] pod_quiesce_o,
    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o,
    output logic [PODS-1:0] pod_cdc_busy_o,
    output logic [PODS-1:0] noc_cdc_busy_o,
    output logic [PODS-1:0] control_router_busy_o,
    output logic [DATA_LANES*PODS-1:0] data_router_busy_o,
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

    // noc_rst_o is intentionally an asynchronously asserted/synchronously
    // released reset for CDC controls and a sampled reset for Mesh state.
    /* verilator lint_off SYNCASYNCNET */

    logic reset_event;
    logic noc_quiesce;
    logic [PODS-1:0] pod_cdc_quiesced;
    logic [PODS-1:0] noc_cdc_quiesced;
    logic [PODS-1:0] cdc_protocol_error;
    logic [PODS-1:0] pod_busy_noc_sync;
    logic [PODS-1:0] pod_quiesced_noc_sync;

    logic [PODS-1:0] noc_control_tx_valid;
    logic [PODS-1:0] noc_control_tx_ready;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] noc_control_tx_flit;
    logic [PODS-1:0] noc_control_rx_valid;
    logic [PODS-1:0] noc_control_rx_ready;
    logic [PODS*CONTROL_FLIT_WIDTH-1:0] noc_control_rx_flit;
    logic [PODS*DATA_LANES-1:0] noc_data_tx_valid;
    logic [PODS*DATA_LANES-1:0] noc_data_tx_ready;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_tx_flit;
    logic [PODS*DATA_LANES-1:0] noc_data_rx_valid;
    logic [PODS*DATA_LANES-1:0] noc_data_rx_ready;
    logic [PODS*DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_rx_flit;

    logic mesh_busy;
    logic mesh_quiesced;
    logic mesh_protocol_error;
    logic [PODS-1:0] control_router_quiesced;
    logic [DATA_LANES*PODS-1:0] data_router_quiesced;
    logic drain_candidate;
    logic [2:0] drain_stable_count_q;

    assign reset_event = async_rst_i || clear_i;

    npu_noc_reset_sync u_noc_reset_sync (
        .clk_i(noc_clk_i),
        .async_rst_i(reset_event),
        .sync_rst_o(noc_rst_o)
    );

    npu_noc_level_sync u_noc_quiesce_sync (
        .clk_i(noc_clk_i),
        .rst_i(noc_rst_o),
        .async_level_i(quiesce_i),
        .sync_level_o(noc_quiesce)
    );

    generate
        for (genvar pod = 0; pod < PODS; pod++) begin : g_pod_cdc
            npu_noc_reset_sync u_pod_reset_sync (
                .clk_i(pod_clk_i[pod]),
                .async_rst_i(reset_event),
                .sync_rst_o(pod_rst_o[pod])
            );

            npu_noc_level_sync u_pod_quiesce_sync (
                .clk_i(pod_clk_i[pod]),
                .rst_i(pod_rst_o[pod]),
                .async_level_i(quiesce_i),
                .sync_level_o(pod_quiesce_o[pod])
            );

            npu_noc_pod_cdc u_pod_cdc (
                .pod_clk_i(pod_clk_i[pod]),
                .pod_rst_i(pod_rst_o[pod]),
                .noc_clk_i(noc_clk_i),
                .noc_rst_i(noc_rst_o),
                .pod_control_tx_valid_i(pod_control_tx_valid_i[pod]),
                .pod_control_tx_ready_o(pod_control_tx_ready_o[pod]),
                .pod_control_tx_flit_i(pod_control_tx_flit_i[
                    pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]),
                .noc_control_tx_valid_o(noc_control_tx_valid[pod]),
                .noc_control_tx_ready_i(noc_control_tx_ready[pod]),
                .noc_control_tx_flit_o(noc_control_tx_flit[
                    pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]),
                .pod_data_tx_valid_i(pod_data_tx_valid_i[
                    pod*DATA_LANES +: DATA_LANES]),
                .pod_data_tx_ready_o(pod_data_tx_ready_o[
                    pod*DATA_LANES +: DATA_LANES]),
                .pod_data_tx_flit_i(pod_data_tx_flit_i[
                    pod*DATA_LANES*DATA_FLIT_WIDTH +:
                    DATA_LANES*DATA_FLIT_WIDTH]),
                .noc_data_tx_valid_o(noc_data_tx_valid[
                    pod*DATA_LANES +: DATA_LANES]),
                .noc_data_tx_ready_i(noc_data_tx_ready[
                    pod*DATA_LANES +: DATA_LANES]),
                .noc_data_tx_flit_o(noc_data_tx_flit[
                    pod*DATA_LANES*DATA_FLIT_WIDTH +:
                    DATA_LANES*DATA_FLIT_WIDTH]),
                .noc_control_rx_valid_i(noc_control_rx_valid[pod]),
                .noc_control_rx_ready_o(noc_control_rx_ready[pod]),
                .noc_control_rx_flit_i(noc_control_rx_flit[
                    pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]),
                .pod_control_rx_valid_o(pod_control_rx_valid_o[pod]),
                .pod_control_rx_ready_i(pod_control_rx_ready_i[pod]),
                .pod_control_rx_flit_o(pod_control_rx_flit_o[
                    pod*CONTROL_FLIT_WIDTH +: CONTROL_FLIT_WIDTH]),
                .noc_data_rx_valid_i(noc_data_rx_valid[
                    pod*DATA_LANES +: DATA_LANES]),
                .noc_data_rx_ready_o(noc_data_rx_ready[
                    pod*DATA_LANES +: DATA_LANES]),
                .noc_data_rx_flit_i(noc_data_rx_flit[
                    pod*DATA_LANES*DATA_FLIT_WIDTH +:
                    DATA_LANES*DATA_FLIT_WIDTH]),
                .pod_data_rx_valid_o(pod_data_rx_valid_o[
                    pod*DATA_LANES +: DATA_LANES]),
                .pod_data_rx_ready_i(pod_data_rx_ready_i[
                    pod*DATA_LANES +: DATA_LANES]),
                .pod_data_rx_flit_o(pod_data_rx_flit_o[
                    pod*DATA_LANES*DATA_FLIT_WIDTH +:
                    DATA_LANES*DATA_FLIT_WIDTH]),
                .pod_busy_o(pod_cdc_busy_o[pod]),
                .noc_busy_o(noc_cdc_busy_o[pod]),
                .pod_quiesced_o(pod_cdc_quiesced[pod]),
                .noc_quiesced_o(noc_cdc_quiesced[pod]),
                .protocol_error_o(cdc_protocol_error[pod])
            );

            npu_noc_level_sync u_pod_busy_to_noc_sync (
                .clk_i(noc_clk_i),
                .rst_i(noc_rst_o),
                .async_level_i(pod_cdc_busy_o[pod]),
                .sync_level_o(pod_busy_noc_sync[pod])
            );

            npu_noc_level_sync #(
                .RESET_VALUE(1'b1)
            ) u_pod_quiesced_to_noc_sync (
                .clk_i(noc_clk_i),
                .rst_i(noc_rst_o),
                .async_level_i(pod_cdc_quiesced[pod]),
                .sync_level_o(pod_quiesced_noc_sync[pod])
            );
        end
    endgenerate

    npu_noc_mesh u_mesh (
        .clk_i(noc_clk_i),
        .rst_i(noc_rst_o),
        .clear_i(1'b0),
        .quiesce_i(noc_quiesce),
        .pod_control_tx_valid_i(noc_control_tx_valid),
        .pod_control_tx_ready_o(noc_control_tx_ready),
        .pod_control_tx_flit_i(noc_control_tx_flit),
        .pod_control_rx_valid_o(noc_control_rx_valid),
        .pod_control_rx_ready_i(noc_control_rx_ready),
        .pod_control_rx_flit_o(noc_control_rx_flit),
        .pod_data_tx_valid_i(noc_data_tx_valid),
        .pod_data_tx_ready_o(noc_data_tx_ready),
        .pod_data_tx_flit_i(noc_data_tx_flit),
        .pod_data_rx_valid_o(noc_data_rx_valid),
        .pod_data_rx_ready_i(noc_data_rx_ready),
        .pod_data_rx_flit_o(noc_data_rx_flit),
        .busy_o(mesh_busy),
        .quiesced_o(mesh_quiesced),
        .protocol_error_o(mesh_protocol_error),
        .control_router_busy_o(control_router_busy_o),
        .data_router_busy_o(data_router_busy_o),
        .control_router_quiesced_o(control_router_quiesced),
        .data_router_quiesced_o(data_router_quiesced),
        .control_router_protocol_error_o(
            control_router_protocol_error_o),
        .data_router_protocol_error_o(data_router_protocol_error_o),
        .control_accepted_flits_o(control_accepted_flits_o),
        .control_transmitted_flits_o(control_transmitted_flits_o),
        .control_blocked_cycles_o(control_blocked_cycles_o),
        .control_accepted_packets_o(control_accepted_packets_o),
        .control_transmitted_packets_o(control_transmitted_packets_o),
        .control_maximum_wait_cycles_o(control_maximum_wait_cycles_o),
        .control_credit_low_watermark_o(control_credit_low_watermark_o),
        .control_invalid_route_events_o(control_invalid_route_events_o),
        .data_accepted_flits_o(data_accepted_flits_o),
        .data_transmitted_flits_o(data_transmitted_flits_o),
        .data_blocked_cycles_o(data_blocked_cycles_o),
        .data_accepted_packets_o(data_accepted_packets_o),
        .data_transmitted_packets_o(data_transmitted_packets_o),
        .data_maximum_wait_cycles_o(data_maximum_wait_cycles_o),
        .data_credit_low_watermark_o(data_credit_low_watermark_o),
        .data_invalid_route_events_o(data_invalid_route_events_o)
    );

    assign drain_candidate = noc_quiesce && mesh_quiesced &&
        (&noc_cdc_quiesced) && (&pod_quiesced_noc_sync);

    always_ff @(posedge noc_clk_i or posedge noc_rst_o) begin
        if (noc_rst_o) begin
            drain_stable_count_q <= '0;
        end else if (!drain_candidate) begin
            drain_stable_count_q <= '0;
        end else if (drain_stable_count_q < 3'd4) begin
            drain_stable_count_q <= drain_stable_count_q + 1'b1;
        end
    end

    assign busy_o = mesh_busy || (|noc_cdc_busy_o) ||
        (|pod_busy_noc_sync);
    assign quiesced_o = drain_stable_count_q == 3'd4;
    assign protocol_error_o = mesh_protocol_error ||
        (|cdc_protocol_error) || (PODS != npu_noc_pkg::NPU_NOC_PODS) ||
        (DATA_LANES != npu_noc_pkg::NPU_NOC_DATA_LANES);

    wire _unused_router_quiesced = &{1'b0, control_router_quiesced,
        data_router_quiesced};

    /* verilator lint_on SYNCASYNCNET */

endmodule

`default_nettype wire
