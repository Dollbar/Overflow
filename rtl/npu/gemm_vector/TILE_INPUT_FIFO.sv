`timescale 1ns/1ps // 定义Tile输入FIFO仿真的时间单位和精度
`default_nettype none // 禁止隐式网络掩盖接口拼写错误

module TILE_INPUT_FIFO ( // 为Tile的A矩阵行和B矩阵列提供两个独立同步FIFO
    input  logic         clk_i, // 提供两个FIFO和Tile接口的统一时钟
    input  logic         rst_i, // 提供同步高有效复位
    input  logic         clear_i, // 同步丢弃两个FIFO中的全部待处理输入
    input  logic         a_valid_i, // 表示A输入当前提供有效的128位行数据
    output logic         a_ready_o, // 表示A输入FIFO能够接受当前行数据
    input  logic [127:0] a_data_i, // 提供A矩阵的十六个FP8元素
    input  logic         b_valid_i, // 表示B输入当前提供有效的128位列数据
    output logic         b_ready_o, // 表示B输入FIFO能够接受当前列数据
    input  logic [127:0] b_data_i, // 提供B矩阵的十六个FP8元素
    input  logic         independent_mode_i, // 允许A和B队首在静态权重模式下独立消费
    input  logic         pair_ready_i, // 表示Tile能够同拍接受一对A和B数据
    output logic         pair_valid_o, // 表示A和B两个队首均已有效且可以成对消费
    input  logic         a_ready_i, // 独立模式下表示Tile能够接受A队首
    output logic         a_valid_o, // 表示A输入FIFO队首当前有效
    input  logic         b_ready_i, // 独立模式下表示Tile能够接受B队首
    output logic         b_valid_o, // 表示B输入FIFO队首当前有效
    output logic [127:0] a_data_o, // 输出与B队首严格配对的A队首数据
    output logic [127:0] b_data_o, // 输出与A队首严格配对的B队首数据
    output logic         a_full_o, // 表示A输入FIFO已满
    output logic         a_empty_o, // 表示A输入FIFO为空
    output logic [5:0]   a_level_o, // 输出A输入FIFO的占用数量
    output logic         b_full_o, // 表示B输入FIFO已满
    output logic         b_empty_o, // 表示B输入FIFO为空
    output logic [5:0]   b_level_o // 输出B输入FIFO的占用数量
); // 结束Tile双输入FIFO端口列表

    logic a_rd_valid; // 接收A输入FIFO的独立队首有效状态
    logic b_rd_valid; // 接收B输入FIFO的独立队首有效状态
    logic pair_pop; // 动态模式下仅在两个队首同时有效时广播原子出队许可
    logic a_pop; // 选择原子或独立模式生成A队首出队许可
    logic b_pop; // 选择原子或独立模式生成B队首出队许可

    assign pair_valid_o = a_rd_valid && b_rd_valid; // 两个输入都准备好时才向Tile声明有效
    assign a_valid_o = a_rd_valid; // 独立公开A队首有效状态供静态权重模式使用
    assign b_valid_o = b_rd_valid; // 独立公开B队首有效状态供静态权重模式使用
    assign pair_pop = !independent_mode_i && pair_ready_i && pair_valid_o; // 动态模式握手时原子消费两个队首
    assign a_pop = independent_mode_i ? (a_ready_i && a_rd_valid) : pair_pop; // 静态模式允许A独立出队
    assign b_pop = independent_mode_i ? (b_ready_i && b_rd_valid) : pair_pop; // 静态模式允许B独立出队

    FIFO_SYNC_32_128 u_a_fifo ( // 例化保存A矩阵行输入的32深度同步FIFO
        .clk_i      (clk_i), // 连接Tile统一时钟
        .rst_i      (rst_i), // 连接同步高有效复位
        .clear_i    (clear_i), // 连接同步清空控制
        .wr_valid_i (a_valid_i), // 接收A输入有效状态
        .wr_ready_o (a_ready_o), // 返回A输入接收许可
        .wr_data_i  (a_data_i), // 接收128位A行数据
        .rd_ready_i (a_pop), // 按当前模式原子或独立消费A队首
        .rd_valid_o (a_rd_valid), // 接收A队首有效状态
        .rd_data_o  (a_data_o), // 输出A队首数据
        .full_o     (a_full_o), // 输出A满状态
        .empty_o    (a_empty_o), // 输出A空状态
        .level_o    (a_level_o) // 输出A占用数量
    ); // 结束A输入FIFO例化

    FIFO_SYNC_32_128 u_b_fifo ( // 例化保存B矩阵列输入的32深度同步FIFO
        .clk_i      (clk_i), // 连接Tile统一时钟
        .rst_i      (rst_i), // 连接同步高有效复位
        .clear_i    (clear_i), // 连接同步清空控制
        .wr_valid_i (b_valid_i), // 接收B输入有效状态
        .wr_ready_o (b_ready_o), // 返回B输入接收许可
        .wr_data_i  (b_data_i), // 接收128位B列数据
        .rd_ready_i (b_pop), // 按当前模式原子或独立消费B队首
        .rd_valid_o (b_rd_valid), // 接收B队首有效状态
        .rd_data_o  (b_data_o), // 输出B队首数据
        .full_o     (b_full_o), // 输出B满状态
        .empty_o    (b_empty_o), // 输出B空状态
        .level_o    (b_level_o) // 输出B占用数量
    ); // 结束B输入FIFO例化

endmodule // 结束TILE_INPUT_FIFO模块

`default_nettype wire // 恢复默认网络类型避免影响后续编译单元
