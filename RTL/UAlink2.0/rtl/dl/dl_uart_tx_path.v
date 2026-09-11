// Stream0 UART 固件发送路径：复用实际 SRAM FIFO、完整消息暂存源及两级仲裁器。
// 范围：本地同步发送集成；外部提供已解码信用与其余消息资格，完整协议复位和信用更新节奏另行实现。
`timescale 1ps/1ps // 全部逻辑与两侧 SRAM 端口使用同一时钟域。
module dl_uart_tx_path #( // UART 实际存储发送路径模块，总容量包含源内未发送的暂存字。
    parameter integer C_TX_DEPTH = 128 // 标准默认容量一百二十八；一至四千零九十五为本地研究配置。
) ( // 固件与其他消息接口均为内部同步握手，不新增 UALink 线上字段。
    input wire i_clk, // SRAM 两端、FIFO、发送源及仲裁器的共同上升沿时钟。
    input wire i_rstn, // 同步低有效复位共同清除本地控制所有权。
    input wire i_stream_reset, // 同步清除本流数据与信用，并选择性撤销 UART 仲裁占用。
    input wire i_channel4_enabled, // 协商后的通道资格，合法关闭前必须排空已发送头的消息。
    input wire i_uart_start_allowed, // 同域新消息启动许可；已发送头的UART消息仍须完整排空。
    input wire i_fw_valid, // 固件提供一个待写 payload DWORD，阻塞时保持数据与有效性。
    input wire [31:0] i_fw_word, // 完整固件负载，不包含由发送源生成的消息头。
    input wire i_credit_valid, // 上游已完成 Stream0 资格检查的绝对信用更新事件。
    input wire [11:0] i_credit_value, // 已解码的模四千零九十六信用值。
    input wire i_segment_available, // 当前沿实际提供一个消息 DWORD 服务机会。
    input wire [9:0] i_other_pending, // 其余完整且具备发送资格的单字消息源，按零至六及八至十排列。
    input wire [319:0] i_other_words, // 低 DWORD 对应最低外部来源，未被消费前保持队首。
    output wire o_fw_ready, // 固件总占用尚未达到容量且 FIFO 能接纳时有效。
    output wire [12:0] o_buffered_words, // FIFO 全占用加发送源实际未发负载，不把内部暂存当额外容量。
    output wire [11:0] o_tx_counter, // 只有整条 UART 消息完成才增加 captured 负载长度。
    output wire o_uart_busy, // 已捕获一个 UART 消息预约或仍在发送该消息。
    output wire [5:0] o_uart_reserved, // 当前预约的完整负载长度，范围一至三十二。
    output wire [5:0] o_uart_staged, // 当前实际暂存且尚未发送的负载字数。
    output wire [11:0] o_latest_fc, // 发送源保存的最近有效绝对信用。
    output wire o_valid, // 当前沿实际发出一个消息 DWORD 的服务事件。
    output wire [31:0] o_word, // 实际消息头或由真实 SRAM 路径读出的负载。
    output wire [3:0] o_source, // 实际仲裁赢家的本地十一源索引。
    output wire [5:0] o_word_index, // 当前服务 DWORD 在完整消息中的索引，头为零。
    output wire o_last, // 当前服务事件结束整条选中消息。
    output wire [9:0] o_other_take, // 外部十来源逐源实际消费事件。
    output wire [9:0] o_other_done, // 外部十来源逐源消息完成事件。
    output wire o_uart_message_done, // 实际最后负载消费与 UART 信用提交的共同事件。
    output wire o_uart_locked, // 仲裁器已发送 UART 头并保留剩余消息所有权。
    output wire o_error, // 本地容量、来源、完成或索引违约诊断，不定义线上错误码。
    output wire [5:0] o_uart_word_index // 仲裁器期望的下一个 UART 字索引，空闲为零。
); // 结束 UART 实际存储发送模块接口。
    localparam integer C_COUNT_WIDTH = (C_TX_DEPTH < 2) ? 1 : (C_TX_DEPTH < 4) ? 2 : (C_TX_DEPTH < 8) ? 3 : (C_TX_DEPTH < 16) ? 4 : (C_TX_DEPTH < 32) ? 5 : (C_TX_DEPTH < 64) ? 6 : (C_TX_DEPTH < 128) ? 7 : (C_TX_DEPTH < 256) ? 8 : (C_TX_DEPTH < 512) ? 9 : (C_TX_DEPTH < 1024) ? 10 : (C_TX_DEPTH < 2048) ? 11 : 12; // 能表示零至完整容量的 FIFO 派生位宽。
    localparam [12:0] C_CAPACITY = C_TX_DEPTH[12:0]; // 使用足够位宽保留全部 FIFO 与暂存相加结果。
    wire [C_COUNT_WIDTH-1:0] fifo_count; // 包含 SRAM、在途读及两个输出缓存的实际 FIFO 占用。
    wire [11:0] fifo_fill; // 发送源接口要求的显式零扩展容量观察。
    wire [12:0] total_words; // 复位屏蔽之前的全部有效数据所有权总和。
    wire stream_rstn; // 数据路径同步复位独立于保留轮询历史的仲裁器。
    wire fifo_ready, fifo_valid, source_ready, source_pending; // 实际 FIFO 与完整消息源之间的握手资格。
    wire [31:0] fifo_word, source_word; // SRAM 真实输出字和源当前消息 DWORD。
    wire [5:0] source_count, source_index; // 发送源捕获的总长度和当前待消费索引。
    wire [10:0] source_take, message_done; // 实际十一源仲裁器逐源事件。
    wire flag_uart_eligible; // 新头受启动许可约束，已开始消息保留服务资格。
    wire source_error, arbiter_error, flag_room; // 独立组件诊断和全路径容量准入。
    assign flag_uart_eligible = source_pending && (i_uart_start_allowed || o_uart_locked); // 只门控UART仲裁资格，不改变预取、信用和锁定消息排空。
    assign stream_rstn = i_rstn && !i_stream_reset; // 同域流复位清空 FIFO 与源，原始时钟保持直连。
    assign fifo_fill = {{(12-C_COUNT_WIDTH){1'b0}}, fifo_count}; // 不截断 FIFO 全容量，也不假定深度为二次幂。
    assign total_words = {1'b0, fifo_fill}+{7'd0, o_uart_staged}; // 内部移入发送暂存不释放固件可见容量。
    assign flag_room = total_words < C_CAPACITY; // 禁止用本沿可能发生的发送提前借用空间。
    assign o_fw_ready = stream_rstn && fifo_ready && flag_room; // 接纳必须同时满足真实 FIFO 及全部未发字的容量限制。
    assign o_buffered_words = stream_rstn ? total_words : 13'd0; // 复位沿前公开占用立即屏蔽，内部控制仍同步清零。
    assign o_other_take = {source_take[10:8], source_take[6:0]}; // UART transport 的消费由内部源七独占。
    assign o_other_done = {message_done[10:8], message_done[6:0]}; // 保持外部十来源输入和完成输出相同顺序。
    assign o_error = stream_rstn && (source_error || arbiter_error || (total_words > C_CAPACITY) || (o_uart_message_done != message_done[7]) || (o_uart_locked && source_pending && (source_index != o_uart_word_index))); // 捕获容量、边界或索引的真实集成违约。
    generate // 非法研究配置在展开阶段明确失败。
        if ((C_TX_DEPTH < 1) || (C_TX_DEPTH > 4095)) begin : gen_invalid // 十二位信用接口限制可表达的本地容量范围。
            dl_uart_tx_path_parameters_invalid Invalid_Inst (); // 未定义的明确错误层次禁止非法配置产生网表。
        end // 结束容量合法性条件。
    endgenerate // 结束参数范围校验。
    upli_receive_storage #( // 复用实际同步 FIFO 及获授权的 SRAM 存储映射。
        .C_DEPTH(C_TX_DEPTH), .C_DATA_WIDTH(32), .C_COUNT_WIDTH(C_COUNT_WIDTH) // 物理最小深度映射不改变固件逻辑容量。
    ) Storage_Inst ( // 存储内容不受本地控制复位直接清零。
        .i_clk(i_clk), .i_rstn(stream_rstn), // FIFO 与发送源共享流复位，清除全部旧数据有效性。
        .i_write_valid(i_fw_valid && flag_room), .i_write_data(i_fw_word), .o_write_ready(fifo_ready), // 只有全路径容量允许的固件字才进入 FIFO。
        .i_read_ready(source_ready), .o_read_valid(fifo_valid), .o_read_data(fifo_word), .o_count(fifo_count) // 发送源是 FIFO 的唯一消费者。
    ); // 结束真实 SRAM FIFO 连接。
    dl_uart_tx_source Source_Inst ( // 完整预约和暂存保证仲裁头提交后不依赖后续 FIFO 可用性。
        .i_clk(i_clk), .i_rstn(stream_rstn), .i_channel4_enabled(i_channel4_enabled), // 同域本地控制与通道资格。
        .i_payload_fill(fifo_fill), .i_payload_valid(fifo_valid), .i_payload_word(fifo_word), // 数据来自实际注册 SRAM 读路径。
        .i_credit_valid(i_credit_valid), .i_credit_value(i_credit_value), .i_source_take(source_take[7]), // 只响应真实源七服务，信用更新由独立上游解码。
        .o_payload_ready(source_ready), .o_source_pending(source_pending), .o_word(source_word), // 等全部预约负载到达才参与仲裁。
        .o_word_count(source_count), .o_word_index(source_index), .o_busy(o_uart_busy), // 发送源自己持有长度与索引，和仲裁器交叉检查。
        .o_reserved_words(o_uart_reserved), .o_staged_words(o_uart_staged), // 分别暴露完整预约及实际尚未发送的数据所有权。
        .o_tx_counter(o_tx_counter), .o_latest_fc(o_latest_fc), .o_message_done(o_uart_message_done), .o_error(source_error) // 整消息计数及本地诊断。
    ); // 结束实际 UART 完整消息源连接。
    dl_message_arbiter Arbiter_Inst ( // 实际三组两级轮询及 UART 完整消息锁定。
        .i_uart_cancel(i_stream_reset), .i_clk(i_clk), .i_rstn(i_rstn), .i_segment_available(i_segment_available), // 同域服务机会不代表 PHY 时钟或 Flit 计时。
        .i_source_pending({i_other_pending[9:7], flag_uart_eligible, i_other_pending[6:0]}), // 在固定源七插入内部 UART transport 资格。
        .i_source_words({i_other_words[319:224], source_word, i_other_words[223:0]}), .i_uart_word_count(source_count), // 实际源头字与完整长度按固定十一源布局连接。
        .o_valid(o_valid), .o_word(o_word), .o_source(o_source), .o_word_index(o_word_index), .o_last(o_last), // 输出真实服务及完整消息边界。
        .o_source_take(source_take), .o_message_done(message_done), .o_error(arbiter_error), // 所有消费和完成都来自同一实际仲裁器。
        .o_locked(o_uart_locked), .o_uart_word_index(o_uart_word_index) // 消息占用与发送源索引可独立交叉检查。
    ); // 结束实际两级仲裁器连接。
endmodule // 结束 UART 实际存储发送路径模块。
