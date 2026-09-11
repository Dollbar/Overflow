`timescale 1ps/1ps // 语义控制器时间精度统一为皮秒
module dl_control_controller #( // 模块：共享握手与Channel/Width完整语义状态机
parameter integer C_CLOCK_PERIOD_PS = 640, // 明确角色、协议PL能力及实际时基参数
parameter integer C_ROLE_SWITCH = 0, // 明确角色、协议PL能力及实际时基参数
parameter integer C_LANES = 4, // 明确角色、协议PL能力及实际时基参数
parameter integer C_FOLDING = 1, // 明确角色、协议PL能力及实际时基参数
parameter integer C_RESILIENCY = 1, // 明确角色、协议PL能力及实际时基参数
parameter integer C_INITIAL_WIDTH = 0, // 明确角色、协议PL能力及实际时基参数
parameter integer C_ALLOWED_PL_MASK = 3, // 明确角色、协议PL能力及实际时基参数
parameter integer C_TX_READY_SUPPORT = 0 // 明确角色、协议PL能力及实际时基参数
) ( // 原生接口所有输入同域且已可靠分帧
input wire i_clk, // 唯一原始上升沿时钟
input wire i_rstn, // 同步低有效复位
input wire [1:0] i_source_take, // Width与Channel唯一沿前队首实际提交
input wire i_rx_valid, // 可靠分帧接收字有效
input wire [31:0] i_rx_word, // 可靠有序且去重的接收字
input wire i_request_valid, // 显式本地请求有效
input wire i_request_channel, // 本地种类零Width一Channel
input wire [3:0] i_request_target, // 显式请求原始目标
input wire i_request_priority, // 显式Width请求优先级
input wire [1:0] i_channel_ready, // Channel0与Channel4在线接收准备
input wire i_width_ready, // 允许履行普通扩宽Pending重启
input wire i_clear_soft_lockout, // 本沿固件清除软锁
output reg [1:0] o_source_pending, // 沿前有效队首，低位Width高位Channel
output reg [63:0] o_source_words, // 沿前两来源字，仅队首有效
output reg [1:0] o_source_purpose, // 队首用途：零Request，一回复，二确认
output reg [31:0] o_source_request_word, // 队首所属交换的原请求字
output reg o_local_ready, // TX和RX处理后的本地接纳资格
output reg o_local_accept, // 本沿真正接纳本地请求
output reg o_tx_valid, // 本沿实际发送队首
output reg [31:0] o_tx_word, // 本沿实际发送完整字
output reg [3:0] o_rx_status, // 本沿接收结果编码
output reg o_local_busy, // 沿前本地请求占用
output reg [31:0] o_local_request_word, // 沿前本地原请求快照
output reg [1:0] o_local_phase, // 零排队，一等响应，二确认排队
output reg o_local_restart, // 沿前本地请求正在履行pending重启
output reg o_remote_busy, // 沿前对端交换占用
output reg [31:0] o_remote_request_word, // 沿前对端原请求快照
output reg [31:0] o_remote_reply_word, // 沿前已冻结回复字
output reg o_remote_reply_sent, // 沿前ACK已发送且仍等确认
output reg o_remote_from_pending, // 对端交换履行先前pending重启
output reg [1:0] o_waiting_peer, // 按kind等待对端重启并完成
output reg [1:0] o_owed_restart, // 按kind保留本地重启责任
output reg [63:0] o_owed_requests, // 两种kind原始重启目标与消息快照
output reg [1:0] o_queue_count, // 沿前两条发送队列占用
output reg o_local_done, // 本沿本地交换完成
output reg o_local_done_channel, // 本地完成种类
output reg [3:0] o_local_done_target, // 本地完成原目标
output reg o_local_success, // 本地完成是否成功
output reg o_remote_done, // 本沿对端交换完成
output reg o_remote_done_channel, // 对端完成种类
output reg [3:0] o_remote_done_target, // 对端完成原目标
output reg o_remote_success, // 对端完成是否成功
output reg o_response_miss, // 本沿首次超过回复截止
output reg o_response_fault, // 回复超时粘滞诊断
output reg [1:0] o_restart_miss, // 本沿两种kind首次超过重启截止
output reg o_restart_fault, // 任一重启超时粘滞诊断
output reg o_take_error, // 实际消费输入不对应有效单一队首
output reg o_protocol_error, // 本沿接收或回复策略违约
output reg o_protocol_fault, // 握手或消费违约粘滞诊断
output reg o_pending_sent, // 本沿实际发送pending
output reg o_pending_received, // 本沿匹配接收pending
output reg [1:0] o_restart_commit, // 本沿实际提交所欠重启Request
output reg [1:0] o_channel_online, // 沿前Channel0与Channel4在线状态
output reg [1:0] o_channel_closing, // 沿前正在下线的Channel0与Channel4
output reg [3:0] o_negotiated_width, // 协商逻辑宽度，非物理PL状态
output reg o_soft_lockout, // 沿前硬件软锁
output reg o_lockout_notify, // 本沿软锁从清除到重新置位通知
output reg o_peer_tx_ready_support, // 对端最近Width字的TxReady能力
output reg [1:0] o_auto_restart, // 本沿两kind自动重启接纳事件
output reg o_owed_first_channel, // 沿前最早仍未发送的Pending重启义务kind
output reg o_retry_blocked, // 宽度冲突失败的重试目标有效
output reg [3:0] o_retry_target, // 有效冲突失败重试目标
output reg o_round_valid, // 沿前Width协商轮次有效
output reg [3:0] o_round_target, // 当前宽度轮次胜出目标
output reg o_round_remote_accepted, // 轮次曾接纳对端请求
output reg o_round_conflict, // 轮次存在不同目标冲突
output reg o_round_sent_ack, // 轮次已经实际发送ACK
output reg o_round_received_ack, // 轮次已经匹配收到ACK
output reg o_round_applied, // 本轮ACK对已应用一次
output reg o_width_event_valid, // 前一沿形成的寄存宽度动作有效
output reg [3:0] o_width_event_old, // 宽度动作前的协商状态
output reg [3:0] o_width_event_new, // 宽度动作后的协商状态
output reg [1:0] o_width_event_action, // 一进入掉电，二等待对端掉电，三进入Fault
output reg o_width_event_pl, // 宽度动作使用协议PL编号
output reg o_repeat_error, // 本沿接纳当前Channel状态请求的诊断
output reg o_repeat_fault, // 当前Channel状态请求粘滞诊断
output reg o_unsupported, // 本沿收到未支持的语义消息
output reg o_unsupported_fault // 未支持语义消息的粘滞诊断
); // 结束完整控制器端口定义
localparam [63:0] C_RESPONSE_ALLOWED = 64'd1000000 / ((C_CLOCK_PERIOD_PS > 0) ? {32'd0,C_CLOCK_PERIOD_PS[31:0]} : 64'd1); // 完整常量除法保留精确物理时间，非法周期由展开门拒绝
localparam [63:0] C_RESTART_ALLOWED = 64'd10000000000 / ((C_CLOCK_PERIOD_PS > 0) ? {32'd0,C_CLOCK_PERIOD_PS[31:0]} : 64'd1); // 完整常量除法保留精确物理时间，非法周期由展开门拒绝
localparam integer C_RESPONSE_BITS = // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 1)) ? 1 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 2)) ? 2 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 3)) ? 3 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 4)) ? 4 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 5)) ? 5 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 6)) ? 6 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 7)) ? 7 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 8)) ? 8 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 9)) ? 9 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 10)) ? 10 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 11)) ? 11 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 12)) ? 12 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 13)) ? 13 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 14)) ? 14 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 15)) ? 15 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 16)) ? 16 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 17)) ? 17 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 18)) ? 18 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESPONSE_ALLOWED < (64'd1 << 19)) ? 19 : 20; // 按合法最大年龄选择最小饱和计数器宽度
localparam [C_RESPONSE_BITS-1:0] C_RESPONSE_LIMIT = C_RESPONSE_ALLOWED[C_RESPONSE_BITS-1:0]; // 显式常量截取避免隐式宽度转换
localparam integer C_RESTART_BITS = // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 1)) ? 1 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 2)) ? 2 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 3)) ? 3 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 4)) ? 4 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 5)) ? 5 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 6)) ? 6 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 7)) ? 7 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 8)) ? 8 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 9)) ? 9 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 10)) ? 10 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 11)) ? 11 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 12)) ? 12 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 13)) ? 13 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 14)) ? 14 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 15)) ? 15 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 16)) ? 16 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 17)) ? 17 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 18)) ? 18 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 19)) ? 19 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 20)) ? 20 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 21)) ? 21 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 22)) ? 22 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 23)) ? 23 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 24)) ? 24 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 25)) ? 25 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 26)) ? 26 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 27)) ? 27 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 28)) ? 28 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 29)) ? 29 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 30)) ? 30 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 31)) ? 31 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 32)) ? 32 : // 按合法最大年龄选择最小饱和计数器宽度
    (C_RESTART_ALLOWED < (64'd1 << 33)) ? 33 : 34; // 按合法最大年龄选择最小饱和计数器宽度
localparam [C_RESTART_BITS-1:0] C_RESTART_LIMIT = C_RESTART_ALLOWED[C_RESTART_BITS-1:0]; // 显式常量截取避免隐式宽度转换
generate // 结束非法周期展开检查；禁止生成错误时间参数网表
if (C_CLOCK_PERIOD_PS < 1 || C_CLOCK_PERIOD_PS > 1000000) begin : g_invalid_period // 结束非法周期展开检查；禁止生成错误时间参数网表
UALINK_CONTROL_PERIOD_MUST_BE_VALID invalid_period (); // 结束非法周期展开检查；禁止生成错误时间参数网表
end // 结束非法周期展开检查；禁止生成错误时间参数网表
endgenerate // 结束非法周期展开检查；禁止生成错误时间参数网表
generate // 结束非法角色与能力组合展开检查
if ((C_ROLE_SWITCH != 0 && C_ROLE_SWITCH != 1) || (C_LANES != 1 && C_LANES != 2 && C_LANES != 4) || (C_FOLDING != 0 && C_FOLDING != 1) || (C_RESILIENCY != 0 && C_RESILIENCY != 1) || (C_TX_READY_SUPPORT != 0 && C_TX_READY_SUPPORT != 1) || ((C_FOLDING != 0) && ((C_RESILIENCY == 0) || C_LANES < 2)) || ((C_RESILIENCY != 0) && C_LANES < 2) || ((C_TX_READY_SUPPORT != 0) && (C_FOLDING == 0)) || (C_INITIAL_WIDTH != 0 && C_INITIAL_WIDTH != 1 && C_INITIAL_WIDTH != 9) || (C_INITIAL_WIDTH != 0 && (C_RESILIENCY == 0)) || (C_ALLOWED_PL_MASK < 1 || C_ALLOWED_PL_MASK > 3) || (C_INITIAL_WIDTH == 0 && C_ALLOWED_PL_MASK != 3) || (C_INITIAL_WIDTH == 1 && !C_ALLOWED_PL_MASK[0]) || (C_INITIAL_WIDTH == 9 && !C_ALLOWED_PL_MASK[1])) begin : g_invalid_capabilities // 结束非法角色与能力组合展开检查
UALINK_CONTROL_CAPABILITIES_MUST_BE_VALID invalid_capabilities (); // 结束非法角色与能力组合展开检查
end // 结束非法角色与能力组合展开检查
endgenerate // 结束非法角色与能力组合展开检查
reg r_local_busy; // 本地交换所有权：寄存态和完整下一态
reg n_local_busy; // 本地交换所有权：寄存态和完整下一态
reg [31:0] r_local_word; // 本地规范化请求字：寄存态和完整下一态
reg [31:0] n_local_word; // 本地规范化请求字：寄存态和完整下一态
reg [1:0] r_local_phase; // 本地排队等待回复与确认待发送阶段：寄存态和完整下一态
reg [1:0] n_local_phase; // 本地排队等待回复与确认待发送阶段：寄存态和完整下一态
reg r_local_restart; // 本地请求来自Pending重启责任：寄存态和完整下一态
reg n_local_restart; // 本地请求来自Pending重启责任：寄存态和完整下一态
reg r_remote_busy; // 对端交换所有权：寄存态和完整下一态
reg n_remote_busy; // 对端交换所有权：寄存态和完整下一态
reg [31:0] r_remote_word; // 对端规范化原请求字：寄存态和完整下一态
reg [31:0] n_remote_word; // 对端规范化原请求字：寄存态和完整下一态
reg [31:0] r_remote_reply; // 接收当沿冻结的回复字：寄存态和完整下一态
reg [31:0] n_remote_reply; // 接收当沿冻结的回复字：寄存态和完整下一态
reg r_remote_sent; // 回复已实际发送：寄存态和完整下一态
reg n_remote_sent; // 回复已实际发送：寄存态和完整下一态
reg r_remote_pending; // 对端请求来自等待其重启：寄存态和完整下一态
reg n_remote_pending; // 对端请求来自等待其重启：寄存态和完整下一态
reg r_remote_missed; // 本次对端请求已报告回复超时：寄存态和完整下一态
reg n_remote_missed; // 本次对端请求已报告回复超时：寄存态和完整下一态
reg [C_RESPONSE_BITS-1:0] r_response_age; // 未发送回复的饱和年龄：寄存态和完整下一态
reg [C_RESPONSE_BITS-1:0] n_response_age; // 未发送回复的饱和年龄：寄存态和完整下一态
reg [1:0] r_waiting; // 两种消息等待对端重启：寄存态和完整下一态
reg [1:0] n_waiting; // 两种消息等待对端重启：寄存态和完整下一态
reg [1:0] r_owed; // 两种消息欠本地重启：寄存态和完整下一态
reg [1:0] n_owed; // 两种消息欠本地重启：寄存态和完整下一态
reg [31:0] r_owed_width; // Width原始重启目标：寄存态和完整下一态
reg [31:0] n_owed_width; // Width原始重启目标：寄存态和完整下一态
reg [31:0] r_owed_channel; // Channel原始重启目标：寄存态和完整下一态
reg [31:0] n_owed_channel; // Channel原始重启目标：寄存态和完整下一态
reg [C_RESTART_BITS-1:0] r_width_age; // Width重启饱和年龄：寄存态和完整下一态
reg [C_RESTART_BITS-1:0] n_width_age; // Width重启饱和年龄：寄存态和完整下一态
reg [C_RESTART_BITS-1:0] r_channel_age; // Channel重启饱和年龄：寄存态和完整下一态
reg [C_RESTART_BITS-1:0] n_channel_age; // Channel重启饱和年龄：寄存态和完整下一态
reg [1:0] r_restart_missed; // 各重启责任已报告超时：寄存态和完整下一态
reg [1:0] n_restart_missed; // 各重启责任已报告超时：寄存态和完整下一态
reg [1:0] r_count; // 有序发送队列占用：寄存态和完整下一态
reg [1:0] n_count; // 有序发送队列占用：寄存态和完整下一态
reg [31:0] r_word0; // 发送队首字：寄存态和完整下一态
reg [31:0] n_word0; // 发送队首字：寄存态和完整下一态
reg [31:0] r_word1; // 发送队尾字：寄存态和完整下一态
reg [31:0] n_word1; // 发送队尾字：寄存态和完整下一态
reg [1:0] r_purpose0; // 队首用途：请求回复确认：寄存态和完整下一态
reg [1:0] n_purpose0; // 队首用途：请求回复确认：寄存态和完整下一态
reg [1:0] r_purpose1; // 队尾用途：请求回复确认：寄存态和完整下一态
reg [1:0] n_purpose1; // 队尾用途：请求回复确认：寄存态和完整下一态
reg r_response_fault; // 回复超时粘滞状态：寄存态和完整下一态
reg n_response_fault; // 回复超时粘滞状态：寄存态和完整下一态
reg r_restart_fault; // 重启超时粘滞状态：寄存态和完整下一态
reg n_restart_fault; // 重启超时粘滞状态：寄存态和完整下一态
reg r_protocol_fault; // 协议或输入违约粘滞状态：寄存态和完整下一态
reg n_protocol_fault; // 协议或输入违约粘滞状态：寄存态和完整下一态
reg [1:0] r_channel_online; // Channel0及Channel4在线状态：寄存态和完整下一态
reg [1:0] n_channel_online; // Channel0及Channel4在线状态：寄存态和完整下一态
reg [3:0] r_width; // 当前协商逻辑宽度：寄存态和完整下一态
reg [3:0] n_width; // 当前协商逻辑宽度：寄存态和完整下一态
reg r_soft_lock; // 硬件软锁：寄存态和完整下一态
reg n_soft_lock; // 硬件软锁：寄存态和完整下一态
reg r_peer_ready; // 对端最近报告的TxReady能力：寄存态和完整下一态
reg n_peer_ready; // 对端最近报告的TxReady能力：寄存态和完整下一态
reg r_retry_valid; // 冲突失败重试目标有效：寄存态和完整下一态
reg n_retry_valid; // 冲突失败重试目标有效：寄存态和完整下一态
reg [3:0] r_retry_target; // 冲突失败重试目标：寄存态和完整下一态
reg [3:0] n_retry_target; // 冲突失败重试目标：寄存态和完整下一态
reg r_round_valid; // 宽度协商轮次有效：寄存态和完整下一态
reg n_round_valid; // 宽度协商轮次有效：寄存态和完整下一态
reg [3:0] r_round_target; // 当前轮次胜出宽度：寄存态和完整下一态
reg [3:0] n_round_target; // 当前轮次胜出宽度：寄存态和完整下一态
reg r_round_remote; // 当前轮次接纳了对端请求：寄存态和完整下一态
reg n_round_remote; // 当前轮次接纳了对端请求：寄存态和完整下一态
reg r_round_conflict; // 当前轮次不同目标冲突：寄存态和完整下一态
reg n_round_conflict; // 当前轮次不同目标冲突：寄存态和完整下一态
reg r_round_sent; // 当前轮次实际发送过ACK：寄存态和完整下一态
reg n_round_sent; // 当前轮次实际发送过ACK：寄存态和完整下一态
reg r_round_received; // 当前轮次匹配收到ACK：寄存态和完整下一态
reg n_round_received; // 当前轮次匹配收到ACK：寄存态和完整下一态
reg r_round_applied; // 当前轮次已经应用宽度动作：寄存态和完整下一态
reg n_round_applied; // 当前轮次已经应用宽度动作：寄存态和完整下一态
reg r_event_valid; // 寄存宽度动作有效：寄存态和完整下一态
reg n_event_valid; // 寄存宽度动作有效：寄存态和完整下一态
reg [3:0] r_event_old; // 动作前协商宽度：寄存态和完整下一态
reg [3:0] n_event_old; // 动作前协商宽度：寄存态和完整下一态
reg [3:0] r_event_new; // 动作后协商宽度：寄存态和完整下一态
reg [3:0] n_event_new; // 动作后协商宽度：寄存态和完整下一态
reg [1:0] r_event_action; // 掉电或Fault动作类别：寄存态和完整下一态
reg [1:0] n_event_action; // 掉电或Fault动作类别：寄存态和完整下一态
reg r_event_pl; // 物理动作的协议PL编号：寄存态和完整下一态
reg n_event_pl; // 物理动作的协议PL编号：寄存态和完整下一态
reg r_repeat_fault; // 当前Channel状态请求粘滞诊断：寄存态和完整下一态
reg n_repeat_fault; // 当前Channel状态请求粘滞诊断：寄存态和完整下一态
reg r_unsupported_fault; // 未支持语义消息粘滞诊断：寄存态和完整下一态
reg n_unsupported_fault; // 未支持语义消息粘滞诊断：寄存态和完整下一态
reg r_owed_first; // 两种Pending义务中先建立者的kind：寄存态和完整下一态
reg n_owed_first; // 两种Pending义务中先建立者的kind：寄存态和完整下一态
reg [31:0] calc_reply; // 语义决定只在当前组合阶段有效，不形成额外状态
reg [3:0] calc_winner; // 语义决定只在当前组合阶段有效，不形成额外状态
reg [3:0] calc_owed_channel_target; // 语义决定只在当前组合阶段有效，不形成额外状态
reg flag_winner_valid; // 语义决定只在当前组合阶段有效，不形成额外状态
reg flag_repeated; // 语义决定只在当前组合阶段有效，不形成额外状态
reg flag_rx_local_width; // 语义决定只在当前组合阶段有效，不形成额外状态
reg [3:0] calc_rx_local_target; // 语义决定只在当前组合阶段有效，不形成额外状态
wire [3:0] wire_rx_target; // 接收目标显式拆为四位语义字段
assign wire_rx_target = i_rx_word[19:16]; // 接收目标显式拆为四位语义字段
wire flag_rx_channel; // 只解析可靠分帧输入，不引入额外线协议字段
wire flag_rx_known; // 只解析可靠分帧输入，不引入额外线协议字段
wire [31:0] wire_rx_canonical; // 只解析可靠分帧输入，不引入额外线协议字段
wire [10:0] unused_rx_reserved; // 接收保留位显式丢弃，不参与协议判定
assign unused_rx_reserved = {i_rx_word[31:29],i_rx_word[14:9],i_rx_word[1:0]}; // 接收保留位显式丢弃，不参与协议判定
assign flag_rx_channel = i_rx_word[8]; // 已知消息下类型零为Width，类型四为Channel
assign flag_rx_known = (i_rx_word[5:2] == 4'd8) && ((i_rx_word[8:6] == 3'd0) || (i_rx_word[8:6] == 3'd4)) && ((i_rx_word[23:20] == 4'd4) || (i_rx_word[23:20] == 4'd6) || (i_rx_word[23:20] == 4'd7) || (i_rx_word[23:20] == 4'd8)); // 仅终结规定类别类型和四种握手命令
assign wire_rx_canonical = {3'd0, (!flag_rx_channel && i_rx_word[28]), (i_rx_word[23:20] == 4'd4 ? 4'd0 : i_rx_word[27:24]), i_rx_word[23:20], (i_rx_word[23:20] == 4'd8 ? 4'd0 : i_rx_word[19:16]), (!flag_rx_channel && i_rx_word[15]), 6'd0, i_rx_word[8:6], 4'd8, 2'd0}; // 忽略接收保留位，规范化请求回显和Pending目标
always @(*) begin // 沿前输出只依赖旧寄存态与全局复位，不依赖本沿实际take。
o_source_pending = 2'd0; // 沿前有效队首，低位Width高位Channel默认无效或清零
o_source_words = 64'd0; // 沿前两来源字，仅队首有效默认无效或清零
o_source_purpose = 2'd0; // 队首用途：零Request，一回复，二确认默认无效或清零
o_source_request_word = 32'd0; // 队首所属交换的原请求字默认无效或清零
o_local_busy = 1'd0; // 沿前本地请求占用默认无效或清零
o_local_request_word = 32'd0; // 沿前本地原请求快照默认无效或清零
o_local_phase = 2'd0; // 零排队，一等响应，二确认排队默认无效或清零
o_local_restart = 1'd0; // 沿前本地请求正在履行pending重启默认无效或清零
o_remote_busy = 1'd0; // 沿前对端交换占用默认无效或清零
o_remote_request_word = 32'd0; // 沿前对端原请求快照默认无效或清零
o_remote_reply_word = 32'd0; // 沿前已冻结回复字默认无效或清零
o_remote_reply_sent = 1'd0; // 沿前ACK已发送且仍等确认默认无效或清零
o_remote_from_pending = 1'd0; // 对端交换履行先前pending重启默认无效或清零
o_waiting_peer = 2'd0; // 按kind等待对端重启并完成默认无效或清零
o_owed_restart = 2'd0; // 按kind保留本地重启责任默认无效或清零
o_owed_requests = 64'd0; // 两种kind原始重启目标与消息快照默认无效或清零
o_queue_count = 2'd0; // 沿前两条发送队列占用默认无效或清零
o_response_fault = 1'd0; // 回复超时粘滞诊断默认无效或清零
o_restart_fault = 1'd0; // 任一重启超时粘滞诊断默认无效或清零
o_protocol_fault = 1'd0; // 握手或消费违约粘滞诊断默认无效或清零
o_channel_online = 2'd0; // 沿前Channel0与Channel4在线状态默认无效
o_channel_closing = 2'd0; // 沿前正在下线的Channel0与Channel4默认无效
o_negotiated_width = 4'd0; // 协商逻辑宽度，非物理PL状态默认无效
o_soft_lockout = 1'd0; // 沿前硬件软锁默认无效
o_peer_tx_ready_support = 1'd0; // 对端最近Width字的TxReady能力默认无效
o_owed_first_channel = 1'd0; // 沿前最早仍未发送的Pending重启义务kind默认无效
o_retry_blocked = 1'd0; // 宽度冲突失败的重试目标有效默认无效
o_retry_target = 4'd0; // 有效冲突失败重试目标默认无效
o_round_valid = 1'd0; // 沿前Width协商轮次有效默认无效
o_round_target = 4'd0; // 当前宽度轮次胜出目标默认无效
o_round_remote_accepted = 1'd0; // 轮次曾接纳对端请求默认无效
o_round_conflict = 1'd0; // 轮次存在不同目标冲突默认无效
o_round_sent_ack = 1'd0; // 轮次已经实际发送ACK默认无效
o_round_received_ack = 1'd0; // 轮次已经匹配收到ACK默认无效
o_round_applied = 1'd0; // 本轮ACK对已应用一次默认无效
o_width_event_valid = 1'd0; // 前一沿形成的寄存宽度动作有效默认无效
o_width_event_old = 4'd0; // 宽度动作前的协商状态默认无效
o_width_event_new = 4'd0; // 宽度动作后的协商状态默认无效
o_width_event_action = 2'd0; // 一进入掉电，二等待对端掉电，三进入Fault默认无效
o_width_event_pl = 1'd0; // 宽度动作使用协议PL编号默认无效
o_repeat_fault = 1'd0; // 当前Channel状态请求粘滞诊断默认无效
o_unsupported_fault = 1'd0; // 未支持语义消息的粘滞诊断默认无效
o_negotiated_width = C_INITIAL_WIDTH[3:0]; // 复位可见初始协商宽度与参考一致
if (i_rstn) begin // 同步复位期间保持原有外部屏蔽语义。
o_source_pending = r_count == 0 ? 2'd0 : (r_word0[8] ? 2'd2 : 2'd1); // 沿前状态提供稳定所有权和唯一待发队首
o_source_words = r_count == 0 ? 64'd0 : (r_word0[8] ? {r_word0,32'd0} : {32'd0,r_word0}); // 沿前状态提供稳定所有权和唯一待发队首
o_source_purpose = r_count == 0 ? 2'd0 : r_purpose0; // 沿前状态提供稳定所有权和唯一待发队首
o_source_request_word = r_count == 0 ? 32'd0 : (r_purpose0 == 2'd1 ? r_remote_word : r_local_word); // 沿前状态提供稳定所有权和唯一待发队首
o_local_busy = r_local_busy; // 沿前状态提供稳定所有权和唯一待发队首
o_local_request_word = r_local_busy ? r_local_word : 32'd0; // 沿前状态提供稳定所有权和唯一待发队首
o_local_phase = r_local_busy ? r_local_phase : 2'd0; // 沿前状态提供稳定所有权和唯一待发队首
o_local_restart = r_local_busy && r_local_restart; // 沿前状态提供稳定所有权和唯一待发队首
o_remote_busy = r_remote_busy; // 沿前状态提供稳定所有权和唯一待发队首
o_remote_request_word = r_remote_busy ? r_remote_word : 32'd0; // 沿前状态提供稳定所有权和唯一待发队首
o_remote_reply_word = r_remote_busy ? r_remote_reply : 32'd0; // 沿前状态提供稳定所有权和唯一待发队首
o_remote_reply_sent = r_remote_busy && r_remote_sent; // 沿前状态提供稳定所有权和唯一待发队首
o_remote_from_pending = r_remote_busy && r_remote_pending; // 沿前状态提供稳定所有权和唯一待发队首
o_waiting_peer = r_waiting; // 沿前状态提供稳定所有权和唯一待发队首
o_owed_restart = r_owed; // 沿前状态提供稳定所有权和唯一待发队首
o_owed_requests = {(r_owed[1] ? r_owed_channel : 32'd0), (r_owed[0] ? r_owed_width : 32'd0)}; // 沿前状态提供稳定所有权和唯一待发队首
o_queue_count = r_count; // 沿前状态提供稳定所有权和唯一待发队首
o_response_fault = r_response_fault; // 沿前状态提供稳定所有权和唯一待发队首
o_restart_fault = r_restart_fault; // 沿前状态提供稳定所有权和唯一待发队首
o_protocol_fault = r_protocol_fault || r_repeat_fault; // 沿前状态提供稳定所有权和唯一待发队首
o_channel_online = r_channel_online; // 沿前语义寄存态与共享状态同步观察
o_negotiated_width = r_width; // 沿前语义寄存态与共享状态同步观察
o_soft_lockout = r_soft_lock; // 沿前语义寄存态与共享状态同步观察
o_peer_tx_ready_support = r_peer_ready; // 沿前语义寄存态与共享状态同步观察
o_owed_first_channel = r_owed == 2'd0 ? 1'b0 : r_owed_first; // 沿前语义寄存态与共享状态同步观察
o_retry_blocked = r_retry_valid; // 沿前语义寄存态与共享状态同步观察
o_retry_target = r_retry_valid ? r_retry_target : 4'd0; // 沿前语义寄存态与共享状态同步观察
o_round_valid = r_round_valid; // 沿前语义寄存态与共享状态同步观察
o_round_target = r_round_valid ? r_round_target : 4'd0; // 沿前语义寄存态与共享状态同步观察
o_round_remote_accepted = r_round_valid && r_round_remote; // 沿前语义寄存态与共享状态同步观察
o_round_conflict = r_round_valid && r_round_conflict; // 沿前语义寄存态与共享状态同步观察
o_round_sent_ack = r_round_valid && r_round_sent; // 沿前语义寄存态与共享状态同步观察
o_round_received_ack = r_round_valid && r_round_received; // 沿前语义寄存态与共享状态同步观察
o_round_applied = r_round_valid && r_round_applied; // 沿前语义寄存态与共享状态同步观察
o_width_event_valid = r_event_valid; // 沿前语义寄存态与共享状态同步观察
o_width_event_old = r_event_valid ? r_event_old : 4'd0; // 沿前语义寄存态与共享状态同步观察
o_width_event_new = r_event_valid ? r_event_new : 4'd0; // 沿前语义寄存态与共享状态同步观察
o_width_event_action = r_event_valid ? r_event_action : 2'd0; // 沿前语义寄存态与共享状态同步观察
o_width_event_pl = r_event_valid && r_event_pl; // 沿前语义寄存态与共享状态同步观察
o_repeat_fault = r_repeat_fault; // 沿前语义寄存态与共享状态同步观察
o_unsupported_fault = r_unsupported_fault; // 沿前语义寄存态与共享状态同步观察
if (r_local_busy && r_local_word[8] && !r_local_word[19] && (r_local_word[18:16] == 3'd0 || r_local_word[18:16] == 3'd4)) o_channel_closing[r_local_word[18]] = 1'b1; // 只有当前交换的明确下线目标阻止对应Channel新消息启动
if (r_remote_busy && r_remote_word[8] && !r_remote_word[19] && (r_remote_word[18:16] == 3'd0 || r_remote_word[18:16] == 3'd4)) o_channel_closing[r_remote_word[18]] = 1'b1; // 只有当前交换的明确下线目标阻止对应Channel新消息启动
end // 结束沿前状态有效分支。
end // 结束独立沿前状态输出。
always @* begin // 组合下一态固定按旧计时、实际TX、RX、本地接纳顺序
n_channel_online = r_channel_online; // Channel0及Channel4在线状态默认保持
n_width = r_width; // 当前协商逻辑宽度默认保持
n_soft_lock = r_soft_lock; // 硬件软锁默认保持
n_peer_ready = r_peer_ready; // 对端最近报告的TxReady能力默认保持
n_retry_valid = r_retry_valid; // 冲突失败重试目标有效默认保持
n_retry_target = r_retry_target; // 冲突失败重试目标默认保持
n_round_valid = r_round_valid; // 宽度协商轮次有效默认保持
n_round_target = r_round_target; // 当前轮次胜出宽度默认保持
n_round_remote = r_round_remote; // 当前轮次接纳了对端请求默认保持
n_round_conflict = r_round_conflict; // 当前轮次不同目标冲突默认保持
n_round_sent = r_round_sent; // 当前轮次实际发送过ACK默认保持
n_round_received = r_round_received; // 当前轮次匹配收到ACK默认保持
n_round_applied = r_round_applied; // 当前轮次已经应用宽度动作默认保持
n_event_valid = r_event_valid; // 寄存宽度动作有效默认保持
n_event_old = r_event_old; // 动作前协商宽度默认保持
n_event_new = r_event_new; // 动作后协商宽度默认保持
n_event_action = r_event_action; // 掉电或Fault动作类别默认保持
n_event_pl = r_event_pl; // 物理动作的协议PL编号默认保持
n_repeat_fault = r_repeat_fault; // 当前Channel状态请求粘滞诊断默认保持
n_unsupported_fault = r_unsupported_fault; // 未支持语义消息粘滞诊断默认保持
n_owed_first = r_owed_first; // 两种Pending义务中先建立者的kind默认保持
n_event_valid = 1'b0; n_event_old = 4'd0; n_event_new = 4'd0; n_event_action = 2'd0; n_event_pl = 1'b0; // 宽度动作是一周期脉冲，临时语义决定完整默认清零
calc_reply = 32'd0; calc_winner = 4'd0; calc_owed_channel_target = 4'd0; flag_winner_valid = 1'b0; flag_repeated = 1'b0; flag_rx_local_width = 1'b0; calc_rx_local_target = 4'd0; // 宽度动作是一周期脉冲，临时语义决定完整默认清零
n_local_busy = r_local_busy; // 本地交换所有权默认保持
n_local_word = r_local_word; // 本地规范化请求字默认保持
n_local_phase = r_local_phase; // 本地排队等待回复与确认待发送阶段默认保持
n_local_restart = r_local_restart; // 本地请求来自Pending重启责任默认保持
n_remote_busy = r_remote_busy; // 对端交换所有权默认保持
n_remote_word = r_remote_word; // 对端规范化原请求字默认保持
n_remote_reply = r_remote_reply; // 接收当沿冻结的回复字默认保持
n_remote_sent = r_remote_sent; // 回复已实际发送默认保持
n_remote_pending = r_remote_pending; // 对端请求来自等待其重启默认保持
n_remote_missed = r_remote_missed; // 本次对端请求已报告回复超时默认保持
n_response_age = r_response_age; // 未发送回复的饱和年龄默认保持
n_waiting = r_waiting; // 两种消息等待对端重启默认保持
n_owed = r_owed; // 两种消息欠本地重启默认保持
n_owed_width = r_owed_width; // Width原始重启目标默认保持
n_owed_channel = r_owed_channel; // Channel原始重启目标默认保持
n_width_age = r_width_age; // Width重启饱和年龄默认保持
n_channel_age = r_channel_age; // Channel重启饱和年龄默认保持
n_restart_missed = r_restart_missed; // 各重启责任已报告超时默认保持
n_count = r_count; // 有序发送队列占用默认保持
n_word0 = r_word0; // 发送队首字默认保持
n_word1 = r_word1; // 发送队尾字默认保持
n_purpose0 = r_purpose0; // 队首用途：请求回复确认默认保持
n_purpose1 = r_purpose1; // 队尾用途：请求回复确认默认保持
n_response_fault = r_response_fault; // 回复超时粘滞状态默认保持
n_restart_fault = r_restart_fault; // 重启超时粘滞状态默认保持
n_protocol_fault = r_protocol_fault; // 协议或输入违约粘滞状态默认保持
o_local_ready = 1'd0; // TX和RX处理后的本地接纳资格默认无效或清零
o_local_accept = 1'd0; // 本沿真正接纳本地请求默认无效或清零
o_tx_valid = 1'd0; // 本沿实际发送队首默认无效或清零
o_tx_word = 32'd0; // 本沿实际发送完整字默认无效或清零
o_rx_status = 4'd0; // 本沿接收结果编码默认无效或清零
o_local_done = 1'd0; // 本沿本地交换完成默认无效或清零
o_local_done_channel = 1'd0; // 本地完成种类默认无效或清零
o_local_done_target = 4'd0; // 本地完成原目标默认无效或清零
o_local_success = 1'd0; // 本地完成是否成功默认无效或清零
o_remote_done = 1'd0; // 本沿对端交换完成默认无效或清零
o_remote_done_channel = 1'd0; // 对端完成种类默认无效或清零
o_remote_done_target = 4'd0; // 对端完成原目标默认无效或清零
o_remote_success = 1'd0; // 对端完成是否成功默认无效或清零
o_response_miss = 1'd0; // 本沿首次超过回复截止默认无效或清零
o_restart_miss = 2'd0; // 本沿两种kind首次超过重启截止默认无效或清零
o_take_error = 1'd0; // 实际消费输入不对应有效单一队首默认无效或清零
o_protocol_error = 1'd0; // 本沿接收或回复策略违约默认无效或清零
o_pending_sent = 1'd0; // 本沿实际发送pending默认无效或清零
o_pending_received = 1'd0; // 本沿匹配接收pending默认无效或清零
o_restart_commit = 2'd0; // 本沿实际提交所欠重启Request默认无效或清零
o_lockout_notify = 1'd0; // 本沿软锁从清除到重新置位通知默认无效
o_auto_restart = 2'd0; // 本沿两kind自动重启接纳事件默认无效
o_repeat_error = 1'd0; // 本沿接纳当前Channel状态请求的诊断默认无效
o_unsupported = 1'd0; // 本沿收到未支持的语义消息默认无效
if (i_rstn) begin // 复位期间屏蔽所有外部可见输出
if (r_remote_busy && !r_remote_sent && !r_remote_missed) begin // 接收当沿年龄为零；严格超过一微秒的下一沿只报告一次
if (r_response_age >= C_RESPONSE_LIMIT) begin // 接收当沿年龄为零；严格超过一微秒的下一沿只报告一次
n_remote_missed = 1'b1; n_response_fault = 1'b1; o_response_miss = 1'b1; // 接收当沿年龄为零；严格超过一微秒的下一沿只报告一次
end else n_response_age = r_response_age + 1'b1; // 接收当沿年龄为零；严格超过一微秒的下一沿只报告一次
end // 接收当沿年龄为零；严格超过一微秒的下一沿只报告一次
if (r_owed[0] && !r_restart_missed[0]) begin // Pending实际发送后计十毫秒，排队不解除责任
if (r_width_age >= C_RESTART_LIMIT) begin // Pending实际发送后计十毫秒，排队不解除责任
n_restart_missed[0] = 1'b1; n_restart_fault = 1'b1; o_restart_miss[0] = 1'b1; // Pending实际发送后计十毫秒，排队不解除责任
end else n_width_age = r_width_age + 1'b1; // Pending实际发送后计十毫秒，排队不解除责任
end // Pending实际发送后计十毫秒，排队不解除责任
if (r_owed[1] && !r_restart_missed[1]) begin // Pending实际发送后计十毫秒，排队不解除责任
if (r_channel_age >= C_RESTART_LIMIT) begin // Pending实际发送后计十毫秒，排队不解除责任
n_restart_missed[1] = 1'b1; n_restart_fault = 1'b1; o_restart_miss[1] = 1'b1; // Pending实际发送后计十毫秒，排队不解除责任
end else n_channel_age = r_channel_age + 1'b1; // Pending实际发送后计十毫秒，排队不解除责任
end // Pending实际发送后计十毫秒，排队不解除责任
if (i_clear_soft_lockout) n_soft_lock = 1'b0; // 本沿策略与固件清除先于任何实际线事件
if (n_owed_first) begin // 原子策略更新后：先检查最早建立的责任，未ready可检查另一kind
if (!n_local_busy && !n_remote_busy && n_owed[1] && n_owed_channel[19] && (n_owed_channel[18:16] == 3'd0 || n_owed_channel[18:16] == 3'd4) && !n_channel_online[n_owed_channel[18]] && i_channel_ready[n_owed_channel[18]] && !n_waiting[1]) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,1'b0,4'd0,4'd4,n_owed_channel[19:16],1'b0,6'd0,3'd4,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[1]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[1] = 1'b1; // 分别记录自动重启与显式本地接纳
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
if (!n_local_busy && !n_remote_busy && n_owed[0] && i_width_ready && (C_ROLE_SWITCH == 0) && (C_FOLDING != 0) && !n_waiting[0] && ((n_owed_width[19:16] == 4'd0 && C_ALLOWED_PL_MASK == 3) || (n_owed_width[19:16] == 4'd1 && C_ALLOWED_PL_MASK[0]) || (n_owed_width[19:16] == 4'd9 && C_ALLOWED_PL_MASK[1])) && ((n_owed_width[19:16] == 4'd0) != (n_width == 4'd0)) && !(n_owed_width[19:16] == 4'd0 && (n_owed_width[15] || n_soft_lock)) && !(n_retry_valid && n_retry_target == n_owed_width[19:16])) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,(C_TX_READY_SUPPORT != 0),4'd0,4'd4,n_owed_width[19:16],n_owed_width[15],6'd0,3'd0,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[0]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[0] = 1'b1; // 分别记录自动重启与显式本地接纳
n_round_valid = 1'b1; n_round_target = n_owed_width[19:16]; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 新本地宽度请求建立独立ACK对轮次
n_retry_valid = 1'b0; n_retry_target = 4'd0; // 新宽度请求接纳后清除旧重试阻塞
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
end else begin // 相反义务建立顺序
if (!n_local_busy && !n_remote_busy && n_owed[0] && i_width_ready && (C_ROLE_SWITCH == 0) && (C_FOLDING != 0) && !n_waiting[0] && ((n_owed_width[19:16] == 4'd0 && C_ALLOWED_PL_MASK == 3) || (n_owed_width[19:16] == 4'd1 && C_ALLOWED_PL_MASK[0]) || (n_owed_width[19:16] == 4'd9 && C_ALLOWED_PL_MASK[1])) && ((n_owed_width[19:16] == 4'd0) != (n_width == 4'd0)) && !(n_owed_width[19:16] == 4'd0 && (n_owed_width[15] || n_soft_lock)) && !(n_retry_valid && n_retry_target == n_owed_width[19:16])) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,(C_TX_READY_SUPPORT != 0),4'd0,4'd4,n_owed_width[19:16],n_owed_width[15],6'd0,3'd0,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[0]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[0] = 1'b1; // 分别记录自动重启与显式本地接纳
n_round_valid = 1'b1; n_round_target = n_owed_width[19:16]; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 新本地宽度请求建立独立ACK对轮次
n_retry_valid = 1'b0; n_retry_target = 4'd0; // 新宽度请求接纳后清除旧重试阻塞
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
if (!n_local_busy && !n_remote_busy && n_owed[1] && n_owed_channel[19] && (n_owed_channel[18:16] == 3'd0 || n_owed_channel[18:16] == 3'd4) && !n_channel_online[n_owed_channel[18]] && i_channel_ready[n_owed_channel[18]] && !n_waiting[1]) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,1'b0,4'd0,4'd4,n_owed_channel[19:16],1'b0,6'd0,3'd4,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[1]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[1] = 1'b1; // 分别记录自动重启与显式本地接纳
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
end // 结束按责任先后自动重启选择
if (i_source_take != 2'd0) begin // 先消费沿前队首；错误take不形成任何线发送
if (i_source_take == 2'd3 || i_source_take != o_source_pending) begin // 先消费沿前队首；错误take不形成任何线发送
o_take_error = 1'b1; n_protocol_fault = 1'b1; // 先消费沿前队首；错误take不形成任何线发送
end else begin // 先消费沿前队首；错误take不形成任何线发送
o_tx_valid = 1'b1; o_tx_word = r_word0; // 先消费沿前队首；错误take不形成任何线发送
n_word0 = r_word1; n_purpose0 = r_purpose1; n_word1 = 32'd0; n_purpose1 = 2'd0; n_count = r_count - 1'b1; // 先消费沿前队首；错误take不形成任何线发送
case (r_purpose0) // 先消费沿前队首；错误take不形成任何线发送
2'd0: begin // 真正Request发送才开始等待回复并完成所欠重启
n_local_phase = 2'd1; // 真正Request发送才开始等待回复并完成所欠重启
if (n_owed[r_word0[8]]) begin // 真正Request发送才开始等待回复并完成所欠重启
o_restart_commit = i_source_take; n_owed[r_word0[8]] = 1'b0; n_restart_missed[r_word0[8]] = 1'b0; // 真正Request发送才开始等待回复并完成所欠重启
if (r_word0[8]) begin n_owed_channel = 32'd0; n_channel_age = {C_RESTART_BITS{1'b0}}; end // 真正Request发送才开始等待回复并完成所欠重启
else begin n_owed_width = 32'd0; n_width_age = {C_RESTART_BITS{1'b0}}; end // 真正Request发送才开始等待回复并完成所欠重启
end // 真正Request发送才开始等待回复并完成所欠重启
end // 真正Request发送才开始等待回复并完成所欠重启
2'd2: begin // 确认ACK发送形成成功本地完成
o_local_done = 1'b1; o_local_done_channel = n_local_word[8]; o_local_done_target = n_local_word[19:16]; o_local_success = 1'b1; // 完成事件携带被释放交换原目标
n_local_busy = 1'b0; n_local_word = 32'd0; n_local_phase = 2'd0; n_local_restart = 1'b0; // 仅完成或合法Pending释放本地交换
end // 结束确认发送处理
2'd1: begin // 回复ACK后仍等待确认，NACK实际发送即结束
case (r_word0[23:20]) // 回复ACK后仍等待确认，NACK实际发送即结束
4'd6: n_remote_sent = 1'b1; // 回复ACK后仍等待确认，NACK实际发送即结束
4'd7: begin // 回复ACK后仍等待确认，NACK实际发送即结束
o_remote_done = 1'b1; o_remote_done_channel = n_remote_word[8]; o_remote_done_target = n_remote_word[19:16]; o_remote_success = 1'b0; // 完成事件携带被释放交换原目标
if (n_remote_pending) n_waiting[n_remote_word[8]] = 1'b0; // 完成对端重启才解除等待标志
n_remote_busy = 1'b0; n_remote_word = 32'd0; n_remote_reply = 32'd0; n_remote_sent = 1'b0; n_remote_pending = 1'b0; n_remote_missed = 1'b0; n_response_age = {C_RESPONSE_BITS{1'b0}}; // 对端结束后清除旧交换元数据
end // 结束NACK回复处理
4'd8: begin // Pending把重启义务和原目标交给本地并从实际发送计时
if (n_owed == 2'd0) n_owed_first = r_word0[8]; // 第一份实际Pending建立两kind自动重启先后
o_pending_sent = 1'b1; n_owed[r_word0[8]] = 1'b1; n_restart_missed[r_word0[8]] = 1'b0; // Pending把重启义务和原目标交给本地并从实际发送计时
if (r_word0[8]) begin n_owed_channel = n_remote_word; n_channel_age = {C_RESTART_BITS{1'b0}}; end // Pending把重启义务和原目标交给本地并从实际发送计时
else begin n_owed_width = n_remote_word; n_width_age = {C_RESTART_BITS{1'b0}}; end // Pending把重启义务和原目标交给本地并从实际发送计时
if (n_remote_pending) n_waiting[n_remote_word[8]] = 1'b0; // Pending把重启义务和原目标交给本地并从实际发送计时
n_remote_busy = 1'b0; n_remote_word = 32'd0; n_remote_reply = 32'd0; n_remote_sent = 1'b0; n_remote_pending = 1'b0; n_remote_missed = 1'b0; n_response_age = {C_RESPONSE_BITS{1'b0}}; // 对端结束后清除旧交换元数据
end // 完整枚举队首用途及回复命令，非法内部状态显式诊断
default: begin o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 完整枚举队首用途及回复命令，非法内部状态显式诊断
endcase // 完整枚举队首用途及回复命令，非法内部状态显式诊断
end // 完整枚举队首用途及回复命令，非法内部状态显式诊断
default: begin o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 完整枚举队首用途及回复命令，非法内部状态显式诊断
endcase // 完整枚举队首用途及回复命令，非法内部状态显式诊断
end // 完整枚举队首用途及回复命令，非法内部状态显式诊断
end // 完整枚举队首用途及回复命令，非法内部状态显式诊断
if (o_tx_valid) begin // 实际TX提交后才同步发送语义
if (!o_tx_word[8]) begin // Width发送不论命令均观察Priority
if (o_tx_word[15] && !n_soft_lock) begin n_soft_lock = 1'b1; o_lockout_notify = 1'b1; end // 真实Width线字优先级置位触发软锁通知
if (o_tx_word[23:20] == 4'd6) begin // 实际ACK发送更新宽度轮次
if (n_round_valid) begin // 仅当前宽度轮次累计实际发送或匹配接收ACK
n_round_sent = 1'b1; // 仅当前宽度轮次累计实际发送或匹配接收ACK
if (n_round_sent && n_round_received && !n_round_applied) begin // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
n_event_valid = 1'b1; n_event_old = n_width; n_event_new = n_round_target; // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
if (n_round_target == 4'd0) begin n_event_action = 2'd3; n_event_pl = (n_width == 4'd1); end // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
else begin n_event_action = n_round_remote ? 2'd1 : 2'd2; n_event_pl = (n_round_target == 4'd1); end // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
n_width = n_round_target; n_round_applied = 1'b1; // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
end // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
end // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
end // 结束Width发送语义
end // 结束Width发送语义
if (o_local_done && o_local_success && o_local_done_channel && (o_local_done_target[2:0] == 3'd0 || o_local_done_target[2:0] == 3'd4)) n_channel_online[o_local_done_target[2]] = o_local_done_target[3]; // 仅成功完成改变Channel，无Width所有权时结束协商轮次
if (o_remote_done && o_remote_success && o_remote_done_channel && (o_remote_done_target[2:0] == 3'd0 || o_remote_done_target[2:0] == 3'd4)) n_channel_online[o_remote_done_target[2]] = o_remote_done_target[3]; // 仅成功完成改变Channel，无Width所有权时结束协商轮次
if (!(n_local_busy && !n_local_word[8]) && !(n_remote_busy && !n_remote_word[8])) begin // 仅成功完成改变Channel，无Width所有权时结束协商轮次
n_round_valid = 1'b0; n_round_target = 4'd0; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 仅成功完成改变Channel，无Width所有权时结束协商轮次
end // 仅成功完成改变Channel，无Width所有权时结束协商轮次
if (n_owed_first) begin // 实际TX完成后：先检查最早建立的责任，未ready可检查另一kind
if (!n_local_busy && !n_remote_busy && n_owed[1] && n_owed_channel[19] && (n_owed_channel[18:16] == 3'd0 || n_owed_channel[18:16] == 3'd4) && !n_channel_online[n_owed_channel[18]] && i_channel_ready[n_owed_channel[18]] && !n_waiting[1]) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,1'b0,4'd0,4'd4,n_owed_channel[19:16],1'b0,6'd0,3'd4,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[1]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[1] = 1'b1; // 分别记录自动重启与显式本地接纳
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
if (!n_local_busy && !n_remote_busy && n_owed[0] && i_width_ready && (C_ROLE_SWITCH == 0) && (C_FOLDING != 0) && !n_waiting[0] && ((n_owed_width[19:16] == 4'd0 && C_ALLOWED_PL_MASK == 3) || (n_owed_width[19:16] == 4'd1 && C_ALLOWED_PL_MASK[0]) || (n_owed_width[19:16] == 4'd9 && C_ALLOWED_PL_MASK[1])) && ((n_owed_width[19:16] == 4'd0) != (n_width == 4'd0)) && !(n_owed_width[19:16] == 4'd0 && (n_owed_width[15] || n_soft_lock)) && !(n_retry_valid && n_retry_target == n_owed_width[19:16])) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,(C_TX_READY_SUPPORT != 0),4'd0,4'd4,n_owed_width[19:16],n_owed_width[15],6'd0,3'd0,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[0]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[0] = 1'b1; // 分别记录自动重启与显式本地接纳
n_round_valid = 1'b1; n_round_target = n_owed_width[19:16]; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 新本地宽度请求建立独立ACK对轮次
n_retry_valid = 1'b0; n_retry_target = 4'd0; // 新宽度请求接纳后清除旧重试阻塞
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
end else begin // 相反义务建立顺序
if (!n_local_busy && !n_remote_busy && n_owed[0] && i_width_ready && (C_ROLE_SWITCH == 0) && (C_FOLDING != 0) && !n_waiting[0] && ((n_owed_width[19:16] == 4'd0 && C_ALLOWED_PL_MASK == 3) || (n_owed_width[19:16] == 4'd1 && C_ALLOWED_PL_MASK[0]) || (n_owed_width[19:16] == 4'd9 && C_ALLOWED_PL_MASK[1])) && ((n_owed_width[19:16] == 4'd0) != (n_width == 4'd0)) && !(n_owed_width[19:16] == 4'd0 && (n_owed_width[15] || n_soft_lock)) && !(n_retry_valid && n_retry_target == n_owed_width[19:16])) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,(C_TX_READY_SUPPORT != 0),4'd0,4'd4,n_owed_width[19:16],n_owed_width[15],6'd0,3'd0,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[0]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[0] = 1'b1; // 分别记录自动重启与显式本地接纳
n_round_valid = 1'b1; n_round_target = n_owed_width[19:16]; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 新本地宽度请求建立独立ACK对轮次
n_retry_valid = 1'b0; n_retry_target = 4'd0; // 新宽度请求接纳后清除旧重试阻塞
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
if (!n_local_busy && !n_remote_busy && n_owed[1] && n_owed_channel[19] && (n_owed_channel[18:16] == 3'd0 || n_owed_channel[18:16] == 3'd4) && !n_channel_online[n_owed_channel[18]] && i_channel_ready[n_owed_channel[18]] && !n_waiting[1]) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,1'b0,4'd0,4'd4,n_owed_channel[19:16],1'b0,6'd0,3'd4,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[1]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[1] = 1'b1; // 分别记录自动重启与显式本地接纳
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
end // 结束按责任先后自动重启选择
end // 结束实际TX同步阶段
if (i_rx_valid) begin // 实际TX同步之后处理一个可靠接收字
if (flag_rx_known && ((!flag_rx_channel && (C_FOLDING == 0)) || (flag_rx_channel && i_rx_word[23:20] == 4'd4 && i_rx_word[18:16] != 3'd0 && i_rx_word[18:16] != 3'd4))) begin // 无Folding的Width或未知Channel请求不虚构回复
o_rx_status = 4'd13; o_unsupported = 1'b1; n_unsupported_fault = 1'b1; // 无Folding的Width或未知Channel请求不虚构回复
end else begin // 无Folding的Width或未知Channel请求不虚构回复
flag_rx_local_width = n_local_busy && !n_local_word[8]; calc_rx_local_target = n_local_word[19:16]; // 接收处理前保存本地宽度所有权与NACK失败目标
if (flag_rx_known && !flag_rx_channel) begin // 支持的Width线字先于回复策略更新能力与Priority
if (i_rx_word[15] && !n_soft_lock) begin n_soft_lock = 1'b1; o_lockout_notify = 1'b1; end // 真实Width线字优先级置位触发软锁通知
n_peer_ready = i_rx_word[28]; // 记录对端最近Width字的TxReady能力
end // 记录对端最近Width字的TxReady能力
if (flag_rx_known && i_rx_word[23:20] == 4'd4) begin // Channel同时请求禁止Pending；Width默认NACK回显当前或已发请求目标
if (flag_rx_channel) begin // Channel同时请求禁止Pending；Width默认NACK回显当前或已发请求目标
flag_repeated = (n_channel_online[i_rx_word[18]] == i_rx_word[19]); // Channel同时请求禁止Pending；Width默认NACK回显当前或已发请求目标
calc_reply = {3'd0,1'b0,i_rx_word[19:16],4'd6,i_rx_word[19:16],1'b0,6'd0,3'd4,4'd8,2'd0}; // Channel同时请求禁止Pending；Width默认NACK回显当前或已发请求目标
if (!(n_local_busy && n_local_word[8]) && !flag_repeated && i_rx_word[19] && !i_channel_ready[i_rx_word[18]]) begin calc_reply[23:20] = 4'd8; calc_reply[19:16] = 4'd0; end // Channel同时请求禁止Pending；Width默认NACK回显当前或已发请求目标
end else begin // Channel同时请求禁止Pending；Width默认NACK回显当前或已发请求目标
calc_reply = {3'd0,(C_TX_READY_SUPPORT != 0),i_rx_word[19:16],4'd7,(flag_rx_local_width ? n_local_word[19:16] : n_width),(flag_rx_local_width && n_local_word[15]),6'd0,3'd0,4'd8,2'd0}; // Channel同时请求禁止Pending；Width默认NACK回显当前或已发请求目标
if (((i_rx_word[19:16] == 4'd0 && C_ALLOWED_PL_MASK == 3) || (i_rx_word[19:16] == 4'd1 && C_ALLOWED_PL_MASK[0]) || (i_rx_word[19:16] == 4'd9 && C_ALLOWED_PL_MASK[1])) && ((i_rx_word[19:16] == 4'd0) != (n_width == 4'd0)) && !(i_rx_word[19:16] == 4'd0 && (i_rx_word[15] || n_soft_lock))) begin // 宽度合法性和软锁先于冲突胜者选择
flag_winner_valid = 1'b1; // 宽度合法性和软锁先于冲突胜者选择
if (flag_rx_local_width) begin // 宽度合法性和软锁先于冲突胜者选择
if (n_local_word[19:16] == i_rx_word[19:16]) calc_winner = n_local_word[19:16]; // 相同目标不变，PL0优于PL1，紧急取窄，普通取宽
else if (n_local_word[19:16] != 4'd0 && i_rx_word[19:16] != 4'd0) calc_winner = 4'd1; // 相同目标不变，PL0优于PL1，紧急取窄，普通取宽
else if (n_local_word[15] && i_rx_word[15]) calc_winner = (n_local_word[19:16] == 4'd0) ? i_rx_word[19:16] : n_local_word[19:16]; // 相同目标不变，PL0优于PL1，紧急取窄，普通取宽
else if (n_local_word[15]) calc_winner = n_local_word[19:16]; // 相同目标不变，PL0优于PL1，紧急取窄，普通取宽
else if (i_rx_word[15]) calc_winner = i_rx_word[19:16]; // 相同目标不变，PL0优于PL1，紧急取窄，普通取宽
else calc_winner = 4'd0; // 相同目标不变，PL0优于PL1，紧急取窄，普通取宽
calc_reply[23:20] = (calc_winner == wire_rx_target) ? 4'd6 : 4'd7; // 相同目标不变，PL0优于PL1，紧急取窄，普通取宽
calc_reply[19:16] = calc_winner; // 相同目标不变，PL0优于PL1，紧急取窄，普通取宽
end else begin // 只有Accelerator可对普通恢复最大宽度Pending，并承担后续重启
calc_winner = i_rx_word[19:16]; calc_reply[23:20] = 4'd6; calc_reply[19:16] = i_rx_word[19:16]; // 只有Accelerator可对普通恢复最大宽度Pending，并承担后续重启
if ((C_ROLE_SWITCH == 0) && !i_width_ready && !i_rx_word[15] && (i_rx_word[19:16] == 4'd0 || C_ALLOWED_PL_MASK != 3)) begin calc_reply[23:20] = 4'd8; calc_reply[19:16] = 4'd0; end // 只有Accelerator可对普通恢复最大宽度Pending，并承担后续重启
end // 只有Accelerator可对普通恢复最大宽度Pending，并承担后续重启
end // 只有Accelerator可对普通恢复最大宽度Pending，并承担后续重启
end // 只有Accelerator可对普通恢复最大宽度Pending，并承担后续重启
end // 只有Accelerator可对普通恢复最大宽度Pending，并承担后续重启
if (!flag_rx_known) o_rx_status = 4'd6; // 新请求不得覆盖旧对端槽或提前重启责任，合法回复策略在接收沿冻结
else if (i_rx_word[23:20] == 4'd4) begin // 新请求不得覆盖旧对端槽或提前重启责任，合法回复策略在接收沿冻结
if (n_remote_busy) o_rx_status = 4'd7; // 新请求不得覆盖旧对端槽或提前重启责任，合法回复策略在接收沿冻结
else if (n_owed[flag_rx_channel] || (n_local_busy && n_local_restart && n_local_word[8] == flag_rx_channel)) o_rx_status = 4'd8; // 新请求不得覆盖旧对端槽或提前重启责任，合法回复策略在接收沿冻结
else if ((calc_reply[23:20] != 4'd6 && calc_reply[23:20] != 4'd7 && calc_reply[23:20] != 4'd8) || (calc_reply[23:20] == 4'd8 && n_local_busy && n_local_word[8] == flag_rx_channel)) o_rx_status = 4'd11; // 新请求不得覆盖旧对端槽或提前重启责任，合法回复策略在接收沿冻结
else begin // 新请求不得覆盖旧对端槽或提前重启责任，合法回复策略在接收沿冻结
o_rx_status = 4'd1; n_remote_busy = 1'b1; n_remote_word = wire_rx_canonical; n_remote_reply = calc_reply; n_remote_sent = 1'b0; n_remote_pending = n_waiting[flag_rx_channel]; n_remote_missed = 1'b0; n_response_age = {C_RESPONSE_BITS{1'b0}}; // 新请求不得覆盖旧对端槽或提前重启责任，合法回复策略在接收沿冻结
if (n_count == 2'd0) begin n_word0 = calc_reply; n_purpose0 = 2'd1; n_count = 2'd1; end // 新发送严格追加于旧队首之后，合法所有权限制容量为二
else if (n_count == 2'd1) begin n_word1 = calc_reply; n_purpose1 = 2'd1; n_count = 2'd2; end // 新发送严格追加于旧队首之后，合法所有权限制容量为二
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新发送严格追加于旧队首之后，合法所有权限制容量为二
end // 结束请求接纳
end // 结束请求接纳
else if (n_local_busy && n_local_phase == 2'd1 && n_local_word[8] == flag_rx_channel && i_rx_word[27:24] == n_local_word[19:16]) begin // 合法响应先匹配本地等待阶段及原目标回显
if (i_rx_word[23:20] == 4'd8 && n_remote_busy && n_remote_word[8] == flag_rx_channel) o_rx_status = 4'd9; // 合法响应先匹配本地等待阶段及原目标回显
else if (i_rx_word[23:20] == 4'd6) begin // 合法响应先匹配本地等待阶段及原目标回显
o_rx_status = 4'd2; n_local_phase = 2'd2; // 合法响应先匹配本地等待阶段及原目标回显
if (n_count == 2'd0) begin n_word0 = {3'd0,n_local_word[28],i_rx_word[19:16],4'd6,n_local_word[19:0]}; n_purpose0 = 2'd2; n_count = 2'd1; end // 新发送严格追加于旧队首之后，合法所有权限制容量为二
else if (n_count == 2'd1) begin n_word1 = {3'd0,n_local_word[28],i_rx_word[19:16],4'd6,n_local_word[19:0]}; n_purpose1 = 2'd2; n_count = 2'd2; end // 新发送严格追加于旧队首之后，合法所有权限制容量为二
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新发送严格追加于旧队首之后，合法所有权限制容量为二
end else if (i_rx_word[23:20] == 4'd7) begin // NACK结束失败本地交换
o_rx_status = 4'd3; // NACK结束失败本地交换
o_local_done = 1'b1; o_local_done_channel = n_local_word[8]; o_local_done_target = n_local_word[19:16]; o_local_success = 1'b0; // 完成事件携带被释放交换原目标
n_local_busy = 1'b0; n_local_word = 32'd0; n_local_phase = 2'd0; n_local_restart = 1'b0; // 仅完成或合法Pending释放本地交换
end else begin // Pending转为等待该消息类型对端重启
o_rx_status = 4'd4; o_pending_received = 1'b1; n_waiting[flag_rx_channel] = 1'b1; // Pending转为等待该消息类型对端重启
n_local_busy = 1'b0; n_local_word = 32'd0; n_local_phase = 2'd0; n_local_restart = 1'b0; // 仅完成或合法Pending释放本地交换
end // 结束本地响应处理
end // 结束本地响应处理
else if (i_rx_word[23:20] == 4'd6 && n_remote_busy && n_remote_sent && n_remote_reply[23:20] == 4'd6 && n_remote_word[8] == flag_rx_channel && i_rx_word[19:16] == n_remote_word[19:16] && i_rx_word[27:24] == n_remote_reply[19:16]) begin // 对端确认必须匹配已实际发送ACK的目标和回显
o_rx_status = 4'd5; // 对端确认必须匹配已实际发送ACK的目标和回显
o_remote_done = 1'b1; o_remote_done_channel = n_remote_word[8]; o_remote_done_target = n_remote_word[19:16]; o_remote_success = 1'b1; // 完成事件携带被释放交换原目标
if (n_remote_pending) n_waiting[n_remote_word[8]] = 1'b0; // 完成对端重启才解除等待标志
n_remote_busy = 1'b0; n_remote_word = 32'd0; n_remote_reply = 32'd0; n_remote_sent = 1'b0; n_remote_pending = 1'b0; n_remote_missed = 1'b0; n_response_age = {C_RESPONSE_BITS{1'b0}}; // 对端结束后清除旧交换元数据
end else o_rx_status = 4'd10; // 未匹配响应仅诊断而不破坏旧交换
if (o_rx_status >= 4'd7) begin o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 未匹配响应仅诊断而不破坏旧交换
if (flag_rx_known) begin // 已定义且已支持的消息按参考执行语义同步
if (o_rx_status == 4'd1 && flag_repeated) begin o_repeat_error = 1'b1; o_protocol_error = 1'b1; n_repeat_fault = 1'b1; end // 仅真正接纳的请求记录语义诊断或建立有效宽度轮次
if (o_rx_status == 4'd1 && !flag_rx_channel && flag_winner_valid) begin // 仅真正接纳的请求记录语义诊断或建立有效宽度轮次
n_retry_valid = 1'b0; n_retry_target = 4'd0; // 仅真正接纳的请求记录语义诊断或建立有效宽度轮次
if (!n_round_valid) begin // 仅真正接纳的请求记录语义诊断或建立有效宽度轮次
n_round_valid = 1'b1; n_round_target = calc_winner; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 新本地宽度请求建立独立ACK对轮次
end // 接收ACK必须先经共享层目标和阶段匹配
n_round_target = calc_winner; n_round_remote = (calc_reply[23:20] == 4'd6); n_round_conflict = flag_rx_local_width && (calc_rx_local_target != i_rx_word[19:16]); // 接收ACK必须先经共享层目标和阶段匹配
end // 接收ACK必须先经共享层目标和阶段匹配
if (!flag_rx_channel) begin // 接收ACK必须先经共享层目标和阶段匹配
if (o_rx_status == 4'd2 || o_rx_status == 4'd5) begin // 接收ACK必须先经共享层目标和阶段匹配
if (n_round_valid) begin // 仅当前宽度轮次累计实际发送或匹配接收ACK
n_round_received = 1'b1; // 仅当前宽度轮次累计实际发送或匹配接收ACK
if (n_round_sent && n_round_received && !n_round_applied) begin // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
n_event_valid = 1'b1; n_event_old = n_width; n_event_new = n_round_target; // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
if (n_round_target == 4'd0) begin n_event_action = 2'd3; n_event_pl = (n_width == 4'd1); end // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
else begin n_event_action = n_round_remote ? 2'd1 : 2'd2; n_event_pl = (n_round_target == 4'd1); end // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
n_width = n_round_target; n_round_applied = 1'b1; // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
end // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
end // 实际ACK对首次满足才登记逻辑宽度和后续协议PL动作
end else if (o_rx_status == 4'd3 && n_round_valid && n_round_conflict) begin n_retry_valid = 1'b1; n_retry_target = calc_rx_local_target; end // 只有已确认冲突的NACK建立重试目标阻塞
end // 只有已确认冲突的NACK建立重试目标阻塞
if (o_local_done && o_local_success && o_local_done_channel && (o_local_done_target[2:0] == 3'd0 || o_local_done_target[2:0] == 3'd4)) n_channel_online[o_local_done_target[2]] = o_local_done_target[3]; // 仅成功完成改变Channel，无Width所有权时结束协商轮次
if (o_remote_done && o_remote_success && o_remote_done_channel && (o_remote_done_target[2:0] == 3'd0 || o_remote_done_target[2:0] == 3'd4)) n_channel_online[o_remote_done_target[2]] = o_remote_done_target[3]; // 仅成功完成改变Channel，无Width所有权时结束协商轮次
if (!(n_local_busy && !n_local_word[8]) && !(n_remote_busy && !n_remote_word[8])) begin // 仅成功完成改变Channel，无Width所有权时结束协商轮次
n_round_valid = 1'b0; n_round_target = 4'd0; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 仅成功完成改变Channel，无Width所有权时结束协商轮次
end // 仅成功完成改变Channel，无Width所有权时结束协商轮次
if (n_owed_first) begin // 支持的RX同步后：先检查最早建立的责任，未ready可检查另一kind
if (!n_local_busy && !n_remote_busy && n_owed[1] && n_owed_channel[19] && (n_owed_channel[18:16] == 3'd0 || n_owed_channel[18:16] == 3'd4) && !n_channel_online[n_owed_channel[18]] && i_channel_ready[n_owed_channel[18]] && !n_waiting[1]) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,1'b0,4'd0,4'd4,n_owed_channel[19:16],1'b0,6'd0,3'd4,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[1]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[1] = 1'b1; // 分别记录自动重启与显式本地接纳
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
if (!n_local_busy && !n_remote_busy && n_owed[0] && i_width_ready && (C_ROLE_SWITCH == 0) && (C_FOLDING != 0) && !n_waiting[0] && ((n_owed_width[19:16] == 4'd0 && C_ALLOWED_PL_MASK == 3) || (n_owed_width[19:16] == 4'd1 && C_ALLOWED_PL_MASK[0]) || (n_owed_width[19:16] == 4'd9 && C_ALLOWED_PL_MASK[1])) && ((n_owed_width[19:16] == 4'd0) != (n_width == 4'd0)) && !(n_owed_width[19:16] == 4'd0 && (n_owed_width[15] || n_soft_lock)) && !(n_retry_valid && n_retry_target == n_owed_width[19:16])) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,(C_TX_READY_SUPPORT != 0),4'd0,4'd4,n_owed_width[19:16],n_owed_width[15],6'd0,3'd0,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[0]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[0] = 1'b1; // 分别记录自动重启与显式本地接纳
n_round_valid = 1'b1; n_round_target = n_owed_width[19:16]; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 新本地宽度请求建立独立ACK对轮次
n_retry_valid = 1'b0; n_retry_target = 4'd0; // 新宽度请求接纳后清除旧重试阻塞
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
end else begin // 相反义务建立顺序
if (!n_local_busy && !n_remote_busy && n_owed[0] && i_width_ready && (C_ROLE_SWITCH == 0) && (C_FOLDING != 0) && !n_waiting[0] && ((n_owed_width[19:16] == 4'd0 && C_ALLOWED_PL_MASK == 3) || (n_owed_width[19:16] == 4'd1 && C_ALLOWED_PL_MASK[0]) || (n_owed_width[19:16] == 4'd9 && C_ALLOWED_PL_MASK[1])) && ((n_owed_width[19:16] == 4'd0) != (n_width == 4'd0)) && !(n_owed_width[19:16] == 4'd0 && (n_owed_width[15] || n_soft_lock)) && !(n_retry_valid && n_retry_target == n_owed_width[19:16])) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,(C_TX_READY_SUPPORT != 0),4'd0,4'd4,n_owed_width[19:16],n_owed_width[15],6'd0,3'd0,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[0]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[0] = 1'b1; // 分别记录自动重启与显式本地接纳
n_round_valid = 1'b1; n_round_target = n_owed_width[19:16]; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 新本地宽度请求建立独立ACK对轮次
n_retry_valid = 1'b0; n_retry_target = 4'd0; // 新宽度请求接纳后清除旧重试阻塞
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
if (!n_local_busy && !n_remote_busy && n_owed[1] && n_owed_channel[19] && (n_owed_channel[18:16] == 3'd0 || n_owed_channel[18:16] == 3'd4) && !n_channel_online[n_owed_channel[18]] && i_channel_ready[n_owed_channel[18]] && !n_waiting[1]) begin // 空闲共享类别才可履行对应原目标重启
n_local_busy = 1'b1; n_local_word = {3'd0,1'b0,4'd0,4'd4,n_owed_channel[19:16],1'b0,6'd0,3'd4,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[1]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_auto_restart[1] = 1'b1; // 分别记录自动重启与显式本地接纳
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束当前kind自动重启尝试
end // 结束按责任先后自动重启选择
end // 结束可靠接收和语义同步阶段
end // 结束可靠接收和语义同步阶段
end // 结束可靠接收和语义同步阶段
calc_owed_channel_target = n_owed_channel[19:16]; // 所有自动重启尝试结束后再按语义条件接纳显式请求
o_local_ready = !n_local_busy && !n_remote_busy && !n_waiting[i_request_channel]; // 所有自动重启尝试结束后再按语义条件接纳显式请求
if (i_request_channel) o_local_ready = o_local_ready && !i_request_priority && ((i_request_target[2:0] == 3'd0 || i_request_target[2:0] == 3'd4) && (i_request_target[3] != n_channel_online[i_request_target[2]]) && (!i_request_target[3] || i_channel_ready[i_request_target[2]]) && (!n_owed[1] || i_request_target == calc_owed_channel_target)); // 所有自动重启尝试结束后再按语义条件接纳显式请求
else o_local_ready = o_local_ready && (C_ROLE_SWITCH == 0) && (C_FOLDING != 0) && (((i_request_target == 4'd0 && C_ALLOWED_PL_MASK == 3) || (i_request_target == 4'd1 && C_ALLOWED_PL_MASK[0]) || (i_request_target == 4'd9 && C_ALLOWED_PL_MASK[1])) && ((i_request_target == 4'd0) != (n_width == 4'd0)) && !(i_request_target == 4'd0 && (i_request_priority || n_soft_lock))) && !(n_retry_valid && n_retry_target == i_request_target); // 所有自动重启尝试结束后再按语义条件接纳显式请求
if (i_request_valid && o_local_ready) begin // 所有自动重启尝试结束后再按语义条件接纳显式请求
if (i_request_channel) begin // 所有自动重启尝试结束后再按语义条件接纳显式请求
n_local_busy = 1'b1; n_local_word = {3'd0,1'b0,4'd0,4'd4,i_request_target,1'b0,6'd0,3'd4,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[1]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_local_accept = 1'b1; // 分别记录自动重启与显式本地接纳
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end else begin // 显式Width请求已经过角色宽度软锁与重试检查
n_local_busy = 1'b1; n_local_word = {3'd0,(C_TX_READY_SUPPORT != 0),4'd0,4'd4,i_request_target,i_request_priority,6'd0,3'd0,4'd8,2'd0}; n_local_phase = 2'd0; n_local_restart = n_owed[0]; // 接纳时冻结合法语义目标；排队不清除Pending计时
o_local_accept = 1'b1; // 分别记录自动重启与显式本地接纳
n_round_valid = 1'b1; n_round_target = i_request_target; n_round_remote = 1'b0; n_round_conflict = 1'b0; n_round_sent = 1'b0; n_round_received = 1'b0; n_round_applied = 1'b0; // 新本地宽度请求建立独立ACK对轮次
n_retry_valid = 1'b0; n_retry_target = 4'd0; // 新宽度请求接纳后清除旧重试阻塞
if (n_count == 2'd0) begin n_word0 = n_local_word; n_purpose0 = 2'd0; n_count = 2'd1; end // 新字追加到当前有序队列尾部
else if (n_count == 2'd1) begin n_word1 = n_local_word; n_purpose1 = 2'd0; n_count = 2'd2; end // 新字追加到当前有序队列尾部
else begin o_rx_status = 4'd12; o_protocol_error = 1'b1; n_protocol_fault = 1'b1; end // 新字追加到当前有序队列尾部
end // 结束显式本地语义接纳
end // 结束显式本地语义接纳
if (n_owed == 2'd0 || n_owed == 2'd1) n_owed_first = 1'b0; // 单kind责任规范化先后标志，结束完整组合下一态
else if (n_owed == 2'd2) n_owed_first = 1'b1; // 单kind责任规范化先后标志，结束完整组合下一态
end // 单kind责任规范化先后标志，结束完整组合下一态
end // 单kind责任规范化先后标志，结束完整组合下一态
always @(posedge i_clk) begin // 本地交换所有权：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_local_busy <= 1'b0; // 本地交换所有权：单寄存器原始上升沿同步低有效复位
else r_local_busy <= n_local_busy; // 本地交换所有权：单寄存器原始上升沿同步低有效复位
end // 本地交换所有权：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 本地规范化请求字：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_local_word <= 32'd0; // 本地规范化请求字：单寄存器原始上升沿同步低有效复位
else r_local_word <= n_local_word; // 本地规范化请求字：单寄存器原始上升沿同步低有效复位
end // 本地规范化请求字：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 本地排队等待回复与确认待发送阶段：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_local_phase <= 2'd0; // 本地排队等待回复与确认待发送阶段：单寄存器原始上升沿同步低有效复位
else r_local_phase <= n_local_phase; // 本地排队等待回复与确认待发送阶段：单寄存器原始上升沿同步低有效复位
end // 本地排队等待回复与确认待发送阶段：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 本地请求来自Pending重启责任：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_local_restart <= 1'b0; // 本地请求来自Pending重启责任：单寄存器原始上升沿同步低有效复位
else r_local_restart <= n_local_restart; // 本地请求来自Pending重启责任：单寄存器原始上升沿同步低有效复位
end // 本地请求来自Pending重启责任：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 对端交换所有权：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_remote_busy <= 1'b0; // 对端交换所有权：单寄存器原始上升沿同步低有效复位
else r_remote_busy <= n_remote_busy; // 对端交换所有权：单寄存器原始上升沿同步低有效复位
end // 对端交换所有权：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 对端规范化原请求字：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_remote_word <= 32'd0; // 对端规范化原请求字：单寄存器原始上升沿同步低有效复位
else r_remote_word <= n_remote_word; // 对端规范化原请求字：单寄存器原始上升沿同步低有效复位
end // 对端规范化原请求字：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 接收当沿冻结的回复字：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_remote_reply <= 32'd0; // 接收当沿冻结的回复字：单寄存器原始上升沿同步低有效复位
else r_remote_reply <= n_remote_reply; // 接收当沿冻结的回复字：单寄存器原始上升沿同步低有效复位
end // 接收当沿冻结的回复字：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 回复已实际发送：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_remote_sent <= 1'b0; // 回复已实际发送：单寄存器原始上升沿同步低有效复位
else r_remote_sent <= n_remote_sent; // 回复已实际发送：单寄存器原始上升沿同步低有效复位
end // 回复已实际发送：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 对端请求来自等待其重启：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_remote_pending <= 1'b0; // 对端请求来自等待其重启：单寄存器原始上升沿同步低有效复位
else r_remote_pending <= n_remote_pending; // 对端请求来自等待其重启：单寄存器原始上升沿同步低有效复位
end // 对端请求来自等待其重启：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 本次对端请求已报告回复超时：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_remote_missed <= 1'b0; // 本次对端请求已报告回复超时：单寄存器原始上升沿同步低有效复位
else r_remote_missed <= n_remote_missed; // 本次对端请求已报告回复超时：单寄存器原始上升沿同步低有效复位
end // 本次对端请求已报告回复超时：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 未发送回复的饱和年龄：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_response_age <= {C_RESPONSE_BITS{1'b0}}; // 未发送回复的饱和年龄：单寄存器原始上升沿同步低有效复位
else r_response_age <= n_response_age; // 未发送回复的饱和年龄：单寄存器原始上升沿同步低有效复位
end // 未发送回复的饱和年龄：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 两种消息等待对端重启：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_waiting <= 2'd0; // 两种消息等待对端重启：单寄存器原始上升沿同步低有效复位
else r_waiting <= n_waiting; // 两种消息等待对端重启：单寄存器原始上升沿同步低有效复位
end // 两种消息等待对端重启：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 两种消息欠本地重启：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_owed <= 2'd0; // 两种消息欠本地重启：单寄存器原始上升沿同步低有效复位
else r_owed <= n_owed; // 两种消息欠本地重启：单寄存器原始上升沿同步低有效复位
end // 两种消息欠本地重启：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // Width原始重启目标：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_owed_width <= 32'd0; // Width原始重启目标：单寄存器原始上升沿同步低有效复位
else r_owed_width <= n_owed_width; // Width原始重启目标：单寄存器原始上升沿同步低有效复位
end // Width原始重启目标：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // Channel原始重启目标：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_owed_channel <= 32'd0; // Channel原始重启目标：单寄存器原始上升沿同步低有效复位
else r_owed_channel <= n_owed_channel; // Channel原始重启目标：单寄存器原始上升沿同步低有效复位
end // Channel原始重启目标：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // Width重启饱和年龄：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_width_age <= {C_RESTART_BITS{1'b0}}; // Width重启饱和年龄：单寄存器原始上升沿同步低有效复位
else r_width_age <= n_width_age; // Width重启饱和年龄：单寄存器原始上升沿同步低有效复位
end // Width重启饱和年龄：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // Channel重启饱和年龄：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_channel_age <= {C_RESTART_BITS{1'b0}}; // Channel重启饱和年龄：单寄存器原始上升沿同步低有效复位
else r_channel_age <= n_channel_age; // Channel重启饱和年龄：单寄存器原始上升沿同步低有效复位
end // Channel重启饱和年龄：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 各重启责任已报告超时：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_restart_missed <= 2'd0; // 各重启责任已报告超时：单寄存器原始上升沿同步低有效复位
else r_restart_missed <= n_restart_missed; // 各重启责任已报告超时：单寄存器原始上升沿同步低有效复位
end // 各重启责任已报告超时：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 有序发送队列占用：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_count <= 2'd0; // 有序发送队列占用：单寄存器原始上升沿同步低有效复位
else r_count <= n_count; // 有序发送队列占用：单寄存器原始上升沿同步低有效复位
end // 有序发送队列占用：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 发送队首字：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_word0 <= 32'd0; // 发送队首字：单寄存器原始上升沿同步低有效复位
else r_word0 <= n_word0; // 发送队首字：单寄存器原始上升沿同步低有效复位
end // 发送队首字：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 发送队尾字：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_word1 <= 32'd0; // 发送队尾字：单寄存器原始上升沿同步低有效复位
else r_word1 <= n_word1; // 发送队尾字：单寄存器原始上升沿同步低有效复位
end // 发送队尾字：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 队首用途：请求回复确认：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_purpose0 <= 2'd0; // 队首用途：请求回复确认：单寄存器原始上升沿同步低有效复位
else r_purpose0 <= n_purpose0; // 队首用途：请求回复确认：单寄存器原始上升沿同步低有效复位
end // 队首用途：请求回复确认：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 队尾用途：请求回复确认：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_purpose1 <= 2'd0; // 队尾用途：请求回复确认：单寄存器原始上升沿同步低有效复位
else r_purpose1 <= n_purpose1; // 队尾用途：请求回复确认：单寄存器原始上升沿同步低有效复位
end // 队尾用途：请求回复确认：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 回复超时粘滞状态：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_response_fault <= 1'b0; // 回复超时粘滞状态：单寄存器原始上升沿同步低有效复位
else r_response_fault <= n_response_fault; // 回复超时粘滞状态：单寄存器原始上升沿同步低有效复位
end // 回复超时粘滞状态：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 重启超时粘滞状态：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_restart_fault <= 1'b0; // 重启超时粘滞状态：单寄存器原始上升沿同步低有效复位
else r_restart_fault <= n_restart_fault; // 重启超时粘滞状态：单寄存器原始上升沿同步低有效复位
end // 重启超时粘滞状态：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // 协议或输入违约粘滞状态：单寄存器原始上升沿同步低有效复位
if (!i_rstn) r_protocol_fault <= 1'b0; // 协议或输入违约粘滞状态：单寄存器原始上升沿同步低有效复位
else r_protocol_fault <= n_protocol_fault; // 协议或输入违约粘滞状态：单寄存器原始上升沿同步低有效复位
end // 协议或输入违约粘滞状态：单寄存器原始上升沿同步低有效复位
always @(posedge i_clk) begin // Channel0及Channel4在线状态：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_channel_online <= 2'd0; // Channel0及Channel4在线状态：单状态寄存器原始正沿同步低有效复位
else r_channel_online <= n_channel_online; // Channel0及Channel4在线状态：单状态寄存器原始正沿同步低有效复位
end // Channel0及Channel4在线状态：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 当前协商逻辑宽度：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_width <= C_INITIAL_WIDTH[3:0]; // 当前协商逻辑宽度：单状态寄存器原始正沿同步低有效复位
else r_width <= n_width; // 当前协商逻辑宽度：单状态寄存器原始正沿同步低有效复位
end // 当前协商逻辑宽度：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 硬件软锁：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_soft_lock <= 1'd0; // 硬件软锁：单状态寄存器原始正沿同步低有效复位
else r_soft_lock <= n_soft_lock; // 硬件软锁：单状态寄存器原始正沿同步低有效复位
end // 硬件软锁：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 对端最近报告的TxReady能力：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_peer_ready <= 1'd0; // 对端最近报告的TxReady能力：单状态寄存器原始正沿同步低有效复位
else r_peer_ready <= n_peer_ready; // 对端最近报告的TxReady能力：单状态寄存器原始正沿同步低有效复位
end // 对端最近报告的TxReady能力：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 冲突失败重试目标有效：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_retry_valid <= 1'd0; // 冲突失败重试目标有效：单状态寄存器原始正沿同步低有效复位
else r_retry_valid <= n_retry_valid; // 冲突失败重试目标有效：单状态寄存器原始正沿同步低有效复位
end // 冲突失败重试目标有效：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 冲突失败重试目标：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_retry_target <= 4'd0; // 冲突失败重试目标：单状态寄存器原始正沿同步低有效复位
else r_retry_target <= n_retry_target; // 冲突失败重试目标：单状态寄存器原始正沿同步低有效复位
end // 冲突失败重试目标：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 宽度协商轮次有效：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_round_valid <= 1'd0; // 宽度协商轮次有效：单状态寄存器原始正沿同步低有效复位
else r_round_valid <= n_round_valid; // 宽度协商轮次有效：单状态寄存器原始正沿同步低有效复位
end // 宽度协商轮次有效：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 当前轮次胜出宽度：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_round_target <= 4'd0; // 当前轮次胜出宽度：单状态寄存器原始正沿同步低有效复位
else r_round_target <= n_round_target; // 当前轮次胜出宽度：单状态寄存器原始正沿同步低有效复位
end // 当前轮次胜出宽度：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 当前轮次接纳了对端请求：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_round_remote <= 1'd0; // 当前轮次接纳了对端请求：单状态寄存器原始正沿同步低有效复位
else r_round_remote <= n_round_remote; // 当前轮次接纳了对端请求：单状态寄存器原始正沿同步低有效复位
end // 当前轮次接纳了对端请求：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 当前轮次不同目标冲突：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_round_conflict <= 1'd0; // 当前轮次不同目标冲突：单状态寄存器原始正沿同步低有效复位
else r_round_conflict <= n_round_conflict; // 当前轮次不同目标冲突：单状态寄存器原始正沿同步低有效复位
end // 当前轮次不同目标冲突：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 当前轮次实际发送过ACK：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_round_sent <= 1'd0; // 当前轮次实际发送过ACK：单状态寄存器原始正沿同步低有效复位
else r_round_sent <= n_round_sent; // 当前轮次实际发送过ACK：单状态寄存器原始正沿同步低有效复位
end // 当前轮次实际发送过ACK：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 当前轮次匹配收到ACK：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_round_received <= 1'd0; // 当前轮次匹配收到ACK：单状态寄存器原始正沿同步低有效复位
else r_round_received <= n_round_received; // 当前轮次匹配收到ACK：单状态寄存器原始正沿同步低有效复位
end // 当前轮次匹配收到ACK：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 当前轮次已经应用宽度动作：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_round_applied <= 1'd0; // 当前轮次已经应用宽度动作：单状态寄存器原始正沿同步低有效复位
else r_round_applied <= n_round_applied; // 当前轮次已经应用宽度动作：单状态寄存器原始正沿同步低有效复位
end // 当前轮次已经应用宽度动作：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 寄存宽度动作有效：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_event_valid <= 1'd0; // 寄存宽度动作有效：单状态寄存器原始正沿同步低有效复位
else r_event_valid <= n_event_valid; // 寄存宽度动作有效：单状态寄存器原始正沿同步低有效复位
end // 寄存宽度动作有效：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 动作前协商宽度：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_event_old <= 4'd0; // 动作前协商宽度：单状态寄存器原始正沿同步低有效复位
else r_event_old <= n_event_old; // 动作前协商宽度：单状态寄存器原始正沿同步低有效复位
end // 动作前协商宽度：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 动作后协商宽度：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_event_new <= 4'd0; // 动作后协商宽度：单状态寄存器原始正沿同步低有效复位
else r_event_new <= n_event_new; // 动作后协商宽度：单状态寄存器原始正沿同步低有效复位
end // 动作后协商宽度：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 掉电或Fault动作类别：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_event_action <= 2'd0; // 掉电或Fault动作类别：单状态寄存器原始正沿同步低有效复位
else r_event_action <= n_event_action; // 掉电或Fault动作类别：单状态寄存器原始正沿同步低有效复位
end // 掉电或Fault动作类别：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 物理动作的协议PL编号：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_event_pl <= 1'd0; // 物理动作的协议PL编号：单状态寄存器原始正沿同步低有效复位
else r_event_pl <= n_event_pl; // 物理动作的协议PL编号：单状态寄存器原始正沿同步低有效复位
end // 物理动作的协议PL编号：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 当前Channel状态请求粘滞诊断：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_repeat_fault <= 1'd0; // 当前Channel状态请求粘滞诊断：单状态寄存器原始正沿同步低有效复位
else r_repeat_fault <= n_repeat_fault; // 当前Channel状态请求粘滞诊断：单状态寄存器原始正沿同步低有效复位
end // 当前Channel状态请求粘滞诊断：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 未支持语义消息粘滞诊断：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_unsupported_fault <= 1'd0; // 未支持语义消息粘滞诊断：单状态寄存器原始正沿同步低有效复位
else r_unsupported_fault <= n_unsupported_fault; // 未支持语义消息粘滞诊断：单状态寄存器原始正沿同步低有效复位
end // 未支持语义消息粘滞诊断：单状态寄存器原始正沿同步低有效复位
always @(posedge i_clk) begin // 两种Pending义务中先建立者的kind：单状态寄存器原始正沿同步低有效复位
if (!i_rstn) r_owed_first <= 1'd0; // 两种Pending义务中先建立者的kind：单状态寄存器原始正沿同步低有效复位
else r_owed_first <= n_owed_first; // 两种Pending义务中先建立者的kind：单状态寄存器原始正沿同步低有效复位
end // 两种Pending义务中先建立者的kind：单状态寄存器原始正沿同步低有效复位
endmodule // 结束共享握手和Channel/Width语义控制器模块
