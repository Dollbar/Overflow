`include "collective_defs.vh" // 引入冻结的 header 字段定义
module coll_packetizer ( // 定义 logical flit header 构造和 CRC packetizer
    input  wire clk_i, // 接收 link core 时钟
    input  wire rst_n_i, // 接收低有效异步复位
    input  wire valid_i, // 接收待封装 payload 有效
    input  wire [511:0] payload_i, // 接收 Tensor payload
    input  wire [6:0] payload_bytes_i, // 接收 payload 有效字节数
    input  wire [3:0] message_type_i, // 接收消息类型
    input  wire [2:0] opcode_i, // 接收 collective opcode
    input  wire phase_i, // 接收 collective phase
    input  wire [1:0] dtype_i, // 接收 Tensor 数据类型
    input  wire [1:0] vc_i, // 接收目标 VC
    input  wire [2:0] src_rank_i, // 接收当前 hop 源 rank
    input  wire [2:0] dst_rank_i, // 接收当前 hop 目标 rank
    input  wire [11:0] collective_id_i, // 接收 collective ID
    input  wire [15:0] chunk_id_i, // 接收 chunk ID
    input  wire [15:0] packet_seq_i, // 接收 packet sequence
    input  wire [7:0] flit_seq_i, // 接收 packet 内 flit sequence
    input  wire sop_i, // 接收 packet 首 flit 标志
    input  wire eop_i, // 接收 packet 尾 flit标志
    input  wire retry_i, // 接收 replay 标志
    input  wire [7:0] link_epoch_i, // 接收当前 link epoch
    output wire valid_o, // 指示封装完成 logical flit 有效
    output wire [639:0] flit_o // 输出带 CRC 的 logical flit
); // 结束端口声明
    reg [95:0] header_base; // 保存不含 CRC 的组合 header
    wire crc_valid; // 指示 CRC 流水输出有效
    wire [31:0] crc_value; // 保存流水 CRC 结果
    wire [95:0] aligned_header; // 保存与 CRC 对齐的 header
    wire [511:0] aligned_payload; // 保存与 CRC 对齐的 payload
    wire [6:0] aligned_payload_bytes; // 保存与 CRC 对齐的 payload 字节数
    wire aligned_metadata_match; // 指示对齐 payload 字节数与 header 副本一致
    always @(*) begin // 组合构造冻结协议 header bits 零至九十五
        header_base = 96'd0; // 默认清零全部 header 字段和保留位
        header_base[3:0] = 4'd1; // 写入协议版本一
        header_base[7:4] = message_type_i; // 写入消息类型
        header_base[10:8] = opcode_i; // 写入 collective opcode
        header_base[11] = phase_i; // 写入 collective phase
        header_base[13:12] = dtype_i; // 写入 Tensor 数据类型
        header_base[15:14] = vc_i; // 写入目标 VC
        header_base[18:16] = src_rank_i; // 写入当前 hop 源 rank
        header_base[21:19] = dst_rank_i; // 写入当前 hop 目标 rank
        header_base[33:22] = collective_id_i; // 写入 collective ID
        header_base[49:34] = chunk_id_i; // 写入 chunk ID
        header_base[65:50] = packet_seq_i; // 写入 packet sequence
        header_base[73:66] = flit_seq_i; // 写入 packet 内 flit sequence
        header_base[80:74] = payload_bytes_i; // 写入 payload 有效字节数
        header_base[81] = sop_i; // 写入 packet 首 flit标志
        header_base[82] = eop_i; // 写入 packet 尾 flit标志
        header_base[83] = retry_i; // 写入 replay 标志
        header_base[91:84] = link_epoch_i; // 写入当前 link epoch
        header_base[95:92] = 4'd0; // 保持协议保留字段为零
    end // 结束 header 组合构造
    coll_crc32_flit_pipeline u_crc_pipeline ( // 实例化十九级 flit CRC 流水
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(valid_i), .header_i(header_base), // 连接时钟复位有效和 header
        .payload_i(payload_i), .payload_bytes_i(payload_bytes_i), .valid_o(crc_valid), .crc_o(crc_value), // 连接 payload 字节数和 CRC 结果
        .header_o(aligned_header), .payload_o(aligned_payload), .payload_bytes_o(aligned_payload_bytes) // 连接流水对齐数据
    ); // 结束 flit CRC 流水实例
    assign aligned_metadata_match = (aligned_payload_bytes == aligned_header[80:74]); // 检查流水 metadata 对齐不变式
    assign valid_o = crc_valid && aligned_metadata_match; // 仅在 CRC 和 metadata 对齐时输出有效
    assign flit_o = {crc_value, aligned_header, aligned_payload}; // 拼接 CRC、对齐 header 和 Tensor payload
endmodule // 结束 logical flit packetizer
