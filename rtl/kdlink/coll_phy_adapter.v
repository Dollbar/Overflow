module coll_phy_adapter ( // 定义 coll_clk 与异步 phy_clk 双向 logical link 适配器
    input  wire coll_clk_i, // 接收 collective core 时钟
    input  wire coll_rst_n_i, // 接收 collective 域低有效异步复位
    input  wire phy_clk_i, // 接收 PHY adapter 时钟
    input  wire phy_rst_n_i, // 接收 PHY 域低有效异步复位
    input  wire [639:0] coll_tx_flit_i, // 接收 collective 域 forward TX flit
    input  wire coll_tx_valid_i, // 接收 collective 域 forward TX 有效
    output wire coll_tx_ready_o, // 返回 collective 域 forward TX 能力
    output wire [639:0] phy_tx_flit_o, // 输出 PHY 域 forward TX flit
    output wire phy_tx_valid_o, // 指示 PHY 域 forward TX 有效
    input  wire phy_tx_ready_i, // 接收 PHY forward TX 能力
    input  wire [639:0] phy_rx_flit_i, // 接收 PHY 域 forward RX flit
    input  wire phy_rx_valid_i, // 接收 PHY 域 forward RX 有效
    output wire phy_rx_ready_o, // 返回 PHY forward RX 能力
    output wire [639:0] coll_rx_flit_o, // 输出 collective 域 forward RX flit
    output wire coll_rx_valid_o, // 指示 collective 域 forward RX 有效
    input  wire coll_rx_ready_i, // 接收 collective forward RX 能力
    input  wire [95:0] coll_reverse_tx_i, // 接收 collective 域 reverse TX word
    input  wire coll_reverse_tx_valid_i, // 接收 collective 域 reverse TX 有效
    output wire coll_reverse_tx_ready_o, // 返回 collective 域 reverse TX 能力
    output wire [95:0] phy_reverse_tx_o, // 输出 PHY 域 reverse TX word
    output wire phy_reverse_tx_valid_o, // 指示 PHY 域 reverse TX 有效
    input  wire phy_reverse_tx_ready_i, // 接收 PHY reverse TX 能力
    input  wire [95:0] phy_reverse_rx_i, // 接收 PHY 域 reverse RX word
    input  wire phy_reverse_rx_valid_i, // 接收 PHY 域 reverse RX 有效
    output wire phy_reverse_rx_ready_o, // 返回 PHY reverse RX 能力
    output wire [95:0] coll_reverse_rx_o, // 输出 collective 域 reverse RX word
    output wire coll_reverse_rx_valid_o, // 指示 collective 域 reverse RX 有效
    input  wire coll_reverse_rx_ready_i, // 接收 collective reverse RX 能力
    output wire cdc_error_o // 汇总任一 async FIFO overflow underflow
); // 结束端口声明
    wire tx_overflow; // 保存 forward TX CDC overflow
    wire tx_underflow; // 保存 forward TX CDC underflow
    wire rx_overflow; // 保存 forward RX CDC overflow
    wire rx_underflow; // 保存 forward RX CDC underflow
    wire rev_tx_overflow; // 保存 reverse TX CDC overflow
    wire rev_tx_underflow; // 保存 reverse TX CDC underflow
    wire rev_rx_overflow; // 保存 reverse RX CDC overflow
    wire rev_rx_underflow; // 保存 reverse RX CDC underflow
    coll_async_fifo #(.WIDTH(640), .ADDR_W(3)) u_forward_tx_cdc ( // 实例化 forward TX async FIFO
        .write_clk_i(coll_clk_i), .write_rst_n_i(coll_rst_n_i), .write_data_i(coll_tx_flit_i), .write_valid_i(coll_tx_valid_i), .write_ready_o(coll_tx_ready_o), // 连接 collective 写侧
        .read_clk_i(phy_clk_i), .read_rst_n_i(phy_rst_n_i), .read_data_o(phy_tx_flit_o), .read_valid_o(phy_tx_valid_o), .read_ready_i(phy_tx_ready_i), // 连接 PHY 读侧
        .overflow_o(tx_overflow), .underflow_o(tx_underflow) // 连接 CDC 错误状态
    ); // 结束 forward TX CDC 实例
    coll_async_fifo #(.WIDTH(640), .ADDR_W(3)) u_forward_rx_cdc ( // 实例化 forward RX async FIFO
        .write_clk_i(phy_clk_i), .write_rst_n_i(phy_rst_n_i), .write_data_i(phy_rx_flit_i), .write_valid_i(phy_rx_valid_i), .write_ready_o(phy_rx_ready_o), // 连接 PHY 写侧
        .read_clk_i(coll_clk_i), .read_rst_n_i(coll_rst_n_i), .read_data_o(coll_rx_flit_o), .read_valid_o(coll_rx_valid_o), .read_ready_i(coll_rx_ready_i), // 连接 collective 读侧
        .overflow_o(rx_overflow), .underflow_o(rx_underflow) // 连接 CDC 错误状态
    ); // 结束 forward RX CDC 实例
    coll_async_fifo #(.WIDTH(96), .ADDR_W(3)) u_reverse_tx_cdc ( // 实例化 reverse TX async FIFO
        .write_clk_i(coll_clk_i), .write_rst_n_i(coll_rst_n_i), .write_data_i(coll_reverse_tx_i), .write_valid_i(coll_reverse_tx_valid_i), .write_ready_o(coll_reverse_tx_ready_o), // 连接 collective 写侧
        .read_clk_i(phy_clk_i), .read_rst_n_i(phy_rst_n_i), .read_data_o(phy_reverse_tx_o), .read_valid_o(phy_reverse_tx_valid_o), .read_ready_i(phy_reverse_tx_ready_i), // 连接 PHY 读侧
        .overflow_o(rev_tx_overflow), .underflow_o(rev_tx_underflow) // 连接 CDC 错误状态
    ); // 结束 reverse TX CDC 实例
    coll_async_fifo #(.WIDTH(96), .ADDR_W(3)) u_reverse_rx_cdc ( // 实例化 reverse RX async FIFO
        .write_clk_i(phy_clk_i), .write_rst_n_i(phy_rst_n_i), .write_data_i(phy_reverse_rx_i), .write_valid_i(phy_reverse_rx_valid_i), .write_ready_o(phy_reverse_rx_ready_o), // 连接 PHY 写侧
        .read_clk_i(coll_clk_i), .read_rst_n_i(coll_rst_n_i), .read_data_o(coll_reverse_rx_o), .read_valid_o(coll_reverse_rx_valid_o), .read_ready_i(coll_reverse_rx_ready_i), // 连接 collective 读侧
        .overflow_o(rev_rx_overflow), .underflow_o(rev_rx_underflow) // 连接 CDC 错误状态
    ); // 结束 reverse RX CDC 实例
    assign cdc_error_o = tx_overflow || tx_underflow || rx_overflow || rx_underflow || rev_tx_overflow || rev_tx_underflow || rev_rx_overflow || rev_rx_underflow; // 汇总全部 CDC FIFO 错误
endmodule // 结束双向 PHY CDC adapter
