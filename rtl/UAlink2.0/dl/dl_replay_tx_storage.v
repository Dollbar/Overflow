module dl_replay_tx_storage #( // dl_replay_tx_storage模块：实际同步SRAM重放与输出保持槽
 parameter integer C_DEPTH = 255, // 精确逻辑存储容量
 parameter integer C_DATA_WIDTH = 32, // 不透明payload数据宽度，必须为正整字节
 parameter integer C_ADDR_WIDTH = (C_DEPTH <= 2) ? 1 : (C_DEPTH <= 4) ? 2 : (C_DEPTH <= 8) ? 3 : (C_DEPTH <= 16) ? 4 : (C_DEPTH <= 32) ? 5 : (C_DEPTH <= 64) ? 6 : (C_DEPTH <= 128) ? 7 : (C_DEPTH <= 256) ? 8 : (C_DEPTH <= 512) ? 9 : (C_DEPTH <= 1024) ? 10 : (C_DEPTH <= 2048) ? 11 : 12 // 与控制器匹配的派生地址宽度
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
wire flag_active; // 复位和链路清除外的工作资格
wire normal_push; // 获得输出槽的正常源写入请求
wire [C_WORD_WIDTH-1:0] memory_write_data; // 写入实际SRAM的完整字及序号
wire [C_WORD_WIDTH-1:0] memory_read_data; // 实际同步SRAM沿后注册输出
wire ctl_ack_accept; // 已证明控制器原生观察
wire [8-1:0] ctl_ack_count; // 已证明控制器原生观察
wire ctl_request_accept; // 已证明控制器原生观察
wire ctl_command_reject; // 已证明控制器原生观察
wire ctl_push_ready; // 已证明控制器原生观察
wire ctl_push_accept; // 已证明控制器原生观察
wire [9-1:0] ctl_push_sequence; // 已证明控制器原生观察
wire [C_ADDR_WIDTH-1:0] ctl_write_addr; // 已证明控制器原生观察
wire ctl_replay_valid; // 已证明控制器原生观察
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
assign flag_active = i_rstn && !i_link_reset; // 原生握手、状态或实际数据选择
assign o_issue_ready = flag_active && (!reg_valid || i_out_ready); // 原生握手、状态或实际数据选择
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
 .i_ingress_event(i_ingress_event), // 原生控制接口连接
 .i_command_valid(i_command_valid), // 原生控制接口连接
 .i_command_request(i_command_request), // 原生控制接口连接
 .i_command_target(i_command_target), // 原生控制接口连接
 .i_push(normal_push), // 原生控制接口连接
 .i_replay_take(o_issue_accept), // 原生控制接口连接
 .o_ack_accept(ctl_ack_accept), // 原生控制接口连接
 .o_ack_count(ctl_ack_count), // 原生控制接口连接
 .o_request_accept(ctl_request_accept), // 原生控制接口连接
 .o_command_reject(ctl_command_reject), // 原生控制接口连接
 .o_push_ready(ctl_push_ready), // 原生控制接口连接
 .o_push_accept(ctl_push_accept), // 原生控制接口连接
 .o_push_sequence(ctl_push_sequence), // 原生控制接口连接
 .o_write_addr(ctl_write_addr), // 原生控制接口连接
 .o_replay_valid(ctl_replay_valid), // 原生控制接口连接
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
 .read_cs_i(ctl_replay_take), // 实际存储端口连接
 .read_addr_i(ctl_replay_addr), // 实际存储端口连接
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
endmodule // 结束dl_replay_tx_storage模块
