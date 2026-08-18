`timescale 1ns/1ps // 定义仿真时间单位与精度
`default_nettype none // 禁止隐式网络掩盖端口拼写错误

module SRAM_32_32 ( // 用现有32乘64位宏的低半字提供32乘32位真双端口SRAM接口
    input  wire         clk_i, // 连接两个端口共用的上升沿时钟
    input  wire         rst_i, // 同步高有效复位且只清除读有效状态
    input  wire         a_req_i, // A口访问请求
    input  wire         a_we_i, // A口写使能且高电平表示写操作
    input  wire [4:0]   a_addr_i, // A口五位字地址
    input  wire [31:0]  a_wdata_i, // A口32位写数据
    output wire [31:0]  a_rdata_o, // A口32位同步读数据
    output wire         a_rvalid_o, // A口同步读有效
    input  wire         b_req_i, // B口访问请求
    input  wire         b_we_i, // B口写使能且高电平表示写操作
    input  wire [4:0]   b_addr_i, // B口五位字地址
    input  wire [31:0]  b_wdata_i, // B口32位写数据
    output wire [31:0]  b_rdata_o, // B口32位同步读数据
    output wire         b_rvalid_o // B口同步读有效
); // 结束端口列表

    /* verilator lint_off UNUSEDSIGNAL */
    wire [63:0] a_rdata_wide; // 接收底层64位宏的A口完整读数据且有意丢弃高半字
    wire [63:0] b_rdata_wide; // 接收底层64位宏的B口完整读数据且有意丢弃高半字
    /* verilator lint_on UNUSEDSIGNAL */

    assign a_rdata_o = a_rdata_wide[31:0]; // 仅向上层返回A口低32位有效数据
    assign b_rdata_o = b_rdata_wide[31:0]; // 仅向上层返回B口低32位有效数据

    SRAM_32_64 u_storage ( // 复用已有且物理视图可生成的32乘64位真双端口宏
        .clk_i      (clk_i), // 连接共用时钟
        .rst_i      (rst_i), // 连接同步复位
        .a_req_i    (a_req_i), // 连接A口请求
        .a_we_i     (a_we_i), // 连接A口写使能
        .a_addr_i   (a_addr_i), // 连接A口地址
        .a_wdata_i  ({32'd0, a_wdata_i}), // 高半字固定写零且低半字保存A口数据
        .a_rdata_o  (a_rdata_wide), // 接收A口64位读数据
        .a_rvalid_o (a_rvalid_o), // 直接传递A口读有效
        .b_req_i    (b_req_i), // 连接B口请求
        .b_we_i     (b_we_i), // 连接B口写使能
        .b_addr_i   (b_addr_i), // 连接B口地址
        .b_wdata_i  ({32'd0, b_wdata_i}), // 高半字固定写零且低半字保存B口数据
        .b_rdata_o  (b_rdata_wide), // 接收B口64位读数据
        .b_rvalid_o (b_rvalid_o) // 直接传递B口读有效
    ); // 结束底层存储宏例化

endmodule // 结束SRAM_32_32模块

`default_nettype wire // 恢复默认网络类型避免影响外部文件
