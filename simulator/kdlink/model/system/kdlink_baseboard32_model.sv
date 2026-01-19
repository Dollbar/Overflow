module kdlink_baseboard32_model (
    input wire clk_i,
    input wire rst_n_i,
    input wire [7:0] card_present_i,
    input wire [7:0] card_reset_done_i,
    input wire [7:0] plane_enable_i,
    input wire [511:0] endpoint_slice_link_up_i,
    input wire [511:0] endpoint_tx_valid_i,
    output wire [511:0] endpoint_tx_ready_o,
    input wire [327679:0] endpoint_tx_flit_i,
    output wire [511:0] endpoint_rx_valid_o,
    input wire [511:0] endpoint_rx_ready_i,
    output wire [327679:0] endpoint_rx_flit_o,
    output wire [7:0] card_active_o,
    output wire [15:0] protocol_error_o
);
    wire [511:0] qualified_slice_link_up;
    wire [511:0] card_to_fabric_valid;
    wire [511:0] card_to_fabric_ready;
    wire [327679:0] card_to_fabric_flit;
    wire [511:0] fabric_to_card_valid;
    wire [511:0] fabric_to_card_ready;
    wire [327679:0] fabric_to_card_flit;
    genvar node_index;
    genvar plane_index;
    genvar slice_index;
    generate
        for (node_index = 0; node_index < 32; node_index = node_index + 1) begin : g_link_node
            for (plane_index = 0; plane_index < 8; plane_index = plane_index + 1) begin : g_link_plane
                for (slice_index = 0; slice_index < 2; slice_index = slice_index + 1) begin : g_link_slice
                    localparam integer ENDPOINT_INDEX = node_index*16 + plane_index*2 + slice_index;
                    assign qualified_slice_link_up[ENDPOINT_INDEX] =
                        endpoint_slice_link_up_i[ENDPOINT_INDEX] && plane_enable_i[plane_index];
                end
            end
        end
    endgenerate

    genvar card_index;
    generate
        for (card_index = 0; card_index < 8; card_index = card_index + 1) begin : g_card
            kdlink_card_model u_card (
                .card_present_i(card_present_i[card_index]),
                .card_reset_done_i(card_reset_done_i[card_index]),
                .slice_link_up_i(qualified_slice_link_up[card_index*64 +: 64]),
                .local_tx_valid_i(endpoint_tx_valid_i[card_index*64 +: 64]),
                .local_tx_ready_o(endpoint_tx_ready_o[card_index*64 +: 64]),
                .local_tx_flit_i(endpoint_tx_flit_i[card_index*40960 +: 40960]),
                .local_rx_valid_o(endpoint_rx_valid_o[card_index*64 +: 64]),
                .local_rx_ready_i(endpoint_rx_ready_i[card_index*64 +: 64]),
                .local_rx_flit_o(endpoint_rx_flit_o[card_index*40960 +: 40960]),
                .baseboard_tx_valid_o(card_to_fabric_valid[card_index*64 +: 64]),
                .baseboard_tx_ready_i(card_to_fabric_ready[card_index*64 +: 64]),
                .baseboard_tx_flit_o(card_to_fabric_flit[card_index*40960 +: 40960]),
                .baseboard_rx_valid_i(fabric_to_card_valid[card_index*64 +: 64]),
                .baseboard_rx_ready_o(fabric_to_card_ready[card_index*64 +: 64]),
                .baseboard_rx_flit_i(fabric_to_card_flit[card_index*40960 +: 40960]),
                .card_active_o(card_active_o[card_index])
            );
        end
    endgenerate

    kdlink_fabric32 u_fabric (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .endpoint_tx_valid_i(card_to_fabric_valid), .endpoint_tx_ready_o(card_to_fabric_ready),
        .endpoint_tx_flit_i(card_to_fabric_flit),
        .endpoint_rx_valid_o(fabric_to_card_valid), .endpoint_rx_ready_i(fabric_to_card_ready),
        .endpoint_rx_flit_o(fabric_to_card_flit), .protocol_error_o(protocol_error_o)
    );
endmodule
