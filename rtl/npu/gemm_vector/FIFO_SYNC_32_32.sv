`timescale 1ns/1ps // 定义同步FIFO仿真的时间单位和精度
`default_nettype none // 禁止隐式网络掩盖端口连接错误

module FIFO_SYNC_32_32 ( // 使用一颗32乘32真双端口SRAM构造同步FIFO
    input  logic        clk_i, // 提供FIFO控制和SRAM访问的统一时钟
    input  logic        rst_i, // 提供同步高有效复位且不清除SRAM位单元
    input  logic        clear_i, // 同步清空FIFO控制状态且不清除SRAM位单元
    input  logic        wr_valid_i, // 表示写侧当前提供有效数据
    output logic        wr_ready_o, // 表示FIFO当前能够接受一个写数据
    input  logic [31:0] wr_data_i, // 提供待入队的32位数据
    input  logic        rd_ready_i, // 表示读侧愿意接受当前队首数据
    output logic        rd_valid_o, // 表示当前队首数据有效
    output logic [31:0] rd_data_o, // 输出保持到握手完成的32位队首数据
    output logic        full_o, // 表示逻辑FIFO已占用全部32个位置
    output logic        empty_o, // 表示逻辑FIFO中没有有效数据
    output logic [5:0]  level_o // 输出零到三十二的当前占用数量
); // 结束同步FIFO端口列表

    localparam logic [5:0] FIFO_DEPTH = 6'd32; // 固定逻辑容量以匹配32深度物理宏

    logic [4:0] wr_ptr_q; // 保存下一次被接受写事务使用的SRAM地址
    logic [4:0] rd_ptr_q; // 保存下一次队首预取使用的SRAM地址
    logic [5:0] count_q; // 保存包含输出队首在内的FIFO占用数量
    logic rd_valid_q; // 保存SRAM输出当前是否构成有效队首
    logic flush_active; // 汇总同步复位和同步清空条件
    logic write_fire; // 标识本周期完成一个写侧握手
    logic read_fire; // 标识本周期完成一个读侧握手
    logic read_issue; // 标识本周期从SRAM预取下一个队首
    logic [31:0] ram_read_data; // 接收SRAM读端口的同步返回数据

    assign flush_active = rst_i || clear_i; // 任一清空条件有效时停止接受新事务
    assign full_o = (count_q == FIFO_DEPTH); // 占用数量达到三十二时声明满状态
    assign empty_o = (count_q == 6'd0); // 占用数量为零时声明空状态
    assign level_o = count_q; // 直接输出当前逻辑占用数量
    assign rd_valid_o = rd_valid_q; // 输出保持式队首有效状态
    assign rd_data_o = rd_valid_q ? ram_read_data : 32'd0; // 无有效队首时输出确定的零值
    assign read_fire = rd_valid_q && rd_ready_i; // 有效队首被读侧接受时完成出队
    assign wr_ready_o = !flush_active && (!full_o || read_fire); // 非满或同拍出队时允许入队
    assign write_fire = wr_valid_i && wr_ready_o; // 写侧valid和ready同时有效时完成入队
    assign read_issue = !flush_active && (!rd_valid_q || read_fire) && // 输出空闲或正在消费时允许预取
                        (rd_valid_q ? (count_q > 6'd1) : (count_q != 6'd0)); // 仅从已经存在的RAM数据中预取

    always_ff @(posedge clk_i) begin // 在统一时钟上升沿推进指针和占用状态
        if (flush_active) begin // 同步复位或清空时丢弃全部逻辑队列内容
            wr_ptr_q <= 5'd0; // 写指针回到物理地址零
            rd_ptr_q <= 5'd0; // 读预取指针回到物理地址零
            count_q <= 6'd0; // 逻辑占用数量清零
            rd_valid_q <= 1'b0; // 立即使任何旧SRAM返回失效
        end else begin // 正常工作时处理独立的读写握手
            if (write_fire) begin // 被接受写事务推进写指针
                wr_ptr_q <= wr_ptr_q + 5'd1; // 五位自然溢出实现三十二深度回绕
            end // 结束写指针更新
            if (read_issue) begin // 发出的SRAM预取推进读指针
                rd_ptr_q <= rd_ptr_q + 5'd1; // 五位自然溢出实现三十二深度回绕
            end // 结束读指针更新
            unique case ({write_fire, read_fire}) // 根据外部入队和出队组合更新占用数量
                2'b10: count_q <= count_q + 6'd1; // 仅入队时占用数量增加一
                2'b01: count_q <= count_q - 6'd1; // 仅出队时占用数量减少一
                default: count_q <= count_q; // 同拍读写或无事务时保持占用数量
            endcase // 结束占用数量更新选择
            unique case ({read_issue, read_fire}) // 根据预取和消费组合更新输出有效状态
                2'b10: rd_valid_q <= 1'b1; // 新预取在本时钟沿后成为有效队首
                2'b01: rd_valid_q <= 1'b0; // 只消费未补充时清空队首有效状态
                2'b11: rd_valid_q <= 1'b1; // 消费旧队首并预取新队首时维持连续有效
                default: rd_valid_q <= rd_valid_q; // 背压或空闲时保持队首有效状态
            endcase // 结束输出有效状态更新选择
        end // 结束FIFO正常工作分支
    end // 结束同步FIFO时序过程

    SRAM_32_32 u_storage ( // 连接外部提供的32x32真双端口SRAM宏
        .clk_i      (clk_i), // SRAM与FIFO控制共享同一时钟
        .rst_i      (flush_active), // 清空期间只复位SRAM接口有效状态
        .a_req_i    (write_fire), // 固定A口承担独立写事务
        .a_we_i     (1'b1), // A口请求始终解释为整字写入
        .a_addr_i   (wr_ptr_q), // 使用当前写指针作为A口地址
        .a_wdata_i  (wr_data_i), // 将写侧数据送入A口
        /* verilator lint_off PINCONNECTEMPTY */
        .a_rdata_o  (), // 写专用A口不使用读数据
        .a_rvalid_o (), // 写专用A口不使用读有效
        /* verilator lint_on PINCONNECTEMPTY */
        .b_req_i    (read_issue), // 固定B口承担独立同步预取
        .b_we_i     (1'b0), // B口请求始终解释为读取
        .b_addr_i   (rd_ptr_q), // 使用当前读指针作为B口地址
        .b_wdata_i  (32'd0), // 读专用B口的写数据固定为零
        .b_rdata_o  (ram_read_data), // 接收同步读出的队首数据
        /* verilator lint_off PINCONNECTEMPTY */
        .b_rvalid_o () // FIFO控制按照发出的读请求维护保持式valid
        /* verilator lint_on PINCONNECTEMPTY */
    ); // 结束双端口SRAM例化

endmodule // 结束FIFO_SYNC_32_32模块

`default_nettype wire // 恢复默认网络类型避免影响后续编译单元
