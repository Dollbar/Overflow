`include "kdlink_defs.vh" // 引入 KDLink 字段和 VC 编码
module kdlink_header_checker #( // 定义 KDLink header 合法性检查器
    parameter [0:0] ALLOW_ROUTE_CONTEXT = 1'b0 // 默认只接受基线 schema 二
) ( // 开始 header checker 端口声明
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
    wire route_context; // 标记显式允许的层次路由上下文
    wire global_commit; // 标记显式允许的全局提交确认消息
    assign message_type = header_i[7:4]; // 连接消息类型字段
    assign opcode = header_i[10:8]; // 连接操作码字段
    assign vc = header_i[15:13]; // 连接虚拟通道字段
    assign retry = header_i[19]; // 连接 replay 标志字段
    assign dst_node = header_i[29:25]; // 连接最终目的节点字段
    assign hop_limit = header_i[37:33]; // 连接剩余跳数字段
    assign payload_bytes = header_i[94:88]; // 连接 payload 字节数字段
    assign route_context = ALLOW_ROUTE_CONTEXT && (header_i[3:0] == `KDL_ROUTE_SCHEMA) && (message_type == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT); // 识别可选 Route Context header
    assign global_commit = ALLOW_ROUTE_CONTEXT && (header_i[3:0] == `KDL_SCHEMA_VERSION) && (message_type == `KDL_MESSAGE_TYPE_GLOBAL_COMMIT); // 识别层次扩展中使用基线 schema 的全局提交确认 header
    always @(*) begin // 组合检查全部冻结协议约束
        error_o = 8'd0; // 默认没有协议错误
        if ((header_i[3:0] != `KDL_SCHEMA_VERSION) && !route_context) error_o[0] = 1'b1; // 检查基线或可选层次 schema
        if ((message_type > `KDL_MESSAGE_TYPE_FAULT) && !route_context && !global_commit) error_o[1] = 1'b1; // 检查基线或显式层次扩展消息范围
        if ((message_type == `KDL_MESSAGE_TYPE_DATA) && (opcode > `KDL_OPCODE_POINT_TO_POINT)) error_o[2] = 1'b1; // 检查 data opcode范围
        if (payload_bytes > 7'd64) error_o[3] = 1'b1; // 检查 payload 字节数范围
        if (header_i[95]) error_o[4] = 1'b1; // 检查保留位为零
        if (endpoint_check_i && (dst_node != local_node_i)) error_o[5] = 1'b1; // 检查 endpoint 最终目的匹配
        if (!endpoint_check_i && (hop_limit == 5'd0)) error_o[6] = 1'b1; // 检查 router 转发跳数尚未耗尽
        if (route_context) begin // 检查单 flit Route Context 的 header 形态
            if (!header_i[17] || !header_i[18] || (payload_bytes != 7'd64) || (retry ? (vc != `KDL_VC_ROLE_REPLAY) : (vc > `KDL_VC_ROLE_CONTROL))) error_o[7] = 1'b1; // 检查 Route Context 边界和物理 VC
        end else if (global_commit) begin // 检查单 flit 全局提交确认的 header 形态
            if (!header_i[17] || !header_i[18] || (payload_bytes != 7'd64) || (retry ? (vc != `KDL_VC_ROLE_REPLAY) : (vc != `KDL_VC_ROLE_CONTROL))) error_o[7] = 1'b1; // 检查全局确认边界、长度和控制或重放 VC
        end else if ((retry && (vc != `KDL_VC_ROLE_REPLAY)) || (!retry && (((message_type == `KDL_MESSAGE_TYPE_DATA) && (vc > `KDL_VC_ROLE_POINT_TO_POINT)) || ((message_type >= `KDL_MESSAGE_TYPE_COLL_SETUP) && (message_type < (`KDL_MESSAGE_TYPE_COLL_ABORT + 1)) && (vc != `KDL_VC_ROLE_CONTROL)) || ((message_type >= `KDL_MESSAGE_TYPE_KEEPALIVE) && (vc != `KDL_VC_ROLE_MANAGEMENT))))) error_o[7] = 1'b1; // 检查基线 message VC 和统一 replay VC 映射
        valid_o = (error_o == 8'd0); // 汇总全部检查结果
    end // 结束 header 合法性组合逻辑
endmodule // 结束 KDLink header checker
