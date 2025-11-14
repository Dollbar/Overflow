module kdlink_v2_tensor_bank_lane ( // 定义单个 512-bit Tensor bank 双向弹性边界
    input wire clk_i, // 接收 slice 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire source_valid_i, // 接收 Tensor source 有效位
    output wire source_ready_o, // 返回 Tensor source 本地接收能力
    input wire [95:0] source_header_i, // 接收 Tensor source 协议 header
    input wire [511:0] source_data_i, // 接收 Tensor source payload
    input wire [6:0] source_bytes_i, // 接收 Tensor source 有效字节数
    output wire link_tx_valid_o, // 输出注册化 link TX 有效位
    input wire link_tx_ready_i, // 接收同域 link TX 本地接收能力
    output wire [95:0] link_tx_header_o, // 输出注册化 link TX header
    output wire [511:0] link_tx_data_o, // 输出注册化 link TX payload
    output wire [6:0] link_tx_bytes_o, // 输出注册化 link TX 有效字节数
    input wire link_rx_valid_i, // 接收 link RX 有效位
    output wire link_rx_ready_o, // 返回同域 link RX 本地接收能力
    input wire [95:0] link_rx_header_i, // 接收 link RX header
    input wire [511:0] link_rx_data_i, // 接收 link RX payload
    input wire [6:0] link_rx_bytes_i, // 接收 link RX 有效字节数
    output wire result_valid_o, // 输出注册化 Tensor result 有效位
    input wire result_ready_i, // 接收 Tensor result 消费能力
    output wire [95:0] result_header_o, // 输出注册化 Tensor result header
    output wire [511:0] result_data_o, // 输出注册化 Tensor result payload
    output wire [6:0] result_bytes_o // 输出注册化 Tensor result 有效字节数
); // 结束端口声明
    reg tx_valid_q; // 保存 source 到 link 的弹性有效位
    reg [95:0] tx_header_q; // 保存 source 到 link 的 header
    reg [511:0] tx_data_q; // 保存 source 到 link 的 payload
    reg [6:0] tx_bytes_q; // 保存 source 到 link 的有效字节数
    reg rx_valid_q; // 保存 link 到 result 的弹性有效位
    reg [95:0] rx_header_q; // 保存 link 到 result 的 header
    reg [511:0] rx_data_q; // 保存 link 到 result 的 payload
    reg [6:0] rx_bytes_q; // 保存 link 到 result 的有效字节数
    assign source_ready_o = !tx_valid_q || link_tx_ready_i; // 仅使用同域本地 ready 形成 source 许可
    assign link_tx_valid_o = tx_valid_q; // 输出 TX 弹性有效位
    assign link_tx_header_o = tx_header_q; // 输出 TX 弹性 header
    assign link_tx_data_o = tx_data_q; // 输出 TX 弹性 payload
    assign link_tx_bytes_o = tx_bytes_q; // 输出 TX 弹性字节数
    assign link_rx_ready_o = !rx_valid_q || result_ready_i; // 仅使用本地 result ready 形成 RX 许可
    assign result_valid_o = rx_valid_q; // 输出 result 弹性有效位
    assign result_header_o = rx_header_q; // 输出 result 弹性 header
    assign result_data_o = rx_data_q; // 输出 result 弹性 payload
    assign result_bytes_o = rx_bytes_q; // 输出 result 弹性字节数
    always @(posedge clk_i or negedge rst_n_i) begin // 更新单 bank 双向弹性状态
        if (!rst_n_i) begin // 检测复位有效
            tx_valid_q <= 1'b0; // 清除 TX 有效位
            tx_header_q <= 96'd0; // 清零 TX header
            tx_data_q <= 512'd0; // 清零 TX payload
            tx_bytes_q <= 7'd0; // 清零 TX 字节数
            rx_valid_q <= 1'b0; // 清除 RX 有效位
            rx_header_q <= 96'd0; // 清零 RX header
            rx_data_q <= 512'd0; // 清零 RX payload
            rx_bytes_q <= 7'd0; // 清零 RX 字节数
        end else begin // 处理正常双向传输
            if (source_ready_o) begin // 检查 TX 弹性级可以更新
                tx_valid_q <= source_valid_i; // 注册 source 有效位
                if (source_valid_i) begin // 仅在有效输入时更新 TX 数据
                    tx_header_q <= source_header_i; // 注册 source header
                    tx_data_q <= source_data_i; // 注册 source payload
                    tx_bytes_q <= source_bytes_i; // 注册 source 字节数
                end // 结束 TX 数据更新
            end // 结束 TX 弹性级更新
            if (link_rx_ready_o) begin // 检查 RX 弹性级可以更新
                rx_valid_q <= link_rx_valid_i; // 注册 link RX 有效位
                if (link_rx_valid_i) begin // 仅在有效输入时更新 RX 数据
                    rx_header_q <= link_rx_header_i; // 注册 link RX header
                    rx_data_q <= link_rx_data_i; // 注册 link RX payload
                    rx_bytes_q <= link_rx_bytes_i; // 注册 link RX 字节数
                end // 结束 RX 数据更新
            end // 结束 RX 弹性级更新
        end // 结束正常传输处理
    end // 结束双向弹性状态更新
endmodule // 结束单 Tensor bank lane
