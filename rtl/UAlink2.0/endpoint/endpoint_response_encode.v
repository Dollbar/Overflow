// single64B Read Response 编码；规范位段见 Common 2.0 Table 5-30，局部子集见 endpoint_transaction_contract.json。
`default_nettype none // 禁止隐式网络掩盖端口拼写错误
module endpoint_response_encode #(parameter FULL_READ_ENABLE=0) ( // Response 编码模块仅生成 Control，完整响应仍必须具备两个 Data 半 Flit
    input wire i_valid, // 调用方提供待编码的响应描述符
    input wire [10:0] i_tag, // 调用方负责关联原请求的完整 Tag
    input wire [9:0] i_src, // 响应源标识由调用方提供，仅用于调试语义
    input wire [9:0] i_dst, // 调用方应提供原请求源标识
    input wire [3:0] i_status, // 默认仅零/三；完整普通Read额外支持二/六/八
    input wire [1:0] i_num_beats, // LEN 字段；单个六十四字节响应使用零
    input wire [1:0] i_offset, // 完整模式为相对Beat编号零至三，默认固定零
    input wire i_last, // 完整模式标记最后实际发送Beat，默认必须置一
    input wire [1:0] i_vc, // 当前子集仅开放 VC0
    input wire i_pool, // 当前子集选择 TL pool0
    output wire o_valid, // 输入有效且符合子集时响应字段可用
    output wire o_error, // 有效输入超出子集的本地诊断
    output wire [255:0] o_control // 低六十四位响应字段，高一百九十二位为零 NOP
); // 有类型字段服务接口不声明事务完成
wire profile_legal; // 检查本地单响应约束
wire [63:0] response_field; // 普通未压缩 Read 响应字段
assign profile_legal = ((i_status == 4'd0) || (i_status == 4'd3) || (FULL_READ_ENABLE && ((i_status == 4'd2) || (i_status == 4'd6) || (i_status == 4'd8)))) && // 错误响应同样保留正常 Read 的 Data tenure
                       (i_num_beats == 2'd0) && (FULL_READ_ENABLE || ((i_offset == 2'd0) && i_last)) && // 六十四字节一次完整响应
                       (i_vc == 2'd0) && !i_pool; // 第一版 TL VC 与 pool 选择
assign response_field = {4'd2, i_vc, i_tag, i_pool, i_num_beats, i_offset, // FTYPE 至 OFFSET 对应 Table 5-30
                         i_status, 1'b1, i_last, i_src, i_dst, 2'd0, 14'd0}; // RD_WR 为 Read，普通单播 RSPTYPE 与 SPARE 发零
assign o_valid = i_valid && profile_legal; // 输出有效不证明 Data 可用或 Tag 已完成
assign o_error = i_valid && !profile_legal; // 空闲时忽略描述符内容
assign o_control = o_valid ? {192'd0, response_field} : 256'd0; // 字段以自然边界从低 sector 开始并用零填充
endmodule // 结束无状态 Read Response 编码器
`default_nettype wire // 恢复外围编译单元默认设置
