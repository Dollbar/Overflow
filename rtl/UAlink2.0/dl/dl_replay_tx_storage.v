module dl_replay_tx_storage #( // dl_replay_tx_storage模块：实际同步SRAM重放与输出保持槽
 parameter integer C_DEPTH = 255, // 精确逻辑存储容量
 parameter integer C_DATA_WIDTH = 32, // 不透明payload数据宽度，必须为正整字节
 parameter integer C_ADDR_WIDTH = (C_DEPTH <= 2) ? 1 : (C_DEPTH <= 4) ? 2 : (C_DEPTH <= 8) ? 3 : (C_DEPTH <= 16) ? 4 : (C_DEPTH <= 32) ? 5 : (C_DEPTH <= 64) ? 6 : (C_DEPTH <= 128) ? 7 : (C_DEPTH <= 256) ? 8 : (C_DEPTH <= 512) ? 9 : (C_DEPTH <= 1024) ? 10 : (C_DEPTH <= 2048) ? 11 : 12 // 与控制器匹配的派生地址宽度
,parameter integer C_EPOCH_SNAPSHOT_ENABLE=0,C_EPOCH_WIDTH=8,C_ATTEMPT_WIDTH=8 // 显式管理快照，默认关闭不改变普通DL路径。
) ( // 声明同域事务及输出握手
 input wire i_clk, // 同域事务、控制状态或完整输出观察
 input wire i_rstn, // 同域事务、控制状态或完整输出观察
 input wire i_link_reset, // 同域事务、控制状态或完整输出观察
 input wire i_ingress_event, // 同域事务、控制状态或完整输出观察
 input wire i_command_valid, // 同域事务、控制状态或完整输出观察
 input wire i_command_request, // 同域事务、控制状态或完整输出观察
 input wire [9-1:0] i_command_target, // 同域事务、控制状态或完整输出观察
 input wire i_issue, // 同域事务、控制状态或完整输出观察
 input wire i_payload, // 同域事务、控制状态或完整输出观察
 input wire [C_DATA_WIDTH-1:0] i_data, // 同域事务、控制状态或完整输出观察
 input wire i_out_ready, // 同域事务、控制状态或完整输出观察
 output wire o_issue_ready, // 同域事务、控制状态或完整输出观察
 output wire o_issue_accept, // 同域事务、控制状态或完整输出观察
 output wire o_payload_accept, // 同域事务、控制状态或完整输出观察
 output wire o_issue_payload, // 同域事务、控制状态或完整输出观察
 output wire o_issue_replay, // 同域事务、控制状态或完整输出观察
 output wire o_issue_first, // 同域事务、控制状态或完整输出观察
 output wire [9-1:0] o_issue_sequence, // 同域事务、控制状态或完整输出观察
 output wire o_out_valid, // 同域事务、控制状态或完整输出观察
 output wire o_out_payload, // 同域事务、控制状态或完整输出观察
 output wire o_out_replay, // 同域事务、控制状态或完整输出观察
 output wire o_out_first, // 同域事务、控制状态或完整输出观察
 output wire [9-1:0] o_out_sequence, // 同域事务、控制状态或完整输出观察
 output wire [C_DATA_WIDTH-1:0] o_out_data, // 同域事务、控制状态或完整输出观察
 output wire o_tag_error, // 同域事务、控制状态或完整输出观察
 output wire [9-1:0] o_out_stored_sequence, // 同域事务、控制状态或完整输出观察
 output wire o_ack_accept, // 同域事务、控制状态或完整输出观察
 output wire [8-1:0] o_ack_count, // 同域事务、控制状态或完整输出观察
 output wire o_request_accept, // 同域事务、控制状态或完整输出观察
 output wire o_command_reject, // 同域事务、控制状态或完整输出观察
 output wire [8-1:0] o_resident_count, // 同域事务、控制状态或完整输出观察
 output wire [9-1:0] o_ctl_last_sequence, // 同域事务、控制状态或完整输出观察
 output wire [9-1:0] o_ctl_last_ack, // 同域事务、控制状态或完整输出观察
 output wire [4-1:0] o_ctl_ignore_count, // 同域事务、控制状态或完整输出观察
 output wire [8-1:0] o_ctl_unacked_count, // 同域事务、控制状态或完整输出观察
 output wire [C_ADDR_WIDTH-1:0] o_ctl_head_pointer, // 同域事务、控制状态或完整输出观察
 output wire [C_ADDR_WIDTH-1:0] o_ctl_write_pointer, // 同域事务、控制状态或完整输出观察
 output wire [9-1:0] o_ctl_scheduled_sequence, // 同域事务、控制状态或完整输出观察
 output wire [8-1:0] o_ctl_scheduled_count, // 同域事务、控制状态或完整输出观察
 output wire [C_ADDR_WIDTH-1:0] o_ctl_scheduled_pointer, // 同域事务、控制状态或完整输出观察
 output wire o_ctl_first_pending // 同域事务、控制状态或完整输出观察
,input wire i_snapshot_begin,output wire o_snapshot_begin_ready, // 有效候选携带完整旧会话身份，握手一次建立快照责任。
 input wire i_snapshot_owner_error, // 上层实际DL诊断保持源，不能把数据遍历完成误当全链健康。
 input wire i_snapshot_scope,input wire [C_EPOCH_WIDTH-1:0] i_snapshot_epoch,i_current_epoch, // 已封闭本端范围与请求/实际时期。
 input wire [C_ATTEMPT_WIDTH-1:0] i_snapshot_attempt, // 本次管理尝试，不能以旧证书替代。
 input wire [1:0] i_snapshot_fenced,input wire [C_EPOCH_WIDTH-1:0] i_snapshot_fence_epoch,input wire [C_ATTEMPT_WIDTH-1:0] i_snapshot_fence_attempt, // 来自真实双向记录封闭服务。
 output wire o_snapshot_valid,input wire i_snapshot_ready, // 快照副本普通背压接口，消费不退休原DL存储。
 output wire [C_DATA_WIDTH-1:0] o_snapshot_data,output wire [8:0] o_snapshot_sequence, // 现有SRAM完整字与实际存储序号。
 output wire [7:0] o_snapshot_index,o_snapshot_count,output wire o_snapshot_last, // 精确窗口位置与最后副本，不能当成信用退款。
 output wire [C_EPOCH_WIDTH-1:0] o_snapshot_epoch,output wire [C_ATTEMPT_WIDTH-1:0] o_snapshot_attempt, // 只返回握手保存的身份。
 output wire o_snapshot_active,o_snapshot_done,o_snapshot_error // 完整读出成功资格持续检查；错误不清任何原有账。
); // 结束接口声明
localparam integer C_MAPPED_DEPTH = (C_DEPTH < 2) ? 2 : C_DEPTH; // 最小物理映射不扩大逻辑容量
localparam integer C_WORD_WIDTH = C_DATA_WIDTH + 16; // 九位序号与七位填充共同按字节保存
generate // 编译展开时检查数据宽度
 if ((C_DATA_WIDTH < 8) || ((C_DATA_WIDTH % 8) != 0)) begin : gen_invalid_width // 拒绝非整字节数据接口
  UALINK_REPLAY_STORAGE_WIDTH_INVALID invalid_width (); // 非法配置不能生成可用硬件
 end // 结束非法宽度分支
endgenerate // 结束参数检查
reg reg_valid; // 输出槽独立寄存状态
reg reg_payload; // 输出槽独立寄存状态
reg reg_replay; // 输出槽独立寄存状态
reg reg_first; // 输出槽独立寄存状态
reg [9-1:0] reg_sequence; // 输出槽独立寄存状态
reg [C_DATA_WIDTH-1:0] reg_normal_data; // 输出槽独立寄存状态
reg snapshot_active_q,snapshot_valid_q,snapshot_done_q,snapshot_fault_q; // 快照控制不复制原存储数据。
reg [C_ADDR_WIDTH-1:0] snapshot_pointer_q;reg [8:0] snapshot_sequence_q; // 下一实际SRAM地址及独立应有序号。
reg [7:0] snapshot_remaining_q,snapshot_count_q,snapshot_index_q; // 原窗口大小和已读副本进度。
reg [C_EPOCH_WIDTH-1:0] snapshot_epoch_q;reg [C_ATTEMPT_WIDTH-1:0] snapshot_attempt_q; // 管理身份保持至明确链路清理。
wire snapshot_requested,snapshot_hold,snapshot_begin_qualified,snapshot_qualified,snapshot_scope_fault,snapshot_tag_fault,snapshot_read; // 无ready反馈的管理资格链。
wire [C_ADDR_WIDTH-1:0] snapshot_next_pointer;wire [8:0] snapshot_next_sequence; // 精确物理环和非零线序号后继。
wire [C_ADDR_WIDTH-1:0] actual_read_address;wire actual_read_enable; // 快照和正常重放共用唯一真实SRAM读端口。
wire flag_active; // 复位和链路清除外的工作资格
wire normal_push; // 获得输出槽的正常源写入请求
wire [C_WORD_WIDTH-1:0] memory_write_data; // 写入实际SRAM的完整字及序号
wire [C_WORD_WIDTH-1:0] memory_read_data; // 实际同步SRAM沿后注册输出
wire ctl_ack_accept; // 已证明控制器原生观察
wire [8-1:0] ctl_ack_count; // 已证明控制器原生观察
wire ctl_request_accept; // 已证明控制器原生观察
wire ctl_command_reject; // 已证明控制器原生观察
wire unused_ctl_push_ready; // 已证明控制器原生观察
wire ctl_push_accept; // 已证明控制器原生观察
wire [9-1:0] ctl_push_sequence; // 已证明控制器原生观察
wire [C_ADDR_WIDTH-1:0] ctl_write_addr; // 已证明控制器原生观察
wire unused_ctl_replay_valid; // 已证明控制器原生观察
wire ctl_replay_take; // 已证明控制器原生观察
wire [9-1:0] ctl_replay_sequence; // 已证明控制器原生观察
wire [C_ADDR_WIDTH-1:0] ctl_replay_addr; // 已证明控制器原生观察
wire ctl_first_replay; // 已证明控制器原生观察
wire [8-1:0] ctl_resident_count; // 已证明控制器原生观察
wire [9-1:0] ctl_last_sequence; // 已证明控制器原生观察
wire [9-1:0] ctl_last_ack; // 已证明控制器原生观察
wire [4-1:0] ctl_ignore_count; // 已证明控制器原生观察
wire [8-1:0] ctl_unacked_count; // 已证明控制器原生观察
wire [C_ADDR_WIDTH-1:0] ctl_head_pointer; // 已证明控制器原生观察
wire [C_ADDR_WIDTH-1:0] ctl_write_pointer; // 已证明控制器原生观察
wire [9-1:0] ctl_scheduled_sequence; // 已证明控制器原生观察
wire [8-1:0] ctl_scheduled_count; // 已证明控制器原生观察
wire [C_ADDR_WIDTH-1:0] ctl_scheduled_pointer; // 已证明控制器原生观察
wire ctl_first_pending; // 已证明控制器原生观察
localparam [31:0] C_SNAPSHOT_LAST_ADDRESS_WIDE=C_DEPTH-1; // 派生常量先保留完整参数宽度。
localparam [C_ADDR_WIDTH-1:0] C_SNAPSHOT_LAST_ADDRESS=C_SNAPSHOT_LAST_ADDRESS_WIDE[C_ADDR_WIDTH-1:0]; // 精确物理末地址，受原容量参数保护。
assign snapshot_requested=(C_EPOCH_SNAPSHOT_ENABLE!=0)&&i_snapshot_begin; // 默认关闭忽略全部新增输入。
assign snapshot_hold=(C_EPOCH_SNAPSHOT_ENABLE!=0)&&(snapshot_requested||snapshot_active_q||snapshot_done_q||snapshot_fault_q); // 快照和完成保持期间禁止控制窗口变化。
assign snapshot_begin_qualified=!i_snapshot_owner_error&&i_snapshot_scope&&(&i_snapshot_fenced)&&(i_snapshot_epoch==i_current_epoch)&&(i_snapshot_fence_epoch==i_snapshot_epoch)&&(i_snapshot_fence_attempt==i_snapshot_attempt); // 双端实际证书必须与请求及当前会话同时匹配。
assign snapshot_qualified=!i_snapshot_owner_error&&i_snapshot_scope&&(&i_snapshot_fenced)&&(snapshot_epoch_q==i_current_epoch)&&(i_snapshot_fence_epoch==snapshot_epoch_q)&&(i_snapshot_fence_attempt==snapshot_attempt_q); // 已接纳责任不跟随候选字段漂移。
assign snapshot_scope_fault=(snapshot_active_q||snapshot_done_q)&&(!snapshot_qualified||i_issue||i_ingress_event); // 新原生事件违反真实封闭范围，同沿撤销完成资格。
assign snapshot_tag_fault=snapshot_active_q&&snapshot_valid_q&&(memory_read_data[C_DATA_WIDTH+:9]!=snapshot_sequence_q); // 用真实SRAM中的序号核查读地址/窗口一致性。
assign o_snapshot_error=(C_EPOCH_SNAPSHOT_ENABLE!=0)&&i_rstn&&!i_link_reset&&(snapshot_fault_q||snapshot_scope_fault||snapshot_tag_fault||(snapshot_requested&&!snapshot_active_q&&!snapshot_done_q&&(!snapshot_begin_qualified||i_issue||i_ingress_event))); // 非法管理和原生并发不能静默改变窗口。
assign o_snapshot_begin_ready=(C_EPOCH_SNAPSHOT_ENABLE!=0)&&i_rstn&&!i_link_reset&&!snapshot_active_q&&!snapshot_done_q&&!snapshot_fault_q&&snapshot_begin_qualified&&!reg_valid&&!i_issue&&!i_ingress_event; // 等待已预约输出转交，不撤销普通输出握手。
assign snapshot_read=(C_EPOCH_SNAPSHOT_ENABLE!=0)&&i_rstn&&!i_link_reset&&snapshot_active_q&&!snapshot_valid_q&&(snapshot_remaining_q!=8'd0)&&!o_snapshot_error; // 串行读取现有存储，消费者停顿时保持SRAM读使能关闭。
assign actual_read_enable=snapshot_read||ctl_replay_take; // snapshot_hold保证两个实际读源互斥。
assign actual_read_address=snapshot_read?snapshot_pointer_q:ctl_replay_addr; // 默认路径原样使用真实重放地址。
assign snapshot_next_pointer=(snapshot_pointer_q==C_SNAPSHOT_LAST_ADDRESS)?{C_ADDR_WIDTH{1'b0}}:snapshot_pointer_q+{{(C_ADDR_WIDTH-1){1'b0}},1'b1}; // 在精确非二次幂容量处环回。
assign snapshot_next_sequence=(snapshot_sequence_q==9'd511)?9'd1:snapshot_sequence_q+9'd1; // 与真实DL非零序号空间一致。
assign o_snapshot_valid=(C_EPOCH_SNAPSHOT_ENABLE!=0)&&i_rstn&&!i_link_reset&&snapshot_active_q&&snapshot_valid_q; // 已提供副本即使后续故障也保持到消费者取走，故障禁止完整证书。
assign o_snapshot_data=o_snapshot_valid?memory_read_data[C_DATA_WIDTH-1:0]:{C_DATA_WIDTH{1'b0}}; // 数据唯一来源是原SRAM完整保存字。
assign o_snapshot_sequence=o_snapshot_valid?memory_read_data[C_DATA_WIDTH+:9]:9'd0; // 不用预期序号伪造存储内容。
assign o_snapshot_index=snapshot_index_q;assign o_snapshot_count=snapshot_count_q; // 计数只描述本次快照副本。
assign o_snapshot_last=o_snapshot_valid&&(snapshot_remaining_q==8'd1); // last本身不等于成功快照完成。
assign o_snapshot_epoch=snapshot_epoch_q;assign o_snapshot_attempt=snapshot_attempt_q; // 快照身份公开供逐记录记账。
assign o_snapshot_active=(C_EPOCH_SNAPSHOT_ENABLE!=0)&&i_rstn&&!i_link_reset&&snapshot_active_q; // 故障状态仍保持原窗口的冻结责任。
assign o_snapshot_done=(C_EPOCH_SNAPSHOT_ENABLE!=0)&&i_rstn&&!i_link_reset&&snapshot_done_q&&snapshot_qualified&&!o_snapshot_error; // 只有最后副本真实消费后才能发布持续有效的遍历完成，不能据此复位信用。
always @(posedge i_clk)begin // 单时钟快照状态不修改真实DL指针或占用。
 if(!i_rstn||i_link_reset)begin snapshot_active_q<=1'b0;snapshot_valid_q<=1'b0;snapshot_done_q<=1'b0;snapshot_fault_q<=1'b0;snapshot_pointer_q<={C_ADDR_WIDTH{1'b0}};snapshot_sequence_q<=9'd0;snapshot_remaining_q<=8'd0;snapshot_count_q<=8'd0;snapshot_index_q<=8'd0;snapshot_epoch_q<={C_EPOCH_WIDTH{1'b0}};snapshot_attempt_q<={C_ATTEMPT_WIDTH{1'b0}};end // 实际DL清理只重置快照生命周期，不承担外部TL核账。
 else if(C_EPOCH_SNAPSHOT_ENABLE!=0)begin // 关闭时不参与正常DL事务。
  if(o_snapshot_error)begin snapshot_fault_q<=1'b1;if(snapshot_valid_q&&i_snapshot_ready)snapshot_valid_q<=1'b0;end // 错误锁存，允许已提供的副本完成握手但绝不生成完成证书。
  else if(snapshot_requested&&o_snapshot_begin_ready)begin // 原子保存真实窗口和管理身份。
   snapshot_epoch_q<=i_snapshot_epoch;snapshot_attempt_q<=i_snapshot_attempt;snapshot_count_q<=ctl_resident_count;snapshot_remaining_q<=ctl_resident_count;snapshot_index_q<=8'd0;snapshot_valid_q<=1'b0; // 只捕获计数，没有镜像payload阵列。
   snapshot_pointer_q<=(ctl_scheduled_count>ctl_unacked_count)?ctl_scheduled_pointer:ctl_head_pointer; // ACK超越尚未完成重放时必须保留更早的scheduled窗口。
   snapshot_sequence_q<=(ctl_scheduled_count>ctl_unacked_count)?ctl_scheduled_sequence:((ctl_last_ack==9'd511)?9'd1:ctl_last_ack+9'd1); // 用真实窗口头独立验证SRAM序号。
   snapshot_active_q<=(ctl_resident_count!=8'd0);snapshot_done_q<=(ctl_resident_count==8'd0); // 空窗口也需实际begin握手，不能绑常量ACK。
  end else if(snapshot_active_q)begin // 一次读取和一次副本消费分开，管理吞吐不改变真实事务。
   if(snapshot_read)snapshot_valid_q<=1'b1; // 同步SRAM本沿返回当前地址字，停顿期间不再读。
   else if(snapshot_valid_q&&i_snapshot_ready)begin snapshot_valid_q<=1'b0;snapshot_remaining_q<=snapshot_remaining_q-8'd1;snapshot_pointer_q<=snapshot_next_pointer;snapshot_sequence_q<=snapshot_next_sequence; // 每次实际副本握手推进一次。
    if(snapshot_remaining_q==8'd1)begin snapshot_active_q<=1'b0;snapshot_done_q<=1'b1;end else snapshot_index_q<=snapshot_index_q+8'd1; // 最后一次接纳才完成，不因valid或read使能提前结束。
   end // 结束快照副本消费。
  end // 结束活动窗口处理。
 end // 结束opt-in快照控制。
end // 结束快照时序逻辑。
assign flag_active = i_rstn && !i_link_reset; // 原生握手、状态或实际数据选择
assign o_issue_ready = flag_active && !snapshot_hold && (!reg_valid || i_out_ready); // 原生握手、状态或实际数据选择
assign o_issue_accept = i_issue && o_issue_ready; // 原生握手、状态或实际数据选择
assign normal_push = o_issue_accept && i_payload; // 原生握手、状态或实际数据选择
assign o_payload_accept = ctl_push_accept; // 原生握手、状态或实际数据选择
assign o_issue_payload = o_issue_accept && (ctl_replay_take || ctl_push_accept); // 原生握手、状态或实际数据选择
assign o_issue_replay = ctl_replay_take; // 原生握手、状态或实际数据选择
assign o_issue_first = ctl_replay_take && ctl_first_replay; // 原生握手、状态或实际数据选择
assign o_issue_sequence = o_issue_accept ? (ctl_replay_take ? ctl_replay_sequence : (ctl_push_accept ? ctl_push_sequence : ctl_last_sequence)) : 9'd0; // 原生握手、状态或实际数据选择
assign memory_write_data = {7'd0, ctl_push_sequence, i_data}; // 原生握手、状态或实际数据选择
assign o_out_valid = flag_active && reg_valid; // 原生握手、状态或实际数据选择
assign o_out_payload = o_out_valid && reg_payload; // 原生握手、状态或实际数据选择
assign o_out_replay = o_out_valid && reg_replay; // 原生握手、状态或实际数据选择
assign o_out_first = o_out_valid && reg_first; // 原生握手、状态或实际数据选择
assign o_out_sequence = o_out_valid ? reg_sequence : 9'd0; // 原生握手、状态或实际数据选择
assign o_out_data = o_out_payload ? (reg_replay ? memory_read_data[C_DATA_WIDTH-1:0] : reg_normal_data) : {C_DATA_WIDTH{1'b0}}; // 原生握手、状态或实际数据选择
assign o_out_stored_sequence = o_out_replay ? memory_read_data[C_DATA_WIDTH +: 9] : 9'd0; // 原生握手、状态或实际数据选择
assign o_tag_error = o_out_replay && (o_out_stored_sequence != reg_sequence); // 原生握手、状态或实际数据选择
assign o_ack_accept = ctl_ack_accept; // 原生握手、状态或实际数据选择
assign o_ack_count = ctl_ack_count; // 原生握手、状态或实际数据选择
assign o_request_accept = ctl_request_accept; // 原生握手、状态或实际数据选择
assign o_command_reject = ctl_command_reject; // 原生握手、状态或实际数据选择
assign o_resident_count = ctl_resident_count; // 原生握手、状态或实际数据选择
assign o_ctl_last_sequence = ctl_last_sequence; // 原生握手、状态或实际数据选择
assign o_ctl_last_ack = ctl_last_ack; // 原生握手、状态或实际数据选择
assign o_ctl_ignore_count = ctl_ignore_count; // 原生握手、状态或实际数据选择
assign o_ctl_unacked_count = ctl_unacked_count; // 原生握手、状态或实际数据选择
assign o_ctl_head_pointer = ctl_head_pointer; // 原生握手、状态或实际数据选择
assign o_ctl_write_pointer = ctl_write_pointer; // 原生握手、状态或实际数据选择
assign o_ctl_scheduled_sequence = ctl_scheduled_sequence; // 原生握手、状态或实际数据选择
assign o_ctl_scheduled_count = ctl_scheduled_count; // 原生握手、状态或实际数据选择
assign o_ctl_scheduled_pointer = ctl_scheduled_pointer; // 原生握手、状态或实际数据选择
assign o_ctl_first_pending = ctl_first_pending; // 原生握手、状态或实际数据选择
dl_replay_tx_control #( // 复用已证明的窗口与环地址控制
 .C_DEPTH(C_DEPTH), .C_ADDR_WIDTH(C_ADDR_WIDTH) // 精确逻辑容量与地址宽度
) u_control ( // 实例化同域控制器
 .i_clk(i_clk), // 原生控制接口连接
 .i_rstn(i_rstn), // 原生控制接口连接
 .i_link_reset(i_link_reset), // 原生控制接口连接
 .i_ingress_event(i_ingress_event&&!snapshot_hold), // 原生控制接口连接
 .i_command_valid(i_command_valid&&!snapshot_hold), // 原生控制接口连接
 .i_command_request(i_command_request), // 原生控制接口连接
 .i_command_target(i_command_target), // 原生控制接口连接
 .i_push(normal_push), // 原生控制接口连接
 .i_replay_take(o_issue_accept), // 原生控制接口连接
 .o_ack_accept(ctl_ack_accept), // 原生控制接口连接
 .o_ack_count(ctl_ack_count), // 原生控制接口连接
 .o_request_accept(ctl_request_accept), // 原生控制接口连接
 .o_command_reject(ctl_command_reject), // 原生控制接口连接
 .o_push_ready(unused_ctl_push_ready), // 原生控制接口连接
 .o_push_accept(ctl_push_accept), // 原生控制接口连接
 .o_push_sequence(ctl_push_sequence), // 原生控制接口连接
 .o_write_addr(ctl_write_addr), // 原生控制接口连接
 .o_replay_valid(unused_ctl_replay_valid), // 原生控制接口连接
 .o_replay_take(ctl_replay_take), // 原生控制接口连接
 .o_replay_sequence(ctl_replay_sequence), // 原生控制接口连接
 .o_replay_addr(ctl_replay_addr), // 原生控制接口连接
 .o_first_replay(ctl_first_replay), // 原生控制接口连接
 .o_resident_count(ctl_resident_count), // 原生控制接口连接
 .o_last_sequence(ctl_last_sequence), // 原生控制接口连接
 .o_last_ack(ctl_last_ack), // 原生控制接口连接
 .o_ignore_count(ctl_ignore_count), // 原生控制接口连接
 .o_unacked_count(ctl_unacked_count), // 原生控制接口连接
 .o_head_pointer(ctl_head_pointer), // 原生控制接口连接
 .o_write_pointer(ctl_write_pointer), // 原生控制接口连接
 .o_scheduled_sequence(ctl_scheduled_sequence), // 原生控制接口连接
 .o_scheduled_count(ctl_scheduled_count), // 原生控制接口连接
 .o_scheduled_pointer(ctl_scheduled_pointer), // 原生控制接口连接
 .o_first_pending(ctl_first_pending) // 原生控制接口连接
); // 结束u_control实例
kd28_fifo_sdp_storage_map #( // 绑定获授权的固定SDP真实模型或等端口物理宏
 .DATA_WIDTH(C_WORD_WIDTH), .DEPTH(C_MAPPED_DEPTH), .ADDR_WIDTH(C_ADDR_WIDTH) // 完整字宽与物理容量映射
) u_storage ( // 实例化共享时钟的实际SRAM存储
 .write_clk_i(i_clk), // 实际存储端口连接
 .write_cs_i(ctl_push_accept), // 实际存储端口连接
 .write_addr_i(ctl_write_addr), // 实际存储端口连接
 .write_data_i(memory_write_data), // 实际存储端口连接
 .read_clk_i(i_clk), // 实际存储端口连接
 .read_cs_i(actual_read_enable), // 实际存储端口连接
 .read_addr_i(actual_read_address), // 实际存储端口连接
 .read_data_o(memory_read_data) // 实际存储端口连接
); // 结束u_storage实例
always @(posedge i_clk) begin // reg_valid独立输出槽寄存
 if (!i_rstn) begin // 同步低有效复位
  reg_valid <= 1'b0; // 清除输出槽状态
 end else if (i_link_reset) begin // 同步链路清除
  reg_valid <= 1'b0; // 旧SRAM内容不能重新发布
 end else if (o_issue_accept) begin // 已预约事务或旧输出消费
  reg_valid <= 1'b1; // 与实际SRAM读采样沿对齐
 end else if (i_out_ready) begin // 已预约事务或旧输出消费
  reg_valid <= 1'b0; // 与实际SRAM读采样沿对齐
 end // 结束更新分支，停顿时保持
end // 结束reg_valid寄存块
always @(posedge i_clk) begin // reg_payload独立输出槽寄存
 if (!i_rstn) begin // 同步低有效复位
  reg_payload <= 1'b0; // 清除输出槽状态
 end else if (i_link_reset) begin // 同步链路清除
  reg_payload <= 1'b0; // 旧SRAM内容不能重新发布
 end else if (o_issue_accept) begin // 已预约事务或旧输出消费
  reg_payload <= o_issue_payload; // 与实际SRAM读采样沿对齐
 end // 结束更新分支，停顿时保持
end // 结束reg_payload寄存块
always @(posedge i_clk) begin // reg_replay独立输出槽寄存
 if (!i_rstn) begin // 同步低有效复位
  reg_replay <= 1'b0; // 清除输出槽状态
 end else if (i_link_reset) begin // 同步链路清除
  reg_replay <= 1'b0; // 旧SRAM内容不能重新发布
 end else if (o_issue_accept) begin // 已预约事务或旧输出消费
  reg_replay <= o_issue_replay; // 与实际SRAM读采样沿对齐
 end // 结束更新分支，停顿时保持
end // 结束reg_replay寄存块
always @(posedge i_clk) begin // reg_first独立输出槽寄存
 if (!i_rstn) begin // 同步低有效复位
  reg_first <= 1'b0; // 清除输出槽状态
 end else if (i_link_reset) begin // 同步链路清除
  reg_first <= 1'b0; // 旧SRAM内容不能重新发布
 end else if (o_issue_accept) begin // 已预约事务或旧输出消费
  reg_first <= o_issue_first; // 与实际SRAM读采样沿对齐
 end // 结束更新分支，停顿时保持
end // 结束reg_first寄存块
always @(posedge i_clk) begin // reg_sequence独立输出槽寄存
 if (!i_rstn) begin // 同步低有效复位
  reg_sequence <= 9'd0; // 清除输出槽状态
 end else if (i_link_reset) begin // 同步链路清除
  reg_sequence <= 9'd0; // 旧SRAM内容不能重新发布
 end else if (o_issue_accept) begin // 已预约事务或旧输出消费
  reg_sequence <= o_issue_sequence; // 与实际SRAM读采样沿对齐
 end // 结束更新分支，停顿时保持
end // 结束reg_sequence寄存块
always @(posedge i_clk) begin // reg_normal_data独立输出槽寄存
 if (!i_rstn) begin // 同步低有效复位
  reg_normal_data <= {C_DATA_WIDTH{1'b0}}; // 清除输出槽状态
 end else if (i_link_reset) begin // 同步链路清除
  reg_normal_data <= {C_DATA_WIDTH{1'b0}}; // 旧SRAM内容不能重新发布
 end else if (ctl_push_accept) begin // 已预约事务或旧输出消费
  reg_normal_data <= i_data; // 与实际SRAM读采样沿对齐
 end else if (o_issue_accept) begin // 已预约事务或旧输出消费
  reg_normal_data <= {C_DATA_WIDTH{1'b0}}; // 与实际SRAM读采样沿对齐
 end // 结束更新分支，停顿时保持
end // 结束reg_normal_data寄存块
wire [6:0] unused_memory_padding = memory_read_data[C_WORD_WIDTH-1:C_DATA_WIDTH+9]; // 存储整字节对齐的七位填充不属于payload或sequence。
endmodule // 结束dl_replay_tx_storage模块
