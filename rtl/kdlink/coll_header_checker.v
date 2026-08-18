`include "collective_defs.vh" // 引入冻结协议编码
module coll_header_checker ( // 定义 forward header 合法性组合检查器
    /* verilator lint_off UNUSEDSIGNAL */ input wire [95:0] header_i, /* verilator lint_on UNUSEDSIGNAL */ // 接收不含 CRC 的 forward header 且保留协议未检查字段
    input  wire [1:0] local_rank_i, // 接收本 hop 目标 rank
    input  wire [7:0] link_epoch_i, // 接收当前 link epoch
    output reg valid_o, // 指示 header 满足协议约束
    output reg [7:0] status_o // 输出首个 malformed 原因编码
); // 结束端口声明
    wire [3:0] message_type; // 提取消息类型
    wire [2:0] opcode; // 提取 collective opcode
    wire phase; // 提取 data phase
    wire [1:0] vc; // 提取 VC 编号
    wire retry; // 提取 replay 标志
    assign message_type = header_i[7:4]; // 连接消息类型字段
    assign opcode = header_i[10:8]; // 连接 opcode 字段
    assign phase = header_i[11]; // 连接 phase 字段
    assign vc = header_i[15:14]; // 连接 VC 字段
    assign retry = header_i[83]; // 连接 retry 字段
    always @(*) begin // 按固定优先级检查 header
        valid_o = 1'b0; // 默认 header 非法
        status_o = 8'h32; // 默认返回 protocol malformed
        if (header_i[3:0] != 4'd1) begin // 检查协议版本
            status_o = 8'h32; // 返回版本错误
        end else if (message_type > `COLL_MESSAGE_TYPE_LINK_INIT) begin // 检查消息类型范围
            status_o = 8'h32; // 返回保留消息类型错误
        end else if (opcode > `COLL_OPCODE_ALL_REDUCE) begin // 检查 collective opcode 范围
            status_o = 8'h32; // 返回 opcode 错误
        end else if (header_i[21:19] != {1'b0, local_rank_i}) begin // 检查当前 hop 目标 rank
            status_o = 8'h32; // 返回 hop destination 错误
        end else if (header_i[91:84] != link_epoch_i) begin // 检查 link epoch
            status_o = 8'h35; // 返回 epoch mismatch
        end else if (header_i[80:74] > 7'd64) begin // 检查 payload 字节范围
            status_o = 8'h32; // 返回 payload 长度错误
        end else if (message_type == `COLL_MESSAGE_TYPE_DATA && header_i[49:34] > 16'd3) begin // 检查 data chunk 范围
            status_o = 8'h32; // 返回 chunk 错误
        end else if (message_type == `COLL_MESSAGE_TYPE_DATA && retry && vc != 2'd3) begin // 检查 replay VC 映射
            status_o = 8'h32; // 返回 replay VC 错误
        end else if (message_type == `COLL_MESSAGE_TYPE_DATA && !retry && ((!phase && vc != 2'd0) || (phase && vc != 2'd1))) begin // 检查正常 data VC 映射
            status_o = 8'h32; // 返回 phase VC 错误
        end else if (message_type != `COLL_MESSAGE_TYPE_DATA && vc != 2'd2) begin // 检查全局控制 VC 映射
            status_o = 8'h32; // 返回 control VC 错误
        end else if ((message_type >= `COLL_MESSAGE_TYPE_COLL_SETUP) && (message_type <= `COLL_MESSAGE_TYPE_COLL_ABORT) && (!header_i[81] || !header_i[82] || header_i[80:74] != 7'd16)) begin // 检查 collective control packet 形态
            status_o = 8'h32; // 返回 control packet 形态错误
        end else begin // 处理全部 header 约束通过
            valid_o = 1'b1; // 声明 header 合法
            status_o = 8'd0; // 返回成功状态
        end // 结束 header 合法性选择
    end // 结束 header 检查组合逻辑
endmodule // 结束 forward header 检查器
