module dl_replay_data_port #( // dl_replay_data_port模块：预约Flit槽的一拍头数据响应
 parameter integer C_DEPTH = 255, // 精确逻辑重放容量
 parameter integer C_DATA_WIDTH = 32, // 不透明payload宽度，必须为正整字节
 parameter integer C_ADDR_WIDTH = (C_DEPTH <= 2) ? 1 : (C_DEPTH <= 4) ? 2 : (C_DEPTH <= 8) ? 3 : (C_DEPTH <= 16) ? 4 : (C_DEPTH <= 32) ? 5 : (C_DEPTH <= 64) ? 6 : (C_DEPTH <= 128) ? 7 : (C_DEPTH <= 256) ? 8 : (C_DEPTH <= 512) ? 9 : (C_DEPTH <= 1024) ? 10 : (C_DEPTH <= 2048) ? 11 : 12 // 与实际存储一致的派生地址宽度
,parameter integer C_EPOCH_SNAPSHOT_ENABLE=0,C_EPOCH_WIDTH=8,C_ATTEMPT_WIDTH=8 // 本地快照不改变外部DL字段定义。
) ( // 预约已获得下游确定延迟的响应槽
 input wire i_clk, // 同域事务、完整事件或状态观察
 input wire i_rstn, // 同域事务、完整事件或状态观察
 input wire i_link_reset, // 同域事务、完整事件或状态观察
 input wire i_rx_event_valid, // 同域事务、完整事件或状态观察
 input wire i_rx_event_discard, // 同域事务、完整事件或状态观察
 input wire i_rx_crc_ok, // 同域事务、完整事件或状态观察
 input wire [23:0] i_rx_header, // 同域事务、完整事件或状态观察
 input wire [7:0] i_rx_replay_limit, // 同域事务、完整事件或状态观察
 input wire [C_DATA_WIDTH-1:0] i_rx_data, // 本拍接收事件的不透明payload
 input wire i_flit_request, // 本拍预约一个Flit槽，下个时钟沿返回完整响应
 input wire i_new_group, // 仅由有效预约限定的FEC组起点
 input wire i_payload, // 同域事务、完整事件或状态观察
 input wire [C_DATA_WIDTH-1:0] i_data, // 正常发送源保持到payload_accept的完整字
 output wire o_issue_ready, // 同域事务、完整事件或状态观察
 output wire o_issue_accept, // 同域事务、完整事件或状态观察
 output wire o_payload_accept, // 同域事务、完整事件或状态观察
 output wire o_issue_payload, // 同域事务、完整事件或状态观察
 output wire o_issue_replay, // 同域事务、完整事件或状态观察
 output wire o_issue_first, // 同域事务、完整事件或状态观察
 output wire [8:0] o_issue_sequence, // 同域事务、完整事件或状态观察
 output wire o_out_valid, // 同域事务、完整事件或状态观察
 output wire o_out_payload, // 同域事务、完整事件或状态观察
 output wire o_out_replay, // 同域事务、完整事件或状态观察
 output wire o_out_first, // 同域事务、完整事件或状态观察
 output wire [8:0] o_out_sequence, // 同域事务、完整事件或状态观察
 output wire [C_DATA_WIDTH-1:0] o_out_data, // 同域事务、完整事件或状态观察
 output wire o_tag_error, // 同域事务、完整事件或状态观察
 output wire [8:0] o_out_stored_sequence, // 同域事务、完整事件或状态观察
 output wire o_ack_accept, // 同域事务、完整事件或状态观察
 output wire [7:0] o_ack_count, // 同域事务、完整事件或状态观察
 output wire o_request_accept, // 同域事务、完整事件或状态观察
 output wire o_command_reject, // 同域事务、完整事件或状态观察
 output wire [7:0] o_resident_count, // 同域事务、完整事件或状态观察
 output wire [8:0] o_ctl_last_sequence, // 同域事务、完整事件或状态观察
 output wire [8:0] o_ctl_last_ack, // 同域事务、完整事件或状态观察
 output wire [3:0] o_ctl_ignore_count, // 同域事务、完整事件或状态观察
 output wire [7:0] o_ctl_unacked_count, // 同域事务、完整事件或状态观察
 output wire [C_ADDR_WIDTH-1:0] o_ctl_head_pointer, // 同域事务、完整事件或状态观察
 output wire [C_ADDR_WIDTH-1:0] o_ctl_write_pointer, // 同域事务、完整事件或状态观察
 output wire [8:0] o_ctl_scheduled_sequence, // 同域事务、完整事件或状态观察
 output wire [7:0] o_ctl_scheduled_count, // 同域事务、完整事件或状态观察
 output wire [C_ADDR_WIDTH-1:0] o_ctl_scheduled_pointer, // 同域事务、完整事件或状态观察
 output wire o_ctl_first_pending, // 同域事务、完整事件或状态观察
 output wire o_rx_ingress_event, // 同域事务、完整事件或状态观察
 output wire o_rx_accept, // 同域事务、完整事件或状态观察
 output wire o_rx_payload_accept, // 同域事务、完整事件或状态观察
 output wire o_rx_sequence_valid, // 同域事务、完整事件或状态观察
 output wire [8:0] o_rx_sequence, // 同域事务、完整事件或状态观察
 output wire o_rx_replay_request, // 同域事务、完整事件或状态观察
 output wire o_rx_command_valid, // 同域事务、完整事件或状态观察
 output wire o_rx_command_request, // 同域事务、完整事件或状态观察
 output wire [8:0] o_rx_command_target, // 同域事务、完整事件或状态观察
 output wire o_rx_crc_error, // 同域事务、完整事件或状态观察
 output wire o_rx_zero_sequence, // 同域事务、完整事件或状态观察
 output wire o_rx_zero_command, // 同域事务、完整事件或状态观察
 output wire o_rx_backpressure_drop, // 同域事务、完整事件或状态观察
 output wire o_rx_unexpected, // 同域事务、完整事件或状态观察
 output wire o_rx_ambiguous_drop, // 同域事务、完整事件或状态观察
 output wire o_rx_replay_drop, // 同域事务、完整事件或状态观察
 output wire [8:0] o_rx_last_sequence, // 同域事务、完整事件或状态观察
 output wire [2:0] o_rx_bad_crc_count, // 同域事务、完整事件或状态观察
 output wire [7:0] o_rx_unexpected_count, // 同域事务、完整事件或状态观察
 output wire o_rx_ambiguous, // 同域事务、完整事件或状态观察
 output wire o_rx_replay, // 同域事务、完整事件或状态观察
 output wire [23:0] o_issue_header, // 同域事务、完整事件或状态观察
 output wire o_issue_header_valid, // 同域事务、完整事件或状态观察
 output wire o_issue_metadata_error, // 同域事务、完整事件或状态观察
 output wire [2:0] o_tx_explicit_count, // 同域事务、完整事件或状态观察
 output wire [1:0] o_tx_request_count, // 同域事务、完整事件或状态观察
 output wire [8:0] o_tx_request_sequence, // 同域事务、完整事件或状态观察
 output wire o_tx_group_used, // 同域事务、完整事件或状态观察
 output wire [8:0] o_rx_effective_sequence, // 同域事务、完整事件或状态观察
 output wire [23:0] o_out_header, // 与真实SRAM返回数据同沿注册的完整头
 output wire [C_DATA_WIDTH-1:0] o_rx_data // 仅接纳payload事件时转发的本拍接收内容
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

); // 结束公开接口
wire flag_tx_metadata_ok; // 使用已证明的真实源类别和寄存器提前判定发送元数据
assign flag_tx_metadata_ok = o_payload_accept || (o_issue_replay ? (o_request_accept || (o_ctl_scheduled_sequence != 9'd0)) : (o_ctl_last_sequence != 9'd0)); // 实际提交时与完整原始发送源保护等价，保留零序号诊断
reg [23:0] reg_header; // 与存储输出槽同步的完整头寄存器
assign o_out_header = o_out_valid ? reg_header : 24'd0; // 空槽和清除时不暴露旧头
assign o_rx_data = o_rx_payload_accept ? i_rx_data : {C_DATA_WIDTH{1'b0}}; // 仅传递实际接纳的接收payload
always @(posedge i_clk) begin // 唯一新增寄存器只由真实时钟沿更新
 if (!i_rstn) reg_header <= 24'd0; // 同步复位头状态
 else if (i_link_reset) reg_header <= 24'd0; // 链路清除取消旧响应
 else if (o_issue_accept) reg_header <= o_issue_header; // 同沿记录真实选中元数据生成的头
end // 无新预约时保持内部头，输出由真实槽有效位限定
dl_replay_tx_storage #(.C_DEPTH(C_DEPTH), .C_DATA_WIDTH(C_DATA_WIDTH), .C_ADDR_WIDTH(C_ADDR_WIDTH),.C_EPOCH_SNAPSHOT_ENABLE(C_EPOCH_SNAPSHOT_ENABLE),.C_EPOCH_WIDTH(C_EPOCH_WIDTH),.C_ATTEMPT_WIDTH(C_ATTEMPT_WIDTH)) u_storage ( // 接入实际子模块并共享唯一时钟

 .i_snapshot_begin(i_snapshot_begin), // 原样连接真实存储快照接口。
 .o_snapshot_begin_ready(o_snapshot_begin_ready), // 原样连接真实存储快照接口。
 .i_snapshot_owner_error(i_snapshot_owner_error), // 原样连接真实存储快照接口。
 .i_snapshot_scope(i_snapshot_scope), // 原样连接真实存储快照接口。
 .i_snapshot_epoch(i_snapshot_epoch), // 原样连接真实存储快照接口。
 .i_current_epoch(i_current_epoch), // 原样连接真实存储快照接口。
 .i_snapshot_attempt(i_snapshot_attempt), // 原样连接真实存储快照接口。
 .i_snapshot_fenced(i_snapshot_fenced), // 原样连接真实存储快照接口。
 .i_snapshot_fence_epoch(i_snapshot_fence_epoch), // 原样连接真实存储快照接口。
 .i_snapshot_fence_attempt(i_snapshot_fence_attempt), // 原样连接真实存储快照接口。
 .o_snapshot_valid(o_snapshot_valid), // 原样连接真实存储快照接口。
 .i_snapshot_ready(i_snapshot_ready), // 原样连接真实存储快照接口。
 .o_snapshot_data(o_snapshot_data), // 原样连接真实存储快照接口。
 .o_snapshot_sequence(o_snapshot_sequence), // 原样连接真实存储快照接口。
 .o_snapshot_index(o_snapshot_index), // 原样连接真实存储快照接口。
 .o_snapshot_count(o_snapshot_count), // 原样连接真实存储快照接口。
 .o_snapshot_last(o_snapshot_last), // 原样连接真实存储快照接口。
 .o_snapshot_epoch(o_snapshot_epoch), // 原样连接真实存储快照接口。
 .o_snapshot_attempt(o_snapshot_attempt), // 原样连接真实存储快照接口。
 .o_snapshot_active(o_snapshot_active), // 原样连接真实存储快照接口。
 .o_snapshot_done(o_snapshot_done), // 原样连接真实存储快照接口。
 .o_snapshot_error(o_snapshot_error), // 原样连接真实存储快照接口。
 .i_clk(i_clk), // 明确绑定原生接口
 .i_rstn(i_rstn), // 明确绑定原生接口
 .i_link_reset(i_link_reset), // 明确绑定原生接口
 .i_ingress_event(o_rx_ingress_event), // 明确绑定原生接口
 .i_command_valid(o_rx_command_valid), // 明确绑定原生接口
 .i_command_request(o_rx_command_request), // 明确绑定原生接口
 .i_command_target(i_rx_header[19:11]), // 明确绑定原生接口
 .i_issue(i_flit_request), // 明确绑定原生接口
 .i_payload(i_payload), // 明确绑定原生接口
 .i_data(i_data), // 明确绑定原生接口
 .i_out_ready(1'b1), // 明确绑定原生接口
 .o_issue_ready(o_issue_ready), // 明确绑定原生接口
 .o_issue_accept(o_issue_accept), // 明确绑定原生接口
 .o_payload_accept(o_payload_accept), // 明确绑定原生接口
 .o_issue_payload(o_issue_payload), // 明确绑定原生接口
 .o_issue_replay(o_issue_replay), // 明确绑定原生接口
 .o_issue_first(o_issue_first), // 明确绑定原生接口
 .o_issue_sequence(o_issue_sequence), // 明确绑定原生接口
 .o_out_valid(o_out_valid), // 明确绑定原生接口
 .o_out_payload(o_out_payload), // 明确绑定原生接口
 .o_out_replay(o_out_replay), // 明确绑定原生接口
 .o_out_first(o_out_first), // 明确绑定原生接口
 .o_out_sequence(o_out_sequence), // 明确绑定原生接口
 .o_out_data(o_out_data), // 明确绑定原生接口
 .o_tag_error(o_tag_error), // 明确绑定原生接口
 .o_out_stored_sequence(o_out_stored_sequence), // 明确绑定原生接口
 .o_ack_accept(o_ack_accept), // 明确绑定原生接口
 .o_ack_count(o_ack_count), // 明确绑定原生接口
 .o_request_accept(o_request_accept), // 明确绑定原生接口
 .o_command_reject(o_command_reject), // 明确绑定原生接口
 .o_resident_count(o_resident_count), // 明确绑定原生接口
 .o_ctl_last_sequence(o_ctl_last_sequence), // 明确绑定原生接口
 .o_ctl_last_ack(o_ctl_last_ack), // 明确绑定原生接口
 .o_ctl_ignore_count(o_ctl_ignore_count), // 明确绑定原生接口
 .o_ctl_unacked_count(o_ctl_unacked_count), // 明确绑定原生接口
 .o_ctl_head_pointer(o_ctl_head_pointer), // 明确绑定原生接口
 .o_ctl_write_pointer(o_ctl_write_pointer), // 明确绑定原生接口
 .o_ctl_scheduled_sequence(o_ctl_scheduled_sequence), // 明确绑定原生接口
 .o_ctl_scheduled_count(o_ctl_scheduled_count), // 明确绑定原生接口
 .o_ctl_scheduled_pointer(o_ctl_scheduled_pointer), // 明确绑定原生接口
 .o_ctl_first_pending(o_ctl_first_pending) // 明确绑定原生接口
); // 结束u_storage连接
dl_replay_event_port #(.C_EARLY_TX_METADATA(1)) u_events ( // 接入实际子模块并共享唯一时钟
 .i_clk(i_clk), // 明确绑定原生接口
 .i_rstn(i_rstn), // 明确绑定原生接口
 .i_link_reset(i_link_reset), // 明确绑定原生接口
 .i_rx_event_valid(i_rx_event_valid), // 明确绑定原生接口
 .i_rx_event_discard(i_rx_event_discard), // 明确绑定原生接口
 .i_rx_crc_ok(i_rx_crc_ok), // 明确绑定原生接口
 .i_rx_header(i_rx_header), // 明确绑定原生接口
 .i_rx_replay_limit(i_rx_replay_limit), // 明确绑定原生接口
 .i_tx_flit_send(o_issue_accept), // 明确绑定原生接口
 .i_tx_payload(o_issue_payload), // 明确绑定原生接口
 .i_tx_replay(o_issue_replay), // 明确绑定原生接口
 .i_tx_first_replay(o_issue_first), // 明确绑定原生接口
 .i_tx_sequence(o_issue_sequence), // 明确绑定原生接口
 .i_tx_metadata_ok(flag_tx_metadata_ok), // 仅实际集成显式启用经完整旧RTL证明的提前谓词
 .i_tx_new_group(i_new_group && o_issue_accept), // 明确绑定原生接口
 .o_rx_ingress_event(o_rx_ingress_event), // 明确绑定原生接口
 .o_rx_accept(o_rx_accept), // 明确绑定原生接口
 .o_rx_payload_accept(o_rx_payload_accept), // 明确绑定原生接口
 .o_rx_sequence_valid(o_rx_sequence_valid), // 明确绑定原生接口
 .o_rx_sequence(o_rx_sequence), // 明确绑定原生接口
 .o_rx_replay_request(o_rx_replay_request), // 明确绑定原生接口
 .o_rx_command_valid(o_rx_command_valid), // 明确绑定原生接口
 .o_rx_command_request(o_rx_command_request), // 明确绑定原生接口
 .o_rx_command_target(o_rx_command_target), // 明确绑定原生接口
 .o_rx_crc_error(o_rx_crc_error), // 明确绑定原生接口
 .o_rx_zero_sequence(o_rx_zero_sequence), // 明确绑定原生接口
 .o_rx_zero_command(o_rx_zero_command), // 明确绑定原生接口
 .o_rx_backpressure_drop(o_rx_backpressure_drop), // 明确绑定原生接口
 .o_rx_unexpected(o_rx_unexpected), // 明确绑定原生接口
 .o_rx_ambiguous_drop(o_rx_ambiguous_drop), // 明确绑定原生接口
 .o_rx_replay_drop(o_rx_replay_drop), // 明确绑定原生接口
 .o_rx_last_sequence(o_rx_last_sequence), // 明确绑定原生接口
 .o_rx_bad_crc_count(o_rx_bad_crc_count), // 明确绑定原生接口
 .o_rx_unexpected_count(o_rx_unexpected_count), // 明确绑定原生接口
 .o_rx_ambiguous(o_rx_ambiguous), // 明确绑定原生接口
 .o_rx_replay(o_rx_replay), // 明确绑定原生接口
 .o_tx_header(o_issue_header), // 明确绑定原生接口
 .o_tx_header_valid(o_issue_header_valid), // 明确绑定原生接口
 .o_tx_metadata_error(o_issue_metadata_error), // 明确绑定原生接口
 .o_tx_explicit_count(o_tx_explicit_count), // 明确绑定原生接口
 .o_tx_request_count(o_tx_request_count), // 明确绑定原生接口
 .o_tx_request_sequence(o_tx_request_sequence), // 明确绑定原生接口
 .o_tx_group_used(o_tx_group_used), // 明确绑定原生接口
 .o_rx_effective_sequence(o_rx_effective_sequence) // 明确绑定原生接口
); // 结束u_events连接
endmodule // 结束预约头数据端口
