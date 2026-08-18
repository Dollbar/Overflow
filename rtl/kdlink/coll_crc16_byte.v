module coll_crc16_byte ( // 定义 CRC-16 CCITT-FALSE 单字节组合更新单元
    input  wire [15:0] crc_i, // 接收字节更新前 CRC 状态
    input  wire [7:0] data_i, // 接收按最高位优先处理的数据字节
    output wire [15:0] crc_o // 输出字节更新后的 CRC 状态
); // 结束端口声明
    wire [15:0] c0; // 保存 bit 七更新前状态
    wire [15:0] c1; // 保存 bit 七更新后状态
    wire [15:0] c2; // 保存 bit 六更新后状态
    wire [15:0] c3; // 保存 bit 五更新后状态
    wire [15:0] c4; // 保存 bit 四更新后状态
    wire [15:0] c5; // 保存 bit 三更新后状态
    wire [15:0] c6; // 保存 bit 二更新后状态
    wire [15:0] c7; // 保存 bit 一更新后状态
    wire [15:0] c8; // 保存 bit 零更新后状态
    assign c0 = crc_i; // 连接输入 CRC 状态
    assign c1 = (c0[15] ^ data_i[7]) ? ((c0 << 1) ^ 16'h1021) : (c0 << 1); // 更新数据 bit 七
    assign c2 = (c1[15] ^ data_i[6]) ? ((c1 << 1) ^ 16'h1021) : (c1 << 1); // 更新数据 bit 六
    assign c3 = (c2[15] ^ data_i[5]) ? ((c2 << 1) ^ 16'h1021) : (c2 << 1); // 更新数据 bit 五
    assign c4 = (c3[15] ^ data_i[4]) ? ((c3 << 1) ^ 16'h1021) : (c3 << 1); // 更新数据 bit 四
    assign c5 = (c4[15] ^ data_i[3]) ? ((c4 << 1) ^ 16'h1021) : (c4 << 1); // 更新数据 bit 三
    assign c6 = (c5[15] ^ data_i[2]) ? ((c5 << 1) ^ 16'h1021) : (c5 << 1); // 更新数据 bit 二
    assign c7 = (c6[15] ^ data_i[1]) ? ((c6 << 1) ^ 16'h1021) : (c6 << 1); // 更新数据 bit 一
    assign c8 = (c7[15] ^ data_i[0]) ? ((c7 << 1) ^ 16'h1021) : (c7 << 1); // 更新数据 bit 零
    assign crc_o = c8; // 输出八位更新后的 CRC 状态
endmodule // 结束 CRC-16 单字节更新单元
