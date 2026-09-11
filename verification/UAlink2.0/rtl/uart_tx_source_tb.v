// UART TX 来源的独立向量自检，比较全部输出及沿后状态。
`timescale 1ps/1ps // 使用整数时间，对两种本地测试周期执行同一功能轨迹。
module uart_tx_source_tb; // 真实 RTL 的逐沿全字段比较测试模块。
    parameter integer C_HALF_PERIOD_PS = 320; // 本地验证半周期，不作为物理链路时序证明。
    reg i_clk; // 单个测试采样时钟。
    reg [60:0] stimulus; // 复位、通道、FIFO、信用及真实来源消费输入。
    reg [84:0] expected, expected_after; // 参考模型给出的完整沿前与沿后输出。
    wire [84:0] observed; // DUT 全部公开输出的固定顺序拼接。
    wire payload_ready, pending, busy, done, error; // 真实 FIFO 接收资格、来源资格和完成诊断。
    wire [31:0] word; // 当前服务的完整头或 payload DWORD。
    wire [5:0] word_count, word_index, reserved_words, staged_words; // 完整长度、字索引及两种占用。
    wire [11:0] tx_counter, latest_fc; // 真实发送与最近绝对信用计数。
    reg [4095:0] vector_path; // 命令行指定的独立向量文件路径。
    integer fd, fields, rows, loads, words, messages, errors; // 文件解析状态与实际 DUT 事件计数。
    assign observed = {payload_ready, pending, word, word_count, word_index, busy, reserved_words, staged_words, tx_counter, latest_fc, done, error}; // 与生成器公开信号结构顺序一致。
    dl_uart_tx_source Source_Inst ( // 实例化实际可综合 UART 来源，无行为替代模块。
        .i_clk(i_clk), .i_rstn(stimulus[60]), .i_channel4_enabled(stimulus[59]), // 单时钟同步复位和通道资格。
        .i_payload_fill(stimulus[58:47]), .i_payload_valid(stimulus[46]), .i_payload_word(stimulus[45:14]), // 独立 FIFO 填充及实际队首握手。
        .i_credit_valid(stimulus[13]), .i_credit_value(stimulus[12:1]), .i_source_take(stimulus[0]), // 解码后信用与当前来源消费。
        .o_payload_ready(payload_ready), .o_source_pending(pending), .o_word(word), // 实际上游接收和下游数据资格。
        .o_word_count(word_count), .o_word_index(word_index), .o_busy(busy), // 完整消息边界及单预约占用。
        .o_reserved_words(reserved_words), .o_staged_words(staged_words), // 信用预约和实际暂存容量分别核对。
        .o_tx_counter(tx_counter), .o_latest_fc(latest_fc), .o_message_done(done), .o_error(error) // 所有计数与错误输出都参与比较。
    ); // 结束真实 DUT 接口连接。
    initial begin // 每行先检查组合输出，再检查同沿更新后的全部输出。
        i_clk = 1'b0; stimulus = 61'd0; // 首条向量之前保持本地同步复位条件。
        rows = 0; loads = 0; words = 0; messages = 0; errors = 0; // 计数仅来自真实 DUT 沿前事件。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 必须明确提供独立向量，禁止空跑通过。
            $display("FAIL uart_tx_source missing VECTORS"); $stop; // 入口错误传播为仿真失败。
        end // 结束命令行向量路径校验。
        fd = $fopen(vector_path, "r"); // 只读当前构建保存的精确向量。
        if (fd == 0) begin // 无法打开文件不能当成空轨迹通过。
            $display("FAIL uart_tx_source vector open"); $stop; // 保留文件错误并停止。
        end // 结束文件可读性校验。
        fields = $fscanf(fd, "%h %h %h", stimulus, expected, expected_after); // 每行是输入、沿前输出和沿后输出。
        while (fields == 3) begin // 只有完整记录才允许推进真实时钟。
            #(C_HALF_PERIOD_PS-1); // 留出组合输出稳定时间。
            if (observed !== expected) begin // 数据、占用、索引、计数和错误都必须逐位相等。
                $display("FAIL uart_tx_source pre row=%0d actual=%h expected=%h", rows, observed, expected); $stop; // 首个差异给出完整比较值。
            end // 结束沿前全输出比较。
            if (payload_ready && stimulus[46]) loads = loads+1; // 只统计真实 FIFO DWORD 捕获。
            if (pending && stimulus[0]) words = words+1; // 头和每个实际 payload 服务都计入总发送字数。
            if (done) messages = messages+1; // 只在最后一个实际 payload 消费时计消息完成。
            if (error) errors = errors+1; // 单列故障注入的组合诊断事件。
            #1 i_clk = 1'b1; // 所有实际握手在共同上升沿发生。
            #1; // 等待非阻塞赋值后再检查更新结果。
            if (observed !== expected_after) begin // 保持相同输入检查完整沿后状态，而非只比较 valid。
                $display("FAIL uart_tx_source post row=%0d actual=%h expected=%h", rows, observed, expected_after); $stop; // 检出错误预约、计数及数据推进。
            end // 结束沿后全输出比较。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成当前本地测试时钟周期。
            rows = rows+1; // 实际行数必须与生成器摘要完全相等。
            fields = $fscanf(fd, "%h %h %h", stimulus, expected, expected_after); // 继续读取下一条独立记录。
        end // 结束完整向量文件执行。
        if ((fields != -1) || (rows < 10000) || (words < 4000)) begin // 拒绝破损文件、未完成记录和缺少活动的短跑。
            $display("FAIL uart_tx_source incomplete fields=%0d rows=%0d words=%0d", fields, rows, words); $stop; // 与运行器的精确计数校验共同拒绝假通过。
        end // 结束终态及活动量检查。
        $fclose(fd); // 完整处理后关闭只读文件。
        $display("PASS uart_tx_source rows=%0d loads=%0d words=%0d messages=%0d errors=%0d", rows, loads, words, messages, errors); // 唯一机器可核查完成标记。
        $finish; // 完整轨迹且全部字段一致后正常退出。
    end // 结束 UART 来源自检主序列。
endmodule // 结束逐沿模型对照测试台。
