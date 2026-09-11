`timescale 1ps/1ps // 全部子模块和双SRAM在同一原始时钟域运行。
module dl_message_port #( // 消息端口模块连接Basic生命周期、UART收发和实际仲裁。
    parameter integer C_TX_DEPTH = 128, // 总发送容量包括尚未发出的UART暂存字。
    parameter integer C_RX_DEPTH = 128, // 实际接收SRAM逻辑容量。
    parameter integer C_CLOCK_PERIOD_PS = 640, // 真实原始时钟周期用于Basic和UART截止计时。
    parameter integer C_RESPONSE_DEPTH = 4 // 远端UART复位义务的有限响应队列容量。
) ( // 原生内部同步接口接受可靠有序消息字和实际发送机会。
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
    input wire i_credit_pending, // 外部信用调度器稳定队首有效
    input wire [31:0] i_credit_word, // 外部已编码信用通告字
    output wire o_uart_tx_storage_ready, // transmit 模型公开观察 fw_ready
    output wire [12:0] o_uart_tx_buffered_words, // transmit 模型公开观察 buffered_words
    output wire [11:0] o_uart_tx_counter, // transmit 模型公开观察 tx_counter
    output wire o_uart_tx_busy, // transmit 模型公开观察 uart_busy
    output wire [5:0] o_uart_tx_reserved, // transmit 模型公开观察 uart_reserved
    output wire [5:0] o_uart_tx_staged, // transmit 模型公开观察 uart_staged
    output wire [11:0] o_uart_tx_latest_fc, // transmit 模型公开观察 latest_fc
    output wire o_uart_tx_valid, // transmit 模型公开观察 valid
    output wire [31:0] o_uart_tx_word, // transmit 模型公开观察 word
    output wire [3:0] o_uart_tx_source, // transmit 模型公开观察 source
    output wire [5:0] o_uart_tx_word_index, // transmit 模型公开观察 word_index
    output wire o_uart_tx_last, // transmit 模型公开观察 last
    output wire [9:0] o_uart_tx_other_take, // transmit 模型公开观察 other_take
    output wire [9:0] o_uart_tx_other_done, // transmit 模型公开观察 other_done
    output wire o_uart_tx_message_done, // transmit 模型公开观察 uart_message_done
    output wire o_uart_tx_locked, // transmit 模型公开观察 uart_locked
    output wire o_uart_tx_error, // transmit 模型公开观察 error
    output wire [5:0] o_uart_tx_uart_index, // transmit 模型公开观察 uart_word_index
    output wire o_uart_fw_rx_valid, // receive 模型公开观察 fw_valid
    output wire [31:0] o_uart_fw_rx_word, // receive 模型公开观察 fw_word
    output wire [11:0] o_uart_rx_fill, // receive 模型公开观察 rx_fill
    output wire o_uart_rx_initialized, // receive 模型公开观察 initialized
    output wire [11:0] o_uart_rx_counter, // receive 模型公开观察 rx_counter
    output wire o_uart_rx_credit_available, // receive 模型公开观察 credit_available
    output wire [5:0] o_uart_rx_remaining, // receive 模型公开观察 remaining
    output wire o_uart_rx_dropping, // receive 模型公开观察 dropping
    output wire o_uart_rx_header, // receive 模型公开观察 header
    output wire o_uart_rx_payload_write, // receive 模型公开观察 payload_write
    output wire o_uart_rx_payload_discard, // receive 模型公开观察 payload_discard
    output wire o_uart_rx_done, // receive 模型公开观察 done
    output wire o_uart_rx_credit_valid, // receive 模型公开观察 credit_valid
    output wire [11:0] o_uart_rx_credit_value, // receive 模型公开观察 credit_value
    output wire o_uart_rx_reset_request, // receive 模型公开观察 reset_request
    output wire o_uart_rx_request_all, // receive 模型公开观察 request_all
    output wire o_uart_rx_reset_response, // receive 模型公开观察 reset_response
    output wire o_uart_rx_response_all, // receive 模型公开观察 response_all
    output wire [2:0] o_uart_rx_response_status, // receive 模型公开观察 response_status
    output wire o_uart_rx_other_valid, // receive 模型公开观察 other_valid
    output wire [31:0] o_uart_rx_other_word, // receive 模型公开观察 other_word
    output wire o_uart_rx_error, // receive 模型公开观察 error
    output wire o_uart_local_ready, // control 模型公开观察 local_ready
    output wire o_uart_stream_reset, // control 模型公开观察 stream_reset
    output wire o_uart_block_messages, // control 模型公开观察 block_messages
    output wire o_uart_reset_tx_pending, // control 模型公开观察 tx_pending
    output wire [31:0] o_uart_reset_tx_word, // control 模型公开观察 tx_word
    output wire [1:0] o_uart_reset_tx_kind, // control 模型公开观察 tx_kind
    output wire o_uart_reset_waiting, // control 模型公开观察 waiting
    output wire [5:0] o_uart_reset_noops_left, // control 模型公开观察 noops_left
    output wire [4:0] o_uart_reset_response_count, // control 模型公开观察 response_count
    output wire o_uart_local_start, // control 模型公开观察 local_start
    output wire o_uart_local_done, // control 模型公开观察 local_done
    output wire o_uart_retry, // control 模型公开观察 retry
    output wire o_uart_reply_done, // control 模型公开观察 reply_done
    output wire o_uart_reset_fault, // control 模型公开观察 fault
    output wire o_uart_reset_error, // control 模型公开观察 error
    output wire o_uart_fw_tx_ready, // 端口组合握手或诊断 fw_tx_ready
    output wire o_uart_fw_tx_accepted, // 端口组合握手或诊断 fw_tx_accepted
    output wire o_uart_fw_tx_discard, // 端口组合握手或诊断 fw_tx_discard
    output wire [5:0] o_uart_normal_take, // 端口组合握手或诊断 normal_take
    output wire o_uart_credit_take, // 端口组合握手或诊断 credit_take
    output wire o_uart_credit_cancel, // 端口组合握手或诊断 credit_cancel
    output wire o_uart_error, // 端口组合握手或诊断 error
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
    output wire o_basic_local_ready, // 独立参考观察 local_ready
    output wire o_basic_local_pending, // 独立参考观察 local_pending
    output wire o_basic_local_waiting, // 独立参考观察 local_waiting
    output wire o_basic_remote_pending, // 独立参考观察 remote_pending
    output wire [3:0] o_basic_source_pending, // 独立参考观察 source_pending
    output wire [127:0] o_basic_source_words, // 独立参考观察 source_words
    output wire o_basic_local_start, // 独立参考观察 local_start
    output wire o_basic_local_commit, // 独立参考观察 local_commit
    output wire o_basic_local_done, // 独立参考观察 local_done
    output wire o_basic_reply_done, // 独立参考观察 reply_done
    output wire o_basic_rx_request, // 独立参考观察 rx_request
    output wire o_basic_rx_noop, // 独立参考观察 rx_noop
    output wire o_basic_rx_unhandled, // 独立参考观察 rx_unhandled
    output wire o_basic_rx_unsupported, // 独立参考观察 rx_unsupported
    output wire o_basic_rx_unmatched_ack, // 独立参考观察 rx_unmatched_ack
    output wire o_basic_rx_overlap, // 独立参考观察 rx_overlap
    output wire o_basic_peer_rate_valid, // 独立参考观察 peer_rate_valid
    output wire [15:0] o_basic_peer_rate, // 独立参考观察 peer_rate
    output wire o_basic_peer_device_valid, // 独立参考观察 peer_device_valid
    output wire [1:0] o_basic_peer_device_type, // 独立参考观察 peer_device_type
    output wire [9:0] o_basic_peer_device_id, // 独立参考观察 peer_device_id
    output wire o_basic_peer_port_valid, // 独立参考观察 peer_port_valid
    output wire [11:0] o_basic_peer_port, // 独立参考观察 peer_port
    output wire o_basic_peer_rate_update, // 独立参考观察 peer_rate_update
    output wire o_basic_deadline_miss, // 独立参考观察 deadline_miss
    output wire o_basic_deadline_fault, // 独立参考观察 deadline_fault
    output wire o_basic_protocol_fault, // 独立参考观察 protocol_fault
    output wire o_basic_error, // 独立参考观察 error
    input wire [1:0] i_control_pending, // 两个外部Control队首有效位。
    input wire [63:0] i_control_words, // Control来源五在低DWORD、来源六在高DWORD。
    output wire [1:0] o_control_take, // 实际提交的两个Control来源消费位。
    output wire o_unhandled_valid, // 经UART边界分发后Basic仍未处理的消息字有效。
    output wire [31:0] o_unhandled_word, // 仅有效时转交上层的原始消息字。
    output wire o_error // 当前Basic与UART错误汇总，不反馈发送资格。
); // 结束完整输入输出边界。
    wire [5:0] normal_pending; // 四种Basic及两种外部Control队首的固定来源资格。
    wire [191:0] normal_words; // 六个完整DWORD按原始仲裁器来源顺序排列。
    assign normal_pending = {i_control_pending, o_basic_source_pending}; // Basic仅提供已具备发送资格的旧队首。
    assign normal_words = {i_control_words, o_basic_source_words}; // 低四字依次为TxReady、Rate、Device及Port。
    assign o_control_take = o_uart_normal_take[5:4]; // Control消费只来自真实发送器的普通来源提交。
    assign o_unhandled_valid = o_uart_rx_other_valid && o_basic_rx_unhandled; // 只转交UART已解帧且Basic未处理的实际消息字。
    assign o_unhandled_word = o_unhandled_valid ? o_uart_rx_other_word : 32'd0; // 无有效转交时公开字保持零。
    assign o_error = o_uart_error || o_basic_error; // 诊断汇总不反向改变本沿仲裁资格。
    dl_uart_port #( // UART实例保留真实SRAM、完整消息占用和流复位处理。
        .C_TX_DEPTH(C_TX_DEPTH), .C_RX_DEPTH(C_RX_DEPTH), // 传递实际逻辑容量。
        .C_CLOCK_PERIOD_PS(C_CLOCK_PERIOD_PS), .C_RESPONSE_DEPTH(C_RESPONSE_DEPTH) // 超时和响应队列使用同一明确配置。
    ) Uart_Inst ( // 完整UART输入输出均连接而不抽象存储返回。
        .i_clk(i_clk), // 连接UART原生信号 i_clk。
        .i_rstn(i_rstn), // 连接UART原生信号 i_rstn。
        .i_channel4_enabled(i_channel4_enabled), // 连接UART原生信号 i_channel4_enabled。
        .i_uart_start_allowed(i_uart_start_allowed), // 逐层传递新头许可，不替代协商后的通道资格。
        .i_fw_tx_valid(i_fw_tx_valid), // 连接UART原生信号 i_fw_tx_valid。
        .i_fw_tx_word(i_fw_tx_word), // 连接UART原生信号 i_fw_tx_word。
        .i_fw_rx_ready(i_fw_rx_ready), // 连接UART原生信号 i_fw_rx_ready。
        .i_rx_word_valid(i_rx_word_valid), // 连接UART原生信号 i_rx_word_valid。
        .i_rx_word(i_rx_word), // 连接UART原生信号 i_rx_word。
        .i_segment_available(i_segment_available), // 连接UART原生信号 i_segment_available。
        .i_local_request(i_local_request), // 连接UART原生信号 i_local_request。
        .i_local_all(i_local_all), // 连接UART原生信号 i_local_all。
        .i_normal_pending(normal_pending), // 连接UART原生信号 i_normal_pending。
        .i_normal_words(normal_words), // 连接UART原生信号 i_normal_words。
        .i_credit_pending(i_credit_pending), // 连接UART原生信号 i_credit_pending。
        .i_credit_word(i_credit_word), // 连接UART原生信号 i_credit_word。
        .o_tx_storage_ready(o_uart_tx_storage_ready), // 连接UART原生信号 o_tx_storage_ready。
        .o_tx_buffered_words(o_uart_tx_buffered_words), // 连接UART原生信号 o_tx_buffered_words。
        .o_tx_counter(o_uart_tx_counter), // 连接UART原生信号 o_tx_counter。
        .o_tx_busy(o_uart_tx_busy), // 连接UART原生信号 o_tx_busy。
        .o_tx_reserved(o_uart_tx_reserved), // 连接UART原生信号 o_tx_reserved。
        .o_tx_staged(o_uart_tx_staged), // 连接UART原生信号 o_tx_staged。
        .o_tx_latest_fc(o_uart_tx_latest_fc), // 连接UART原生信号 o_tx_latest_fc。
        .o_tx_valid(o_uart_tx_valid), // 连接UART原生信号 o_tx_valid。
        .o_tx_word(o_uart_tx_word), // 连接UART原生信号 o_tx_word。
        .o_tx_source(o_uart_tx_source), // 连接UART原生信号 o_tx_source。
        .o_tx_word_index(o_uart_tx_word_index), // 连接UART原生信号 o_tx_word_index。
        .o_tx_last(o_uart_tx_last), // 连接UART原生信号 o_tx_last。
        .o_tx_other_take(o_uart_tx_other_take), // 连接UART原生信号 o_tx_other_take。
        .o_tx_other_done(o_uart_tx_other_done), // 连接UART原生信号 o_tx_other_done。
        .o_tx_message_done(o_uart_tx_message_done), // 连接UART原生信号 o_tx_message_done。
        .o_tx_locked(o_uart_tx_locked), // 连接UART原生信号 o_tx_locked。
        .o_tx_error(o_uart_tx_error), // 连接UART原生信号 o_tx_error。
        .o_tx_uart_index(o_uart_tx_uart_index), // 连接UART原生信号 o_tx_uart_index。
        .o_fw_rx_valid(o_uart_fw_rx_valid), // 连接UART原生信号 o_fw_rx_valid。
        .o_fw_rx_word(o_uart_fw_rx_word), // 连接UART原生信号 o_fw_rx_word。
        .o_rx_fill(o_uart_rx_fill), // 连接UART原生信号 o_rx_fill。
        .o_rx_initialized(o_uart_rx_initialized), // 连接UART原生信号 o_rx_initialized。
        .o_rx_counter(o_uart_rx_counter), // 连接UART原生信号 o_rx_counter。
        .o_rx_credit_available(o_uart_rx_credit_available), // 连接UART原生信号 o_rx_credit_available。
        .o_rx_remaining(o_uart_rx_remaining), // 连接UART原生信号 o_rx_remaining。
        .o_rx_dropping(o_uart_rx_dropping), // 连接UART原生信号 o_rx_dropping。
        .o_rx_header(o_uart_rx_header), // 连接UART原生信号 o_rx_header。
        .o_rx_payload_write(o_uart_rx_payload_write), // 连接UART原生信号 o_rx_payload_write。
        .o_rx_payload_discard(o_uart_rx_payload_discard), // 连接UART原生信号 o_rx_payload_discard。
        .o_rx_done(o_uart_rx_done), // 连接UART原生信号 o_rx_done。
        .o_rx_credit_valid(o_uart_rx_credit_valid), // 连接UART原生信号 o_rx_credit_valid。
        .o_rx_credit_value(o_uart_rx_credit_value), // 连接UART原生信号 o_rx_credit_value。
        .o_rx_reset_request(o_uart_rx_reset_request), // 连接UART原生信号 o_rx_reset_request。
        .o_rx_request_all(o_uart_rx_request_all), // 连接UART原生信号 o_rx_request_all。
        .o_rx_reset_response(o_uart_rx_reset_response), // 连接UART原生信号 o_rx_reset_response。
        .o_rx_response_all(o_uart_rx_response_all), // 连接UART原生信号 o_rx_response_all。
        .o_rx_response_status(o_uart_rx_response_status), // 连接UART原生信号 o_rx_response_status。
        .o_rx_other_valid(o_uart_rx_other_valid), // 连接UART原生信号 o_rx_other_valid。
        .o_rx_other_word(o_uart_rx_other_word), // 连接UART原生信号 o_rx_other_word。
        .o_rx_error(o_uart_rx_error), // 连接UART原生信号 o_rx_error。
        .o_local_ready(o_uart_local_ready), // 连接UART原生信号 o_local_ready。
        .o_stream_reset(o_uart_stream_reset), // 连接UART原生信号 o_stream_reset。
        .o_block_messages(o_uart_block_messages), // 连接UART原生信号 o_block_messages。
        .o_reset_tx_pending(o_uart_reset_tx_pending), // 连接UART原生信号 o_reset_tx_pending。
        .o_reset_tx_word(o_uart_reset_tx_word), // 连接UART原生信号 o_reset_tx_word。
        .o_reset_tx_kind(o_uart_reset_tx_kind), // 连接UART原生信号 o_reset_tx_kind。
        .o_reset_waiting(o_uart_reset_waiting), // 连接UART原生信号 o_reset_waiting。
        .o_reset_noops_left(o_uart_reset_noops_left), // 连接UART原生信号 o_reset_noops_left。
        .o_reset_response_count(o_uart_reset_response_count), // 连接UART原生信号 o_reset_response_count。
        .o_local_start(o_uart_local_start), // 连接UART原生信号 o_local_start。
        .o_local_done(o_uart_local_done), // 连接UART原生信号 o_local_done。
        .o_retry(o_uart_retry), // 连接UART原生信号 o_retry。
        .o_reply_done(o_uart_reply_done), // 连接UART原生信号 o_reply_done。
        .o_reset_fault(o_uart_reset_fault), // 连接UART原生信号 o_reset_fault。
        .o_reset_error(o_uart_reset_error), // 连接UART原生信号 o_reset_error。
        .o_fw_tx_ready(o_uart_fw_tx_ready), // 连接UART原生信号 o_fw_tx_ready。
        .o_fw_tx_accepted(o_uart_fw_tx_accepted), // 连接UART原生信号 o_fw_tx_accepted。
        .o_fw_tx_discard(o_uart_fw_tx_discard), // 连接UART原生信号 o_fw_tx_discard。
        .o_normal_take(o_uart_normal_take), // 连接UART原生信号 o_normal_take。
        .o_credit_take(o_uart_credit_take), // 连接UART原生信号 o_credit_take。
        .o_credit_cancel(o_uart_credit_cancel), // 连接UART原生信号 o_credit_cancel。
        .o_error(o_uart_error) // 连接UART原生信号 o_error。
    ); // 结束实际UART端口实例。
    dl_basic_message_control #(.C_CLOCK_PERIOD_PS(C_CLOCK_PERIOD_PS)) Basic_Inst ( // Basic实例仅用全局复位，UART流复位不能取消其独立义务。
        .i_clk(i_clk), // 连接Basic原生信号 i_clk。
        .i_rstn(i_rstn), // 只有全局复位清空Basic所有权和故障。
        .i_local_valid(i_basic_local_valid), // 连接Basic原生信号 i_local_valid。
        .i_local_kind(i_basic_local_kind), // 连接Basic原生信号 i_local_kind。
        .i_local_rate(i_basic_local_rate), // 连接Basic原生信号 i_local_rate。
        .i_device_valid(i_basic_device_valid), // 连接Basic原生信号 i_device_valid。
        .i_device_id(i_basic_device_id), // 连接Basic原生信号 i_device_id。
        .i_device_type(i_basic_device_type), // 连接Basic原生信号 i_device_type。
        .i_port_valid(i_basic_port_valid), // 连接Basic原生信号 i_port_valid。
        .i_port(i_basic_port), // 连接Basic原生信号 i_port。
        .i_folding(i_basic_folding), // 连接Basic原生信号 i_folding。
        .i_tx_ready_advertised(i_basic_tx_ready_advertised), // 连接Basic原生信号 i_tx_ready_advertised。
        .i_symbols_valid(i_basic_symbols_valid), // 连接Basic原生信号 i_symbols_valid。
        .i_tx_limit_valid(i_basic_tx_limit_valid), // 连接Basic原生信号 i_tx_limit_valid。
        .i_tx_limit(i_basic_tx_limit), // 连接Basic原生信号 i_tx_limit。
        .i_rx_valid(o_uart_rx_other_valid), // 只有UART原始framing确认的其它消息边界进入Basic。
        .i_rx_word(o_uart_rx_other_word), // 保留已经解帧的完整消息字。
        .i_source_take(o_uart_normal_take[3:0]), // 四个Basic队首只在对应实际普通来源提交时退休。
        .o_local_ready(o_basic_local_ready), // 连接Basic原生信号 o_local_ready。
        .o_local_pending(o_basic_local_pending), // 连接Basic原生信号 o_local_pending。
        .o_local_waiting(o_basic_local_waiting), // 连接Basic原生信号 o_local_waiting。
        .o_remote_pending(o_basic_remote_pending), // 连接Basic原生信号 o_remote_pending。
        .o_source_pending(o_basic_source_pending), // 连接Basic原生信号 o_source_pending。
        .o_source_words(o_basic_source_words), // 连接Basic原生信号 o_source_words。
        .o_local_start(o_basic_local_start), // 连接Basic原生信号 o_local_start。
        .o_local_commit(o_basic_local_commit), // 连接Basic原生信号 o_local_commit。
        .o_local_done(o_basic_local_done), // 连接Basic原生信号 o_local_done。
        .o_reply_done(o_basic_reply_done), // 连接Basic原生信号 o_reply_done。
        .o_rx_request(o_basic_rx_request), // 连接Basic原生信号 o_rx_request。
        .o_rx_noop(o_basic_rx_noop), // 连接Basic原生信号 o_rx_noop。
        .o_rx_unhandled(o_basic_rx_unhandled), // 连接Basic原生信号 o_rx_unhandled。
        .o_rx_unsupported(o_basic_rx_unsupported), // 连接Basic原生信号 o_rx_unsupported。
        .o_rx_unmatched_ack(o_basic_rx_unmatched_ack), // 连接Basic原生信号 o_rx_unmatched_ack。
        .o_rx_overlap(o_basic_rx_overlap), // 连接Basic原生信号 o_rx_overlap。
        .o_peer_rate_valid(o_basic_peer_rate_valid), // 连接Basic原生信号 o_peer_rate_valid。
        .o_peer_rate(o_basic_peer_rate), // 连接Basic原生信号 o_peer_rate。
        .o_peer_device_valid(o_basic_peer_device_valid), // 连接Basic原生信号 o_peer_device_valid。
        .o_peer_device_type(o_basic_peer_device_type), // 连接Basic原生信号 o_peer_device_type。
        .o_peer_device_id(o_basic_peer_device_id), // 连接Basic原生信号 o_peer_device_id。
        .o_peer_port_valid(o_basic_peer_port_valid), // 连接Basic原生信号 o_peer_port_valid。
        .o_peer_port(o_basic_peer_port), // 连接Basic原生信号 o_peer_port。
        .o_peer_rate_update(o_basic_peer_rate_update), // 连接Basic原生信号 o_peer_rate_update。
        .o_deadline_miss(o_basic_deadline_miss), // 连接Basic原生信号 o_deadline_miss。
        .o_deadline_fault(o_basic_deadline_fault), // 连接Basic原生信号 o_deadline_fault。
        .o_protocol_fault(o_basic_protocol_fault), // 连接Basic原生信号 o_protocol_fault。
        .o_error(o_basic_error) // 连接Basic原生信号 o_error。
    ); // 结束Basic生命周期实例。
endmodule // 结束Basic与UART消息端口模块。
