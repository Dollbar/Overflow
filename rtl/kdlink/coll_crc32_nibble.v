module coll_crc32_nibble ( // 定义 CRC-32 reflected 半字节组合更新单元
    input  wire [31:0] crc_i, // 接收半字节更新前 CRC 状态
    input  wire [3:0] data_i, // 接收按最低位优先处理的数据半字节
    input  wire [7:0] enable_i, // 为八个四位 CRC 段复制覆盖使能
    output wire [31:0] crc_o // 输出半字节更新后的 CRC 状态
); // 结束端口声明
    wire [31:0] c0; // 保存 bit 零更新前状态
    wire [31:0] c1; // 保存 bit 零更新后状态
    wire [31:0] c2; // 保存 bit 一更新后状态
    wire [31:0] c3; // 保存 bit 二更新后状态
    wire [31:0] c4; // 保存 bit 三更新后状态
    assign c0 = crc_i; // 连接输入 CRC 状态
    assign c1 = (c0[0] ^ data_i[0]) ? ((c0 >> 1) ^ 32'hEDB88320) : (c0 >> 1); // 更新数据 bit 零
    assign c2 = (c1[0] ^ data_i[1]) ? ((c1 >> 1) ^ 32'hEDB88320) : (c1 >> 1); // 更新数据 bit 一
    assign c3 = (c2[0] ^ data_i[2]) ? ((c2 >> 1) ^ 32'hEDB88320) : (c2 >> 1); // 更新数据 bit 二
    assign c4 = (c3[0] ^ data_i[3]) ? ((c3 >> 1) ^ 32'hEDB88320) : (c3 >> 1); // 更新数据 bit 三
    assign crc_o[3:0] = enable_i[0] ? c4[3:0] : crc_i[3:0]; // 使用本地使能更新 CRC 段零
    assign crc_o[7:4] = enable_i[1] ? c4[7:4] : crc_i[7:4]; // 使用本地使能更新 CRC 段一
    assign crc_o[11:8] = enable_i[2] ? c4[11:8] : crc_i[11:8]; // 使用本地使能更新 CRC 段二
    assign crc_o[15:12] = enable_i[3] ? c4[15:12] : crc_i[15:12]; // 使用本地使能更新 CRC 段三
    assign crc_o[19:16] = enable_i[4] ? c4[19:16] : crc_i[19:16]; // 使用本地使能更新 CRC 段四
    assign crc_o[23:20] = enable_i[5] ? c4[23:20] : crc_i[23:20]; // 使用本地使能更新 CRC 段五
    assign crc_o[27:24] = enable_i[6] ? c4[27:24] : crc_i[27:24]; // 使用本地使能更新 CRC 段六
    assign crc_o[31:28] = enable_i[7] ? c4[31:28] : crc_i[31:28]; // 使用本地使能更新 CRC 段七
endmodule // 结束 CRC-32 半字节更新单元
