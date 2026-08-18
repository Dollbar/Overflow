module kdlink_v2_pcs ( // 定义单 slice 全双工数字 PCS 边界
    input wire clk_i, // 接收 PCS 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire tx_flit_valid_i, // 接收 TX logical flit 有效位
    input wire [639:0] tx_flit_i, // 接收 TX logical flit
    input wire tx_training_i, // 接收 TX training 请求
    input wire tx_alignment_marker_i, // 接收 TX alignment marker 请求
    input wire [15:0] tx_marker_sequence_i, // 接收 TX marker sequence
    output wire tx_blocks_valid_o, // 输出 TX 十 lane block group 有效位
    output wire [659:0] tx_blocks_o, // 输出 TX 十个 66-bit block
    input wire [9:0] rx_lane_valid_i, // 接收 RX 十 lane 独立有效位
    input wire [659:0] rx_lane_blocks_i, // 接收 RX 十 lane block
    output wire rx_flit_valid_o, // 输出 RX logical flit 有效位
    output wire [639:0] rx_flit_o, // 输出 RX logical flit
    output wire rx_block_lock_o, // 输出 RX block lock
    output wire rx_deskew_locked_o, // 输出 RX deskew lock
    output wire rx_block_error_o, // 输出 RX block error
    output wire rx_deskew_overflow_o // 输出 RX deskew overflow
); // 结束端口声明
    kdlink_v2_pcs_tx u_tx ( // 实例化数字 PCS 发送器
        .clk_i(clk_i), .rst_n_i(rst_n_i), .flit_valid_i(tx_flit_valid_i), .flit_i(tx_flit_i), .training_i(tx_training_i), .alignment_marker_i(tx_alignment_marker_i), .marker_sequence_i(tx_marker_sequence_i), // 连接 TX logical 和 control 输入
        .blocks_valid_o(tx_blocks_valid_o), .blocks_o(tx_blocks_o) // 连接 TX block group 输出
    ); // 结束 PCS TX 实例
    kdlink_v2_pcs_rx u_rx ( // 实例化数字 PCS 接收器
        .clk_i(clk_i), .rst_n_i(rst_n_i), .lane_valid_i(rx_lane_valid_i), .lane_blocks_i(rx_lane_blocks_i), // 连接 RX lane 输入
        .flit_valid_o(rx_flit_valid_o), .flit_o(rx_flit_o), .block_lock_o(rx_block_lock_o), .deskew_locked_o(rx_deskew_locked_o), .block_error_o(rx_block_error_o), .deskew_overflow_o(rx_deskew_overflow_o) // 连接 RX logical 和状态输出
    ); // 结束 PCS RX 实例
endmodule // 结束全双工数字 PCS
