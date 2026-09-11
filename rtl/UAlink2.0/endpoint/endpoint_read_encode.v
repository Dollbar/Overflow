// 普通Read字段编码与完整几何/字节掩码；规范位段见 Common 2.0 Table 5-29，局部子集见 endpoint_transaction_contract.json。
`default_nettype none // 禁止隐式网络掩盖端口拼写错误
module endpoint_read_encode #(parameter integer FULL_READ_ENABLE=0) ( // Read 编码模块为纯组合字段服务，不承担事务接纳、信用或 Tag 生命周期
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
    output wire [255:0] o_control, // 低一百二十八位请求字段，其余 sector 为零 NOP
    output wire [1:0] o_num_beats, // 实际响应所需Beat数减一，不编码到Read Request NUMBEATS
    output wire [255:0] o_be // 按完整256-byte区域编号的首尾DWORD字节使能
); // 有类型接口替代原未实现服务壳
wire profile_legal; // 子集检查不缩窄规范字段位宽
wire [127:0] request_field; // 未压缩普通请求的自然对齐字段
wire legacy_legal; // 原局部Read模式保持完全一致
assign legacy_legal = (i_address[5:0] == 6'd0) && (i_length == 6'd15) && // 六十四字节对齐请求不会跨越二百五十六字节边界
                       (i_attr == 8'hff) && (i_vc == 2'd0) && !i_pool && // 第一版仅实现全字节 VC0 与 pool0
                       (i_asi == 2'd0) && (i_metadata == 8'd0); // 局部地址空间和元数据选择
wire [8:0] end_byte={1'b0,i_address[7:0]}+{1'b0,i_length,2'b00}+9'd4; // 长度扩宽，256不会溢出为零
wire full_legal=(i_address[1:0]==2'd0)&&(end_byte<=9'd256)&&(i_vc==2'd0)&&!i_pool; // ASI/ATTR/META在完整Read中合法且原样转发
wire [8:0] beat_span={3'd0,i_address[5:0]}+{1'b0,i_length,2'b00}+9'd3; // ceil((偏移+字节数)/64)-1等于(偏移+字节数-1)>>6
wire unused_beat_geometry=^{beat_span[8],beat_span[5:0]}; // 只需中间两位响应计数，余位不进入协议字段
reg [255:0] byte_mask;integer lane; // 有界区域字节掩码，不要求线上无效lane数据为零
always @* begin
 byte_mask=256'd0;
 for(lane=0;lane<256;lane=lane+1)begin
  if(lane[8:0]>={1'b0,i_address[7:0]}&&lane[8:0]<end_byte)begin
   if(lane[7:2]==i_address[7:2])byte_mask[lane]=i_attr[{1'b0,lane[1:0]}]; // 首DW总是使用低半ATTR
   else if({2'd0,lane[8:2]}==((end_byte-9'd1)>>2))byte_mask[lane]=i_attr[{1'b1,lane[1:0]}]; // LEN0不会进入该分支，末DW使用高半ATTR
   else byte_mask[lane]=1'b1; // 两端之间全部字节有效
  end
 end
end
assign profile_legal=(FULL_READ_ENABLE!=0)?full_legal:legacy_legal; // 显式开启完整Read，默认不改变历史能力
assign o_be=o_valid?byte_mask:256'd0; // 非法或空闲时无可读字节
assign o_num_beats=o_valid?beat_span[7:6]:2'd0; // 最大四Beat，最高未用位在合法条件下为零
assign request_field = {4'd1, 6'd3, i_vc, i_asi, i_tag, i_pool, i_attr, // FTYPE、Read CMD 与身份字段遵守 Table 5-29
                        i_length, i_metadata, i_address[56:2], i_src, i_dst, // 低两位地址按规范省略，其余五十五位全部保留
                        1'b0, 2'd0, 2'd0}; // CLOAD、CWAY 与 Read NUMBEATS 均为零
assign o_valid = i_valid && profile_legal; // 仅表明字段有效，不构成下游接纳握手
assign o_error = i_valid && !profile_legal; // 空闲输入不产生错误
assign o_control = o_valid ? {128'd0, request_field} : 256'd0; // 无效或拒绝时整半 Flit 清零以防陈旧字段泄漏
endmodule // 结束无状态 Read 编码器
`default_nettype wire // 恢复外围编译单元默认设置
