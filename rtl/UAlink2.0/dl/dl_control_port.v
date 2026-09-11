`timescale 1ps/1ps // 实际组合消息端口所有状态共享一个原始时钟域。
module dl_control_port #( // 模块连接Control语义、Basic生命周期、UART及真实双SRAM。
parameter integer C_TX_DEPTH = 128, // 传递子模块既有配置边界。
parameter integer C_RX_DEPTH = 128, // 传递子模块既有配置边界。
parameter integer C_CLOCK_PERIOD_PS = 640, // 传递子模块既有配置边界。
parameter integer C_RESPONSE_DEPTH = 4, // 传递子模块既有配置边界。
parameter integer C_ROLE_SWITCH = 0, // 传递子模块既有配置边界。
parameter integer C_LANES = 4, // 传递子模块既有配置边界。
parameter integer C_FOLDING = 1, // 传递子模块既有配置边界。
parameter integer C_RESILIENCY = 1, // 传递子模块既有配置边界。
parameter integer C_INITIAL_WIDTH = 0, // 传递子模块既有配置边界。
parameter integer C_ALLOWED_PL_MASK = 3, // 传递子模块既有配置边界。
parameter integer C_TX_READY_SUPPORT = 0 // 传递子模块既有配置边界。
) ( // 接受可靠有序消息字和实际DWORD发送机会。
input wire i_clk, // 唯一原始采样时钟
input wire i_rstn, // 同步低有效全局复位
input wire i_fw_tx_valid, // 固件发送字有效
input wire [31:0] i_fw_tx_word, // 固件原始发送负载
input wire i_fw_rx_ready, // 固件读取当前接收字
input wire i_rx_word_valid, // 可靠有序消息字有效
input wire [31:0] i_rx_word, // 上游可靠性处理后的消息字
input wire i_segment_available, // 真实消息DWORD发送机会
input wire i_local_request, // 请求本地流复位
input wire i_local_all, // 本地请求的全部流范围
input wire i_credit_pending, // 外部信用调度器稳定队首有效
input wire [31:0] i_credit_word, // 外部已编码信用通告字
output wire o_msg_uart_tx_storage_ready, // transmit 模型公开观察 fw_ready
output wire [12:0] o_msg_uart_tx_buffered_words, // transmit 模型公开观察 buffered_words
output wire [11:0] o_msg_uart_tx_counter, // transmit 模型公开观察 tx_counter
output wire o_msg_uart_tx_busy, // transmit 模型公开观察 uart_busy
output wire [5:0] o_msg_uart_tx_reserved, // transmit 模型公开观察 uart_reserved
output wire [5:0] o_msg_uart_tx_staged, // transmit 模型公开观察 uart_staged
output wire [11:0] o_msg_uart_tx_latest_fc, // transmit 模型公开观察 latest_fc
output wire o_msg_uart_tx_valid, // transmit 模型公开观察 valid
output wire [31:0] o_msg_uart_tx_word, // transmit 模型公开观察 word
output wire [3:0] o_msg_uart_tx_source, // transmit 模型公开观察 source
output wire [5:0] o_msg_uart_tx_word_index, // transmit 模型公开观察 word_index
output wire o_msg_uart_tx_last, // transmit 模型公开观察 last
output wire [9:0] o_msg_uart_tx_other_take, // transmit 模型公开观察 other_take
output wire [9:0] o_msg_uart_tx_other_done, // transmit 模型公开观察 other_done
output wire o_msg_uart_tx_message_done, // transmit 模型公开观察 uart_message_done
output wire o_msg_uart_tx_locked, // transmit 模型公开观察 uart_locked
output wire o_msg_uart_tx_error, // transmit 模型公开观察 error
output wire [5:0] o_msg_uart_tx_uart_index, // transmit 模型公开观察 uart_word_index
output wire o_msg_uart_fw_rx_valid, // receive 模型公开观察 fw_valid
output wire [31:0] o_msg_uart_fw_rx_word, // receive 模型公开观察 fw_word
output wire [11:0] o_msg_uart_rx_fill, // receive 模型公开观察 rx_fill
output wire o_msg_uart_rx_initialized, // receive 模型公开观察 initialized
output wire [11:0] o_msg_uart_rx_counter, // receive 模型公开观察 rx_counter
output wire o_msg_uart_rx_credit_available, // receive 模型公开观察 credit_available
output wire [5:0] o_msg_uart_rx_remaining, // receive 模型公开观察 remaining
output wire o_msg_uart_rx_dropping, // receive 模型公开观察 dropping
output wire o_msg_uart_rx_header, // receive 模型公开观察 header
output wire o_msg_uart_rx_payload_write, // receive 模型公开观察 payload_write
output wire o_msg_uart_rx_payload_discard, // receive 模型公开观察 payload_discard
output wire o_msg_uart_rx_done, // receive 模型公开观察 done
output wire o_msg_uart_rx_credit_valid, // receive 模型公开观察 credit_valid
output wire [11:0] o_msg_uart_rx_credit_value, // receive 模型公开观察 credit_value
output wire o_msg_uart_rx_reset_request, // receive 模型公开观察 reset_request
output wire o_msg_uart_rx_request_all, // receive 模型公开观察 request_all
output wire o_msg_uart_rx_reset_response, // receive 模型公开观察 reset_response
output wire o_msg_uart_rx_response_all, // receive 模型公开观察 response_all
output wire [2:0] o_msg_uart_rx_response_status, // receive 模型公开观察 response_status
output wire o_msg_uart_rx_other_valid, // receive 模型公开观察 other_valid
output wire [31:0] o_msg_uart_rx_other_word, // receive 模型公开观察 other_word
output wire o_msg_uart_rx_error, // receive 模型公开观察 error
output wire o_msg_uart_local_ready, // control 模型公开观察 local_ready
output wire o_msg_uart_stream_reset, // control 模型公开观察 stream_reset
output wire o_msg_uart_block_messages, // control 模型公开观察 block_messages
output wire o_msg_uart_reset_tx_pending, // control 模型公开观察 tx_pending
output wire [31:0] o_msg_uart_reset_tx_word, // control 模型公开观察 tx_word
output wire [1:0] o_msg_uart_reset_tx_kind, // control 模型公开观察 tx_kind
output wire o_msg_uart_reset_waiting, // control 模型公开观察 waiting
output wire [5:0] o_msg_uart_reset_noops_left, // control 模型公开观察 noops_left
output wire [4:0] o_msg_uart_reset_response_count, // control 模型公开观察 response_count
output wire o_msg_uart_local_start, // control 模型公开观察 local_start
output wire o_msg_uart_local_done, // control 模型公开观察 local_done
output wire o_msg_uart_retry, // control 模型公开观察 retry
output wire o_msg_uart_reply_done, // control 模型公开观察 reply_done
output wire o_msg_uart_reset_fault, // control 模型公开观察 fault
output wire o_msg_uart_reset_error, // control 模型公开观察 error
output wire o_msg_uart_fw_tx_ready, // 端口组合握手或诊断 fw_tx_ready
output wire o_msg_uart_fw_tx_accepted, // 端口组合握手或诊断 fw_tx_accepted
output wire o_msg_uart_fw_tx_discard, // 端口组合握手或诊断 fw_tx_discard
output wire [5:0] o_msg_uart_normal_take, // 端口组合握手或诊断 normal_take
output wire o_msg_uart_credit_take, // 端口组合握手或诊断 credit_take
output wire o_msg_uart_credit_cancel, // 端口组合握手或诊断 credit_cancel
output wire o_msg_uart_error, // 端口组合握手或诊断 error
input wire i_basic_local_valid, // 原生输入 local_valid
input wire [2:0] i_basic_local_kind, // 原生输入 local_kind
input wire [15:0] i_basic_local_rate, // 原生输入 local_rate
input wire i_basic_device_valid, // 原生输入 device_valid
input wire [9:0] i_basic_device_id, // 原生输入 device_id
input wire i_basic_device_type, // 原生输入 device_type
input wire i_basic_port_valid, // 原生输入 port_valid
input wire [11:0] i_basic_port, // 原生输入 port
input wire i_basic_folding, // 原生输入 folding
input wire i_basic_tx_ready_advertised, // 原生输入 tx_ready_advertised
input wire i_basic_symbols_valid, // 原生输入 symbols_valid
input wire i_basic_tx_limit_valid, // 原生输入 tx_limit_valid
input wire [15:0] i_basic_tx_limit, // 原生输入 tx_limit
output wire o_msg_basic_local_ready, // 独立参考观察 local_ready
output wire o_msg_basic_local_pending, // 独立参考观察 local_pending
output wire o_msg_basic_local_waiting, // 独立参考观察 local_waiting
output wire o_msg_basic_remote_pending, // 独立参考观察 remote_pending
output wire [3:0] o_msg_basic_source_pending, // 独立参考观察 source_pending
output wire [127:0] o_msg_basic_source_words, // 独立参考观察 source_words
output wire o_msg_basic_local_start, // 独立参考观察 local_start
output wire o_msg_basic_local_commit, // 独立参考观察 local_commit
output wire o_msg_basic_local_done, // 独立参考观察 local_done
output wire o_msg_basic_reply_done, // 独立参考观察 reply_done
output wire o_msg_basic_rx_request, // 独立参考观察 rx_request
output wire o_msg_basic_rx_noop, // 独立参考观察 rx_noop
output wire o_msg_basic_rx_unhandled, // 独立参考观察 rx_unhandled
output wire o_msg_basic_rx_unsupported, // 独立参考观察 rx_unsupported
output wire o_msg_basic_rx_unmatched_ack, // 独立参考观察 rx_unmatched_ack
output wire o_msg_basic_rx_overlap, // 独立参考观察 rx_overlap
output wire o_msg_basic_peer_rate_valid, // 独立参考观察 peer_rate_valid
output wire [15:0] o_msg_basic_peer_rate, // 独立参考观察 peer_rate
output wire o_msg_basic_peer_device_valid, // 独立参考观察 peer_device_valid
output wire [1:0] o_msg_basic_peer_device_type, // 独立参考观察 peer_device_type
output wire [9:0] o_msg_basic_peer_device_id, // 独立参考观察 peer_device_id
output wire o_msg_basic_peer_port_valid, // 独立参考观察 peer_port_valid
output wire [11:0] o_msg_basic_peer_port, // 独立参考观察 peer_port
output wire o_msg_basic_peer_rate_update, // 独立参考观察 peer_rate_update
output wire o_msg_basic_deadline_miss, // 独立参考观察 deadline_miss
output wire o_msg_basic_deadline_fault, // 独立参考观察 deadline_fault
output wire o_msg_basic_protocol_fault, // 独立参考观察 protocol_fault
output wire o_msg_basic_error, // 独立参考观察 error
output wire [1:0] o_msg_control_take, // 实际提交的两个Control来源消费位。
output wire o_msg_unhandled_valid, // 经UART边界分发后Basic仍未处理的消息字有效。
output wire [31:0] o_msg_unhandled_word, // 仅有效时转交上层的原始消息字。
output wire o_msg_error, // 当前Basic与UART错误汇总，不反馈发送资格。
input wire i_ctl_request_valid, // 显式本地请求有效
input wire i_ctl_request_channel, // 本地种类零Width一Channel
input wire [3:0] i_ctl_request_target, // 显式请求原始目标
input wire i_ctl_request_priority, // 显式Width请求优先级
input wire [1:0] i_ctl_channel_ready, // Channel0与Channel4在线接收准备
input wire i_ctl_width_ready, // 允许履行普通扩宽Pending重启
input wire i_ctl_clear_soft_lockout, // 本沿固件清除软锁
output wire [1:0] o_ctl_source_pending, // 沿前有效队首，低位Width高位Channel
output wire [63:0] o_ctl_source_words, // 沿前两来源字，仅队首有效
output wire [1:0] o_ctl_source_purpose, // 队首用途：零Request，一回复，二确认
output wire [31:0] o_ctl_source_request_word, // 队首所属交换的原请求字
output wire o_ctl_local_ready, // TX和RX处理后的本地接纳资格
output wire o_ctl_local_accept, // 本沿真正接纳本地请求
output wire o_ctl_tx_valid, // 本沿实际发送队首
output wire [31:0] o_ctl_tx_word, // 本沿实际发送完整字
output wire [3:0] o_ctl_rx_status, // 本沿接收结果编码
output wire o_ctl_local_busy, // 沿前本地请求占用
output wire [31:0] o_ctl_local_request_word, // 沿前本地原请求快照
output wire [1:0] o_ctl_local_phase, // 零排队，一等响应，二确认排队
output wire o_ctl_local_restart, // 沿前本地请求正在履行pending重启
output wire o_ctl_remote_busy, // 沿前对端交换占用
output wire [31:0] o_ctl_remote_request_word, // 沿前对端原请求快照
output wire [31:0] o_ctl_remote_reply_word, // 沿前已冻结回复字
output wire o_ctl_remote_reply_sent, // 沿前ACK已发送且仍等确认
output wire o_ctl_remote_from_pending, // 对端交换履行先前pending重启
output wire [1:0] o_ctl_waiting_peer, // 按kind等待对端重启并完成
output wire [1:0] o_ctl_owed_restart, // 按kind保留本地重启责任
output wire [63:0] o_ctl_owed_requests, // 两种kind原始重启目标与消息快照
output wire [1:0] o_ctl_queue_count, // 沿前两条发送队列占用
output wire o_ctl_local_done, // 本沿本地交换完成
output wire o_ctl_local_done_channel, // 本地完成种类
output wire [3:0] o_ctl_local_done_target, // 本地完成原目标
output wire o_ctl_local_success, // 本地完成是否成功
output wire o_ctl_remote_done, // 本沿对端交换完成
output wire o_ctl_remote_done_channel, // 对端完成种类
output wire [3:0] o_ctl_remote_done_target, // 对端完成原目标
output wire o_ctl_remote_success, // 对端完成是否成功
output wire o_ctl_response_miss, // 本沿首次超过回复截止
output wire o_ctl_response_fault, // 回复超时粘滞诊断
output wire [1:0] o_ctl_restart_miss, // 本沿两种kind首次超过重启截止
output wire o_ctl_restart_fault, // 任一重启超时粘滞诊断
output wire o_ctl_take_error, // 实际消费输入不对应有效单一队首
output wire o_ctl_protocol_error, // 本沿接收或回复策略违约
output wire o_ctl_protocol_fault, // 握手或消费违约粘滞诊断
output wire o_ctl_pending_sent, // 本沿实际发送pending
output wire o_ctl_pending_received, // 本沿匹配接收pending
output wire [1:0] o_ctl_restart_commit, // 本沿实际提交所欠重启Request
output wire [1:0] o_ctl_channel_online, // 沿前Channel0与Channel4在线状态
output wire [1:0] o_ctl_channel_closing, // 沿前正在下线的Channel0与Channel4
output wire [3:0] o_ctl_negotiated_width, // 协商逻辑宽度，非物理PL状态
output wire o_ctl_soft_lockout, // 沿前硬件软锁
output wire o_ctl_lockout_notify, // 本沿软锁从清除到重新置位通知
output wire o_ctl_peer_tx_ready_support, // 对端最近Width字的TxReady能力
output wire [1:0] o_ctl_auto_restart, // 本沿两kind自动重启接纳事件
output wire o_ctl_owed_first_channel, // 沿前最早仍未发送的Pending重启义务kind
output wire o_ctl_retry_blocked, // 宽度冲突失败的重试目标有效
output wire [3:0] o_ctl_retry_target, // 有效冲突失败重试目标
output wire o_ctl_round_valid, // 沿前Width协商轮次有效
output wire [3:0] o_ctl_round_target, // 当前宽度轮次胜出目标
output wire o_ctl_round_remote_accepted, // 轮次曾接纳对端请求
output wire o_ctl_round_conflict, // 轮次存在不同目标冲突
output wire o_ctl_round_sent_ack, // 轮次已经实际发送ACK
output wire o_ctl_round_received_ack, // 轮次已经匹配收到ACK
output wire o_ctl_round_applied, // 本轮ACK对已应用一次
output wire o_ctl_width_event_valid, // 前一沿形成的寄存宽度动作有效
output wire [3:0] o_ctl_width_event_old, // 宽度动作前的协商状态
output wire [3:0] o_ctl_width_event_new, // 宽度动作后的协商状态
output wire [1:0] o_ctl_width_event_action, // 一进入掉电，二等待对端掉电，三进入Fault
output wire o_ctl_width_event_pl, // 宽度动作使用协议PL编号
output wire o_ctl_repeat_error, // 本沿接纳当前Channel状态请求的诊断
output wire o_ctl_repeat_fault, // 当前Channel状态请求粘滞诊断
output wire o_ctl_unsupported, // 本沿收到未支持的语义消息
output wire o_ctl_unsupported_fault, // 未支持语义消息的粘滞诊断
output wire o_unhandled_valid, // 真正未处理或不支持的消息有效
output wire [31:0] o_unhandled_word, // 仅有效时转交原始字
output wire o_error // 当前消息与Control事件诊断汇总
); // 结束联合原生输入输出边界。
assign o_unhandled_valid = o_msg_unhandled_valid && ((o_ctl_rx_status == 4'd6) || (o_ctl_rx_status == 4'd13)); // 仅转交语义层未处理或不支持的真实消息。
assign o_unhandled_word = o_unhandled_valid ? o_msg_unhandled_word : 32'd0; // 无有效转交时数据归零。
assign o_error = o_msg_error || o_ctl_protocol_fault || o_ctl_response_fault || o_ctl_restart_fault; // 沿前Control粘滞故障和当前消息错误按参考汇总。
dl_message_port #( // 实际子模块保留其全部状态和数据路径。
.C_TX_DEPTH(C_TX_DEPTH), // 同域时间和原生能力保持明确。
.C_RX_DEPTH(C_RX_DEPTH), // 同域时间和原生能力保持明确。
.C_CLOCK_PERIOD_PS(C_CLOCK_PERIOD_PS), // 同域时间和原生能力保持明确。
.C_RESPONSE_DEPTH(C_RESPONSE_DEPTH) // 同域时间和原生能力保持明确。
) Message_Inst ( // 连线只传递原生输入和实际结果，不引入预测提交。
.i_clk(i_clk), // 完整连接实际子模块端口。
.i_rstn(i_rstn), // 完整连接实际子模块端口。
.i_channel4_enabled(o_ctl_channel_online[1]), // 完整连接实际子模块端口。
.i_uart_start_allowed(!o_ctl_channel_closing[1]), // 沿前Channel关闭新头、允许已开始消息排空。
.i_fw_tx_valid(i_fw_tx_valid), // 完整连接实际子模块端口。
.i_fw_tx_word(i_fw_tx_word), // 完整连接实际子模块端口。
.i_fw_rx_ready(i_fw_rx_ready), // 完整连接实际子模块端口。
.i_rx_word_valid(i_rx_word_valid), // 完整连接实际子模块端口。
.i_rx_word(i_rx_word), // 完整连接实际子模块端口。
.i_segment_available(i_segment_available), // 完整连接实际子模块端口。
.i_local_request(i_local_request), // 完整连接实际子模块端口。
.i_local_all(i_local_all), // 完整连接实际子模块端口。
.i_credit_pending(i_credit_pending), // 完整连接实际子模块端口。
.i_credit_word(i_credit_word), // 完整连接实际子模块端口。
.o_uart_tx_storage_ready(o_msg_uart_tx_storage_ready), // 完整连接实际子模块端口。
.o_uart_tx_buffered_words(o_msg_uart_tx_buffered_words), // 完整连接实际子模块端口。
.o_uart_tx_counter(o_msg_uart_tx_counter), // 完整连接实际子模块端口。
.o_uart_tx_busy(o_msg_uart_tx_busy), // 完整连接实际子模块端口。
.o_uart_tx_reserved(o_msg_uart_tx_reserved), // 完整连接实际子模块端口。
.o_uart_tx_staged(o_msg_uart_tx_staged), // 完整连接实际子模块端口。
.o_uart_tx_latest_fc(o_msg_uart_tx_latest_fc), // 完整连接实际子模块端口。
.o_uart_tx_valid(o_msg_uart_tx_valid), // 完整连接实际子模块端口。
.o_uart_tx_word(o_msg_uart_tx_word), // 完整连接实际子模块端口。
.o_uart_tx_source(o_msg_uart_tx_source), // 完整连接实际子模块端口。
.o_uart_tx_word_index(o_msg_uart_tx_word_index), // 完整连接实际子模块端口。
.o_uart_tx_last(o_msg_uart_tx_last), // 完整连接实际子模块端口。
.o_uart_tx_other_take(o_msg_uart_tx_other_take), // 完整连接实际子模块端口。
.o_uart_tx_other_done(o_msg_uart_tx_other_done), // 完整连接实际子模块端口。
.o_uart_tx_message_done(o_msg_uart_tx_message_done), // 完整连接实际子模块端口。
.o_uart_tx_locked(o_msg_uart_tx_locked), // 完整连接实际子模块端口。
.o_uart_tx_error(o_msg_uart_tx_error), // 完整连接实际子模块端口。
.o_uart_tx_uart_index(o_msg_uart_tx_uart_index), // 完整连接实际子模块端口。
.o_uart_fw_rx_valid(o_msg_uart_fw_rx_valid), // 完整连接实际子模块端口。
.o_uart_fw_rx_word(o_msg_uart_fw_rx_word), // 完整连接实际子模块端口。
.o_uart_rx_fill(o_msg_uart_rx_fill), // 完整连接实际子模块端口。
.o_uart_rx_initialized(o_msg_uart_rx_initialized), // 完整连接实际子模块端口。
.o_uart_rx_counter(o_msg_uart_rx_counter), // 完整连接实际子模块端口。
.o_uart_rx_credit_available(o_msg_uart_rx_credit_available), // 完整连接实际子模块端口。
.o_uart_rx_remaining(o_msg_uart_rx_remaining), // 完整连接实际子模块端口。
.o_uart_rx_dropping(o_msg_uart_rx_dropping), // 完整连接实际子模块端口。
.o_uart_rx_header(o_msg_uart_rx_header), // 完整连接实际子模块端口。
.o_uart_rx_payload_write(o_msg_uart_rx_payload_write), // 完整连接实际子模块端口。
.o_uart_rx_payload_discard(o_msg_uart_rx_payload_discard), // 完整连接实际子模块端口。
.o_uart_rx_done(o_msg_uart_rx_done), // 完整连接实际子模块端口。
.o_uart_rx_credit_valid(o_msg_uart_rx_credit_valid), // 完整连接实际子模块端口。
.o_uart_rx_credit_value(o_msg_uart_rx_credit_value), // 完整连接实际子模块端口。
.o_uart_rx_reset_request(o_msg_uart_rx_reset_request), // 完整连接实际子模块端口。
.o_uart_rx_request_all(o_msg_uart_rx_request_all), // 完整连接实际子模块端口。
.o_uart_rx_reset_response(o_msg_uart_rx_reset_response), // 完整连接实际子模块端口。
.o_uart_rx_response_all(o_msg_uart_rx_response_all), // 完整连接实际子模块端口。
.o_uart_rx_response_status(o_msg_uart_rx_response_status), // 完整连接实际子模块端口。
.o_uart_rx_other_valid(o_msg_uart_rx_other_valid), // 完整连接实际子模块端口。
.o_uart_rx_other_word(o_msg_uart_rx_other_word), // 完整连接实际子模块端口。
.o_uart_rx_error(o_msg_uart_rx_error), // 完整连接实际子模块端口。
.o_uart_local_ready(o_msg_uart_local_ready), // 完整连接实际子模块端口。
.o_uart_stream_reset(o_msg_uart_stream_reset), // 完整连接实际子模块端口。
.o_uart_block_messages(o_msg_uart_block_messages), // 完整连接实际子模块端口。
.o_uart_reset_tx_pending(o_msg_uart_reset_tx_pending), // 完整连接实际子模块端口。
.o_uart_reset_tx_word(o_msg_uart_reset_tx_word), // 完整连接实际子模块端口。
.o_uart_reset_tx_kind(o_msg_uart_reset_tx_kind), // 完整连接实际子模块端口。
.o_uart_reset_waiting(o_msg_uart_reset_waiting), // 完整连接实际子模块端口。
.o_uart_reset_noops_left(o_msg_uart_reset_noops_left), // 完整连接实际子模块端口。
.o_uart_reset_response_count(o_msg_uart_reset_response_count), // 完整连接实际子模块端口。
.o_uart_local_start(o_msg_uart_local_start), // 完整连接实际子模块端口。
.o_uart_local_done(o_msg_uart_local_done), // 完整连接实际子模块端口。
.o_uart_retry(o_msg_uart_retry), // 完整连接实际子模块端口。
.o_uart_reply_done(o_msg_uart_reply_done), // 完整连接实际子模块端口。
.o_uart_reset_fault(o_msg_uart_reset_fault), // 完整连接实际子模块端口。
.o_uart_reset_error(o_msg_uart_reset_error), // 完整连接实际子模块端口。
.o_uart_fw_tx_ready(o_msg_uart_fw_tx_ready), // 完整连接实际子模块端口。
.o_uart_fw_tx_accepted(o_msg_uart_fw_tx_accepted), // 完整连接实际子模块端口。
.o_uart_fw_tx_discard(o_msg_uart_fw_tx_discard), // 完整连接实际子模块端口。
.o_uart_normal_take(o_msg_uart_normal_take), // 完整连接实际子模块端口。
.o_uart_credit_take(o_msg_uart_credit_take), // 完整连接实际子模块端口。
.o_uart_credit_cancel(o_msg_uart_credit_cancel), // 完整连接实际子模块端口。
.o_uart_error(o_msg_uart_error), // 完整连接实际子模块端口。
.i_basic_local_valid(i_basic_local_valid), // 完整连接实际子模块端口。
.i_basic_local_kind(i_basic_local_kind), // 完整连接实际子模块端口。
.i_basic_local_rate(i_basic_local_rate), // 完整连接实际子模块端口。
.i_basic_device_valid(i_basic_device_valid), // 完整连接实际子模块端口。
.i_basic_device_id(i_basic_device_id), // 完整连接实际子模块端口。
.i_basic_device_type(i_basic_device_type), // 完整连接实际子模块端口。
.i_basic_port_valid(i_basic_port_valid), // 完整连接实际子模块端口。
.i_basic_port(i_basic_port), // 完整连接实际子模块端口。
.i_basic_folding(i_basic_folding), // 完整连接实际子模块端口。
.i_basic_tx_ready_advertised(i_basic_tx_ready_advertised), // 完整连接实际子模块端口。
.i_basic_symbols_valid(i_basic_symbols_valid), // 完整连接实际子模块端口。
.i_basic_tx_limit_valid(i_basic_tx_limit_valid), // 完整连接实际子模块端口。
.i_basic_tx_limit(i_basic_tx_limit), // 完整连接实际子模块端口。
.o_basic_local_ready(o_msg_basic_local_ready), // 完整连接实际子模块端口。
.o_basic_local_pending(o_msg_basic_local_pending), // 完整连接实际子模块端口。
.o_basic_local_waiting(o_msg_basic_local_waiting), // 完整连接实际子模块端口。
.o_basic_remote_pending(o_msg_basic_remote_pending), // 完整连接实际子模块端口。
.o_basic_source_pending(o_msg_basic_source_pending), // 完整连接实际子模块端口。
.o_basic_source_words(o_msg_basic_source_words), // 完整连接实际子模块端口。
.o_basic_local_start(o_msg_basic_local_start), // 完整连接实际子模块端口。
.o_basic_local_commit(o_msg_basic_local_commit), // 完整连接实际子模块端口。
.o_basic_local_done(o_msg_basic_local_done), // 完整连接实际子模块端口。
.o_basic_reply_done(o_msg_basic_reply_done), // 完整连接实际子模块端口。
.o_basic_rx_request(o_msg_basic_rx_request), // 完整连接实际子模块端口。
.o_basic_rx_noop(o_msg_basic_rx_noop), // 完整连接实际子模块端口。
.o_basic_rx_unhandled(o_msg_basic_rx_unhandled), // 完整连接实际子模块端口。
.o_basic_rx_unsupported(o_msg_basic_rx_unsupported), // 完整连接实际子模块端口。
.o_basic_rx_unmatched_ack(o_msg_basic_rx_unmatched_ack), // 完整连接实际子模块端口。
.o_basic_rx_overlap(o_msg_basic_rx_overlap), // 完整连接实际子模块端口。
.o_basic_peer_rate_valid(o_msg_basic_peer_rate_valid), // 完整连接实际子模块端口。
.o_basic_peer_rate(o_msg_basic_peer_rate), // 完整连接实际子模块端口。
.o_basic_peer_device_valid(o_msg_basic_peer_device_valid), // 完整连接实际子模块端口。
.o_basic_peer_device_type(o_msg_basic_peer_device_type), // 完整连接实际子模块端口。
.o_basic_peer_device_id(o_msg_basic_peer_device_id), // 完整连接实际子模块端口。
.o_basic_peer_port_valid(o_msg_basic_peer_port_valid), // 完整连接实际子模块端口。
.o_basic_peer_port(o_msg_basic_peer_port), // 完整连接实际子模块端口。
.o_basic_peer_rate_update(o_msg_basic_peer_rate_update), // 完整连接实际子模块端口。
.o_basic_deadline_miss(o_msg_basic_deadline_miss), // 完整连接实际子模块端口。
.o_basic_deadline_fault(o_msg_basic_deadline_fault), // 完整连接实际子模块端口。
.o_basic_protocol_fault(o_msg_basic_protocol_fault), // 完整连接实际子模块端口。
.o_basic_error(o_msg_basic_error), // 完整连接实际子模块端口。
.i_control_pending(o_ctl_source_pending), // 完整连接实际子模块端口。
.i_control_words(o_ctl_source_words), // 完整连接实际子模块端口。
.o_control_take(o_msg_control_take), // 完整连接实际子模块端口。
.o_unhandled_valid(o_msg_unhandled_valid), // 完整连接实际子模块端口。
.o_unhandled_word(o_msg_unhandled_word), // 完整连接实际子模块端口。
.o_error(o_msg_error) // 完整连接实际子模块端口。
); // 结束实际子模块实例。
dl_control_controller #( // 实际子模块保留其全部状态和数据路径。
.C_CLOCK_PERIOD_PS(C_CLOCK_PERIOD_PS), // 同域时间和原生能力保持明确。
.C_ROLE_SWITCH(C_ROLE_SWITCH), // 同域时间和原生能力保持明确。
.C_LANES(C_LANES), // 同域时间和原生能力保持明确。
.C_FOLDING(C_FOLDING), // 同域时间和原生能力保持明确。
.C_RESILIENCY(C_RESILIENCY), // 同域时间和原生能力保持明确。
.C_INITIAL_WIDTH(C_INITIAL_WIDTH), // 同域时间和原生能力保持明确。
.C_ALLOWED_PL_MASK(C_ALLOWED_PL_MASK), // 同域时间和原生能力保持明确。
.C_TX_READY_SUPPORT(C_TX_READY_SUPPORT) // 同域时间和原生能力保持明确。
) Control_Inst ( // 连线只传递原生输入和实际结果，不引入预测提交。
.i_clk(i_clk), // 完整连接实际子模块端口。
.i_rstn(i_rstn), // 完整连接实际子模块端口。
.i_source_take(o_msg_control_take), // 完整连接实际子模块端口。
.i_rx_valid(o_msg_unhandled_valid), // 完整连接实际子模块端口。
.i_rx_word(o_msg_unhandled_word), // 完整连接实际子模块端口。
.i_request_valid(i_ctl_request_valid), // 完整连接实际子模块端口。
.i_request_channel(i_ctl_request_channel), // 完整连接实际子模块端口。
.i_request_target(i_ctl_request_target), // 完整连接实际子模块端口。
.i_request_priority(i_ctl_request_priority), // 完整连接实际子模块端口。
.i_channel_ready(i_ctl_channel_ready), // 完整连接实际子模块端口。
.i_width_ready(i_ctl_width_ready), // 完整连接实际子模块端口。
.i_clear_soft_lockout(i_ctl_clear_soft_lockout), // 完整连接实际子模块端口。
.o_source_pending(o_ctl_source_pending), // 完整连接实际子模块端口。
.o_source_words(o_ctl_source_words), // 完整连接实际子模块端口。
.o_source_purpose(o_ctl_source_purpose), // 完整连接实际子模块端口。
.o_source_request_word(o_ctl_source_request_word), // 完整连接实际子模块端口。
.o_local_ready(o_ctl_local_ready), // 完整连接实际子模块端口。
.o_local_accept(o_ctl_local_accept), // 完整连接实际子模块端口。
.o_tx_valid(o_ctl_tx_valid), // 完整连接实际子模块端口。
.o_tx_word(o_ctl_tx_word), // 完整连接实际子模块端口。
.o_rx_status(o_ctl_rx_status), // 完整连接实际子模块端口。
.o_local_busy(o_ctl_local_busy), // 完整连接实际子模块端口。
.o_local_request_word(o_ctl_local_request_word), // 完整连接实际子模块端口。
.o_local_phase(o_ctl_local_phase), // 完整连接实际子模块端口。
.o_local_restart(o_ctl_local_restart), // 完整连接实际子模块端口。
.o_remote_busy(o_ctl_remote_busy), // 完整连接实际子模块端口。
.o_remote_request_word(o_ctl_remote_request_word), // 完整连接实际子模块端口。
.o_remote_reply_word(o_ctl_remote_reply_word), // 完整连接实际子模块端口。
.o_remote_reply_sent(o_ctl_remote_reply_sent), // 完整连接实际子模块端口。
.o_remote_from_pending(o_ctl_remote_from_pending), // 完整连接实际子模块端口。
.o_waiting_peer(o_ctl_waiting_peer), // 完整连接实际子模块端口。
.o_owed_restart(o_ctl_owed_restart), // 完整连接实际子模块端口。
.o_owed_requests(o_ctl_owed_requests), // 完整连接实际子模块端口。
.o_queue_count(o_ctl_queue_count), // 完整连接实际子模块端口。
.o_local_done(o_ctl_local_done), // 完整连接实际子模块端口。
.o_local_done_channel(o_ctl_local_done_channel), // 完整连接实际子模块端口。
.o_local_done_target(o_ctl_local_done_target), // 完整连接实际子模块端口。
.o_local_success(o_ctl_local_success), // 完整连接实际子模块端口。
.o_remote_done(o_ctl_remote_done), // 完整连接实际子模块端口。
.o_remote_done_channel(o_ctl_remote_done_channel), // 完整连接实际子模块端口。
.o_remote_done_target(o_ctl_remote_done_target), // 完整连接实际子模块端口。
.o_remote_success(o_ctl_remote_success), // 完整连接实际子模块端口。
.o_response_miss(o_ctl_response_miss), // 完整连接实际子模块端口。
.o_response_fault(o_ctl_response_fault), // 完整连接实际子模块端口。
.o_restart_miss(o_ctl_restart_miss), // 完整连接实际子模块端口。
.o_restart_fault(o_ctl_restart_fault), // 完整连接实际子模块端口。
.o_take_error(o_ctl_take_error), // 完整连接实际子模块端口。
.o_protocol_error(o_ctl_protocol_error), // 完整连接实际子模块端口。
.o_protocol_fault(o_ctl_protocol_fault), // 完整连接实际子模块端口。
.o_pending_sent(o_ctl_pending_sent), // 完整连接实际子模块端口。
.o_pending_received(o_ctl_pending_received), // 完整连接实际子模块端口。
.o_restart_commit(o_ctl_restart_commit), // 完整连接实际子模块端口。
.o_channel_online(o_ctl_channel_online), // 完整连接实际子模块端口。
.o_channel_closing(o_ctl_channel_closing), // 完整连接实际子模块端口。
.o_negotiated_width(o_ctl_negotiated_width), // 完整连接实际子模块端口。
.o_soft_lockout(o_ctl_soft_lockout), // 完整连接实际子模块端口。
.o_lockout_notify(o_ctl_lockout_notify), // 完整连接实际子模块端口。
.o_peer_tx_ready_support(o_ctl_peer_tx_ready_support), // 完整连接实际子模块端口。
.o_auto_restart(o_ctl_auto_restart), // 完整连接实际子模块端口。
.o_owed_first_channel(o_ctl_owed_first_channel), // 完整连接实际子模块端口。
.o_retry_blocked(o_ctl_retry_blocked), // 完整连接实际子模块端口。
.o_retry_target(o_ctl_retry_target), // 完整连接实际子模块端口。
.o_round_valid(o_ctl_round_valid), // 完整连接实际子模块端口。
.o_round_target(o_ctl_round_target), // 完整连接实际子模块端口。
.o_round_remote_accepted(o_ctl_round_remote_accepted), // 完整连接实际子模块端口。
.o_round_conflict(o_ctl_round_conflict), // 完整连接实际子模块端口。
.o_round_sent_ack(o_ctl_round_sent_ack), // 完整连接实际子模块端口。
.o_round_received_ack(o_ctl_round_received_ack), // 完整连接实际子模块端口。
.o_round_applied(o_ctl_round_applied), // 完整连接实际子模块端口。
.o_width_event_valid(o_ctl_width_event_valid), // 完整连接实际子模块端口。
.o_width_event_old(o_ctl_width_event_old), // 完整连接实际子模块端口。
.o_width_event_new(o_ctl_width_event_new), // 完整连接实际子模块端口。
.o_width_event_action(o_ctl_width_event_action), // 完整连接实际子模块端口。
.o_width_event_pl(o_ctl_width_event_pl), // 完整连接实际子模块端口。
.o_repeat_error(o_ctl_repeat_error), // 完整连接实际子模块端口。
.o_repeat_fault(o_ctl_repeat_fault), // 完整连接实际子模块端口。
.o_unsupported(o_ctl_unsupported), // 完整连接实际子模块端口。
.o_unsupported_fault(o_ctl_unsupported_fault) // 完整连接实际子模块端口。
); // 结束实际子模块实例。
endmodule // 结束Control与Basic/UART实际联合消息端口模块。
