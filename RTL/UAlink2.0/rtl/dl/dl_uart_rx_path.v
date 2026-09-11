// UALink stream0 receive framing, actual SRAM storage and firmware read credits.
// 日期 2026-09-08；本地接收路径，完整复位握手及信用通告调度由上层负责。
`timescale 1ps/1ps // 接收处理和 SRAM 两端口共享同一同步时钟域。
module dl_uart_rx_path #( // UART 接收模块解析有序消息字并向固件提供不透明 payload。
    parameter integer C_RX_DEPTH = 128 // 默认推荐容量，其余一至四千零九十五字为研究配置。
) ( // 本地接口不会在线上增加额外准备或事务字段。
    input wire i_clk, // 协议解析与真实 SRAM 存储的共享采样时钟。
    input wire i_rstn, // 同步低有效全局复位清除消息和数据所有权。
    input wire i_stream_reset, // 流复位清除存储信用但保持线上消息排空。
    input wire i_channel4_enabled, // 已协商的 Channel4 接收运行资格。
    input wire i_word_valid, // 上游已完成可靠性处理的完整消息字资格。
    input wire [31:0] i_word, // 不包含重复或损坏传输的有序三十二位消息字。
    input wire i_fw_ready, // 固件接受当前已缓存的数据队首。
    output wire o_fw_valid, // 真实 SRAM 数据已经进入可消费输出缓存。
    output wire [31:0] o_fw_word, // 无效期间明确为零的固件不透明数据字。
    output wire [11:0] o_rx_fill, // 包括 SRAM 在途读取和缓存的完整逻辑占用。
    output wire o_initialized, // 流复位已经释放并完成容量初始化。
    output wire [11:0] o_rx_counter, // 仅真实固件读取增加的模四千零九十六信用。
    output wire o_credit_available, // 当前可被上层通告调度器观察的信用资格。
    output wire [5:0] o_remaining, // 当前 transport 尚待接收或丢弃的 payload 字数。
    output wire o_dropping, // 本消息当前必须丢弃并保持至原长度末尾。
    output wire o_header, // 识别新的 transport 头而不把该头存入缓冲。
    output wire o_payload_write, // 当前真实 payload 写入存储的沿前事件。
    output wire o_payload_discard, // 当前 payload 因整消息资格被丢弃。
    output wire o_done, // 原 transport 的最后一个有效字完成排空。
    output wire o_credit_valid, // 边界处识别到可以交给发送源的远端信用。
    output wire [11:0] o_credit_value, // 从 DataFCSeq 字段提取的绝对信用值。
    output wire o_reset_request, // 边界处识别到适用于本流的复位请求。
    output wire o_request_all, // 该复位请求指定全部流的原始字段。
    output wire o_reset_response, // 边界处识别到适用于本流的复位响应。
    output wire o_response_all, // 该复位响应指定全部流的原始字段。
    output wire [2:0] o_response_status, // 交给上层复位状态机判断的未修改状态字段。
    output wire o_other_valid, // 当前边界字需要转交其它 DL 消息处理器。
    output wire [31:0] o_other_word, // 原样转交的其它 DL 消息内容。
    output wire o_error // 本地容量或存储契约诊断，不定义新的线上错误码。
); // 结束单时钟 UART 接收路径端口。
    localparam integer C_COUNT_WIDTH = (C_RX_DEPTH < 2) ? 1 : (C_RX_DEPTH < 4) ? 2 : (C_RX_DEPTH < 8) ? 3 : (C_RX_DEPTH < 16) ? 4 : (C_RX_DEPTH < 32) ? 5 : (C_RX_DEPTH < 64) ? 6 : (C_RX_DEPTH < 128) ? 7 : (C_RX_DEPTH < 256) ? 8 : (C_RX_DEPTH < 512) ? 9 : (C_RX_DEPTH < 1024) ? 10 : (C_RX_DEPTH < 2048) ? 11 : 12; // 按精确容量派生包含满值的计数宽度。
    localparam [11:0] C_INITIAL_CREDIT = C_RX_DEPTH[11:0]; // 合法深度完整进入十二位初始信用。
    localparam [12:0] C_CAPACITY = C_RX_DEPTH[12:0]; // 十三位准入比较不会因加入消息长度而回绕。
    reg [5:0] cnt_remaining; // 每个有效线上 payload 减少一字的消息排空状态。
    reg reg_drop; // 一旦本消息失去接收资格即保持至其真实末字。
    reg reg_initialized; // 首个复位释放沿只完成容量初始化。
    reg [11:0] cnt_rx_credit; // 接收信用只跟踪固件实际读出的字数。
    wire storage_rstn, storage_ready, storage_valid; // 同域存储复位及真实读写握手资格。
    wire [31:0] storage_word; // 来自实际 SRAM 缓存的完整数据字。
    wire [C_COUNT_WIDTH-1:0] storage_count; // 包含后台流水所有权的准确 FIFO 填充。
    wire [11:0] rx_count; // 统一零扩展后的十二位本地容量占用。
    wire [5:0] header_count; // 从五位线上长度恢复一至三十二字 payload。
    wire [12:0] required_capacity; // 当前占用加上新消息长度的完整准入计算。
    wire flag_boundary, flag_uart, flag_stream0, flag_all; // 仅在消息边界使用的类别与流适用条件。
    wire flag_credit_kind, flag_request_kind, flag_response_kind; // 与数据接收使能独立的控制消息分类。
    wire flag_admit_error, flag_payload, flag_drop_now, flag_write_error; // 完整消息准入和当前 payload 的实际接纳条件。
    wire flag_consume; // 本沿真正完成的固件读取事件。
    assign storage_rstn = i_rstn && !i_stream_reset && reg_initialized; // 释放首沿继续清空存储以禁止借用未初始化资格。
    assign rx_count = {{(12-C_COUNT_WIDTH){1'b0}}, storage_count}; // 不把物理 padding 或输出缓存漏出占用。
    assign header_count = {1'b0, i_word[31:27]} + 6'd1; // 长度零合法表示一个 payload 字。
    assign required_capacity = {1'b0, rx_count} + {7'd0, header_count}; // 准入只使用沿前空间而不借同拍固件读。
    assign flag_boundary = i_rstn && i_word_valid && (cnt_remaining == 6'd0); // 消息内部数据即使形似头也不能重新解释。
    assign flag_uart = i_word[5:2] == 4'd1; // 只使用规范定义的 UART 消息类字段。
    assign flag_stream0 = i_word[11:9] == 3'd0; // 当前产品只定义第零个 UART 流。
    assign flag_all = flag_stream0 || i_word[12]; // 全部流复位也适用于已实现的第零流。
    assign o_header = flag_boundary && flag_uart && (i_word[8:6] == 3'd0); // 保留字段不参与头匹配，所有流均维持长度排空。
    assign flag_credit_kind = flag_boundary && flag_uart && (i_word[8:6] == 3'd1) && flag_stream0; // 远端信用只能作用于已实现的第零流。
    assign flag_request_kind = flag_boundary && flag_uart && (i_word[8:6] == 3'd6) && flag_all; // 请求事件在流复位期间仍可交给上层。
    assign flag_response_kind = flag_boundary && flag_uart && (i_word[8:6] == 3'd7) && flag_all; // 响应不会因本地流保持复位而丢失。
    assign flag_admit_error = o_header && flag_stream0 && storage_rstn && i_channel4_enabled && (required_capacity > C_CAPACITY); // 超出已发布容量的消息在头部整体拒绝。
    assign flag_payload = i_rstn && i_word_valid && (cnt_remaining != 6'd0); // 只有已跟踪消息的后续字才是 payload。
    assign flag_drop_now = reg_drop || !storage_rstn || !i_channel4_enabled; // 复位或离线立即阻断写入且保持整消息丢弃。
    assign flag_write_error = flag_payload && !flag_drop_now && !storage_ready; // 被正确预约的消息不应遇到存储不可写。
    assign o_payload_write = flag_payload && !flag_drop_now && storage_ready; // 真实写事件是唯一进入 SRAM 的资格。
    assign o_payload_discard = flag_payload && !o_payload_write; // 明确观察每个未进入缓冲的线上 payload。
    assign o_done = flag_payload && (cnt_remaining == 6'd1); // 接受和丢弃消息都必须准确排空原长度。
    assign o_fw_valid = storage_rstn && storage_valid; // 固件可以在 Channel4 离线时读取已有数据。
    assign o_fw_word = o_fw_valid ? storage_word : 32'd0; // 复位与空队列不暴露过期 SRAM 字。
    assign flag_consume = o_fw_valid && i_fw_ready; // 空读和预取不归还远端信用。
    assign o_rx_fill = storage_rstn ? rx_count : 12'd0; // 当前复位输入立即隐藏待清除的旧所有权。
    assign o_initialized = storage_rstn; // 只在已释放且完成初始化的阶段提供正常接收资格。
    assign o_rx_counter = storage_rstn ? cnt_rx_credit : 12'd0; // 流复位期间对外信用保持零。
    assign o_credit_available = storage_rstn && i_channel4_enabled; // 这里只提供快照资格而不定义更新节流事件。
    assign o_remaining = i_rstn ? cnt_remaining : 6'd0; // 全局复位清除排空状态而流复位保持其进度。
    assign o_dropping = i_rstn && (cnt_remaining != 6'd0) && flag_drop_now; // 明确当前活动消息的丢弃资格。
    assign o_credit_valid = flag_credit_kind && storage_rstn; // 已初始化时离线接收的绝对信用也可交给发送侧。
    assign o_credit_value = o_credit_valid ? i_word[31:20] : 12'd0; // 未识别信用消息时不输出无效字段。
    assign o_reset_request = flag_request_kind; // 流复位请求只解码而不在这里擅自运行握手。
    assign o_request_all = flag_request_kind && i_word[12]; // 原样保留请求作用域供上层匹配。
    assign o_reset_response = flag_response_kind; // 所有状态响应均由上层复位状态机处理。
    assign o_response_all = flag_response_kind && i_word[12]; // 原样保留响应作用域供上层匹配。
    assign o_response_status = flag_response_kind ? i_word[15:13] : 3'd0; // 保留非成功编码供上层判断而不误报成功。
    assign o_other_valid = flag_boundary && !(o_header || flag_credit_kind || flag_request_kind || flag_response_kind); // 未处理的单字消息交还上层 DL 分发。
    assign o_other_word = o_other_valid ? i_word : 32'd0; // 不把活动 transport 内的数据泄漏给其它消息解释器。
    assign o_error = flag_admit_error || flag_write_error; // 离线及流复位丢弃不会产生容量诊断。
    generate // 非法逻辑容量不能依赖位宽截断继续构建。
        if ((C_RX_DEPTH < 1) || (C_RX_DEPTH > 4095)) begin : gen_invalid // 明确拒绝未声明的接收深度。
            dl_uart_rx_parameters_invalid Invalid_Inst (); // 使非法配置在 elaboration 阶段失败。
        end // 结束接收逻辑容量参数检查。
    endgenerate // 结束 UART 接收配置合法性结构。
    always @(posedge i_clk) begin // 独立跟踪线上 transport 的剩余 payload 字数。
        if (!i_rstn) cnt_remaining <= 6'd0; // 只有全局复位取消消息边界状态。
        else if (o_header) cnt_remaining <= header_count; // 头部仅建立长度而不进入 payload 存储。
        else if (flag_payload) cnt_remaining <= cnt_remaining - 6'd1; // 每个有效后续字准确减少剩余长度。
    end // 结束保持跨流复位排空的消息计数器。
    always @(posedge i_clk) begin // 独立锁存一条 transport 的丢弃决定。
        if (!i_rstn) reg_drop <= 1'b0; // 全局复位取消旧消息丢弃状态。
        else if (o_header) reg_drop <= !storage_rstn || !i_channel4_enabled || !flag_stream0 || flag_admit_error; // 沿前一次确定新消息的接收资格。
        else if (o_done) reg_drop <= 1'b0; // 必须到原长度末字后才恢复新消息资格。
        else if ((cnt_remaining != 6'd0) && (flag_drop_now || flag_write_error)) reg_drop <= 1'b1; // 即使无输入字，离线或复位也锁存至末字。
    end // 结束整消息持续丢弃状态。
    always @(posedge i_clk) begin // 独立记录本地流复位释放后的初始化完成。
        if (!i_rstn || i_stream_reset) reg_initialized <= 1'b0; // 本地或全局复位均撤销接收信用资格。
        else reg_initialized <= 1'b1; // 首个释放沿建立初始容量，下一周期允许接收。
    end // 结束接收信用初始化资格寄存器。
    always @(posedge i_clk) begin // 独立实现接收方十二位模信用计数器。
        if (!i_rstn || i_stream_reset) cnt_rx_credit <= 12'd0; // 复位丢弃旧数据而不归还正常读取信用。
        else if (!reg_initialized) cnt_rx_credit <= C_INITIAL_CREDIT; // 初始可发布容量等于精确接收缓冲深度。
        else if (flag_consume) cnt_rx_credit <= cnt_rx_credit + 12'd1; // 只有固件真实读握手增加一字信用并自然模回绕。
    end // 结束接收信用计数器。
    upli_receive_storage #( // 复用实际同步 FIFO 与获授权固定 SRAM 存储映射。
        .C_DEPTH(C_RX_DEPTH), .C_DATA_WIDTH(32), .C_COUNT_WIDTH(C_COUNT_WIDTH) // 精确逻辑深度独立于物理宏 padding。
    ) Storage_Inst ( // 接收端只保存不透明 payload，不保存 transport 头。
        .i_clk(i_clk), .i_rstn(storage_rstn), // SRAM 控制仍使用同一原始时钟与同步复位。
        .i_write_valid(o_payload_write), .i_write_data(i_word), .o_write_ready(storage_ready), // 只有实际接纳的 payload 进入后端。
        .i_read_ready(flag_consume), .o_read_valid(storage_valid), .o_read_data(storage_word), // 固件读取来自真实存储缓存而非旁路期望。
        .o_count(storage_count) // 公开完整容量所有权供头部准入检查。
    ); // 结束真实 SRAM 接收数据路径。
endmodule // 结束 UART stream0 接收与固件信用归还实现。
