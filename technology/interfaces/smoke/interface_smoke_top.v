// Apache-2.0 explicit-instance smoke design for the abstract interface cells.
module interface_smoke_top (
    input  wire clk_i,
    input  wire hbm_req_valid_i,
    input  wire hbm_req_write_i,
    input  wire hbm_req_data_i,
    input  wire serdes_tx_valid_i,
    input  wire serdes_tx_block_i,
    output wire hbm_req_ready_o,
    output wire hbm_rsp_valid_o,
    output wire hbm_rsp_error_o,
    output wire hbm_rsp_data_o,
    output wire serdes_rx_valid_o,
    output wire serdes_rx_block_o,
    output wire serdes_link_up_o
);
    OVERFLOW_HBM_PORT_ABSTRACT u_hbm (
        .CLK(clk_i),
        .REQ_VALID(hbm_req_valid_i),
        .REQ_WRITE(hbm_req_write_i),
        .REQ_DATA(hbm_req_data_i),
        .REQ_READY(hbm_req_ready_o),
        .RSP_VALID(hbm_rsp_valid_o),
        .RSP_ERROR(hbm_rsp_error_o),
        .RSP_DATA(hbm_rsp_data_o)
    );

    OVERFLOW_SERDES_SLICE_ABSTRACT u_serdes (
        .CLK(clk_i),
        .TX_VALID(serdes_tx_valid_i),
        .TX_BLOCK(serdes_tx_block_i),
        .RX_VALID(serdes_rx_valid_o),
        .RX_BLOCK(serdes_rx_block_o),
        .LINK_UP(serdes_link_up_o)
    );
endmodule
