module kdlink_slice ( // 定义独立 TX/RX 五百一十二位 KDLink codec slice
    input wire clk_i, // 接收一 GHz slice 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire tx_valid_i, // 接收连续 TX payload 有效标志
    input wire [95:0] tx_header_i, // 接收 TX header
    input wire [511:0] tx_payload_i, // 接收 TX payload
    input wire [6:0] tx_payload_bytes_i, // 接收 TX payload 字节数
    output wire tx_valid_o, // 输出带 CRC TX flit 有效标志
    output wire [639:0] tx_flit_o, // 输出带 CRC TX flit
    input wire rx_valid_i, // 接收 RX flit 有效标志
    input wire [639:0] rx_flit_i, // 接收 RX flit
    output wire rx_valid_o, // 输出 RX 检查完成有效标志
    output wire rx_crc_good_o, // 输出 RX CRC 检查结果
    output wire [95:0] rx_header_o, // 输出 RX 对齐 header
    output wire [511:0] rx_payload_o, // 输出 RX 对齐 payload
    output wire [6:0] rx_payload_bytes_o // 输出 RX 对齐 payload 字节数
); // 结束端口声明
    kdlink_packetizer u_tx_packetizer ( // 实例化独立 TX packetizer
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(tx_valid_i), .header_i(tx_header_i), // 连接 TX 时钟复位有效和 header
        .payload_i(tx_payload_i), .payload_bytes_i(tx_payload_bytes_i), .valid_o(tx_valid_o), .flit_o(tx_flit_o) // 连接 TX payload 和 flit
    ); // 结束 TX packetizer实例
    kdlink_depacketizer u_rx_depacketizer ( // 实例化独立 RX depacketizer
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(rx_valid_i), .flit_i(rx_flit_i), // 连接 RX 时钟复位有效和 flit
        .valid_o(rx_valid_o), .crc_good_o(rx_crc_good_o), .header_o(rx_header_o), // 连接 RX 检查状态和 header
        .payload_o(rx_payload_o), .payload_bytes_o(rx_payload_bytes_o) // 连接 RX payload 和字节数
    ); // 结束 RX depacketizer实例
endmodule // 结束 KDLink codec slice
