module coll_crc32_byte ( // 定义 CRC-32 reflected 单字节组合更新单元
    input  wire [31:0] crc_i, // 接收字节更新前 CRC 状态
    input  wire [7:0] data_i, // 接收按最低位优先处理的数据字节
    input  wire enable_i, // 指示当前字节参与 CRC 覆盖
    output wire [31:0] crc_o // 输出字节更新后的 CRC 状态
); // 结束端口声明
    wire [31:0] c0; // 保存 bit 零更新前状态
    wire [31:0] c1; // 保存 bit 零更新后状态
    wire [31:0] c2; // 保存 bit 一更新后状态
    wire [31:0] c3; // 保存 bit 二更新后状态
    wire [31:0] c4; // 保存 bit 三更新后状态
    wire [31:0] c5; // 保存 bit 四更新后状态
    wire [31:0] c6; // 保存 bit 五更新后状态
    wire [31:0] c7; // 保存 bit 六更新后状态
    wire [31:0] c8; // 保存 bit 七更新后状态
    assign c0 = crc_i; // 连接输入 CRC 状态
    assign c1 = (c0[0] ^ data_i[0]) ? ((c0 >> 1) ^ 32'hEDB88320) : (c0 >> 1); // 更新数据 bit 零
    assign c2 = (c1[0] ^ data_i[1]) ? ((c1 >> 1) ^ 32'hEDB88320) : (c1 >> 1); // 更新数据 bit 一
    assign c3 = (c2[0] ^ data_i[2]) ? ((c2 >> 1) ^ 32'hEDB88320) : (c2 >> 1); // 更新数据 bit 二
    assign c4 = (c3[0] ^ data_i[3]) ? ((c3 >> 1) ^ 32'hEDB88320) : (c3 >> 1); // 更新数据 bit 三
    assign c5 = (c4[0] ^ data_i[4]) ? ((c4 >> 1) ^ 32'hEDB88320) : (c4 >> 1); // 更新数据 bit 四
    assign c6 = (c5[0] ^ data_i[5]) ? ((c5 >> 1) ^ 32'hEDB88320) : (c5 >> 1); // 更新数据 bit 五
    assign c7 = (c6[0] ^ data_i[6]) ? ((c6 >> 1) ^ 32'hEDB88320) : (c6 >> 1); // 更新数据 bit 六
    assign c8 = (c7[0] ^ data_i[7]) ? ((c7 >> 1) ^ 32'hEDB88320) : (c7 >> 1); // 更新数据 bit 七
    assign crc_o = enable_i ? c8 : crc_i; // 无效字节保持 CRC 状态不变
endmodule // 结束 CRC-32 单字节更新单元
