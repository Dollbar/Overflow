module kdlink_v2_tensor_bank_array ( // 定义十六 bank 到八 bonded port 的静态映射边界
    input wire clk_i, // 接收 slice 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire [15:0] source_valid_i, // 接收十六 bank Tensor source 有效位
    output wire [15:0] source_ready_o, // 返回十六 bank Tensor source 本地许可
    input wire [1535:0] source_header_i, // 接收十六 bank 协议 header
    input wire [8191:0] source_data_i, // 接收十六 bank Tensor payload
    input wire [111:0] source_bytes_i, // 接收十六 bank 有效字节数
    output wire [15:0] link_tx_valid_o, // 输出十六 slice TX 有效位
    input wire [15:0] link_tx_ready_i, // 接收十六 slice TX 本地许可
    output wire [1535:0] link_tx_header_o, // 输出十六 slice TX header
    output wire [8191:0] link_tx_data_o, // 输出十六 slice TX payload
    output wire [111:0] link_tx_bytes_o, // 输出十六 slice TX 有效字节数
    input wire [15:0] link_rx_valid_i, // 接收十六 slice RX 有效位
    output wire [15:0] link_rx_ready_o, // 返回十六 slice RX 本地许可
    input wire [1535:0] link_rx_header_i, // 接收十六 slice RX header
    input wire [8191:0] link_rx_data_i, // 接收十六 slice RX payload
    input wire [111:0] link_rx_bytes_i, // 接收十六 slice RX 有效字节数
    output wire [15:0] result_valid_o, // 输出十六 bank Tensor result 有效位
    input wire [15:0] result_ready_i, // 接收十六 bank Tensor result 许可
    output wire [1535:0] result_header_o, // 输出十六 bank Tensor result header
    output wire [8191:0] result_data_o, // 输出十六 bank Tensor result payload
    output wire [111:0] result_bytes_o, // 输出十六 bank Tensor result 有效字节数
    output wire [15:0] source_stall_o, // 输出各 bank source 本地停顿状态
    output wire [15:0] result_stall_o // 输出各 bank result 本地停顿状态
); // 结束端口声明
    assign source_stall_o = source_valid_i & ~source_ready_o; // 汇总各 bank source 停顿状态
    assign result_stall_o = result_valid_o & ~result_ready_i; // 汇总各 bank result 停顿状态
    genvar bank_index; // 提供十六 bank 静态生成索引
    generate // 生成相互独立的十六个双向 bank lane
        for (bank_index = 0; bank_index < 16; bank_index = bank_index + 1) begin : g_bank // 每两个 bank 静态对应一个 bonded port
            kdlink_v2_tensor_bank_lane u_lane ( // 实例化独立 bank 弹性边界
                .clk_i(clk_i), .rst_n_i(rst_n_i), // 连接 bank 时钟和复位
                .source_valid_i(source_valid_i[bank_index]), .source_ready_o(source_ready_o[bank_index]), .source_header_i(source_header_i[bank_index*96 +: 96]), .source_data_i(source_data_i[bank_index*512 +: 512]), .source_bytes_i(source_bytes_i[bank_index*7 +: 7]), // 连接 source bank
                .link_tx_valid_o(link_tx_valid_o[bank_index]), .link_tx_ready_i(link_tx_ready_i[bank_index]), .link_tx_header_o(link_tx_header_o[bank_index*96 +: 96]), .link_tx_data_o(link_tx_data_o[bank_index*512 +: 512]), .link_tx_bytes_o(link_tx_bytes_o[bank_index*7 +: 7]), // 连接对应 slice TX
                .link_rx_valid_i(link_rx_valid_i[bank_index]), .link_rx_ready_o(link_rx_ready_o[bank_index]), .link_rx_header_i(link_rx_header_i[bank_index*96 +: 96]), .link_rx_data_i(link_rx_data_i[bank_index*512 +: 512]), .link_rx_bytes_i(link_rx_bytes_i[bank_index*7 +: 7]), // 连接对应 slice RX
                .result_valid_o(result_valid_o[bank_index]), .result_ready_i(result_ready_i[bank_index]), .result_header_o(result_header_o[bank_index*96 +: 96]), .result_data_o(result_data_o[bank_index*512 +: 512]), .result_bytes_o(result_bytes_o[bank_index*7 +: 7]) // 连接 result bank
            ); // 结束 bank lane 实例
        end // 结束单 bank 静态生成
    endgenerate // 结束十六 bank 生成
endmodule // 结束十六 bank Tensor 边界
