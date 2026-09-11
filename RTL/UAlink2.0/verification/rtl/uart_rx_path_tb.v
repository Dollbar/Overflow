`timescale 1ps/1ps // 用明确皮秒时基验证两种既定功能测试周期。
module uart_rx_path_tb; // UART 接收测试模块联合实际存储和独立线数据记分板。
    parameter integer C_RX_DEPTH = 128; // 本次真实 SRAM 逻辑容量。
    parameter integer C_HALF_PERIOD_PS = 320; // 仅表示功能测试半周期而不宣称物理收敛。
    parameter integer C_CHECK_VECTORS = 1; // 可独立关闭模型字段比较以检查记分板故障检出能力。
    reg i_clk; // 共享采样时钟。
    reg i_rstn; // 同步低有效全局复位。
    reg i_stream_reset; // 本地流复位清除存储并保持线上排空。
    reg i_channel4_enabled; // 协商后的 Channel4 运行资格。
    reg i_word_valid; // 完整且已通过上游可靠性处理的 DL 消息字资格。
    reg [31:0] i_word; // 已展开的三十二位有序消息字。
    reg i_fw_ready; // 固件接受当前可见队首数据。
    wire o_fw_valid; // 固件队首数据已经经过真实 SRAM 读缓存。
    wire [31:0] o_fw_word; // 当前固件可读的不透明完整数据字。
    wire [11:0] o_rx_fill; // 包含 SRAM 在途读取与缓存的完整接收占用。
    wire o_initialized; // 本地接收信用初始化已经完成。
    wire [11:0] o_rx_counter; // 只随真实固件读取推进的十二位接收信用。
    wire o_credit_available; // 当前 Channel4 状态允许观察信用通告值。
    wire [5:0] o_remaining; // 当前线上消息尚待排空的有效 payload 字数。
    wire o_dropping; // 当前消息已进入保持至末字的丢弃状态。
    wire o_header; // 当前字被识别为新的 UART transport 头。
    wire o_payload_write; // 当前线上 payload 真实写入接收存储。
    wire o_payload_discard; // 当前线上 payload 被本地资格规则丢弃。
    wire o_done; // 当前字完成原消息长度的排空。
    wire o_credit_valid; // 当前边界消息携带可接受的远端绝对信用。
    wire [11:0] o_credit_value; // 解码的十二位远端 DataFCSeq。
    wire o_reset_request; // 边界处识别到适用于本流的复位请求。
    wire o_request_all; // 该复位请求的全部流选择位。
    wire o_reset_response; // 边界处识别到适用于本流的复位响应。
    wire o_response_all; // 该复位响应的全部流选择位。
    wire [2:0] o_response_status; // 原样交给上层复位状态机判断的状态字段。
    wire o_other_valid; // 需要交给其它 DL 消息处理器的完整字。
    wire [31:0] o_other_word; // 未经重编码的其它 DL 消息内容。
    wire o_error; // 超出本地信用容量或存储契约的诊断事件。
    reg [36:0] input_bits; // 逐行读取完整三十七位输入组合。
    reg [123:0] expected_pre, expected_post; // 独立模型产生的完整沿前和沿后字段。
    wire [123:0] actual; // 按照冻结字段顺序连接全部真实输出。
    reg [4095:0] vector_path; // 保存显式传入的向量文件路径。
    reg [31:0] expected_words [0:C_RX_DEPTH-1]; // 只由独立线消息解析接受的数据填充固件期望队列。
    integer vector_file, scan_status; // 保存文件读取状态并拒绝残缺向量行。
    integer expected_count, expected_write, expected_read, expected_left, expected_reads; // 独立整数保存容量指针消息余数及不回绕读取总数。
    reg expected_initialized, expected_drop, score_header, score_write, score_reject; // 独立保存初始化和跨复位排空资格。
    integer score_length; // 从线上长度字段独立恢复一至三十二字。
    integer cnt_rows, cnt_payload_writes, cnt_reads, cnt_messages, cnt_headers, cnt_discards; // 累计真实握手和消息边界次数。
    integer cnt_errors, cnt_credits, cnt_requests, cnt_responses, cnt_others, cnt_resets, cnt_stream_resets; // 累计异常与边界控制事件以核对模型统计。
    assign actual = {o_fw_valid, o_fw_word, o_rx_fill, o_initialized, o_rx_counter, o_credit_available, o_remaining, o_dropping, o_header, o_payload_write, o_payload_discard, o_done, o_credit_valid, o_credit_value, o_reset_request, o_request_all, o_reset_response, o_response_all, o_response_status, o_other_valid, o_other_word, o_error}; // 完整比较包括数据及所有已解码事件而非仅通过标记。
    dl_uart_rx_path #(.C_RX_DEPTH(C_RX_DEPTH)) Dut_Inst ( // 实例化真实 SRAM 接收路径并传入精确容量。
        .i_clk(i_clk), // 共享采样时钟。
        .i_rstn(i_rstn), // 同步低有效全局复位。
        .i_stream_reset(i_stream_reset), // 本地流复位清除存储并保持线上排空。
        .i_channel4_enabled(i_channel4_enabled), // 协商后的 Channel4 运行资格。
        .i_word_valid(i_word_valid), // 完整且已通过上游可靠性处理的 DL 消息字资格。
        .i_word(i_word), // 已展开的三十二位有序消息字。
        .i_fw_ready(i_fw_ready), // 固件接受当前可见队首数据。
        .o_fw_valid(o_fw_valid), // 固件队首数据已经经过真实 SRAM 读缓存。
        .o_fw_word(o_fw_word), // 当前固件可读的不透明完整数据字。
        .o_rx_fill(o_rx_fill), // 包含 SRAM 在途读取与缓存的完整接收占用。
        .o_initialized(o_initialized), // 本地接收信用初始化已经完成。
        .o_rx_counter(o_rx_counter), // 只随真实固件读取推进的十二位接收信用。
        .o_credit_available(o_credit_available), // 当前 Channel4 状态允许观察信用通告值。
        .o_remaining(o_remaining), // 当前线上消息尚待排空的有效 payload 字数。
        .o_dropping(o_dropping), // 当前消息已进入保持至末字的丢弃状态。
        .o_header(o_header), // 当前字被识别为新的 UART transport 头。
        .o_payload_write(o_payload_write), // 当前线上 payload 真实写入接收存储。
        .o_payload_discard(o_payload_discard), // 当前线上 payload 被本地资格规则丢弃。
        .o_done(o_done), // 当前字完成原消息长度的排空。
        .o_credit_valid(o_credit_valid), // 当前边界消息携带可接受的远端绝对信用。
        .o_credit_value(o_credit_value), // 解码的十二位远端 DataFCSeq。
        .o_reset_request(o_reset_request), // 边界处识别到适用于本流的复位请求。
        .o_request_all(o_request_all), // 该复位请求的全部流选择位。
        .o_reset_response(o_reset_response), // 边界处识别到适用于本流的复位响应。
        .o_response_all(o_response_all), // 该复位响应的全部流选择位。
        .o_response_status(o_response_status), // 原样交给上层复位状态机判断的状态字段。
        .o_other_valid(o_other_valid), // 需要交给其它 DL 消息处理器的完整字。
        .o_other_word(o_other_word), // 未经重编码的其它 DL 消息内容。
        .o_error(o_error) // 超出本地信用容量或存储契约的诊断事件。
    ); // 结束所有输入与完整输出的真实连接。
    initial begin // 逐行驱动时钟并同时检查模型字段和独立数据记分板。
        i_clk = 1'b0; i_rstn = 1'b0; i_stream_reset = 1'b0; i_channel4_enabled = 1'b0; // 全局复位下建立确定的初始控制输入。
        i_word_valid = 1'b0; i_word = 32'd0; i_fw_ready = 1'b0; // 初始化输入资格与完整数据字。
        expected_count = 0; expected_write = 0; expected_read = 0; expected_left = 0; expected_reads = 0; // 独立所有权与消息排空初始为空。
        expected_initialized = 1'b0; expected_drop = 1'b0; // 信用在首个释放沿才成为容量值。
        cnt_rows = 0; cnt_payload_writes = 0; cnt_reads = 0; cnt_messages = 0; cnt_headers = 0; cnt_discards = 0; // 清除本次运行真实数据统计。
        cnt_errors = 0; cnt_credits = 0; cnt_requests = 0; cnt_responses = 0; cnt_others = 0; cnt_resets = 0; cnt_stream_resets = 0; // 清除本次运行控制事件统计。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin $display("FAIL missing VECTORS"); $stop; end // 必须使用调用方明确给出的独立向量文件。
        vector_file = $fopen(vector_path, "r"); // 只读打开本次快照绑定的向量文件。
        if (vector_file == 0) begin $display("FAIL cannot open VECTORS"); $stop; end // 读取失败不能伪装成零行通过。
        while (!$feof(vector_file)) begin // 每行分别核对沿前握手和沿后状态。
            scan_status = $fscanf(vector_file, "%h %h %h\n", input_bits, expected_pre, expected_post); // 完整读取输入与两份期望字段。
            if (scan_status != 3) begin $display("FAIL incomplete vector row"); $stop; end // 拒绝截断字段或非法向量输入。
            {i_rstn, i_stream_reset, i_channel4_enabled, i_word_valid, i_word, i_fw_ready} = input_bits; // 按冻结三十七位顺序驱动输入。
            #(C_HALF_PERIOD_PS-1); // 给沿前组合逻辑充分建立时间。
            if ((C_CHECK_VECTORS != 0) && (actual !== expected_pre)) begin $display("FAIL pre row=%0d got=%h expected=%h", cnt_rows, actual, expected_pre); $stop; end // 逐位拒绝实际输出与独立模型不一致。
            score_header = i_rstn && (expected_left == 0) && i_word_valid && (i_word[5:2] == 4'd1) && (i_word[8:6] == 3'd0); // 依据独立消息余数判断新头而不读取 DUT 状态。
            score_length = {27'd0, i_word[31:27]} + 32'd1; // 不使用 DUT 长度或写资格作为期望来源。
            score_reject = !expected_initialized || i_stream_reset || !i_channel4_enabled || (i_word[11:9] != 3'd0) || ((expected_count+score_length) > C_RX_DEPTH); // 严格使用沿前占用决定完整消息容量资格。
            score_write = i_rstn && expected_initialized && !i_stream_reset && i_channel4_enabled && !expected_drop && (expected_left != 0) && i_word_valid; // 独立确定当前线上 payload 是否应被存储。
            if (o_payload_write !== score_write) begin $display("FAIL scoreboard payload admission row=%0d", cnt_rows); $stop; end // 独立准入记分板能够发现错误写入或丢弃。
            if (i_rstn) begin // 全局复位以外检查存储所有权和返回信用。
                if ({20'd0, o_rx_fill} != ((expected_initialized && !i_stream_reset) ? expected_count : 0)) begin $display("FAIL scoreboard fill row=%0d", cnt_rows); $stop; end // 隐藏流水缓存仍必须计入精确容量。
                if ({20'd0, o_rx_counter} != ((expected_initialized && !i_stream_reset) ? ((C_RX_DEPTH+expected_reads) % 4096) : 0)) begin $display("FAIL scoreboard credit row=%0d", cnt_rows); $stop; end // 信用期望由独立不回绕读取总数计算。
                if (o_fw_valid && ((expected_count == 0) || (o_fw_word !== expected_words[expected_read]))) begin $display("FAIL scoreboard data row=%0d", cnt_rows); $stop; end // 实际 SRAM 读出的每一字必须等于真实线输入的顺序队首。
            end // 结束沿前独立数据和计数检查。
            cnt_payload_writes = cnt_payload_writes + (o_payload_write ? 1 : 0); // 只统计真实被接收路径保存的 payload。
            cnt_reads = cnt_reads + ((o_fw_valid && i_fw_ready) ? 1 : 0); // 只统计真正交给固件的数据。
            cnt_messages = cnt_messages + ((o_done) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_headers = cnt_headers + ((o_header) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_discards = cnt_discards + ((o_payload_discard) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_errors = cnt_errors + ((o_error) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_credits = cnt_credits + ((o_credit_valid) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_requests = cnt_requests + ((o_reset_request) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_responses = cnt_responses + ((o_reset_response) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_others = cnt_others + ((o_other_valid) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_resets = cnt_resets + ((!i_rstn) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            cnt_stream_resets = cnt_stream_resets + ((i_rstn && i_stream_reset) ? 1 : 0); // 记录本沿该类真实事件而不重复累计沿后组合值。
            if (!i_rstn) begin // 全局复位同时取消存储和所有消息排空资格。
                expected_left = 0; expected_drop = 1'b0; // 全局复位清除独立消息边界跟踪。
            end else if (expected_left != 0) begin // 活动 transport 字不能解释为新的控制消息。
                if (!expected_initialized || i_stream_reset || !i_channel4_enabled) expected_drop = 1'b1; // 空输入周期出现复位或离线也锁存整条消息的丢弃。
                if (i_word_valid) expected_left = expected_left-1; // 仅有效线上字推进消息排空。
                if (expected_left == 0) expected_drop = 1'b0; // 准确末字之后才恢复下一条消息的解释资格。
            end else if (score_header) begin // 根据独立头解析建立新消息的排空状态。
                expected_left = score_length; expected_drop = score_reject; // 一次冻结长度和整消息容量资格。
            end // 结束独立消息边界状态更新。
            if (!i_rstn || i_stream_reset || !expected_initialized) begin // 复位和初始化沿清除全部本地存储所有权。
                expected_count = 0; expected_write = 0; expected_read = 0; expected_reads = 0; // 不把被复位丢弃的数据归还为正常读信用。
                expected_initialized = i_rstn && !i_stream_reset; // 释放的首个沿只初始化容量而不接收或读取数据。
            end else begin // 正常沿可以同时处理固件读出和独立准入数据。
                if (o_fw_valid && i_fw_ready) begin // 真实读握手释放一个独立队首所有权。
                    expected_read = (expected_read+1) % C_RX_DEPTH; expected_count = expected_count-1; expected_reads = expected_reads+1; // 读出推进准确环形指针和不回绕信用计数。
                end // 结束独立固件读握手更新。
                if (score_write) begin // 仅独立确认的线上 payload 进入期望存储。
                    expected_words[expected_write] = i_word; // 期望数据来自输入线而不引用 DUT 写数据。
                    expected_write = (expected_write+1) % C_RX_DEPTH; expected_count = expected_count+1; // 写入推进准确容量和环形队列。
                end // 结束独立 payload 追加更新。
            end // 结束本地存储和返回信用的独立更新。
            #1; i_clk = 1'b1; #1; // 在明确上升沿后检查全部寄存器引起的输出变化。
            if ((C_CHECK_VECTORS != 0) && (actual !== expected_post)) begin $display("FAIL post row=%0d got=%h expected=%h", cnt_rows, actual, expected_post); $stop; end // 完整沿后比较检测错误优先级和重复事件状态。
            #(C_HALF_PERIOD_PS-1); i_clk = 1'b0; // 结束完整功能周期并回到下一行输入建立阶段。
            cnt_rows = cnt_rows+1; // 只把完整执行的向量行计入结果。
        end // 结束全部确定向量与随机流量。
        if ((cnt_rows == 0) || (expected_count != 0) || (expected_left != 0)) begin $display("FAIL incomplete final drain"); $stop; end // 拒绝零行运行及尚未排空的数据或消息。
        $display("PASS uart_rx_path rows=%0d payload_writes=%0d reads=%0d messages=%0d headers=%0d discards=%0d errors=%0d credits=%0d requests=%0d responses=%0d others=%0d resets=%0d stream_resets=%0d", cnt_rows, cnt_payload_writes, cnt_reads, cnt_messages, cnt_headers, cnt_discards, cnt_errors, cnt_credits, cnt_requests, cnt_responses, cnt_others, cnt_resets, cnt_stream_resets); // 完整功能和记分板检查后才输出统计通过标记。
        $fclose(vector_file); $finish; // 完成测试后关闭只读向量文件。
    end // 结束自检主进程。
endmodule // 结束实际 UART 接收路径测试台。
