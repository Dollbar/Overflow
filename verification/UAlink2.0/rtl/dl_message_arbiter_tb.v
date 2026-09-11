// DL 消息仲裁器的独立逐沿向量对照；只验证已暂存消息源的调度接口。
`timescale 1ps/1ps // 使用精确整数时间，在两种本地测试周期下检查同步行为。
module dl_message_arbiter_tb; // 仲裁器测试模块，检查完整 DWORD、来源、边界和 UART 所有权。
    parameter integer C_HALF_PERIOD_PS = 320; // 可选本地测试时钟半周期，不等于物理链路节奏。
    reg i_clk; // 仅由测试序列驱动的公共采样时钟。
    reg [370:0] stimulus; // 独立文件提供复位、服务机会及全部消息源输入。
    reg [73:0] expected; // 独立模型给出的沿前完整事件。
    reg [6:0] expected_after; // 沿后 UART 所有权及下一 DWORD 索引。
    wire [73:0] observed; // DUT 的全部公开事件与沿前状态观察。
    wire [6:0] state_observed; // DUT 的 UART 状态，单独检查采样沿更新。
    wire valid, last, error, locked; // 当前服务与本地接口错误标志。
    wire [31:0] word; // 当前被服务的原始 DWORD。
    wire [3:0] source; // 当前本地来源索引，不是线上 mclass 编码。
    wire [5:0] word_index, uart_word_index; // 当前有效事件与 UART 暂存器读地址。
    wire [10:0] source_take, message_done; // 逐源 DWORD 消耗及消息完成事件。
    reg [4095:0] vector_path; // 从命令行接入本次独立输入文件。
    integer fd, fields, rows, words, messages, errors; // 记录文件状态和真实事件计数。
    assign observed = {valid, word, source, word_index, last, source_take, message_done, error, locked, uart_word_index}; // 与向量字段顺序逐位一致。
    assign state_observed = {locked, uart_word_index}; // 保留所有权观察，不能用事件期望反推 DUT 状态。
    dl_message_arbiter Arbiter_Inst ( // 实例化真实仲裁器，不接行为替代模型。
        .i_clk(i_clk), .i_rstn(stimulus[370]), .i_segment_available(stimulus[369]), // 同步复位与真实输入服务事件。
        .i_source_pending(stimulus[368:358]), .i_source_words(stimulus[357:6]), .i_uart_word_count(stimulus[5:0]), // 全部暂存源 DWORD 和首字长度。
        .o_valid(valid), .o_word(word), .o_source(source), .o_word_index(word_index), .o_last(last), // 当前采样沿的完整输出。
        .o_source_take(source_take), .o_message_done(message_done), .o_error(error), // 逐源消费、退休和本地错误。
        .o_locked(locked), .o_uart_word_index(uart_word_index) // 外部 UART 完整暂存器的地址及所有权观察。
    ); // 结束真实 DUT 连接。
    initial begin // 从零事件开始执行有限独立轨迹。
        i_clk = 1'b0; stimulus = 371'd0; // 首个向量前保持同步复位输入。
        rows = 0; words = 0; messages = 0; errors = 0; // 所有计数来自 DUT 的实际输出。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 缺少向量时拒绝空跑。
            $display("FAIL dl_message missing VECTORS"); $stop; // 将入口错误传播为非零退出。
        end // 结束输入路径校验。
        fd = $fopen(vector_path, "r"); // 只读本次独立轨迹文件。
        if (fd == 0) begin // 路径错误不能被当作零行通过。
            $display("FAIL dl_message vector open"); $stop; // 文件打不开立即失败。
        end // 结束文件可读性校验。
        fields = $fscanf(fd, "%h %h %h", stimulus, expected, expected_after); // 每行包含输入、沿前事件、沿后状态。
        while (fields == 3) begin // 完整记录才可驱动下一个采样沿。
            #(C_HALF_PERIOD_PS-1); // 保留组合路径稳定时间。
            if (observed !== expected) begin // 比较数据、来源、Last、所有权和故障，不只检查 valid。
                $display("FAIL dl_message pre row=%0d actual=%h expected=%h", rows, observed, expected); $stop; // 首个差异保留精确位置。
            end // 结束沿前独立模型检查。
            if (valid) words = words+1; // 每个真实 DWORD 只计一次。
            if (|message_done) messages = messages+1; // 单拍至多完成一个消息。
            if (error) errors = errors+1; // 单列本地接口负例的错误观察。
            #1 i_clk = 1'b1; // 在同一上升沿完成消费和调度状态更新。
            #1; // 等待非阻塞赋值完成后观察状态。
            if (state_observed !== expected_after) begin // 检查锁定、释放及下一字索引，没有额外的仲裁周期。
                $display("FAIL dl_message post row=%0d actual=%h expected=%h", rows, state_observed, expected_after); $stop; // 捕获错误推进及过早释放。
            end // 结束沿后状态检查。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成当前测试周期。
            rows = rows+1; // 行数与生成器完成摘要必须精确相等。
            fields = $fscanf(fd, "%h %h %h", stimulus, expected, expected_after); // 读下一条完整独立记录。
        end // 结束全部合法向量记录。
        if ((fields != -1) || (rows < 1000) || (words < 1000)) begin // 拒绝损坏文件、截断字段和无效短跑。
            $display("FAIL dl_message incomplete fields=%0d rows=%0d words=%0d", fields, rows, words); $stop; // 非空检查与 Python 精确计数双重约束。
        end // 结束终态文件与活动量检查。
        $fclose(fd); // 完整处理后释放只读向量文件。
        $display("PASS dl_message rows=%0d words=%0d messages=%0d errors=%0d", rows, words, messages, errors); // 输出唯一的机器可核查完成记录。
        $finish; // 成功走到完整轨迹末尾后正常退出。
    end // 结束 DL 消息逐沿自检序列。
endmodule // 结束 DL 消息仲裁器测试模块。
