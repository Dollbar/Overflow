module kdlink_v2_int32_reduce512 ( // 定义 512-bit INT32 SUM 与 header 对齐包装器
    input wire clk_i, // 接收 reduction 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire valid_i, // 接收本地和远端 operand 有效位
    input wire [95:0] header_i, // 接收与 operand 对齐的协议 header
    input wire [511:0] local_i, // 接收本地 Tensor payload
    input wire [511:0] remote_i, // 接收远端 Tensor payload
    output wire valid_o, // 输出 reduction 结果有效位
    output wire [95:0] header_o, // 输出与结果对齐的协议 header
    output wire [511:0] result_o // 输出十六 lane INT32 modulo SUM
); // 结束端口声明
    reg [95:0] header_q0; // 保存 reduction 流水第一级 header
    reg [95:0] header_q1; // 保存 reduction 流水第二级 header
    reg [95:0] header_q2; // 保存 reduction 流水第三级 header
    wire [63:0] byte_valid_unused; // 保存未导出的全字节有效 mask
    assign header_o = header_q2; // 输出与三级 reduction 结果对齐的 header
    coll_int32_reduction u_reduction ( // 复用已关闭时序的十六 lane INT32 reduction
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(valid_i), // 连接 reduction 时钟复位和有效位
        .local_i(local_i), .remote_i(remote_i), .byte_valid_i(64'hFFFF_FFFF_FFFF_FFFF), // 连接 operands 和全字节有效 mask
        .valid_o(valid_o), .result_o(result_o), .byte_valid_o(byte_valid_unused) // 连接 reduction 结果
    ); // 结束 INT32 reduction 实例
    always @(posedge clk_i or negedge rst_n_i) begin // 对齐三拍 reduction header metadata
        if (!rst_n_i) begin // 检测复位有效
            header_q0 <= 96'd0; // 清零第一级 header
            header_q1 <= 96'd0; // 清零第二级 header
            header_q2 <= 96'd0; // 清零第三级 header
        end else begin // 处理正常 header 前推
            header_q0 <= header_i; // 捕获 reduction 输入 header
            header_q1 <= header_q0; // 前推第二级 header
            header_q2 <= header_q1; // 前推第三级 header
        end // 结束 header 前推
    end // 结束 header metadata 流水
endmodule // 结束 INT32 reduction 包装器
