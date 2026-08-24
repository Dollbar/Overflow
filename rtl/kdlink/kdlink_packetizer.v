`include "kdlink_defs.vh" // 引入 KDLink 位级字段定义
module kdlink_packetizer #( // 定义 KDLink 512-bit payload 发包流水
    parameter [0:0] ALLOW_ROUTE_CONTEXT = 1'b0 // 默认保持只发送基线 schema 二的兼容行为
) ( // 开始 packetizer 端口声明
    input wire clk_i, // 接收一 GHz slice 工作时钟
    input wire rst_n_i, // 接收低有效异步复位
    input wire valid_i, // 接收连续 payload 有效标志
    input wire [95:0] header_i, // 接收不含 CRC 的 KDLink header
    input wire [511:0] payload_i, // 接收固定五百一十二位 payload
    input wire [6:0] payload_bytes_i, // 接收当前 flit 有效字节数
    output wire valid_o, // 输出 CRC 完成 flit 有效标志
    output wire [639:0] flit_o // 输出带 CRC 的六百四十位 flit
); // 结束端口声明
    reg [95:0] normalized_header; // 保存协议规范化后的 header
    wire crc_valid; // 保存 CRC 流水输出有效标志
    wire [31:0] crc_value; // 保存 CRC-32 计算结果
    wire [95:0] aligned_header; // 保存与 CRC 对齐的 header
    wire [511:0] aligned_payload; // 保存与 CRC 对齐的 payload
    wire [6:0] aligned_payload_bytes; // 保存与 CRC 对齐的有效字节数
    always @(*) begin // 组合规范化协议控制字段
        normalized_header = header_i; // 默认保留调用方提供的网络 identity
        if (ALLOW_ROUTE_CONTEXT && (header_i[3:0] == `KDL_ROUTE_SCHEMA) && (header_i[7:4] == `KDL_MESSAGE_TYPE_ROUTE_CONTEXT)) normalized_header[3:0] = `KDL_ROUTE_SCHEMA; // 显式开启时保留合法 Route Context schema
        else normalized_header[3:0] = `KDL_SCHEMA_VERSION; // 其余流量保持基线 schema 二
        normalized_header[94:88] = payload_bytes_i; // 强制写入真实 payload 字节数
        normalized_header[95] = 1'b0; // 强制清零协议保留位
    end // 结束 header 规范化组合逻辑
    coll_crc32_flit_pipeline u_crc_pipeline ( // 复用已收敛的三百零四级 CRC-32 流水
        .clk_i(clk_i), .rst_n_i(rst_n_i), .valid_i(valid_i), .header_i(normalized_header), // 连接时钟复位有效和 header
        .payload_i(payload_i), .payload_bytes_i(payload_bytes_i), .valid_o(crc_valid), .crc_o(crc_value), // 连接 payload 和 CRC 结果
        .header_o(aligned_header), .payload_o(aligned_payload), .payload_bytes_o(aligned_payload_bytes) // 连接流水对齐数据
    ); // 结束 CRC 流水实例
    assign valid_o = crc_valid && (aligned_header[94:88] == aligned_payload_bytes); // 只输出 metadata 对齐的有效 flit
    assign flit_o = {crc_value, aligned_header, aligned_payload}; // 拼接 CRC header 和 payload
endmodule // 结束 KDLink packetizer
