module tl_receive_credit_deferred #( // tl_receive_credit模块：实际接收FIFO与FC发布器的消费原子连接
parameter integer WIDTH=8, // 每逻辑信用槽初始容量位宽，范围1至16
parameter integer DEPTH=128, // 实际600位FIFO字数，容量预算同时验证
parameter integer COUNT_WIDTH=(DEPTH<2)?1:(DEPTH<4)?2:(DEPTH<8)?3:(DEPTH<16)?4:(DEPTH<32)?5:(DEPTH<64)?6:(DEPTH<128)?7:(DEPTH<256)?8:(DEPTH<512)?9:(DEPTH<1024)?10:(DEPTH<2048)?11:(DEPTH<4096)?12:(DEPTH<8192)?13:(DEPTH<16384)?14:(DEPTH<32768)?15:16 // 沿用真实FIFO位宽约束
,parameter integer CMD_COUNT_WIDTH=WIDTH+1 // Enough for each original configured account, with one guard bit.
)( // 同一输入时钟，外部链路适配层负责实际发送确认
input wire i_clk,i_rstn,i_start,i_shared,i_auth, // 配置只在当前链路初始化接纳一次
input wire [20*WIDTH-1:0] i_capacities, // 初始声明的20个实际缓冲资源容量
output wire o_start_ready,o_start_taken,o_config_error, // 预算不足时不发布部分初始信用
output wire [WIDTH+5:0] o_required_words, // 保守所需FIFO容量，供配置审计
input wire i_valid,input wire [511:0] i_flit,input wire [1:0] i_msg, // 实际入站本地Flit接口
output wire o_allowed,o_taken,o_rejected,o_fatal, // 与接收存储相同的接纳语义
input wire i_read_ready,output wire o_read_valid,output wire [511:0] o_read_flit, // 应用接纳必须同时交付释放向量
output wire [1:0] o_read_msg,output wire [5:0] o_read_classes,output wire [79:0] o_read_releases,output wire o_retired, // 完整保存字及消费事件
input wire i_fc_send,output wire o_fc_valid,o_fc_taken,o_fc_complete, // 只有实际发送才能确认FC或完成消息
output wire [511:0] o_fc_flit,output wire [1:0] o_fc_msg, // 由发布快照构造合法Control或MSG1
output wire o_active,o_done,output wire [20*(WIDTH+1)-1:0] o_pending, // 发布器初始化与未发归还状态
output wire [COUNT_WIDTH-1:0] o_count,output wire o_release_taken // 独立核对消费者和信用发布接纳事件
,output wire [79:0] o_rx_demands,output wire [663:0] o_epoch_context,output wire [89:0] o_epoch_validation, // I真实需求和未完成上下文。
output wire [48+20*(WIDTH+1):0] o_epoch_publish,output wire [20*(COUNT_WIDTH+4)-1:0] o_epoch_stored_releases, // 实际publisher与保存字释放聚合。
output wire [139:0] o_epoch_context_releases,output wire o_epoch_owner_error // 已预扣而尚未形成保存字释放的责任，不生成恢复许可。

,output wire o_epoch_store_taken // 原始600位保存字真实写入事件，不是候选valid。
,input wire i_cmd_release_valid,input wire [39:0] i_cmd_releases
,output wire o_cmd_release_taken,o_cmd_error,output wire [10*CMD_COUNT_WIDTH-1:0] o_cmd_pending
); // 结束外部接口
wire move_allowed,cmd_publish_valid;wire [39:0] cmd_vector;
wire retire_proposal=storage_valid&&i_read_ready;
wire [79:0] publish_vector={retire_proposal?o_read_releases[79:40]:40'd0,i_cmd_release_valid?cmd_vector:40'd0};
tl_deferred_command_credit #(.COUNT_WIDTH(CMD_COUNT_WIDTH)) Cmd_Owner_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_move(retire_proposal&&release_ready),.i_moved(o_read_releases[39:0]),.i_release_valid(i_cmd_release_valid),.i_releases(i_cmd_releases),.i_publish_ready(release_ready),.o_move_allowed(move_allowed),.o_publish_valid(cmd_publish_valid),.o_publish_releases(cmd_vector),.o_release_taken(o_cmd_release_taken),.o_pending(o_cmd_pending),.o_error(o_cmd_error));
wire budget_ok,pub_start_ready,pub_config_error,storage_valid,release_ready; // 预算及真实子模块握手
wire pub_valid,pub_taken,pub_complete,pub_shared;wire [31:0] pub_word; // 发布器寄存的待发消息
wire [2:0] unused_lower,unused_upper;wire [79:0] unused_demands,unused_proposed;wire unused_store; // 接收提议由子模块独立核验
wire [663:0] unused_context;wire [89:0] unused_validation;wire [48+20*(WIDTH+1):0] unused_publish_state; // 完整子状态可由层次审查观察
wire [WIDTH+4:0] capacity_sum[0:20]; // 20槽加法至多需要WIDTH加五位
assign capacity_sum[0]={(WIDTH+5){1'b0}}; // 求和起点常零
genvar index;generate for(index=0;index<20;index=index+1)begin : capacity_budget // 固定槽数展开配置和
 assign capacity_sum[index+1]=capacity_sum[index]+{5'd0,i_capacities[index*WIDTH+:WIDTH]}; // 无截断汇总每个已声明信用
end endgenerate // 不共享或重复计入合并后的Data Pool
assign o_required_words={capacity_sum[20],1'b0}; // 每CMD覆盖头和BE，每Data覆盖两半存储字
assign budget_ok=({{(26-WIDTH){1'b0}},o_required_words}<=DEPTH); // 与完整32位深度比较不发生窄化
assign o_start_ready=pub_start_ready&&budget_ok; // 两项配置条件必须同时成立
assign o_config_error=i_rstn&&i_start&&!o_active&&(!budget_ok||pub_config_error); // 错误仅属于尚未接纳配置
 tl_receive_storage #(.DEPTH(DEPTH),.COUNT_WIDTH(COUNT_WIDTH)) u_receive(.i_clk(i_clk),.i_rstn(i_rstn),.i_valid(i_valid),.i_auth(i_auth),.i_flit(i_flit),.i_msg(i_msg),.o_allowed(o_allowed),.o_taken(o_taken),.o_rejected(o_rejected),.o_fatal(o_fatal),.o_lower(unused_lower),.o_upper(unused_upper),.o_demands(unused_demands),.o_proposed_releases(unused_proposed),.o_store(unused_store),.i_read_ready(i_read_ready&&release_ready&&move_allowed),.o_read_valid(storage_valid),.o_read_flit(o_read_flit),.o_read_msg(o_read_msg),.o_read_classes(o_read_classes),.o_read_releases(o_read_releases),.o_retired(o_retired),.o_count(o_count),.o_context_state(unused_context),.o_validation_state(unused_validation)); // 真正FIFO退休由发布空间共同控制
assign o_read_valid=storage_valid&&release_ready&&move_allowed; // 应用观察到的握手与实际FIFO退休完全相同
 tl_credit_publish #(.WIDTH(WIDTH)) u_publish(.i_clk(i_clk),.i_rstn(i_rstn),.i_start(i_start&&budget_ok),.i_shared(i_shared),.i_capacities(i_capacities),.o_start_ready(pub_start_ready),.o_start_taken(o_start_taken),.o_config_error(pub_config_error),.i_release_valid(move_allowed&&(retire_proposal||cmd_publish_valid)),.i_releases(publish_vector),.o_release_ready(release_ready),.o_release_taken(o_release_taken),.i_send(i_fc_send&&!o_fatal),.o_valid(pub_valid),.o_taken(pub_taken),.o_complete(pub_complete),.o_shared(pub_shared),.o_word(pub_word),.o_active(o_active),.o_done(o_done),.o_pending(o_pending),.o_state(unused_publish_state)); // 实际保存元数据直接传入，禁止测试模型代替归还
assign o_fc_valid=pub_valid&&!o_fatal;assign o_fc_taken=pub_taken;assign o_fc_complete=o_fc_valid&&pub_complete; // fatal禁止发出旧信用
assign o_fc_flit=!o_fc_valid?512'd0:(pub_complete?{247'd0,pub_shared,8'd1,256'd0}:{480'd0,pub_word}); // 完成消息payload最低位表示共享Data Pool
assign o_fc_msg=o_fc_complete?2'd2:2'd0; // FC位于下半Control，MSG1位于上半消息
wire stored_owner_error; // 观察账本自身故障，不修改旧收发握手。
assign o_epoch_store_taken=o_taken&&unused_store; // 与原FIFO同沿，证书不能猜测分类。
assign o_rx_demands=unused_demands;assign o_epoch_context=unused_context;assign o_epoch_validation=unused_validation;assign o_epoch_publish=unused_publish_state; // 全部来自唯一原始状态所有者。
tl_receive_obligation_tracker #(.WIDTH(COUNT_WIDTH+4)) Epoch_Stored_Inst(.i_clk(i_clk),.i_rstn(i_rstn),.i_store(o_taken&&unused_store),.i_stored_releases(unused_proposed),.i_retire(o_retired),.i_retired_releases(o_read_releases),.o_pending(o_epoch_stored_releases),.o_error(stored_owner_error)); // 与真实600位字写入及实际退休保持同沿。
reg [139:0] context_releases;reg context_error;integer token,account; // 只归约实际注册token，不用I减C恒等式伪造责任。
always @*begin // 有界73个半Flit责任槽。
 context_releases=140'd0;context_error=1'b0;account=0; // 全赋值组合提议。
 if(unused_context[663:657]>7'd73)context_error=1'b1; // 无效窗口不能声称零责任。
 for(token=0;token<73;token=token+1)begin // 每个CMD末token至多归还一个CMD。
  if(token<{25'd0,unused_context[663:657]})begin // 只消费有效窗口，不把未来无效位当当前所有权。
   account={27'd0,unused_context[token*8+:5]}; // 真实Data类原账户。
   if((account<10)||(account>19))context_error=1'b1; // 所有有效Data/BE元数据须有原始CMD/Data归属。
   else begin // 容量范围已验证才做动态索引。
    if(unused_context[token*8+7])context_releases[(account-10)*7+:7]=context_releases[(account-10)*7+:7]+7'd1; // 所有剩余CMD均已在其Header真实预扣。
    if((token==0)&&unused_context[6])context_releases[account*7+:7]=context_releases[account*7+:7]+7'd1; // 只有队首第二半表示已接首半的Data责任，后续未来Data不得提前计入。
   end // 当前有效token归约结束。
  end // 有效窗口结束。
 end // 固定token扫描结束。
end // 只读组合归约结束。
assign o_epoch_context_releases=context_releases;assign o_epoch_owner_error=o_fatal||stored_owner_error||context_error||o_cmd_error; // 原状态错误与观察错误均阻止可信核账，上层承担停止策略。
generate if(CMD_COUNT_WIDTH<WIDTH)begin:invalid_command_capacity
 tl_receive_credit_deferred_command_width_invalid Invalid_Inst();
end endgenerate
endmodule // 结束实际存储消费与信用发布集成
