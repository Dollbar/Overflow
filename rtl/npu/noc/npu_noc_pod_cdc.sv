`timescale 1ns/1ps
`default_nettype none

// Four logical Pod/NoC directions crossed as one control FIFO and two data
// FIFOs in each direction. Resets must be paired and safely released locally.
module npu_noc_pod_cdc #(
    parameter int unsigned DATA_LANES = npu_noc_pkg::NPU_NOC_DATA_LANES,
    parameter int unsigned CONTROL_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_CONTROL_FLIT_WIDTH,
    parameter int unsigned DATA_FLIT_WIDTH =
        npu_pod_noc_pkg::NPU_POD_NOC_DATA_FLIT_WIDTH,
    parameter int unsigned CONTROL_CDC_WIDTH =
        npu_noc_pkg::NPU_NOC_CONTROL_CDC_WIDTH,
    parameter int unsigned DATA_CDC_WIDTH =
        npu_noc_pkg::NPU_NOC_DATA_CDC_WIDTH
) (
    input  logic pod_clk_i,
    input  logic pod_rst_i,
    input  logic noc_clk_i,
    input  logic noc_rst_i,

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

    output logic pod_busy_o,
    output logic noc_busy_o,
    output logic pod_quiesced_o,
    output logic noc_quiesced_o,
    output logic protocol_error_o
);

    localparam int unsigned CONTROL_PAD =
        CONTROL_CDC_WIDTH - CONTROL_FLIT_WIDTH;
    localparam int unsigned DATA_PAD = DATA_CDC_WIDTH - DATA_FLIT_WIDTH;

    logic [CONTROL_CDC_WIDTH-1:0] control_tx_read_data;
    logic [CONTROL_CDC_WIDTH-1:0] control_rx_read_data;
    logic control_tx_write_empty;
    logic control_tx_read_empty;
    logic control_rx_write_empty;
    logic control_rx_read_empty;
    logic control_tx_write_full;
    logic control_rx_write_full;
    logic control_tx_configuration_error;
    logic control_rx_configuration_error;
    logic [DATA_LANES*DATA_CDC_WIDTH-1:0] data_tx_read_data;
    logic [DATA_LANES*DATA_CDC_WIDTH-1:0] data_rx_read_data;
    logic [DATA_LANES-1:0] data_tx_write_empty;
    logic [DATA_LANES-1:0] data_tx_read_empty;
    logic [DATA_LANES-1:0] data_rx_write_empty;
    logic [DATA_LANES-1:0] data_rx_read_empty;
    logic [DATA_LANES-1:0] data_tx_write_full;
    logic [DATA_LANES-1:0] data_rx_write_full;
    logic [DATA_LANES-1:0] data_tx_configuration_error;
    logic [DATA_LANES-1:0] data_rx_configuration_error;

    npu_noc_async_fifo #(
        .WIDTH(CONTROL_CDC_WIDTH),
        .DEPTH(npu_noc_pkg::NPU_NOC_CONTROL_CDC_DEPTH)
    ) u_control_tx_fifo (
        .write_clk_i(pod_clk_i),
        .write_rst_i(pod_rst_i),
        .write_valid_i(pod_control_tx_valid_i),
        .write_ready_o(pod_control_tx_ready_o),
        .write_data_i({{CONTROL_PAD{1'b0}}, pod_control_tx_flit_i}),
        .write_full_o(control_tx_write_full),
        .write_empty_o(control_tx_write_empty),
        .read_clk_i(noc_clk_i),
        .read_rst_i(noc_rst_i),
        .read_valid_o(noc_control_tx_valid_o),
        .read_ready_i(noc_control_tx_ready_i),
        .read_data_o(control_tx_read_data),
        .read_empty_o(control_tx_read_empty),
        .configuration_error_o(control_tx_configuration_error)
    );
    assign noc_control_tx_flit_o = control_tx_read_data[
        CONTROL_FLIT_WIDTH-1:0];

    npu_noc_async_fifo #(
        .WIDTH(CONTROL_CDC_WIDTH),
        .DEPTH(npu_noc_pkg::NPU_NOC_CONTROL_CDC_DEPTH)
    ) u_control_rx_fifo (
        .write_clk_i(noc_clk_i),
        .write_rst_i(noc_rst_i),
        .write_valid_i(noc_control_rx_valid_i),
        .write_ready_o(noc_control_rx_ready_o),
        .write_data_i({{CONTROL_PAD{1'b0}}, noc_control_rx_flit_i}),
        .write_full_o(control_rx_write_full),
        .write_empty_o(control_rx_write_empty),
        .read_clk_i(pod_clk_i),
        .read_rst_i(pod_rst_i),
        .read_valid_o(pod_control_rx_valid_o),
        .read_ready_i(pod_control_rx_ready_i),
        .read_data_o(control_rx_read_data),
        .read_empty_o(control_rx_read_empty),
        .configuration_error_o(control_rx_configuration_error)
    );
    assign pod_control_rx_flit_o = control_rx_read_data[
        CONTROL_FLIT_WIDTH-1:0];

    generate
        for (genvar lane = 0; lane < DATA_LANES; lane++) begin : g_data_cdc
            npu_noc_async_fifo #(
                .WIDTH(DATA_CDC_WIDTH),
                .DEPTH(npu_noc_pkg::NPU_NOC_DATA_CDC_DEPTH)
            ) u_data_tx_fifo (
                .write_clk_i(pod_clk_i),
                .write_rst_i(pod_rst_i),
                .write_valid_i(pod_data_tx_valid_i[lane]),
                .write_ready_o(pod_data_tx_ready_o[lane]),
                .write_data_i({{DATA_PAD{1'b0}}, pod_data_tx_flit_i[
                    lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH]}),
                .write_full_o(data_tx_write_full[lane]),
                .write_empty_o(data_tx_write_empty[lane]),
                .read_clk_i(noc_clk_i),
                .read_rst_i(noc_rst_i),
                .read_valid_o(noc_data_tx_valid_o[lane]),
                .read_ready_i(noc_data_tx_ready_i[lane]),
                .read_data_o(data_tx_read_data[
                    lane*DATA_CDC_WIDTH +: DATA_CDC_WIDTH]),
                .read_empty_o(data_tx_read_empty[lane]),
                .configuration_error_o(data_tx_configuration_error[lane])
            );
            assign noc_data_tx_flit_o[
                lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
                data_tx_read_data[lane*DATA_CDC_WIDTH +: DATA_FLIT_WIDTH];

            npu_noc_async_fifo #(
                .WIDTH(DATA_CDC_WIDTH),
                .DEPTH(npu_noc_pkg::NPU_NOC_DATA_CDC_DEPTH)
            ) u_data_rx_fifo (
                .write_clk_i(noc_clk_i),
                .write_rst_i(noc_rst_i),
                .write_valid_i(noc_data_rx_valid_i[lane]),
                .write_ready_o(noc_data_rx_ready_o[lane]),
                .write_data_i({{DATA_PAD{1'b0}}, noc_data_rx_flit_i[
                    lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH]}),
                .write_full_o(data_rx_write_full[lane]),
                .write_empty_o(data_rx_write_empty[lane]),
                .read_clk_i(pod_clk_i),
                .read_rst_i(pod_rst_i),
                .read_valid_o(pod_data_rx_valid_o[lane]),
                .read_ready_i(pod_data_rx_ready_i[lane]),
                .read_data_o(data_rx_read_data[
                    lane*DATA_CDC_WIDTH +: DATA_CDC_WIDTH]),
                .read_empty_o(data_rx_read_empty[lane]),
                .configuration_error_o(data_rx_configuration_error[lane])
            );
            assign pod_data_rx_flit_o[
                lane*DATA_FLIT_WIDTH +: DATA_FLIT_WIDTH] =
                data_rx_read_data[lane*DATA_CDC_WIDTH +: DATA_FLIT_WIDTH];
        end
    endgenerate

    assign pod_busy_o = !control_tx_write_empty || !control_rx_read_empty ||
        !(&data_tx_write_empty) || !(&data_rx_read_empty);
    assign noc_busy_o = !control_tx_read_empty || !control_rx_write_empty ||
        !(&data_tx_read_empty) || !(&data_rx_write_empty);
    assign pod_quiesced_o = !pod_busy_o;
    assign noc_quiesced_o = !noc_busy_o;
    assign protocol_error_o = control_tx_configuration_error ||
        control_rx_configuration_error || (|data_tx_configuration_error) ||
        (|data_rx_configuration_error) ||
        (noc_control_tx_valid_o &&
         (|control_tx_read_data[CONTROL_CDC_WIDTH-1 -: CONTROL_PAD])) ||
        (pod_control_rx_valid_o &&
         (|control_rx_read_data[CONTROL_CDC_WIDTH-1 -: CONTROL_PAD])) ||
        (noc_data_tx_valid_o[0] &&
         (|data_tx_read_data[DATA_CDC_WIDTH-1 -: DATA_PAD])) ||
        (noc_data_tx_valid_o[1] &&
         (|data_tx_read_data[2*DATA_CDC_WIDTH-1 -: DATA_PAD])) ||
        (pod_data_rx_valid_o[0] &&
         (|data_rx_read_data[DATA_CDC_WIDTH-1 -: DATA_PAD])) ||
        (pod_data_rx_valid_o[1] &&
         (|data_rx_read_data[2*DATA_CDC_WIDTH-1 -: DATA_PAD])) ||
        (CONTROL_CDC_WIDTH != npu_noc_pkg::NPU_NOC_CONTROL_CDC_WIDTH) ||
        (DATA_CDC_WIDTH != npu_noc_pkg::NPU_NOC_DATA_CDC_WIDTH);

    wire _unused_full_status = &{1'b0, control_tx_write_full,
        control_rx_write_full, data_tx_write_full, data_rx_write_full};

endmodule

`default_nettype wire
