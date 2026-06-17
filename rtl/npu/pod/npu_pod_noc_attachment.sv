`timescale 1ns/1ps
`default_nettype none

// Versioned synchronous attachment between future Pod packet clients and a
// separately owned NoC router. Payload interpretation and all router logic are
// intentionally absent from this module.
module npu_pod_noc_attachment #(
    parameter int unsigned POD_ID = 0,
    parameter int unsigned DATA_LANES =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_LANES,
    parameter int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH,
    parameter int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic clear_i,
    input  logic quiesce_i,

    input  logic pod_control_tx_valid_i,
    output logic pod_control_tx_ready_o,
    input  logic [CONTROL_FLIT_WIDTH-1:0] pod_control_tx_flit_i,
    output logic noc_control_tx_valid_o,
    input  logic noc_control_tx_ready_i,
    output logic [CONTROL_FLIT_WIDTH-1:0] noc_control_tx_flit_o,

    input  logic [DATA_LANES-1:0] pod_data_tx_valid_i,
    output logic [DATA_LANES-1:0] pod_data_tx_ready_o,
    input  logic [DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_tx_flit_i,
    output logic [DATA_LANES-1:0] noc_data_tx_valid_o,
    input  logic [DATA_LANES-1:0] noc_data_tx_ready_i,
    output logic [DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_tx_flit_o,

    input  logic noc_control_rx_valid_i,
    output logic noc_control_rx_ready_o,
    input  logic [CONTROL_FLIT_WIDTH-1:0] noc_control_rx_flit_i,
    output logic pod_control_rx_valid_o,
    input  logic pod_control_rx_ready_i,
    output logic [CONTROL_FLIT_WIDTH-1:0] pod_control_rx_flit_o,

    input  logic [DATA_LANES-1:0] noc_data_rx_valid_i,
    output logic [DATA_LANES-1:0] noc_data_rx_ready_o,
    input  logic [DATA_LANES*DATA_FLIT_WIDTH-1:0] noc_data_rx_flit_i,
    output logic [DATA_LANES-1:0] pod_data_rx_valid_o,
    input  logic [DATA_LANES-1:0] pod_data_rx_ready_i,
    output logic [DATA_LANES*DATA_FLIT_WIDTH-1:0] pod_data_rx_flit_o,

    output logic busy_o,
    output logic quiesced_o,
    output logic protocol_error_o,
    output logic control_tx_busy_o,
    output logic [DATA_LANES-1:0] data_tx_busy_o,
    output logic control_rx_busy_o,
    output logic [DATA_LANES-1:0] data_rx_busy_o
);

    localparam logic [npu_pod_noc_pkg::NPU_POD_NOC_POD_ID_WIDTH-1:0]
        LOCAL_POD_ID = POD_ID[
            npu_pod_noc_pkg::NPU_POD_NOC_POD_ID_WIDTH-1:0];

    logic control_tx_quiesced;
    logic control_tx_protocol_error;
    logic control_rx_quiesced;
    logic control_rx_protocol_error;
    logic [DATA_LANES-1:0] data_tx_quiesced;
    logic [DATA_LANES-1:0] data_tx_protocol_error;
    logic [DATA_LANES-1:0] data_rx_quiesced;
    logic [DATA_LANES-1:0] data_rx_protocol_error;
    logic parameter_configuration_error;

    assign parameter_configuration_error =
        (POD_ID >= npu_pod_noc_pkg::NPU_POD_NOC_POD_COUNT) ||
        (DATA_LANES != npu_pod_noc_pkg::NPU_POD_NOC_DATA_LANES) ||
        (CONTROL_FLIT_WIDTH !=
         npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH) ||
        (DATA_FLIT_WIDTH != npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH);

    npu_pod_noc_link_slice #(
        .PAYLOAD_BYTES(npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_BYTES),
        .PROTOCOL_VERSION(npu_pod_noc_pkg::NPU_POD_NOC_VERSION),
        .LOCAL_POD_ID(LOCAL_POD_ID),
        .CHECK_LOCAL_SOURCE(1'b1),
        .FLIT_WIDTH(CONTROL_FLIT_WIDTH)
    ) u_control_tx_slice (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .quiesce_i(quiesce_i),
        .source_valid_i(pod_control_tx_valid_i),
        .source_ready_o(pod_control_tx_ready_o),
        .source_flit_i(pod_control_tx_flit_i),
        .sink_valid_o(noc_control_tx_valid_o),
        .sink_ready_i(noc_control_tx_ready_i),
        .sink_flit_o(noc_control_tx_flit_o),
        .busy_o(control_tx_busy_o),
        .quiesced_o(control_tx_quiesced),
        .protocol_error_o(control_tx_protocol_error)
    );

    npu_pod_noc_link_slice #(
        .PAYLOAD_BYTES(npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_BYTES),
        .PROTOCOL_VERSION(npu_pod_noc_pkg::NPU_POD_NOC_VERSION),
        .LOCAL_POD_ID(LOCAL_POD_ID),
        .CHECK_LOCAL_SOURCE(1'b0),
        .FLIT_WIDTH(CONTROL_FLIT_WIDTH)
    ) u_control_rx_slice (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .quiesce_i(quiesce_i),
        .source_valid_i(noc_control_rx_valid_i),
        .source_ready_o(noc_control_rx_ready_o),
        .source_flit_i(noc_control_rx_flit_i),
        .sink_valid_o(pod_control_rx_valid_o),
        .sink_ready_i(pod_control_rx_ready_i),
        .sink_flit_o(pod_control_rx_flit_o),
        .busy_o(control_rx_busy_o),
        .quiesced_o(control_rx_quiesced),
        .protocol_error_o(control_rx_protocol_error)
    );

    generate
        for (genvar lane = 0; lane < DATA_LANES; lane++) begin : gen_data_lanes
            npu_pod_noc_link_slice #(
                .PAYLOAD_BYTES(npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES),
                .PROTOCOL_VERSION(npu_pod_noc_pkg::NPU_POD_NOC_VERSION),
                .LOCAL_POD_ID(LOCAL_POD_ID),
                .CHECK_LOCAL_SOURCE(1'b1),
                .FLIT_WIDTH(DATA_FLIT_WIDTH)
            ) u_data_tx_slice (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .clear_i(clear_i),
                .quiesce_i(quiesce_i),
                .source_valid_i(pod_data_tx_valid_i[lane]),
                .source_ready_o(pod_data_tx_ready_o[lane]),
                .source_flit_i(pod_data_tx_flit_i[
                    lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH]),
                .sink_valid_o(noc_data_tx_valid_o[lane]),
                .sink_ready_i(noc_data_tx_ready_i[lane]),
                .sink_flit_o(noc_data_tx_flit_o[
                    lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH]),
                .busy_o(data_tx_busy_o[lane]),
                .quiesced_o(data_tx_quiesced[lane]),
                .protocol_error_o(data_tx_protocol_error[lane])
            );

            npu_pod_noc_link_slice #(
                .PAYLOAD_BYTES(npu_pod_noc_pkg::NPU_POD_NOC_DATA_BYTES),
                .PROTOCOL_VERSION(npu_pod_noc_pkg::NPU_POD_NOC_VERSION),
                .LOCAL_POD_ID(LOCAL_POD_ID),
                .CHECK_LOCAL_SOURCE(1'b0),
                .FLIT_WIDTH(DATA_FLIT_WIDTH)
            ) u_data_rx_slice (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .clear_i(clear_i),
                .quiesce_i(quiesce_i),
                .source_valid_i(noc_data_rx_valid_i[lane]),
                .source_ready_o(noc_data_rx_ready_o[lane]),
                .source_flit_i(noc_data_rx_flit_i[
                    lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH]),
                .sink_valid_o(pod_data_rx_valid_o[lane]),
                .sink_ready_i(pod_data_rx_ready_i[lane]),
                .sink_flit_o(pod_data_rx_flit_o[
                    lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH]),
                .busy_o(data_rx_busy_o[lane]),
                .quiesced_o(data_rx_quiesced[lane]),
                .protocol_error_o(data_rx_protocol_error[lane])
            );
        end
    endgenerate

    assign busy_o = control_tx_busy_o || control_rx_busy_o ||
                    (|data_tx_busy_o) || (|data_rx_busy_o);
    assign quiesced_o = control_tx_quiesced && control_rx_quiesced &&
                        (&data_tx_quiesced) && (&data_rx_quiesced);
    assign protocol_error_o = parameter_configuration_error ||
                              control_tx_protocol_error ||
                              control_rx_protocol_error ||
                              (|data_tx_protocol_error) ||
                              (|data_rx_protocol_error);

endmodule

`default_nettype wire
