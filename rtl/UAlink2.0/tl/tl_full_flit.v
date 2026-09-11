module tl_full_flit( // tl_full_flit模块：完整512位Flit分类、预算及内容原子接收
 input wire i_clk,i_rstn,i_commit,i_auth, // commit为实际接收事件，auth复位间稳定
 input wire [511:0] i_flit, // lower低256位，upper高256位
 input wire [1:0] i_msg, // 实际M0和M1侧带
 output wire o_allowed,o_taken,o_rejected, // 本地接收检查结果
 output wire [2:0] o_lower,o_upper, // 两半本地分类
 output wire [6:0] o_pending, // 分类队列长度
 output wire [72:0] o_be, // 当前类型队列
 output wire [2:0] o_requests_available, // 打包请求预算
 output wire [3:0] o_responses_available, // 打包响应预算
 output wire o_fatal,o_pair_open,o_pair_poison // 全部错误停止转发，Data配对状态
); // 尚非完整Endpoint，信用及普通Message内容后续接入
reg r_fatal; // 包括分类和预算错误的锁存
wire seq_allowed,content_allowed,content_fatal; // 两路准入
wire [2:0] lower,upper; // 分类提议
wire [3:0] tags; // 实际Control字段数
wire [1:0] unused_status;wire [31:0] unused_counts;wire [7:0] unused_be; // 描述符由分类模块另消费
wire unused_seq_taken,unused_seq_rejected,unused_content_taken,unused_content_rejected; // 子模块观察事件
tl_atomic_admission u_admission( // 实际分类与预算
 .i_clk(i_clk),.i_rstn(i_rstn),.i_commit(i_commit&&!r_fatal&&content_allowed),.i_auth(i_auth), // 内容失败禁止队列和预算推进
 .i_lower(i_flit[255:0]),.i_msg(i_msg),.i_type0(i_flit[7:0]),.i_type1(i_flit[263:256]), // 类型从实际低字节提取
 .o_allowed(seq_allowed),.o_taken(unused_seq_taken),.o_rejected(unused_seq_rejected), // 准入提议
 .o_lower(lower),.o_upper(upper),.o_pending(o_pending),.o_be(o_be), // 当前类型状态
 .o_requests_available(o_requests_available),.o_responses_available(o_responses_available) // 当前预算
); // 组合接收结束
tl_control_tenure u_tags(i_flit[255:0],unused_status,tags,unused_counts,unused_be); // AuthTags槽数来自实际Control
tl_content u_content( // 实际两半内容与Poison配对
 .i_clk(i_clk),.i_rstn(i_rstn),.i_commit(i_commit&&!r_fatal&&seq_allowed), // 分类预算失败不得推进配对
 .i_lower(i_flit[255:0]),.i_upper(i_flit[511:256]),.i_class0(lower),.i_class1(upper),.i_tags(tags), // 实际内容与分类
 .o_allowed(content_allowed),.o_taken(unused_content_taken),.o_rejected(unused_content_rejected), // 内容准入
 .o_fatal(content_fatal),.o_open(o_pair_open),.o_poison(o_pair_poison) // 内容错误及配对
); // 内容检查结束
assign o_fatal=r_fatal||content_fatal; // 任一错误锁存停止转发
assign o_allowed=seq_allowed&&content_allowed&&!o_fatal; // 完整本地检查通过
assign o_taken=i_commit&&o_allowed; // 唯一实际提交
assign o_rejected=i_rstn&&i_commit&&!o_allowed; // 接收拒绝
assign o_lower=o_allowed?lower:3'd7;assign o_upper=o_allowed?upper:3'd7; // 不暴露部分通过分类
always @(posedge i_clk)begin // 同步复位及接收错误锁存
 if(!i_rstn)r_fatal<=1'b0; // 复位清除fatal
 else if(i_commit&&!o_allowed)r_fatal<=1'b1; // 包括分类、预算及内容错误
end // 状态更新结束
endmodule // 结束tl_full_flit模块， 完整Flit本地接收结束
