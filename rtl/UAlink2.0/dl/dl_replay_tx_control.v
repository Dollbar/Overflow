module dl_replay_tx_control #( // dl_replay_tx_control模块：ACK窗口与实际重放存储环控制
 parameter integer C_DEPTH = 255, // 物理逻辑容量，一至四千零九十五
 parameter integer C_ADDR_WIDTH = (C_DEPTH <= 2) ? 1 : (C_DEPTH <= 4) ? 2 : (C_DEPTH <= 8) ? 3 : (C_DEPTH <= 16) ? 4 : (C_DEPTH <= 32) ? 5 : (C_DEPTH <= 64) ? 6 : (C_DEPTH <= 128) ? 7 : (C_DEPTH <= 256) ? 8 : (C_DEPTH <= 512) ? 9 : (C_DEPTH <= 1024) ? 10 : (C_DEPTH <= 2048) ? 11 : 12 // 派生地址宽度，至少一位
) ( // 声明单域存储事务接口
 input wire i_clk, // 原生同域状态或事务接口
 input wire i_rstn, // 原生同域状态或事务接口
 input wire i_link_reset, // 原生同域状态或事务接口
 input wire i_ingress_event, // 原生同域状态或事务接口
 input wire i_command_valid, // 原生同域状态或事务接口
 input wire i_command_request, // 原生同域状态或事务接口
 input wire [8:0] i_command_target, // 原生同域状态或事务接口
 input wire i_push, // 原生同域状态或事务接口
 input wire i_replay_take, // 原生同域状态或事务接口
 output wire o_ack_accept, // 原生同域状态或事务接口
 output wire [7:0] o_ack_count, // 原生同域状态或事务接口
 output wire o_request_accept, // 原生同域状态或事务接口
 output wire o_command_reject, // 原生同域状态或事务接口
 output wire o_push_ready, // 原生同域状态或事务接口
 output wire o_push_accept, // 原生同域状态或事务接口
 output wire [8:0] o_push_sequence, // 原生同域状态或事务接口
 output wire [C_ADDR_WIDTH-1:0] o_write_addr, // 原生同域状态或事务接口
 output wire o_replay_valid, // 原生同域状态或事务接口
 output wire o_replay_take, // 原生同域状态或事务接口
 output wire [8:0] o_replay_sequence, // 原生同域状态或事务接口
 output wire [C_ADDR_WIDTH-1:0] o_replay_addr, // 原生同域状态或事务接口
 output wire o_first_replay, // 原生同域状态或事务接口
 output wire [7:0] o_resident_count, // 原生同域状态或事务接口
 output wire [8:0] o_last_sequence, // 原生同域状态或事务接口
 output wire [8:0] o_last_ack, // 原生同域状态或事务接口
 output wire [3:0] o_ignore_count, // 原生同域状态或事务接口
 output wire [7:0] o_unacked_count, // 原生同域状态或事务接口
 output wire [C_ADDR_WIDTH-1:0] o_head_pointer, // 原生同域状态或事务接口
 output wire [C_ADDR_WIDTH-1:0] o_write_pointer, // 原生同域状态或事务接口
 output wire [8:0] o_scheduled_sequence, // 原生同域状态或事务接口
 output wire [7:0] o_scheduled_count, // 原生同域状态或事务接口
 output wire [C_ADDR_WIDTH-1:0] o_scheduled_pointer, // 原生同域状态或事务接口
 output wire o_first_pending // 原生同域状态或事务接口
); // 结束接口声明
localparam integer C_EXPECTED_ADDR_WIDTH = (C_DEPTH <= 2) ? 1 : (C_DEPTH <= 4) ? 2 : (C_DEPTH <= 8) ? 3 : (C_DEPTH <= 16) ? 4 : (C_DEPTH <= 32) ? 5 : (C_DEPTH <= 64) ? 6 : (C_DEPTH <= 128) ? 7 : (C_DEPTH <= 256) ? 8 : (C_DEPTH <= 512) ? 9 : (C_DEPTH <= 1024) ? 10 : (C_DEPTH <= 2048) ? 11 : 12; // 精确物理地址位宽
localparam [12:0] C_DEPTH_VALUE = C_DEPTH[12:0]; // 地址运算使用十三位容量
localparam [8:0] C_MAX_LIVE = (C_DEPTH < 255) ? C_DEPTH[8:0] : 9'd255; // 协议与物理容量共同限制
generate // 参数在展开时检查
 if ((C_DEPTH < 1) || (C_DEPTH > 4095) || (C_ADDR_WIDTH != C_EXPECTED_ADDR_WIDTH)) begin : gen_invalid // 拒绝非法参数组合
  UALINK_REPLAY_PARAMETERS_INVALID invalid_parameters (); // 非法参数禁止生成可用硬件
 end // 结束非法参数分支
endgenerate // 结束参数展开检查
reg [8:0] reg_last_sequence; // 独立当前寄存状态
reg [8:0] reg_last_ack; // 独立当前寄存状态
reg [3:0] cnt_ignore; // 独立当前寄存状态
reg [7:0] cnt_unacked; // 独立当前寄存状态
reg [C_ADDR_WIDTH-1:0] reg_head; // 独立当前寄存状态
reg [C_ADDR_WIDTH-1:0] reg_write; // 独立当前寄存状态
reg [8:0] reg_replay_sequence; // 独立当前寄存状态
reg [7:0] cnt_scheduled; // 独立当前寄存状态
reg [C_ADDR_WIDTH-1:0] reg_replay_pointer; // 独立当前寄存状态
reg reg_first; // 独立当前寄存状态
wire flag_active; // 复位和链路清除外的资格
wire flag_command; // 有效命令必须属于真实接收事件
wire [3:0] dec_ignore; // 按事件先递减并饱和
wire [9:0] dec_ack_sum; // 前向十位差，最高位表示借位
wire [9:0] dec_tail_sum; // 尾部到目标的十位差，最高位表示借位
wire [9:0] dec_ack_mod; // 借位时低九位减一，非借位保留五百一十一边界
wire [9:0] dec_tail_mod; // 尾部差的借位修正，零及五百一十一边界保持
wire [8:0] dec_distance; // 前向距离
wire flag_in_buffer; // 非零目标及实际数量下溢保护
wire flag_ack; // 两端ACK窗口包含目标
wire flag_request; // 请求必须位于未确认区且先递减后的忽略为零
wire [7:0] dec_live; // 先释放ACK再决定新写资格
wire [8:0] dec_request_count; // 请求从目标到当前尾部的项数
wire [7:0] dec_scheduled; // 本拍命令之后的重放数量
wire [12:0] dec_head_sum; // ACK释放对应实际地址前移
wire [12:0] dec_head_mod; // 非二次幂容量只减一次
wire [12:0] dec_request_sum; // 目标在当前未确认区中的实际地址
wire [12:0] dec_request_mod; // 请求地址物理环回
wire [C_ADDR_WIDTH-1:0] dec_replay_pointer; // 命令更新之后的首个重放地址
wire [8:0] dec_replay_sequence; // 命令更新之后的首个重放序号
wire [8:0] dec_next_sequence; // 正常写入分配合法环后继
wire [8:0] dec_next_replay_sequence; // 消耗后推进合法重放序号
wire [C_ADDR_WIDTH-1:0] dec_write_next; // 写地址在精确容量处环回
wire [C_ADDR_WIDTH-1:0] dec_replay_next; // 读地址在精确容量处环回
wire flag_scheduled; // 请求成功必定至少安排一项，直接生成重放资格
wire flag_live_room; // 命令前窗口是否已有容量
wire [8:0] dec_live_threshold; // 满窗口分支中提前计算所需释放数量阈值
wire flag_ack_room; // 有效ACK释放足够条目后的新写资格
wire [9:0] dec_window_sum; // 提前计算当前确认序号加未确认数量
wire flag_window_wrap; // 有效目标环跨越五百一十一边界
wire [8:0] dec_window_end; // 当前未确认区间的非零环末端
wire [8:0] dec_tail_anchor; // 零尾序号在非零目标距离中等效为五百一十一
wire [8:0] dec_ack_lower; // ACK尾部允许区间的提前下界
wire [8:0] dec_request_lower; // Request尾部允许区间的提前下界
wire flag_tail_ack; // 晚到目标直接比较ACK尾窗口
wire flag_tail_request; // 晚到目标直接比较Request尾窗口
assign dec_window_sum = {1'b0, reg_last_ack} + {2'b00, cnt_unacked}; // 十位无溢出状态端点
assign flag_window_wrap = dec_window_sum[9]; // 总和大于五百一十一才跨越非零环
assign dec_window_end = flag_window_wrap ? dec_window_sum - 10'd511 : dec_window_sum[8:0]; // 环回下界由状态提前计算
assign dec_tail_anchor = (reg_last_sequence == 9'd0) ? 9'd511 : reg_last_sequence; // 任意当前状态仍保留零尾距离语义
assign dec_ack_lower = (dec_tail_anchor <= 9'd255) ? dec_tail_anchor + 9'd256 : dec_tail_anchor - 9'd255; // 包含尾距离二百五十五的环回端点
assign dec_request_lower = (dec_tail_anchor <= 9'd254) ? dec_tail_anchor + 9'd257 : dec_tail_anchor - 9'd254; // Request尾距离最多二百五十四
assign flag_tail_ack = (dec_tail_anchor <= 9'd255) ? ((i_command_target <= dec_tail_anchor) || (i_command_target >= dec_ack_lower)) : ((i_command_target <= dec_tail_anchor) && (i_command_target >= dec_ack_lower)); // 跨环取两个区间，否则取连续区间
assign flag_tail_request = (dec_tail_anchor <= 9'd254) ? ((i_command_target <= dec_tail_anchor) || (i_command_target >= dec_request_lower)) : ((i_command_target <= dec_tail_anchor) && (i_command_target >= dec_request_lower)); // 边界等号保留五百一十一目标
assign flag_active = i_rstn && !i_link_reset; // 复位和链路清除外的资格
assign flag_command = flag_active && i_ingress_event && i_command_valid; // 有效命令必须属于真实接收事件
assign dec_ignore = (i_ingress_event && (cnt_ignore != 4'd0)) ? cnt_ignore - 4'd1 : cnt_ignore; // 按事件先递减并饱和
assign dec_ack_sum = {1'b0, i_command_target} - {1'b0, reg_last_ack}; // 前向十位差，最高位表示借位
assign dec_tail_sum = {1'b0, reg_last_sequence} - {1'b0, i_command_target}; // 尾部到目标的十位差，最高位表示借位
assign dec_ack_mod = {1'b0, dec_ack_sum[8:0]} - {9'd0, dec_ack_sum[9]}; // 借位时低九位减一，非借位保留五百一十一边界
assign dec_tail_mod = {1'b0, dec_tail_sum[8:0]} - {9'd0, dec_tail_sum[9]}; // 尾部差的借位修正，零及五百一十一边界保持
assign dec_distance = dec_ack_mod[8:0]; // 前向距离
assign flag_in_buffer = (i_command_target != 9'd0) && ((i_command_target >= reg_last_ack) ? (flag_window_wrap || (i_command_target <= dec_window_end)) : (flag_window_wrap && (i_command_target <= dec_window_end))); // 提前状态端点与晚到目标直接比较，包含重复ACK
assign flag_ack = flag_command && !i_command_request && flag_in_buffer && flag_tail_ack; // 八位数量窗口已保证前向距离不超过二百五十五
assign flag_request = flag_command && i_command_request && flag_in_buffer && (dec_ignore == 4'd0) && (i_command_target != reg_last_ack) && flag_tail_request; // Request排除重复确认目标并保留忽略计数优先级
assign dec_live = flag_ack ? cnt_unacked - dec_distance[7:0] : cnt_unacked; // 先释放ACK再决定新写资格
assign dec_request_count = {1'b0, cnt_unacked} - dec_distance + 9'd1; // 请求从目标到当前尾部的项数
assign dec_scheduled = flag_request ? dec_request_count[7:0] : cnt_scheduled; // 本拍命令之后的重放数量
assign dec_head_sum = {{(13-C_ADDR_WIDTH){1'b0}}, reg_head} + {4'd0, dec_distance}; // ACK释放对应实际地址前移
assign dec_head_mod = (dec_head_sum >= C_DEPTH_VALUE) ? dec_head_sum - C_DEPTH_VALUE : dec_head_sum; // 非二次幂容量只减一次
assign dec_request_sum = {{(13-C_ADDR_WIDTH){1'b0}}, reg_head} + {4'd0, dec_distance} - 13'd1; // 目标在当前未确认区中的实际地址
assign dec_request_mod = (dec_request_sum >= C_DEPTH_VALUE) ? dec_request_sum - C_DEPTH_VALUE : dec_request_sum; // 请求地址物理环回
assign dec_replay_pointer = flag_request ? dec_request_mod[C_ADDR_WIDTH-1:0] : reg_replay_pointer; // 命令更新之后的首个重放地址
assign dec_replay_sequence = flag_request ? i_command_target : reg_replay_sequence; // 命令更新之后的首个重放序号
assign dec_next_sequence = (reg_last_sequence == 9'd511) ? 9'd1 : reg_last_sequence + 9'd1; // 正常写入分配合法环后继
assign dec_next_replay_sequence = (dec_replay_sequence == 9'd511) ? 9'd1 : dec_replay_sequence + 9'd1; // 消耗后推进合法重放序号
assign dec_write_next = (reg_write == C_DEPTH_VALUE[C_ADDR_WIDTH-1:0] - {{(C_ADDR_WIDTH-1){1'b0}}, 1'b1}) ? {C_ADDR_WIDTH{1'b0}} : reg_write + {{(C_ADDR_WIDTH-1){1'b0}}, 1'b1}; // 写地址在精确容量处环回
assign dec_replay_next = (dec_replay_pointer == C_DEPTH_VALUE[C_ADDR_WIDTH-1:0] - {{(C_ADDR_WIDTH-1){1'b0}}, 1'b1}) ? {C_ADDR_WIDTH{1'b0}} : dec_replay_pointer + {{(C_ADDR_WIDTH-1){1'b0}}, 1'b1}; // 读地址在精确容量处环回
assign o_ack_accept = flag_ack; // 原生状态或沿前提交观察
assign o_ack_count = flag_ack ? dec_distance[7:0] : 8'd0; // 原生状态或沿前提交观察
assign o_request_accept = flag_request; // 原生状态或沿前提交观察
assign o_command_reject = flag_command && !flag_ack && !flag_request; // 原生状态或沿前提交观察
assign flag_scheduled = flag_request || (cnt_scheduled != 8'd0); // 有效请求项数非零，避免先计算数量再判零
assign flag_live_room = ({1'b0, cnt_unacked} < C_MAX_LIVE); // 只依赖当前寄存器的提前容量比较
assign dec_live_threshold = {1'b0, cnt_unacked} - C_MAX_LIVE; // 阈值只在当前数量不小于容量时参与判定
assign flag_ack_room = flag_ack && (dec_distance > dec_live_threshold); // 有效ACK保证无下溢，严格释放超过满窗口阈值
assign o_push_ready = flag_active && !flag_scheduled && (flag_live_room || flag_ack_room); // 原生状态或沿前提交观察
assign o_push_accept = o_push_ready && i_push; // 原生状态或沿前提交观察
assign o_push_sequence = o_push_ready ? dec_next_sequence : 9'd0; // 原生状态或沿前提交观察
assign o_write_addr = o_push_ready ? reg_write : {C_ADDR_WIDTH{1'b0}}; // 原生状态或沿前提交观察
assign o_replay_valid = flag_active && flag_scheduled; // 原生状态或沿前提交观察
assign o_replay_take = o_replay_valid && i_replay_take; // 原生状态或沿前提交观察
assign o_replay_sequence = o_replay_valid ? dec_replay_sequence : 9'd0; // 原生状态或沿前提交观察
assign o_replay_addr = o_replay_valid ? dec_replay_pointer : {C_ADDR_WIDTH{1'b0}}; // 原生状态或沿前提交观察
assign o_first_replay = o_replay_valid && (flag_request || reg_first); // 原生状态或沿前提交观察
assign o_resident_count = (cnt_unacked > cnt_scheduled) ? cnt_unacked : cnt_scheduled; // 原生状态或沿前提交观察
assign o_last_sequence = reg_last_sequence; // 原生状态或沿前提交观察
assign o_last_ack = reg_last_ack; // 原生状态或沿前提交观察
assign o_ignore_count = cnt_ignore; // 原生状态或沿前提交观察
assign o_unacked_count = cnt_unacked; // 原生状态或沿前提交观察
assign o_head_pointer = reg_head; // 原生状态或沿前提交观察
assign o_write_pointer = reg_write; // 原生状态或沿前提交观察
assign o_scheduled_sequence = reg_replay_sequence; // 原生状态或沿前提交观察
assign o_scheduled_count = cnt_scheduled; // 原生状态或沿前提交观察
assign o_scheduled_pointer = reg_replay_pointer; // 原生状态或沿前提交观察
assign o_first_pending = reg_first; // 原生状态或沿前提交观察
always @(posedge i_clk) begin // reg_last_sequence独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  reg_last_sequence <= 9'd511; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  reg_last_sequence <= 9'd511; // 清除旧事务状态
 end else if (o_push_accept) begin // 按接收命令再源提交的优先级更新
  reg_last_sequence <= dec_next_sequence; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束reg_last_sequence寄存块
always @(posedge i_clk) begin // reg_last_ack独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  reg_last_ack <= 9'd511; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  reg_last_ack <= 9'd511; // 清除旧事务状态
 end else if (flag_ack) begin // 按接收命令再源提交的优先级更新
  reg_last_ack <= i_command_target; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束reg_last_ack寄存块
always @(posedge i_clk) begin // cnt_ignore独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  cnt_ignore <= 4'd0; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  cnt_ignore <= 4'd0; // 清除旧事务状态
 end else if (flag_request) begin // 按接收命令再源提交的优先级更新
  cnt_ignore <= 4'd12; // 本沿提交新状态
 end else if (i_ingress_event) begin // 按接收命令再源提交的优先级更新
  cnt_ignore <= dec_ignore; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束cnt_ignore寄存块
always @(posedge i_clk) begin // cnt_unacked独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  cnt_unacked <= 8'd0; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  cnt_unacked <= 8'd0; // 清除旧事务状态
 end else if (o_push_accept) begin // 按接收命令再源提交的优先级更新
  cnt_unacked <= dec_live + 8'd1; // 本沿提交新状态
 end else if (flag_ack) begin // 按接收命令再源提交的优先级更新
  cnt_unacked <= dec_live; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束cnt_unacked寄存块
always @(posedge i_clk) begin // reg_head独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  reg_head <= {C_ADDR_WIDTH{1'b0}}; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  reg_head <= {C_ADDR_WIDTH{1'b0}}; // 清除旧事务状态
 end else if (flag_ack) begin // 按接收命令再源提交的优先级更新
  reg_head <= dec_head_mod[C_ADDR_WIDTH-1:0]; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束reg_head寄存块
always @(posedge i_clk) begin // reg_write独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  reg_write <= {C_ADDR_WIDTH{1'b0}}; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  reg_write <= {C_ADDR_WIDTH{1'b0}}; // 清除旧事务状态
 end else if (o_push_accept) begin // 按接收命令再源提交的优先级更新
  reg_write <= dec_write_next; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束reg_write寄存块
always @(posedge i_clk) begin // reg_replay_sequence独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  reg_replay_sequence <= 9'd0; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  reg_replay_sequence <= 9'd0; // 清除旧事务状态
 end else if (o_replay_take && (dec_scheduled == 8'd1)) begin // 按接收命令再源提交的优先级更新
  reg_replay_sequence <= 9'd0; // 本沿提交新状态
 end else if (o_replay_take) begin // 按接收命令再源提交的优先级更新
  reg_replay_sequence <= dec_next_replay_sequence; // 本沿提交新状态
 end else if (flag_request) begin // 按接收命令再源提交的优先级更新
  reg_replay_sequence <= i_command_target; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束reg_replay_sequence寄存块
always @(posedge i_clk) begin // cnt_scheduled独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  cnt_scheduled <= 8'd0; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  cnt_scheduled <= 8'd0; // 清除旧事务状态
 end else if (o_replay_take) begin // 按接收命令再源提交的优先级更新
  cnt_scheduled <= dec_scheduled - 8'd1; // 本沿提交新状态
 end else if (flag_request) begin // 按接收命令再源提交的优先级更新
  cnt_scheduled <= dec_scheduled; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束cnt_scheduled寄存块
always @(posedge i_clk) begin // reg_replay_pointer独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  reg_replay_pointer <= {C_ADDR_WIDTH{1'b0}}; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  reg_replay_pointer <= {C_ADDR_WIDTH{1'b0}}; // 清除旧事务状态
 end else if (o_replay_take && (dec_scheduled == 8'd1)) begin // 按接收命令再源提交的优先级更新
  reg_replay_pointer <= {C_ADDR_WIDTH{1'b0}}; // 本沿提交新状态
 end else if (o_replay_take) begin // 按接收命令再源提交的优先级更新
  reg_replay_pointer <= dec_replay_next; // 本沿提交新状态
 end else if (flag_request) begin // 按接收命令再源提交的优先级更新
  reg_replay_pointer <= dec_replay_pointer; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束reg_replay_pointer寄存块
always @(posedge i_clk) begin // reg_first独立时钟寄存
 if (!i_rstn) begin // 同步低有效全局复位
  reg_first <= 1'b0; // 复位默认状态
 end else if (i_link_reset) begin // 同步链路重新初始化
  reg_first <= 1'b0; // 清除旧事务状态
 end else if (o_replay_take) begin // 按接收命令再源提交的优先级更新
  reg_first <= 1'b0; // 本沿提交新状态
 end else if (flag_request) begin // 按接收命令再源提交的优先级更新
  reg_first <= 1'b1; // 本沿提交新状态
 end // 结束状态更新分支，其余保持
end // 结束reg_first寄存块
endmodule // 结束dl_replay_tx_control模块
