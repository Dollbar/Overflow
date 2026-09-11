module integration_reference #(parameter WIDTH=16)( // 实际Flit信用集成，WIDTH至少8
input wire i_clk,i_rstn,i_receive,i_send,i_auth, // 接收尝试与发送候选，auth复位间固定
input wire [511:0] i_flit,input wire [1:0] i_msg, // 实际线上两半及消息侧带
input wire [20*WIDTH-1:0] i_demands, // 本地发送信用需求，关联头生成在上层
output wire o_rx_allowed,o_rx_taken,o_rx_rejected,o_tx_allowed,o_tx_taken, // 收发结果
output wire [2:0] o_lower,o_upper,output wire [6:0] o_pending,output wire [72:0] o_be, // 分类状态
output wire [2:0] o_requests_available,output wire [3:0] o_responses_available, // 打包预算
output wire o_fatal,o_pair_open,o_pair_poison, // 全局停止及Data配对
output wire [20*(WIDTH+1)-1:0] o_capacity,o_available, // 全信用状态
output wire o_done,o_shared,o_init_repeat,o_init_conflict,invariant // 初始化模式及本地重复诊断
); // 接口结束
reg r_fatal; // 联合错误锁存
wire full_allowed,full_fatal,ledger_allowed,ledger_error,events_valid; // 各模块独立评估
wire unused_full_taken,unused_full_rejected;wire [2:0] lower,upper; // 子模块分类提议
wire [159:0] grants;wire [1:0] init,shared,unused_nop,unused_poison; // 两个实际消息事件
wire [20*WIDTH-1:0] extended_grants; // 单Flit八位累积量扩展
wire control=(o_pending<=7'd1)&&!i_msg[0]; // Data负载不能当Control解析
wire mode=o_done?o_shared:(init[0]?shared[0]:shared[1]); // 首次线上顺序完成锁定模式
wire joint_commit=!o_fatal&&(!i_receive||o_rx_allowed); // 无组合反馈的最终账本提交
 full_reference u_full(i_clk,i_rstn,o_rx_taken,i_auth,i_flit,i_msg,full_allowed,unused_full_taken,unused_full_rejected,lower,upper,o_pending,o_be,o_requests_available,o_responses_available,full_fatal,o_pair_open,o_pair_poison); // 单共同接受驱动独立接收参考
 tl_credit_events u_events(i_flit[255:0],i_flit[511:256],i_msg,control,events_valid,grants,unused_nop,init,shared,unused_poison); // 真实线上信用事件
 genvar j;generate for(j=0;j<20;j=j+1)begin:extend_grant // 每槽无损扩宽
  assign extended_grants[j*WIDTH+:WIDTH]={{(WIDTH-8){1'b0}},grants[j*8+:8]}; // 保留全部累加位
 end endgenerate // 扩宽结束
 ledger_reference #(.WIDTH(WIDTH)) u_ledger(i_clk,i_rstn,joint_commit,i_receive,i_send,|init,mode,extended_grants,i_demands,ledger_allowed,o_tx_taken,ledger_error,o_capacity,o_available,o_done,o_shared,invariant); // 候选评估与提交分离
assign o_fatal=r_fatal||full_fatal; // 任一接收错误停止全部转发
assign o_rx_allowed=i_rstn&&!o_fatal&&full_allowed&&events_valid&&!ledger_error; // 共同准入
assign o_rx_taken=i_receive&&o_rx_allowed; // 接收最终接受
assign o_rx_rejected=i_rstn&&i_receive&&!o_rx_allowed; // 接收拒绝
assign o_tx_allowed=ledger_allowed&&joint_commit; // 正常缺信用只等待
assign o_lower=o_rx_allowed?lower:3'd7;assign o_upper=o_rx_allowed?upper:3'd7; // 不暴露部分分类
assign o_init_repeat=i_rstn&&!o_fatal&&i_receive&&(|init)&&(o_done||(&init)); // 重复只作本地诊断
assign o_init_conflict=i_rstn&&!o_fatal&&i_receive&&((init[0]&&(shared[0]!=mode))||(init[1]&&(shared[1]!=mode))); // 不改写已锁定模式
always @(posedge i_clk)begin // 唯一同步时钟
 if(!i_rstn)r_fatal<=1'b0; // 复位清除联合停止
 else if(i_receive&&!o_rx_allowed)r_fatal<=1'b1; // 接收异常锁存
end // 时序结束
endmodule // 集成顶层结束
