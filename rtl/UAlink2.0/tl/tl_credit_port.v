module tl_credit_port #(parameter WIDTH=16)( // 真实Rx信用与Tx关联上下文，WIDTH至少8
input wire i_clk,i_rstn,i_receive,i_send,i_auth,input wire [511:0] i_rx_flit,input wire [1:0] i_rx_msg,input wire [511:0] i_tx_flit,input wire [1:0] i_tx_msg, // 双向实际字段
output wire o_rx_allowed,o_rx_taken,o_rx_rejected,o_tx_allowed,o_tx_taken,o_tx_error, // 联合接纳
output wire [2:0] o_rx_lower,o_rx_upper,o_tx_lower,o_tx_upper,output wire [79:0] o_demands, // 分类与字段生成的需求
output wire [6:0] o_rx_pending,output wire [72:0] o_rx_be,output wire [2:0] o_requests_available,output wire [3:0] o_responses_available, // 接收队列和预算
output wire o_fatal,o_pair_open,o_pair_poison,output wire [20*(WIDTH+1)-1:0] o_capacity,o_available,output wire o_done,o_shared,o_init_repeat,o_init_conflict, // Rx联合状态及共享ledger
output wire [6:0] o_tx_pending,output wire [72:0] o_tx_be,output wire [437:0] o_metadata,output wire [89:0] o_tx_validation_state // Tx完整验证观察
); // 尚待Tx完整内容及接收缓冲集成
wire context_allowed,credit_allowed,unused_context_taken,unused_context_rejected; // 相互独立提议
wire full_allowed,unused_full_taken,unused_full_rejected,tx_fatal,tx_open,tx_poison; // 完整Tx提议
wire [6:0] tx_pending;wire [72:0] tx_be;wire [2:0] tx_requests,unused_context_lower,unused_context_upper;wire [3:0] tx_responses; // Tx完整状态
wire unused_credit_taken; // 有信用发送子事件
wire credit_free=!(|o_demands); // 无CMD/Data预留的合法候选
wire tx_valid=context_allowed&&full_allowed; // 两个Tx检查共同允许
wire rx_joint=i_rstn&&!o_fatal&&(!i_receive||o_rx_allowed); // 无信用发送同样受Rx联合停止约束
wire [20*WIDTH-1:0] extended_demands; // 无外部规范化需求端口
 tl_credit_context u_context(i_clk,i_rstn,o_tx_taken,i_auth,i_tx_flit[255:0],i_tx_msg,i_tx_flit[7:0],i_tx_flit[263:256],context_allowed,unused_context_taken,unused_context_rejected,unused_context_lower,unused_context_upper,o_demands,o_tx_pending,o_tx_be,o_metadata); // 联合发送成功后推进
genvar j;generate for(j=0;j<20;j=j+1)begin:extend_demand // 保留所有四位需求
 assign extended_demands[j*WIDTH+:WIDTH]={{(WIDTH-4){1'b0}},o_demands[j*4+:4]}; // 无损扩宽
end endgenerate // 扩宽结束
 tl_credit_integration #(.WIDTH(WIDTH)) u_rx(i_clk,i_rstn,i_receive,i_send&&tx_valid&&!credit_free,i_auth,i_rx_flit,i_rx_msg,extended_demands,o_rx_allowed,o_rx_taken,o_rx_rejected,credit_allowed,unused_credit_taken,o_rx_lower,o_rx_upper,o_rx_pending,o_rx_be,o_requests_available,o_responses_available,o_fatal,o_pair_open,o_pair_poison,o_capacity,o_available,o_done,o_shared,o_init_repeat,o_init_conflict); // 真实FC与MSG进入同一ledger
 tl_full_flit u_tx_validation(i_clk,i_rstn,o_tx_taken,i_auth,i_tx_flit,i_tx_msg,full_allowed,unused_full_taken,unused_full_rejected,o_tx_lower,o_tx_upper,tx_pending,tx_be,tx_requests,tx_responses,tx_fatal,tx_open,tx_poison); // 全部Tx状态只在联合接纳推进
assign o_tx_validation_state={tx_pending,tx_be,tx_requests,tx_responses,tx_fatal,tx_open,tx_poison}; // 完整输出状态
assign o_tx_allowed=tx_valid&&(credit_free?rx_joint:credit_allowed); // 启动控制流无需预先取得信用
assign o_tx_taken=i_send&&o_tx_allowed; // 唯一对外发送提交
assign o_tx_error=i_rstn&&!tx_valid; // 本地无效提议可修正
endmodule // 真实收发内容与信用集成结束
