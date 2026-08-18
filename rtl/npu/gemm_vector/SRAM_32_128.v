`timescale 1ns/1ps // 定义仿真时间单位与精度
`default_nettype none // 禁止隐式网络掩盖端口拼写错误

module SRAM_32_128 ( // 用两颗32乘64位宏构成32乘128位真双端口SRAM
    input  wire          clk_i, // 两颗叶子宏共用的上升沿时钟
    input  wire          rst_i, // 同步高有效复位且只清除读有效状态
    input  wire          a_req_i, // A口访问请求
    input  wire          a_we_i, // A口写使能且高电平表示写操作
    input  wire [4:0]    a_addr_i, // A口字地址
    input  wire [127:0]  a_wdata_i, // A口128位写数据
    output wire [127:0]  a_rdata_o, // A口128位同步读数据
    output wire          a_rvalid_o, // A口同步读有效
    input  wire          b_req_i, // B口访问请求
    input  wire          b_we_i, // B口写使能且高电平表示写操作
    input  wire [4:0]    b_addr_i, // B口字地址
    input  wire [127:0]  b_wdata_i, // B口128位写数据
    output wire [127:0]  b_rdata_o, // B口128位同步读数据
    output wire          b_rvalid_o // B口同步读有效
); // 结束端口列表

    wire a_rvalid_lo; // 接收低64位叶子的A口读有效
    wire a_rvalid_hi; // 接收高64位叶子的A口读有效
    wire b_rvalid_lo; // 接收低64位叶子的B口读有效
    wire b_rvalid_hi; // 接收高64位叶子的B口读有效

    assign a_rvalid_o = a_rvalid_lo && a_rvalid_hi; // 两个数据切片同时有效时声明A口整字有效
    assign b_rvalid_o = b_rvalid_lo && b_rvalid_hi; // 两个数据切片同时有效时声明B口整字有效

    SRAM_32_64 u_slice_lo ( // 例化低64位叶子宏并承担接口有效信号
        .clk_i      (clk_i), // 连接共用时钟
        .rst_i      (rst_i), // 连接同步复位
        .a_req_i    (a_req_i), // 连接A口请求
        .a_we_i     (a_we_i), // 连接A口写使能
        .a_addr_i   (a_addr_i), // 连接A口地址
        .a_wdata_i  (a_wdata_i[63:0]), // 连接A口低64位写数据
        .a_rdata_o  (a_rdata_o[63:0]), // 连接A口低64位读数据
        .a_rvalid_o (a_rvalid_lo), // 接收低64位叶子的A口读有效
        .b_req_i    (b_req_i), // 连接B口请求
        .b_we_i     (b_we_i), // 连接B口写使能
        .b_addr_i   (b_addr_i), // 连接B口地址
        .b_wdata_i  (b_wdata_i[63:0]), // 连接B口低64位写数据
        .b_rdata_o  (b_rdata_o[63:0]), // 连接B口低64位读数据
        .b_rvalid_o (b_rvalid_lo) // 接收低64位叶子的B口读有效
    ); // 结束低位叶子宏例化

    SRAM_32_64 u_slice_hi ( // 例化高64位叶子宏并复用相同控制
        .clk_i      (clk_i), // 连接共用时钟
        .rst_i      (rst_i), // 连接同步复位
        .a_req_i    (a_req_i), // 连接A口请求
        .a_we_i     (a_we_i), // 连接A口写使能
        .a_addr_i   (a_addr_i), // 连接A口地址
        .a_wdata_i  (a_wdata_i[127:64]), // 连接A口高64位写数据
        .a_rdata_o  (a_rdata_o[127:64]), // 连接A口高64位读数据
        .a_rvalid_o (a_rvalid_hi), // 接收高64位叶子的A口读有效
        .b_req_i    (b_req_i), // 连接B口请求
        .b_we_i     (b_we_i), // 连接B口写使能
        .b_addr_i   (b_addr_i), // 连接B口地址
        .b_wdata_i  (b_wdata_i[127:64]), // 连接B口高64位写数据
        .b_rdata_o  (b_rdata_o[127:64]), // 连接B口高64位读数据
        .b_rvalid_o (b_rvalid_hi) // 接收高64位叶子的B口读有效
    ); // 结束高位叶子宏例化

endmodule // 结束SRAM_32_128模块

`default_nettype wire // 恢复默认网络类型避免影响外部文件
