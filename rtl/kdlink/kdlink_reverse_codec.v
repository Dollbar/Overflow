`include "kdlink_defs.vh"
module kdlink_reverse_codec (
    input wire clk_i,
    input wire rst_n_i,
    input wire tx_valid_i,
    input wire [3:0] message_type_i,
    input wire [2:0] vc_i,
    input wire [2:0] plane_id_i,
    input wire slice_id_i,
    input wire phase_i,
    input wire [7:0] link_epoch_i,
    input wire [4:0] src_node_i,
    input wire [4:0] dst_node_i,
    input wire [11:0] collective_id_i,
    input wire [11:0] packet_seq_i,
    input wire [7:0] credit_delta_i,
    input wire [15:0] credit_total_i,
    input wire [15:0] ack_bitmap_i,
    input wire [7:0] status_i,
    output wire tx_valid_o,
    output wire [127:0] tx_word_o,
    input wire rx_valid_i,
    input wire [127:0] rx_word_i,
    output wire rx_valid_o,
    output wire rx_crc_good_o,
    output wire [111:0] rx_body_o
);
    reg [111:0] tx_body_d;
    reg [111:0] tx_body_q [0:7];
    reg [111:0] rx_body_q [0:7];
    reg [15:0] tx_crc_q [0:7];
    reg [15:0] rx_crc_q [0:7];
    reg [15:0] rx_expected_q [0:7];
    reg tx_valid_q [0:7];
    reg rx_valid_q [0:7];

    always @(*) begin
        tx_body_d = 112'd0;
        tx_body_d[`KDL_REVERSE_VERSION_LSB +: `KDL_REVERSE_VERSION_WIDTH] = `KDL_SCHEMA_VERSION;
        tx_body_d[`KDL_REVERSE_MESSAGE_TYPE_LSB +: `KDL_REVERSE_MESSAGE_TYPE_WIDTH] = message_type_i;
        tx_body_d[`KDL_REVERSE_VC_LSB +: `KDL_REVERSE_VC_WIDTH] = vc_i;
        tx_body_d[`KDL_REVERSE_PLANE_ID_LSB +: `KDL_REVERSE_PLANE_ID_WIDTH] = plane_id_i;
        tx_body_d[`KDL_REVERSE_SLICE_ID_LSB] = slice_id_i;
        tx_body_d[`KDL_REVERSE_PHASE_LSB] = phase_i;
        tx_body_d[`KDL_REVERSE_LINK_EPOCH_LSB +: `KDL_REVERSE_LINK_EPOCH_WIDTH] = link_epoch_i;
        tx_body_d[`KDL_REVERSE_SRC_NODE_LSB +: `KDL_REVERSE_SRC_NODE_WIDTH] = src_node_i;
        tx_body_d[`KDL_REVERSE_DST_NODE_LSB +: `KDL_REVERSE_DST_NODE_WIDTH] = dst_node_i;
        tx_body_d[`KDL_REVERSE_COLLECTIVE_ID_LSB +: `KDL_REVERSE_COLLECTIVE_ID_WIDTH] = collective_id_i;
        tx_body_d[`KDL_REVERSE_PACKET_SEQ_LSB +: `KDL_REVERSE_PACKET_SEQ_WIDTH] = packet_seq_i;
        tx_body_d[`KDL_REVERSE_CREDIT_DELTA_LSB +: `KDL_REVERSE_CREDIT_DELTA_WIDTH] = credit_delta_i;
        tx_body_d[`KDL_REVERSE_CREDIT_TOTAL_LSB +: `KDL_REVERSE_CREDIT_TOTAL_WIDTH] = credit_total_i;
        tx_body_d[`KDL_REVERSE_ACK_BITMAP_LSB +: `KDL_REVERSE_ACK_BITMAP_WIDTH] = ack_bitmap_i;
        tx_body_d[`KDL_REVERSE_STATUS_LSB +: `KDL_REVERSE_STATUS_WIDTH] = status_i;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tx_body_q[0] <= 112'd0;
            rx_body_q[0] <= 112'd0;
            tx_crc_q[0] <= 16'hFFFF;
            rx_crc_q[0] <= 16'hFFFF;
            rx_expected_q[0] <= 16'd0;
            tx_valid_q[0] <= 1'b0;
            rx_valid_q[0] <= 1'b0;
        end else begin
            tx_body_q[0] <= tx_body_d;
            rx_body_q[0] <= rx_word_i[111:0];
            tx_crc_q[0] <= 16'hFFFF;
            rx_crc_q[0] <= 16'hFFFF;
            rx_expected_q[0] <= rx_word_i[127:112];
            tx_valid_q[0] <= tx_valid_i;
            rx_valid_q[0] <= rx_valid_i;
        end
    end

    genvar stage_index;
    generate
        for (stage_index = 0; stage_index < 7; stage_index = stage_index + 1) begin : g_crc_stage
            wire [15:0] tx_crc_b0;
            wire [15:0] tx_crc_b1;
            wire [15:0] rx_crc_b0;
            wire [15:0] rx_crc_b1;
            coll_crc16_byte u_tx_b0 (.crc_i(tx_crc_q[stage_index]), .data_i(tx_body_q[stage_index][stage_index*16 +: 8]), .crc_o(tx_crc_b0));
            coll_crc16_byte u_tx_b1 (.crc_i(tx_crc_b0), .data_i(tx_body_q[stage_index][stage_index*16+8 +: 8]), .crc_o(tx_crc_b1));
            coll_crc16_byte u_rx_b0 (.crc_i(rx_crc_q[stage_index]), .data_i(rx_body_q[stage_index][stage_index*16 +: 8]), .crc_o(rx_crc_b0));
            coll_crc16_byte u_rx_b1 (.crc_i(rx_crc_b0), .data_i(rx_body_q[stage_index][stage_index*16+8 +: 8]), .crc_o(rx_crc_b1));
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    tx_body_q[stage_index+1] <= 112'd0;
                    rx_body_q[stage_index+1] <= 112'd0;
                    tx_crc_q[stage_index+1] <= 16'hFFFF;
                    rx_crc_q[stage_index+1] <= 16'hFFFF;
                    rx_expected_q[stage_index+1] <= 16'd0;
                    tx_valid_q[stage_index+1] <= 1'b0;
                    rx_valid_q[stage_index+1] <= 1'b0;
                end else begin
                    tx_body_q[stage_index+1] <= tx_body_q[stage_index];
                    rx_body_q[stage_index+1] <= rx_body_q[stage_index];
                    tx_crc_q[stage_index+1] <= tx_crc_b1;
                    rx_crc_q[stage_index+1] <= rx_crc_b1;
                    rx_expected_q[stage_index+1] <= rx_expected_q[stage_index];
                    tx_valid_q[stage_index+1] <= tx_valid_q[stage_index];
                    rx_valid_q[stage_index+1] <= rx_valid_q[stage_index];
                end
            end
        end
    endgenerate

    assign tx_valid_o = tx_valid_q[7];
    assign tx_word_o = {tx_crc_q[7], tx_body_q[7]};
    assign rx_valid_o = rx_valid_q[7];
    assign rx_crc_good_o = rx_crc_q[7] == rx_expected_q[7];
    assign rx_body_o = rx_body_q[7];
endmodule
