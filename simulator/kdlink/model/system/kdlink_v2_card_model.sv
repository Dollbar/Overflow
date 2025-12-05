module kdlink_v2_card_model #(
    parameter integer FLIT_WIDTH = 640,
    parameter integer SLICES_PER_CARD = 64
) (
    input wire card_present_i,
    input wire card_reset_done_i,
    input wire [SLICES_PER_CARD-1:0] slice_link_up_i,
    input wire [SLICES_PER_CARD-1:0] local_tx_valid_i,
    output wire [SLICES_PER_CARD-1:0] local_tx_ready_o,
    input wire [SLICES_PER_CARD*FLIT_WIDTH-1:0] local_tx_flit_i,
    output wire [SLICES_PER_CARD-1:0] local_rx_valid_o,
    input wire [SLICES_PER_CARD-1:0] local_rx_ready_i,
    output wire [SLICES_PER_CARD*FLIT_WIDTH-1:0] local_rx_flit_o,
    output wire [SLICES_PER_CARD-1:0] baseboard_tx_valid_o,
    input wire [SLICES_PER_CARD-1:0] baseboard_tx_ready_i,
    output wire [SLICES_PER_CARD*FLIT_WIDTH-1:0] baseboard_tx_flit_o,
    input wire [SLICES_PER_CARD-1:0] baseboard_rx_valid_i,
    output wire [SLICES_PER_CARD-1:0] baseboard_rx_ready_o,
    input wire [SLICES_PER_CARD*FLIT_WIDTH-1:0] baseboard_rx_flit_i,
    output wire card_active_o
);
    wire [SLICES_PER_CARD-1:0] active_slice;
    assign card_active_o = card_present_i && card_reset_done_i;
    assign active_slice = slice_link_up_i & {SLICES_PER_CARD{card_active_o}};
    assign baseboard_tx_valid_o = local_tx_valid_i & active_slice;
    assign local_tx_ready_o = baseboard_tx_ready_i & active_slice;
    assign baseboard_tx_flit_o = local_tx_flit_i;
    assign local_rx_valid_o = baseboard_rx_valid_i & active_slice;
    assign baseboard_rx_ready_o = local_rx_ready_i & active_slice;
    assign local_rx_flit_o = baseboard_rx_flit_i;
endmodule
