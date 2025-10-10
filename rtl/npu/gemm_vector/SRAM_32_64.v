`timescale 1ns/1ps // 定义仿真时间单位与精度
`default_nettype none // 禁止隐式网络掩盖端口拼写错误

module SRAM_32_64 ( // 封装一颗TSMC28 32深度64位真双端口SRAM
    input  wire         clk_i, // A口和B口共用的上升沿时钟
    input  wire         rst_i, // 同步高有效复位且只清除读有效状态
    input  wire         a_req_i, // A口访问请求
    input  wire         a_we_i, // A口写使能且高电平表示写操作
    input  wire [4:0]   a_addr_i, // A口字地址
    input  wire [63:0]  a_wdata_i, // A口写数据
    output wire [63:0]  a_rdata_o, // A口同步读数据
    output reg          a_rvalid_o, // A口同步读有效
    input  wire         b_req_i, // B口访问请求
    input  wire         b_we_i, // B口写使能且高电平表示写操作
    input  wire [4:0]   b_addr_i, // B口字地址
    input  wire [63:0]  b_wdata_i, // B口写数据
    output wire [63:0]  b_rdata_o, // B口同步读数据
    output reg          b_rvalid_o // B口同步读有效
); // 结束端口列表

`ifdef SYNTHESIS // 综合时绑定由TSMC28 compiler生成的物理宏
    wire [63:0] macro_qa; // 接收物理宏A口读数据
    wire [63:0] macro_qb; // 接收物理宏B口读数据

    assign a_rdata_o = macro_qa; // 将物理宏A口读数据送到抽象接口
    assign b_rdata_o = macro_qb; // 将物理宏B口读数据送到抽象接口

    tsdn28hpcpuhdb32x64m4m_170a u_tsmc28_sram ( // 例化关闭BWEB和AWT选项的精简目标物理宏
        .CLK   (clk_i), // 连接共用时钟
        .CEBA  (~a_req_i), // 把高有效A口请求转换为低有效片选
        .WEBA  (~a_we_i), // 把高有效A口写使能转换为低有效写使能
        .AA    (a_addr_i), // 连接A口地址
        .DA    (a_wdata_i), // 连接A口全字写数据
        .QA    (macro_qa), // 连接A口读数据
        .CEBB  (~b_req_i), // 把高有效B口请求转换为低有效片选
        .WEBB  (~b_we_i), // 把高有效B口写使能转换为低有效写使能
        .AB    (b_addr_i), // 连接B口地址
        .DB    (b_wdata_i), // 连接B口全字写数据
        .QB    (macro_qb) // 连接B口读数据
    ); // 结束物理宏例化
`else // 仿真时使用不会进入综合网表的确定性行为模型
    reg [63:0] mem [0:31]; // 建立32字乘64位的仿真存储阵列
    reg [63:0] a_rdata_q; // 保存A口同步读结果
    reg [63:0] b_rdata_q; // 保存B口同步读结果

    assign a_rdata_o = a_rdata_q; // 输出A口同步读寄存值
    assign b_rdata_o = b_rdata_q; // 输出B口同步读寄存值

    always @(posedge clk_i) begin // 在物理宏的共同上升沿执行两个端口操作
        if (rst_i) begin // 同步复位期间屏蔽访问并清除有效状态
            a_rvalid_o <= 1'b0; // 清除A口读有效但不清存储内容
            b_rvalid_o <= 1'b0; // 清除B口读有效但不清存储内容
        end else begin // 非复位周期执行正常双端口访问
            a_rvalid_o <= a_req_i && !a_we_i; // A口读请求在当前边沿后产生有效数据
            b_rvalid_o <= b_req_i && !b_we_i; // B口读请求在当前边沿后产生有效数据
            if (a_req_i && a_we_i) begin // 处理A口全字写请求
                mem[a_addr_i] <= a_wdata_i; // 在A口地址写入64位数据
            end else if (a_req_i) begin // 处理A口读请求
                a_rdata_q <= mem[a_addr_i]; // 锁存A口地址对应的数据
            end // 结束A口操作选择
            if (b_req_i && b_we_i) begin // 处理B口全字写请求
                mem[b_addr_i] <= b_wdata_i; // 在B口地址写入64位数据
            end else if (b_req_i) begin // 处理B口读请求
                b_rdata_q <= mem[b_addr_i]; // 锁存B口地址对应的数据
            end // 结束B口操作选择
            if (a_req_i && b_req_i && (a_addr_i == b_addr_i) && (a_we_i || b_we_i)) begin // 检测工艺宏规定的同地址写冲突
                $display("FAIL: SRAM_32_64 forbids same-address access when either port writes"); // 输出未定义的端口冲突原因
                $stop; // 以Verilator失败状态终止冲突仿真
            end // 结束冲突检测
        end // 结束复位选择
    end // 结束同步存储行为
`endif // 结束综合模型选择

`ifdef SYNTHESIS // 综合分支单独生成读有效寄存器
    always @(posedge clk_i) begin // 在共同上升沿推进接口读有效
        if (rst_i) begin // 同步高有效复位
            a_rvalid_o <= 1'b0; // 清除A口读有效
            b_rvalid_o <= 1'b0; // 清除B口读有效
        end else begin // 正常工作周期
            a_rvalid_o <= a_req_i && !a_we_i; // 记录A口同步读请求
            b_rvalid_o <= b_req_i && !b_we_i; // 记录B口同步读请求
        end // 结束复位选择
    end // 结束读有效寄存器逻辑
`endif // 结束综合专用逻辑

endmodule // 结束SRAM_32_64模块

`default_nettype wire // 恢复默认网络类型避免影响外部文件
