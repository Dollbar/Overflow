`include "kdlink_v2_defs.vh" // 引入 KDLink-v2 字段和 VC 编码
module kdlink_v2_header_checker ( // 定义 KDLink-v2 header 合法性检查器
    input wire [95:0] header_i, // 接收不含 CRC 的 header
    input wire [4:0] local_node_i, // 接收当前 endpoint 或 router 本地节点号
    input wire endpoint_check_i, // 指示当前检查点要求最终目的匹配
    output reg valid_o, // 输出 header 合法标志
    output reg [7:0] error_o // 输出逐类错误位图
); // 结束端口声明
    wire [3:0] message_type; // 提取消息类型
    wire [2:0] opcode; // 提取操作码
    wire [2:0] vc; // 提取虚拟通道
    wire retry; // 提取 replay 标志
    wire [4:0] dst_node; // 提取最终目的节点
    wire [4:0] hop_limit; // 提取剩余跳数
    wire [6:0] payload_bytes; // 提取 payload 有效字节数
    assign message_type = header_i[7:4]; // 连接消息类型字段
    assign opcode = header_i[10:8]; // 连接操作码字段
    assign vc = header_i[15:13]; // 连接虚拟通道字段
    assign retry = header_i[19]; // 连接 replay 标志字段
    assign dst_node = header_i[29:25]; // 连接最终目的节点字段
    assign hop_limit = header_i[37:33]; // 连接剩余跳数字段
    assign payload_bytes = header_i[94:88]; // 连接 payload 字节数字段
    always @(*) begin // 组合检查全部冻结协议约束
        error_o = 8'd0; // 默认没有协议错误
        if (header_i[3:0] != `KDL2_SCHEMA_VERSION) error_o[0] = 1'b1; // 检查协议版本
        if (message_type > `KDL2_MESSAGE_TYPE_FAULT) error_o[1] = 1'b1; // 检查消息类型范围
        if ((message_type == `KDL2_MESSAGE_TYPE_DATA) && (opcode > `KDL2_OPCODE_POINT_TO_POINT)) error_o[2] = 1'b1; // 检查 data opcode范围
        if (payload_bytes > 7'd64) error_o[3] = 1'b1; // 检查 payload 字节数范围
        if (header_i[95]) error_o[4] = 1'b1; // 检查保留位为零
        if (endpoint_check_i && (dst_node != local_node_i)) error_o[5] = 1'b1; // 检查 endpoint 最终目的匹配
        if (!endpoint_check_i && (hop_limit == 5'd0)) error_o[6] = 1'b1; // 检查 router 转发跳数尚未耗尽
        if (((message_type == `KDL2_MESSAGE_TYPE_DATA) && retry && (vc != `KDL2_VC_ROLE_REPLAY)) || ((message_type == `KDL2_MESSAGE_TYPE_DATA) && !retry && (vc > `KDL2_VC_ROLE_POINT_TO_POINT)) || ((message_type >= `KDL2_MESSAGE_TYPE_COLL_SETUP) && (message_type <= `KDL2_MESSAGE_TYPE_COLL_ABORT) && (vc != `KDL2_VC_ROLE_CONTROL)) || ((message_type >= `KDL2_MESSAGE_TYPE_KEEPALIVE) && (vc != `KDL2_VC_ROLE_MANAGEMENT))) error_o[7] = 1'b1; // 检查 message 与 VC 映射
        valid_o = (error_o == 8'd0); // 汇总全部检查结果
    end // 结束 header 合法性组合逻辑
endmodule // 结束 KDLink-v2 header checker
