// single64B Read 字段编码；规范位段见 Common 2.0 Table 5-29，局部子集见 endpoint_transaction_contract.json。
`default_nettype none // 禁止隐式网络掩盖端口拼写错误
module endpoint_read_encode ( // Read 编码模块为纯组合字段服务，不承担事务接纳、信用或 Tag 生命周期
    input wire i_valid, // 调用方提供一个待编码请求
    input wire [10:0] i_tag, // 保留完整十一位事务标识
    input wire [9:0] i_src, // 请求源加速器标识
    input wire [9:0] i_dst, // 请求目标加速器标识
    input wire [56:0] i_address, // 完整字节地址；本层不解释内存映射
    input wire [5:0] i_length, // DWORD 数减一；当前仅支持六十四字节
    input wire [7:0] i_attr, // 当前子集要求全部首尾字节有效
    input wire [1:0] i_vc, // 当前子集仅开放 VC0
    input wire i_pool, // 当前子集选择 TL pool0
    input wire [1:0] i_asi, // 当前局部地址空间选择零
    input wire [7:0] i_metadata, // 当前局部元数据固定为零
    output wire o_valid, // 输入有效且符合局部子集时给出字段
    output wire o_error, // 有效输入超出子集；这是本地诊断而非线协议状态
    output wire [255:0] o_control // 低一百二十八位请求字段，其余 sector 为零 NOP
); // 有类型接口替代原未实现服务壳
wire profile_legal; // 子集检查不缩窄规范字段位宽
wire [127:0] request_field; // 未压缩普通请求的自然对齐字段
assign profile_legal = (i_address[5:0] == 6'd0) && (i_length == 6'd15) && // 六十四字节对齐请求不会跨越二百五十六字节边界
                       (i_attr == 8'hff) && (i_vc == 2'd0) && !i_pool && // 第一版仅实现全字节 VC0 与 pool0
                       (i_asi == 2'd0) && (i_metadata == 8'd0); // 局部地址空间和元数据选择
assign request_field = {4'd1, 6'd3, i_vc, i_asi, i_tag, i_pool, i_attr, // FTYPE、Read CMD 与身份字段遵守 Table 5-29
                        i_length, i_metadata, i_address[56:2], i_src, i_dst, // 低两位地址按规范省略，其余五十五位全部保留
                        1'b0, 2'd0, 2'd0}; // CLOAD、CWAY 与 Read NUMBEATS 均为零
assign o_valid = i_valid && profile_legal; // 仅表明字段有效，不构成下游接纳握手
assign o_error = i_valid && !profile_legal; // 空闲输入不产生错误
assign o_control = o_valid ? {128'd0, request_field} : 256'd0; // 无效或拒绝时整半 Flit 清零以防陈旧字段泄漏
endmodule // 结束无状态 Read 编码器
`default_nettype wire // 恢复外围编译单元默认设置
