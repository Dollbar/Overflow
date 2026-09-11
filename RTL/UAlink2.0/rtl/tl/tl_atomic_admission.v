module tl_atomic_admission ( // 完整逻辑Flit分类与打包预算共同提交
 input wire i_clk,i_rstn,i_commit,i_auth, // 同一时钟及稳定认证模式
 input wire [255:0] i_lower, // 实际lower半Flit
 input wire [1:0] i_msg, // 两半Message标志
 input wire [7:0] i_type0,i_type1, // 两半Message类型
 output wire o_allowed,o_taken,o_rejected, // 唯一对外提交结果
 output wire [2:0] o_lower,o_upper, // 本地分类
 output wire [6:0] o_pending, // 当前队列长度
 output wire [72:0] o_be, // 当前有序类型队列
 output wire [2:0] o_requests_available, // 当前请求预算
 output wire [3:0] o_responses_available // 当前响应预算
); // 后续仍需信用及完整内容验证
wire w_sequence_allowed,w_budget_allowed,w_control; // 两道独立允许条件
wire [2:0] w_lower,w_upper,w_requests; // 实际分类及请求数量
wire [3:0] w_responses; // 响应数量
wire unused_structure,unused_seq_taken,unused_seq_rejected,unused_budget_taken,unused_budget_rejected; // 子模块观察事件
wire [7:0] unused_fields,unused_requests,unused_responses; // 结构起点暂不外传
assign w_control=(o_pending<=7'd1)&&!i_msg[0]; // 从真实队列状态确定Control槽
 tl_control_decode u_decode( // 真实结构计数
 .i_half(i_lower),.o_valid(unused_structure),.o_requests(w_requests),.o_responses(w_responses), // 分类模块另检查结构及tenure
 .o_field_starts(unused_fields),.o_request_starts(unused_requests),.o_response_starts(unused_responses) // 位置输出
 ); // 解码实例结束
 tl_sequence u_sequence( // 实际分类推进实例
 .i_clk(i_clk),.i_rstn(i_rstn),.i_commit(i_commit && w_budget_allowed),.i_auth(i_auth), // 预算不允许时禁止分类推进
 .i_lower(i_lower),.i_msg(i_msg),.i_type0(i_type0),.i_type1(i_type1), // 真实输入
 .o_allowed(w_sequence_allowed),.o_taken(unused_seq_taken),.o_rejected(unused_seq_rejected), // 分类准入
 .o_lower(w_lower),.o_upper(w_upper),.o_pending(o_pending),.o_be(o_be) // 状态与提议输出
 ); // 分类实例结束
 tl_packing_budget u_budget( // 原打包预算实例
 .i_clk(i_clk),.i_rstn(i_rstn),.i_flit_commit(i_commit && w_sequence_allowed), // 分类不允许时预算保持
 .i_requests(w_control ? w_requests : 3'd0),.i_responses(w_control ? w_responses : 4'd0), // 无Control实际Flit仍按零计数退役
 .o_requests_available(o_requests_available),.o_responses_available(o_responses_available), // 当前预算
 .o_allowed(w_budget_allowed),.o_taken(unused_budget_taken),.o_rejected(unused_budget_rejected) // 预算准入
 ); // 预算实例结束
assign o_allowed=w_sequence_allowed && w_budget_allowed; // 两条件共同满足
assign o_taken=i_commit && o_allowed; // 唯一实际提交
assign o_rejected=i_rstn && i_commit && !o_allowed; // 任一条件失败都拒绝
assign o_lower=o_allowed ? w_lower : 3'd7; // 拒绝不暴露部分分类
assign o_upper=o_allowed ? w_upper : 3'd7; // 同拍一致
endmodule // 原子准入结束
