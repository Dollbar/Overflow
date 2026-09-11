`timescale 1ps/1ps // 实际发送、接收与复位控制共享单一原始时钟。
module dl_uart_port #( // UART 端口模块连接真实 SRAM 收发路径、选择性取消与复位握手。
    parameter integer C_TX_DEPTH = 128, // 完整发送容量包括尚未发出的源内暂存。
    parameter integer C_RX_DEPTH = 128, // 推荐接收容量，额外深度属于研究配置。
    parameter integer C_CLOCK_PERIOD_PS = 640, // 原始时钟周期用于计算完整十毫秒超时。
    parameter integer C_RESPONSE_DEPTH = 4 // 本地远端请求响应队列深度，满溢锁存诊断。
) ( // 内部同步接口接收可靠有序消息字并提供实际 DWORD 服务事件。
    input wire i_clk, // 唯一原始采样时钟
    input wire i_rstn, // 同步低有效全局复位
    input wire i_channel4_enabled, // 已协商通道资格
    input wire i_uart_start_allowed, // 同域新消息启动许可；已发送头的UART消息仍须完整排空。
    input wire i_fw_tx_valid, // 固件发送字有效
    input wire [31:0] i_fw_tx_word, // 固件原始发送负载
    input wire i_fw_rx_ready, // 固件读取当前接收字
    input wire i_rx_word_valid, // 可靠有序消息字有效
    input wire [31:0] i_rx_word, // 上游可靠性处理后的消息字
    input wire i_segment_available, // 真实消息DWORD发送机会
    input wire i_local_request, // 请求本地流复位
    input wire i_local_all, // 本地请求的全部流范围
    input wire [5:0] i_normal_pending, // 普通来源一至六的外部待发资格
    input wire [191:0] i_normal_words, // 六个普通消息的完整队首字，来源一在最低字
    input wire i_credit_pending, // 外部信用调度器稳定队首有效
    input wire [31:0] i_credit_word, // 外部已编码信用通告字
    output wire o_tx_storage_ready, // transmit 模型公开观察 fw_ready
    output wire [12:0] o_tx_buffered_words, // transmit 模型公开观察 buffered_words
    output wire [11:0] o_tx_counter, // transmit 模型公开观察 tx_counter
    output wire o_tx_busy, // transmit 模型公开观察 uart_busy
    output wire [5:0] o_tx_reserved, // transmit 模型公开观察 uart_reserved
    output wire [5:0] o_tx_staged, // transmit 模型公开观察 uart_staged
    output wire [11:0] o_tx_latest_fc, // transmit 模型公开观察 latest_fc
    output wire o_tx_valid, // transmit 模型公开观察 valid
    output wire [31:0] o_tx_word, // transmit 模型公开观察 word
    output wire [3:0] o_tx_source, // transmit 模型公开观察 source
    output wire [5:0] o_tx_word_index, // transmit 模型公开观察 word_index
    output wire o_tx_last, // transmit 模型公开观察 last
    output wire [9:0] o_tx_other_take, // transmit 模型公开观察 other_take
    output wire [9:0] o_tx_other_done, // transmit 模型公开观察 other_done
    output wire o_tx_message_done, // transmit 模型公开观察 uart_message_done
    output wire o_tx_locked, // transmit 模型公开观察 uart_locked
    output wire o_tx_error, // transmit 模型公开观察 error
    output wire [5:0] o_tx_uart_index, // transmit 模型公开观察 uart_word_index
    output wire o_fw_rx_valid, // receive 模型公开观察 fw_valid
    output wire [31:0] o_fw_rx_word, // receive 模型公开观察 fw_word
    output wire [11:0] o_rx_fill, // receive 模型公开观察 rx_fill
    output wire o_rx_initialized, // receive 模型公开观察 initialized
    output wire [11:0] o_rx_counter, // receive 模型公开观察 rx_counter
    output wire o_rx_credit_available, // receive 模型公开观察 credit_available
    output wire [5:0] o_rx_remaining, // receive 模型公开观察 remaining
    output wire o_rx_dropping, // receive 模型公开观察 dropping
    output wire o_rx_header, // receive 模型公开观察 header
    output wire o_rx_payload_write, // receive 模型公开观察 payload_write
    output wire o_rx_payload_discard, // receive 模型公开观察 payload_discard
    output wire o_rx_done, // receive 模型公开观察 done
    output wire o_rx_credit_valid, // receive 模型公开观察 credit_valid
    output wire [11:0] o_rx_credit_value, // receive 模型公开观察 credit_value
    output wire o_rx_reset_request, // receive 模型公开观察 reset_request
    output wire o_rx_request_all, // receive 模型公开观察 request_all
    output wire o_rx_reset_response, // receive 模型公开观察 reset_response
    output wire o_rx_response_all, // receive 模型公开观察 response_all
    output wire [2:0] o_rx_response_status, // receive 模型公开观察 response_status
    output wire o_rx_other_valid, // receive 模型公开观察 other_valid
    output wire [31:0] o_rx_other_word, // receive 模型公开观察 other_word
    output wire o_rx_error, // receive 模型公开观察 error
    output wire o_local_ready, // control 模型公开观察 local_ready
    output wire o_stream_reset, // control 模型公开观察 stream_reset
    output wire o_block_messages, // control 模型公开观察 block_messages
    output wire o_reset_tx_pending, // control 模型公开观察 tx_pending
    output wire [31:0] o_reset_tx_word, // control 模型公开观察 tx_word
    output wire [1:0] o_reset_tx_kind, // control 模型公开观察 tx_kind
    output wire o_reset_waiting, // control 模型公开观察 waiting
    output wire [5:0] o_reset_noops_left, // control 模型公开观察 noops_left
    output wire [4:0] o_reset_response_count, // control 模型公开观察 response_count
    output wire o_local_start, // control 模型公开观察 local_start
    output wire o_local_done, // control 模型公开观察 local_done
    output wire o_retry, // control 模型公开观察 retry
    output wire o_reply_done, // control 模型公开观察 reply_done
    output wire o_reset_fault, // control 模型公开观察 fault
    output wire o_reset_error, // control 模型公开观察 error
    output wire o_fw_tx_ready, // 端口组合握手或诊断 fw_tx_ready
    output wire o_fw_tx_accepted, // 端口组合握手或诊断 fw_tx_accepted
    output wire o_fw_tx_discard, // 端口组合握手或诊断 fw_tx_discard
    output wire [5:0] o_normal_take, // 端口组合握手或诊断 normal_take
    output wire o_credit_take, // 端口组合握手或诊断 credit_take
    output wire o_credit_cancel, // 端口组合握手或诊断 credit_cancel
    output wire o_error // 端口组合握手或诊断 error
); // 结束完整端口边界，未定义 PHY 或信用通告节流策略。
    wire [9:0] other_pending; // 外部十来源按零至六及八至十顺序排列。
    wire [319:0] other_words; // 普通队首、信用队首及复位维护字的固定映射。
    wire reset_take; // 只有实际仲裁提交才能推进四十字和超时控制。
    wire [5:0] normal_pending; // 本地阻断期保留上游队首而暂时撤销服务资格。
    wire credit_pending; // 旧信用通告在流复位及未初始化期间不可发出。
    assign normal_pending = o_block_messages ? 6'd0 : i_normal_pending; // 等待成功响应期间普通消息重新参与仲裁。
    assign o_credit_cancel = !i_rstn || o_stream_reset || !o_rx_initialized; // 要求外部信用调度器丢弃旧快照而不虚构新的通告节奏。
    assign credit_pending = i_credit_pending && o_rx_credit_available && !o_credit_cancel && !o_block_messages; // 信用只在正常运行资格下参与实际服务。
    assign other_pending = {o_reset_tx_pending && (o_reset_tx_kind == 2'd3), o_reset_tx_pending && (o_reset_tx_kind == 2'd2), credit_pending, normal_pending, o_reset_tx_pending && (o_reset_tx_kind == 2'd1)}; // NoOp 仅由维护控制产生，UART transport 固定由内部来源七提供。
    assign other_words = {o_reset_tx_word, o_reset_tx_word, i_credit_word, i_normal_words, 32'd0}; // 普通消息完整保留外部队首，最低字是规范 NoOp 零值。
    assign reset_take = o_reset_tx_pending && (((o_reset_tx_kind == 2'd1) && o_tx_other_take[0]) || ((o_reset_tx_kind == 2'd2) && o_tx_other_take[8]) || ((o_reset_tx_kind == 2'd3) && o_tx_other_take[9])); // 维护控制只接收对应当前类型的实际源提交事件。
    assign o_fw_tx_ready = i_rstn && (o_stream_reset || o_tx_storage_ready); // 流复位期间仍接受固件写入并按规范丢弃。
    assign o_fw_tx_accepted = i_fw_tx_valid && o_fw_tx_ready; // 父接口接纳事件包含正常保存和流复位丢弃。
    assign o_fw_tx_discard = o_fw_tx_accepted && o_stream_reset; // 丢弃不会形成实际 FIFO 数据所有权。
    assign o_normal_take = o_tx_other_take[6:1]; // 普通来源仅在真实仲裁消费时通知外部队首退休。
    assign o_credit_take = o_tx_other_take[7]; // 信用队首的消费只来自实际发送机会。
    assign o_error = o_tx_error || o_rx_error || o_reset_error; // 汇总诊断不反向参与本沿服务资格，避免组合环。
    dl_uart_tx_path #(.C_TX_DEPTH(C_TX_DEPTH)) Tx_Inst ( // 实例化实际SRAM 发送、消息暂存及仲裁路径。
        .i_clk(i_clk), // 直连 i_clk，使用同一沿前状态建立联合作用。
        .i_rstn(i_rstn), // 直连 i_rstn，使用同一沿前状态建立联合作用。
        .i_stream_reset(o_stream_reset), // 直连 i_stream_reset，使用同一沿前状态建立联合作用。
        .i_channel4_enabled(i_channel4_enabled), // 直连 i_channel4_enabled，使用同一沿前状态建立联合作用。
        .i_uart_start_allowed(i_uart_start_allowed), // 逐层传递新头许可，不替代协商后的通道资格。
        .i_fw_valid(i_fw_tx_valid), // 直连 i_fw_valid，使用同一沿前状态建立联合作用。
        .i_fw_word(i_fw_tx_word), // 直连 i_fw_word，使用同一沿前状态建立联合作用。
        .i_credit_valid(o_rx_credit_valid), // 直连 i_credit_valid，使用同一沿前状态建立联合作用。
        .i_credit_value(o_rx_credit_value), // 直连 i_credit_value，使用同一沿前状态建立联合作用。
        .i_segment_available(i_segment_available), // 直连 i_segment_available，使用同一沿前状态建立联合作用。
        .i_other_pending(other_pending), // 直连 i_other_pending，使用同一沿前状态建立联合作用。
        .i_other_words(other_words), // 直连 i_other_words，使用同一沿前状态建立联合作用。
        .o_fw_ready(o_tx_storage_ready), // 直连 o_fw_ready，使用同一沿前状态建立联合作用。
        .o_buffered_words(o_tx_buffered_words), // 直连 o_buffered_words，使用同一沿前状态建立联合作用。
        .o_tx_counter(o_tx_counter), // 直连 o_tx_counter，使用同一沿前状态建立联合作用。
        .o_uart_busy(o_tx_busy), // 直连 o_uart_busy，使用同一沿前状态建立联合作用。
        .o_uart_reserved(o_tx_reserved), // 直连 o_uart_reserved，使用同一沿前状态建立联合作用。
        .o_uart_staged(o_tx_staged), // 直连 o_uart_staged，使用同一沿前状态建立联合作用。
        .o_latest_fc(o_tx_latest_fc), // 直连 o_latest_fc，使用同一沿前状态建立联合作用。
        .o_valid(o_tx_valid), // 直连 o_valid，使用同一沿前状态建立联合作用。
        .o_word(o_tx_word), // 直连 o_word，使用同一沿前状态建立联合作用。
        .o_source(o_tx_source), // 直连 o_source，使用同一沿前状态建立联合作用。
        .o_word_index(o_tx_word_index), // 直连 o_word_index，使用同一沿前状态建立联合作用。
        .o_last(o_tx_last), // 直连 o_last，使用同一沿前状态建立联合作用。
        .o_other_take(o_tx_other_take), // 直连 o_other_take，使用同一沿前状态建立联合作用。
        .o_other_done(o_tx_other_done), // 直连 o_other_done，使用同一沿前状态建立联合作用。
        .o_uart_message_done(o_tx_message_done), // 直连 o_uart_message_done，使用同一沿前状态建立联合作用。
        .o_uart_locked(o_tx_locked), // 直连 o_uart_locked，使用同一沿前状态建立联合作用。
        .o_error(o_tx_error), // 直连 o_error，使用同一沿前状态建立联合作用。
        .o_uart_word_index(o_tx_uart_index) // 直连 o_uart_word_index，使用同一沿前状态建立联合作用。
    ); // 结束实际transmit子模块连接。
    dl_uart_rx_path #(.C_RX_DEPTH(C_RX_DEPTH)) Rx_Inst ( // 实例化实际SRAM 接收与跨流复位长度跟踪。
        .i_clk(i_clk), // 直连 i_clk，使用同一沿前状态建立联合作用。
        .i_rstn(i_rstn), // 直连 i_rstn，使用同一沿前状态建立联合作用。
        .i_stream_reset(o_stream_reset), // 直连 i_stream_reset，使用同一沿前状态建立联合作用。
        .i_channel4_enabled(i_channel4_enabled), // 直连 i_channel4_enabled，使用同一沿前状态建立联合作用。
        .i_word_valid(i_rx_word_valid), // 直连 i_word_valid，使用同一沿前状态建立联合作用。
        .i_word(i_rx_word), // 直连 i_word，使用同一沿前状态建立联合作用。
        .i_fw_ready(i_fw_rx_ready), // 直连 i_fw_ready，使用同一沿前状态建立联合作用。
        .o_fw_valid(o_fw_rx_valid), // 直连 o_fw_valid，使用同一沿前状态建立联合作用。
        .o_fw_word(o_fw_rx_word), // 直连 o_fw_word，使用同一沿前状态建立联合作用。
        .o_rx_fill(o_rx_fill), // 直连 o_rx_fill，使用同一沿前状态建立联合作用。
        .o_initialized(o_rx_initialized), // 直连 o_initialized，使用同一沿前状态建立联合作用。
        .o_rx_counter(o_rx_counter), // 直连 o_rx_counter，使用同一沿前状态建立联合作用。
        .o_credit_available(o_rx_credit_available), // 直连 o_credit_available，使用同一沿前状态建立联合作用。
        .o_remaining(o_rx_remaining), // 直连 o_remaining，使用同一沿前状态建立联合作用。
        .o_dropping(o_rx_dropping), // 直连 o_dropping，使用同一沿前状态建立联合作用。
        .o_header(o_rx_header), // 直连 o_header，使用同一沿前状态建立联合作用。
        .o_payload_write(o_rx_payload_write), // 直连 o_payload_write，使用同一沿前状态建立联合作用。
        .o_payload_discard(o_rx_payload_discard), // 直连 o_payload_discard，使用同一沿前状态建立联合作用。
        .o_done(o_rx_done), // 直连 o_done，使用同一沿前状态建立联合作用。
        .o_credit_valid(o_rx_credit_valid), // 直连 o_credit_valid，使用同一沿前状态建立联合作用。
        .o_credit_value(o_rx_credit_value), // 直连 o_credit_value，使用同一沿前状态建立联合作用。
        .o_reset_request(o_rx_reset_request), // 直连 o_reset_request，使用同一沿前状态建立联合作用。
        .o_request_all(o_rx_request_all), // 直连 o_request_all，使用同一沿前状态建立联合作用。
        .o_reset_response(o_rx_reset_response), // 直连 o_reset_response，使用同一沿前状态建立联合作用。
        .o_response_all(o_rx_response_all), // 直连 o_response_all，使用同一沿前状态建立联合作用。
        .o_response_status(o_rx_response_status), // 直连 o_response_status，使用同一沿前状态建立联合作用。
        .o_other_valid(o_rx_other_valid), // 直连 o_other_valid，使用同一沿前状态建立联合作用。
        .o_other_word(o_rx_other_word), // 直连 o_other_word，使用同一沿前状态建立联合作用。
        .o_error(o_rx_error) // 直连 o_error，使用同一沿前状态建立联合作用。
    ); // 结束实际receive子模块连接。
    dl_uart_reset_control #(.C_CLOCK_PERIOD_PS(C_CLOCK_PERIOD_PS), .C_RESPONSE_DEPTH(C_RESPONSE_DEPTH)) Reset_Inst ( // 实例化实际本地和远端复位义务控制。
        .i_clk(i_clk), // 直连 i_clk，使用同一沿前状态建立联合作用。
        .i_rstn(i_rstn), // 直连 i_rstn，使用同一沿前状态建立联合作用。
        .i_local_request(i_local_request), // 直连 i_local_request，使用同一沿前状态建立联合作用。
        .i_local_all(i_local_all), // 直连 i_local_all，使用同一沿前状态建立联合作用。
        .i_rx_request(o_rx_reset_request), // 直连 i_rx_request，使用同一沿前状态建立联合作用。
        .i_rx_request_all(o_rx_request_all), // 直连 i_rx_request_all，使用同一沿前状态建立联合作用。
        .i_rx_response(o_rx_reset_response), // 直连 i_rx_response，使用同一沿前状态建立联合作用。
        .i_rx_response_status(o_rx_response_status), // 直连 i_rx_response_status，使用同一沿前状态建立联合作用。
        .i_tx_take(reset_take), // 直连 i_tx_take，使用同一沿前状态建立联合作用。
        .o_local_ready(o_local_ready), // 直连 o_local_ready，使用同一沿前状态建立联合作用。
        .o_stream_reset(o_stream_reset), // 直连 o_stream_reset，使用同一沿前状态建立联合作用。
        .o_block_messages(o_block_messages), // 直连 o_block_messages，使用同一沿前状态建立联合作用。
        .o_tx_pending(o_reset_tx_pending), // 直连 o_tx_pending，使用同一沿前状态建立联合作用。
        .o_tx_word(o_reset_tx_word), // 直连 o_tx_word，使用同一沿前状态建立联合作用。
        .o_tx_kind(o_reset_tx_kind), // 直连 o_tx_kind，使用同一沿前状态建立联合作用。
        .o_waiting(o_reset_waiting), // 直连 o_waiting，使用同一沿前状态建立联合作用。
        .o_noops_left(o_reset_noops_left), // 直连 o_noops_left，使用同一沿前状态建立联合作用。
        .o_response_count(o_reset_response_count), // 直连 o_response_count，使用同一沿前状态建立联合作用。
        .o_local_start(o_local_start), // 直连 o_local_start，使用同一沿前状态建立联合作用。
        .o_local_done(o_local_done), // 直连 o_local_done，使用同一沿前状态建立联合作用。
        .o_retry(o_retry), // 直连 o_retry，使用同一沿前状态建立联合作用。
        .o_reply_done(o_reply_done), // 直连 o_reply_done，使用同一沿前状态建立联合作用。
        .o_fault(o_reset_fault), // 直连 o_fault，使用同一沿前状态建立联合作用。
        .o_error(o_reset_error) // 直连 o_error，使用同一沿前状态建立联合作用。
    ); // 结束实际control子模块连接。
endmodule // 结束 UART 端口复位、真实存储和消息服务集成。
