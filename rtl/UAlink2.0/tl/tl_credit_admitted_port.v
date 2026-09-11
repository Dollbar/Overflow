module tl_credit_admitted_port #(parameter WIDTH=16)( // tl_credit_admitted_port模块：真实端口前置整段准入，WIDTH为8至16
input wire i_clk,i_rstn,i_receive,i_send,i_auth,input wire [511:0] i_rx_flit,input wire [1:0] i_rx_msg,input wire [511:0] i_tx_flit,input wire [1:0] i_tx_msg, // 双向实际字段
output wire o_rx_allowed,o_rx_taken,o_rx_rejected,o_tx_allowed,o_tx_taken,o_tx_error, // 联合接纳
output wire [2:0] o_rx_lower,o_rx_upper,o_tx_lower,o_tx_upper,output wire [79:0] o_demands, // 分类与字段生成的需求
output wire [6:0] o_rx_pending,output wire [72:0] o_rx_be,output wire [2:0] o_requests_available,output wire [3:0] o_responses_available, // 接收队列和预算
output wire o_fatal,o_pair_open,o_pair_poison,output wire [20*(WIDTH+1)-1:0] o_capacity,o_available,output wire o_done,o_shared,o_init_repeat,o_init_conflict, // Rx联合状态及共享ledger
output wire [6:0] o_tx_pending,output wire [72:0] o_tx_be,output wire [437:0] o_metadata,output wire [89:0] o_tx_validation_state, // Tx完整验证观察
output wire o_admission_wait,o_capacity_shortfall,output wire [119:0] o_requirements // 等待及容量不足本地诊断
); // 模块端口声明结束
wire core_allowed,core_error,admission_allow,admission_wait,capacity_shortfall; // 相互无反馈的候选与最终许可
 tl_credit_admission #(.WIDTH(WIDTH)) u_admission( // 只在实际Control位置检查所有后续信用
 .i_rstn(i_rstn),.i_control((o_tx_pending<=7'd1)&&!i_tx_msg[0]),.i_done(o_done),.i_shared(o_shared), // 同步低有效复位
 .i_half(i_tx_flit[255:0]),.i_available(o_available),.i_capacity(o_capacity), // 同一账本独占信用
 .o_requirements(o_requirements),.o_allow(admission_allow),.o_wait(admission_wait),.o_shortfall(capacity_shortfall) // 组合诊断
 ); // 完成整段信用准入实例端口连接
 tl_credit_port #(.WIDTH(WIDTH)) u_port( // 既有真实收发及逐对信用扣除
 .i_clk(i_clk), // 唯一输入时钟
 .i_rstn(i_rstn), // 同步低有效复位
 .i_receive(i_receive), // 实际收到Flit事件
 .i_send(i_send&&admission_allow), // 整段准入通过后允许实际发送
 .i_auth(i_auth), // 复位周期内固定认证分类模式
 .i_rx_flit(i_rx_flit), // 完整接收Flit
 .i_rx_msg(i_rx_msg), // 接收消息类型侧带
 .i_tx_flit(i_tx_flit), // 待发送完整Flit
 .i_tx_msg(i_tx_msg), // 待发送消息侧带
 .o_rx_allowed(o_rx_allowed), // 联合接收许可
 .o_rx_taken(o_rx_taken), // 唯一实际接收提交
 .o_rx_rejected(o_rx_rejected), // 接收拒绝诊断
 .o_tx_allowed(core_allowed), // 底层字段和当前信用联合许可
 .o_tx_taken(o_tx_taken), // 门控后的唯一实际发送提交
 .o_tx_error(core_error), // 底层发送格式错误
 .o_rx_lower(o_rx_lower), // 接收下半分类
 .o_rx_upper(o_rx_upper), // 接收上半分类
 .o_tx_lower(o_tx_lower), // 发送下半分类
 .o_tx_upper(o_tx_upper), // 发送上半分类
 .o_demands(o_demands), // 当前Flit实际逐对信用扣费需求
 .o_rx_pending(o_rx_pending), // 剩余接收tenure半Flit数
 .o_rx_be(o_rx_be), // 接收待处理BE标记
 .o_requests_available(o_requests_available), // 接收请求catch预算
 .o_responses_available(o_responses_available), // 接收响应catch预算
 .o_fatal(o_fatal), // 接收致命错误停止状态
 .o_pair_open(o_pair_open), // 接收Data对正在组装
 .o_pair_poison(o_pair_poison), // 接收Data对污染状态
 .o_capacity(o_capacity), // 对端初始化后的总物理信用容量
 .o_available(o_available), // 唯一发送账本当前余额
 .o_done(o_done), // 对端初始信用已完成
 .o_shared(o_shared), // 对端固定的共享Data Pool模式
 .o_init_repeat(o_init_repeat), // 重复初始化完成消息诊断
 .o_init_conflict(o_init_conflict), // 初始化共享模式冲突诊断
 .o_tx_pending(o_tx_pending), // 唯一发送序列剩余半Flit数
 .o_tx_be(o_tx_be), // 发送待处理BE标记
 .o_metadata(o_metadata), // 逐Data对信用所有权队列
 .o_tx_validation_state(o_tx_validation_state) // 完整发送验证状态观察
 ); // 全部状态仍由真实taken驱动
assign o_tx_allowed=core_allowed&&admission_allow; // 返回与真实发送提交一致的许可
assign o_tx_error=core_error; // 信用不足不是格式错误
assign o_admission_wait=admission_wait&&!core_error&&!o_fatal; // 只有合法候选才报告等待
assign o_capacity_shortfall=capacity_shortfall&&!core_error&&!o_fatal; // 不声称自动拆分超容量事务
endmodule // 结束tl_credit_admitted_port模块
