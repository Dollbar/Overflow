// Bind the synchronous receive FIFO to externally supplied KD28 SDP storage.
// 日期 2026-09-08；仅复用存储映射，未接用异步复位 FIFO 包装器。
`timescale 1ps/1ps // 控制器与两侧 SRAM 端口共享同一时钟域。
module upli_receive_storage #( // 含实际 SRAM 模型或黑盒映射的同步存储模块。
    parameter integer C_DEPTH = 5, // 精确逻辑容量与控制器保持一致。
    parameter integer C_DATA_WIDTH = 32, // 包含元数据的整字节存储字宽。
    parameter integer C_COUNT_WIDTH = (C_DEPTH < 2) ? 1 : (C_DEPTH < 4) ? 2 : (C_DEPTH < 8) ? 3 : (C_DEPTH < 16) ? 4 : (C_DEPTH < 32) ? 5 : (C_DEPTH < 64) ? 6 : (C_DEPTH < 128) ? 7 : (C_DEPTH < 256) ? 8 : (C_DEPTH < 512) ? 9 : (C_DEPTH < 1024) ? 10 : (C_DEPTH < 2048) ? 11 : (C_DEPTH < 4096) ? 12 : (C_DEPTH < 8192) ? 13 : (C_DEPTH < 16384) ? 14 : (C_DEPTH < 32768) ? 15 : 16, // 派生计数及零扩展地址位宽。
    parameter integer C_ZERO_INVALID = 1 // 默认屏蔽无效字；内部原始可见模式必须由消费者保留有效性门控。
) ( // 这里只暴露本地存储握手，不增加 UPLI 线上信号。
    input wire i_clk, // FIFO 控制与物理双端口 SRAM 的共同采样沿。
    input wire i_rstn, // 同步低有效复位只清除控制与有效缓存。
    input wire i_write_valid, // 本地生产者呈现完整数据字。
    input wire [C_DATA_WIDTH-1:0] i_write_data, // 不透明完整数据及保存元信息。
    output wire o_write_ready, // 完整逻辑占用小于容量时允许写入。
    input wire i_read_ready, // 下游消费者接受当前真实存储字。
    output wire o_read_valid, // 控制器已经捕获一个有效队首字。
    output wire [C_DATA_WIDTH-1:0] o_read_data, // SRAM 经过缓存流水后得到的实际字。
    output wire [C_COUNT_WIDTH-1:0] o_count // 包括 SRAM、在途读和输出缓存的占用。
); // 结束同步接收存储包装器接口。
    localparam integer C_MAPPED_DEPTH = (C_DEPTH < 2) ? 2 : C_DEPTH; // 深度一使用可用最小物理映射但绝不多发布容量。
    wire write_cs, read_cs; // 真正后端写握手和已预约读请求。
    wire [C_COUNT_WIDTH-1:0] write_addr, read_addr; // 同一逻辑容量的显式循环地址。
    wire [C_DATA_WIDTH-1:0] write_data, read_data; // 后端完整字数据，不复用模型作为期望。
    upli_receive_fifo #( // 同步控制器实现读缓存、容量与地址所有权。
        .C_DEPTH(C_DEPTH), .C_DATA_WIDTH(C_DATA_WIDTH), .C_COUNT_WIDTH(C_COUNT_WIDTH), .C_ZERO_INVALID(C_ZERO_INVALID) // 所有派生参数由控制器检查。
    ) Fifo_Inst ( // 保持后端接口和本地接收接口分离。
        .i_clk(i_clk), .i_rstn(i_rstn), // 同步复位不进入 SRAM 的异步复位端。
        .i_write_valid(i_write_valid), .i_write_data(i_write_data), .o_write_ready(o_write_ready), // 完整本地写通路。
        .i_read_ready(i_read_ready), .o_read_valid(o_read_valid), .o_read_data(o_read_data), .o_count(o_count), // 完整本地消费和容量接口。
        .o_sram_write_cs(write_cs), .o_sram_write_addr(write_addr), .o_sram_write_data(write_data), // 后端写端由实际接纳事件驱动。
        .o_sram_read_cs(read_cs), .o_sram_read_addr(read_addr), .i_sram_read_data(read_data) // 一周期注册读契约由外部映射兑现。
    ); // 结束同步 FIFO 控制器实例。
    kd28_fifo_sdp_storage_map #( // 接入获授权外部仓库的固定 SDP SRAM 映射。
        .DATA_WIDTH(C_DATA_WIDTH), .DEPTH(C_MAPPED_DEPTH), .ADDR_WIDTH(C_COUNT_WIDTH) // 允许非二次幂深度、宽度 tiling 及跨 bank。
    ) Storage_Inst ( // 功能仿真使用模型，物理预算可改用相同端口黑盒。
        .write_clk_i(i_clk), .write_cs_i(write_cs), .write_addr_i(write_addr), .write_data_i(write_data), // 写端时钟与实际写资格。
        .read_clk_i(i_clk), .read_cs_i(read_cs), .read_addr_i(read_addr), .read_data_o(read_data) // 读端同域且无额外隐含 ready。
    ); // 结束真实 SRAM 存储映射实例。
endmodule // 结束 upli_receive_storage 后端绑定组件。
