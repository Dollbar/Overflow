// SRAM FIFO、UART 发送源及两级仲裁器的实际连接测试。
`timescale 1ps/1ps // 两种仿真周期只改变测试时间，不宣称物理签核。
module uart_tx_path_tb; // 同时使用独立周期模型和端到端内容记分板的测试模块。
    parameter integer C_HALF_PERIOD_PS = 320; // 可选三百二十或三千二百皮秒半周期。
    parameter integer C_TX_DEPTH = 128; // 固件总容量，包括源内尚未发送的暂存字。
    reg i_clk; // FIFO、SRAM 两端及消息控制均使用此共同采样时钟。
    reg [378:0] stimulus; // 沿前复位、固件、信用和十个外部消息源输入。
    reg [123:0] expected; // 独立组合模型给出的全部沿前输出。
    reg [57:0] expected_after; // 独立组合模型给出的沿后状态观察。
    wire [123:0] observed; // DUT 沿前完整公开接口。
    wire [57:0] observed_after; // 同一输入下的沿后状态接口。
    wire fw_ready, uart_busy, valid, last, uart_done, locked, error; // 实际握手、消息完成和诊断事件。
    wire [12:0] buffered; // 包含 SRAM、缓存及发送暂存器的实际总占用。
    wire [11:0] tx_counter, latest_fc; // 实际已完成发送计数与最新解码信用。
    wire [5:0] reserved, staged, word_index, uart_index; // 单预约长度、未发数据和双方索引。
    wire [31:0] word; // 真实物理存储路径输出到消息槽的 DWORD。
    wire [3:0] source; // 实际两级仲裁赢家的本地索引。
    wire [9:0] other_take, other_done; // 其余十个单字消息源的真实消费与完成。
    reg [31:0] scoreboard [0:8191]; // 只从固件接受事件建立期望，绝不从 DUT SRAM 或向量数据反推。
    reg [4095:0] vector_path; // 命令行指定的当前构建向量文件。
    integer fd, fields, rows, writes, payloads, uart_messages, other_messages, resets; // 真实事件计数与解析状态。
    integer score_read, score_write, score_count, score_tx, active_length, next_index; // 独立队列所有权与完整消息边界。
    assign observed = {fw_ready, buffered, tx_counter, uart_busy, reserved, staged, latest_fc, valid, word, source, word_index, last, other_take, other_done, uart_done, locked, error, uart_index}; // 固定的一百二十四位沿前观测。
    assign observed_after = {fw_ready, buffered, tx_counter, uart_busy, reserved, staged, latest_fc, locked, uart_index}; // 固定的五十八位沿后状态。
    dl_uart_tx_path #(.C_TX_DEPTH(C_TX_DEPTH)) Path_Inst ( // 实例化实际 SRAM 包装器和实际消息控制模块。
        .i_clk(i_clk), .i_rstn(stimulus[378]), .i_channel4_enabled(stimulus[377]), // 同步复位共同丢弃所有控制所有权。
        .i_fw_valid(stimulus[376]), .i_fw_word(stimulus[375:344]), .o_fw_ready(fw_ready), // 固件原始输入是端到端记分板的唯一数据源。
        .i_credit_valid(stimulus[343]), .i_credit_value(stimulus[342:331]), .i_segment_available(stimulus[330]), // 已解码信用与实际消息槽服务机会。
        .i_other_pending(stimulus[329:320]), .i_other_words(stimulus[319:0]), // 十个已具备发送资格的外部单字消息源。
        .o_buffered_words(buffered), .o_tx_counter(tx_counter), .o_uart_busy(uart_busy), // 核对真实容量与整条消息退休计数。
        .o_uart_reserved(reserved), .o_uart_staged(staged), .o_latest_fc(latest_fc), // 核对预约与实际数据暂存的区别。
        .o_valid(valid), .o_word(word), .o_source(source), .o_word_index(word_index), .o_last(last), // 检查实际服务数据及完整消息边界。
        .o_other_take(other_take), .o_other_done(other_done), .o_uart_message_done(uart_done), // 检查各源独立消费和完成事件。
        .o_uart_locked(locked), .o_error(error), .o_uart_word_index(uart_index) // 检查消息锁定与双方索引同步。
    ); // 结束实际 DUT 接口连接。
    initial begin // 逐沿检查模型输出，并从独立固件队列核验真实 SRAM 数据内容。
        i_clk = 1'b0; stimulus = 379'd0; // 首条向量前保持低电平时钟及同步复位输入。
        rows = 0; writes = 0; payloads = 0; uart_messages = 0; other_messages = 0; resets = 0; // 初始化实际事件统计。
        score_read = 0; score_write = 0; score_count = 0; score_tx = 0; active_length = 0; next_index = 0; // 初始化独立有效性，不清除 DUT SRAM 内容。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 未指定向量必须明确失败。
            $display("FAIL uart_tx_path missing VECTORS"); $stop; // 禁止空跑形成通过标记。
        end // 结束命令行路径检查。
        fd = $fopen(vector_path, "r"); // 打开构建中保留的只读向量。
        if (fd == 0) begin // 文件不可读时不能继续仿真。
            $display("FAIL uart_tx_path vector open"); $stop; // 记录入口失败。
        end // 结束文件打开检查。
        fields = $fscanf(fd, "%h %h %h", stimulus, expected, expected_after); // 每条记录包含全部输入、沿前输出及沿后状态。
        while (fields == 3) begin // 只对完整记录推进共同采样沿。
            #(C_HALF_PERIOD_PS-1); // 等待当前输入的组合输出稳定。
            if (observed !== expected) begin // 完整向量核对与内容记分板各自独立。
                $display("FAIL uart_tx_path pre row=%0d actual=%h expected=%h", rows, observed, expected); $stop; // 输出首个完整字段差异。
            end // 结束沿前模型比较。
            if (!stimulus[378]) begin // 协调本地复位丢弃固件队列和消息所有权。
                score_read = 0; score_write = 0; score_count = 0; score_tx = 0; active_length = 0; next_index = 0; resets = resets+1; // 独立记分板同步清零。
            end else begin // 非复位沿只根据真实握手改变期望所有权。
                if ((buffered !== score_count[12:0]) || (fw_ready !== (score_count < C_TX_DEPTH)) || error) begin // 总容量必须从固件接受到最终 payload 发送始终守恒。
                    $display("FAIL uart_tx_path capacity row=%0d count=%0d buffered=%0d", rows, score_count, buffered); $stop; // 拒绝额外暴露发送暂存容量。
                end // 结束独立沿前容量检查。
                if (valid && (source == 4'd7)) begin // UART transport 独立核对头格式和逐字连续性。
                    if (word_index == 6'd0) begin // 新消息头只能在没有未完成消息时提交。
                        if ((active_length != 0) || (word[26:0] != 27'd4) || last || uart_done) begin // 头不释放 payload 存储或完成消息。
                            $display("FAIL uart_tx_path header row=%0d word=%h", rows, word); $stop; // 拒绝重入、错误编码和提前完成。
                        end // 结束新消息头检查。
                        active_length = {27'd0, word[31:27]}+1; next_index = 1; // 从实际头解码独立负载长度。
                        if (active_length > score_count) begin // 完整暂存要求头发送前已有全部固件数据。
                            $display("FAIL uart_tx_path unavailable payload row=%0d", rows); $stop; // 不允许提前发布尚未接纳的数据。
                        end // 结束独立消息长度与数据资格检查。
                    end else begin // 每个实际 payload 必须匹配最早未发送的固件接受字。
                        if ((score_count == 0) || (active_length == 0) || (word_index != next_index[5:0]) || (word !== scoreboard[score_read])) begin // 直接检查真实 SRAM 路径的数据内容与顺序。
                            $display("FAIL uart_tx_path payload row=%0d word=%h expected=%h index=%0d", rows, word, scoreboard[score_read], next_index); $stop; // 检出丢字、重复、重排或位翻转。
                        end // 结束端到端 payload 比较。
                        if ((last !== (next_index == active_length)) || (uart_done !== last)) begin // 完成事件必须精确重合于实际最后负载。
                            $display("FAIL uart_tx_path completion row=%0d", rows); $stop; // 拒绝错误边界或双方完成事件不一致。
                        end // 结束消息末字独立检查。
                        score_read = (score_read+1)%8192; score_count = score_count-1; payloads = payloads+1; // 只有实际 payload 发送释放固件总容量。
                        if (last) begin // 整条消息完成才结算 captured 长度的发送信用。
                            score_tx = (score_tx+active_length)%4096; active_length = 0; next_index = 0; uart_messages = uart_messages+1; // 模计数从实际消息头独立计算。
                        end else next_index = next_index+1; // 中间字只推进待检查的 payload 索引。
                    end // 结束 UART 头与负载分支。
                end else if (valid) begin // 其他组消息只能在 UART 所有权空闲时服务。
                    if ((active_length != 0) || !last || (word_index != 6'd0) || uart_done) begin // 禁止竞争源插入 UART 消息内部。
                        $display("FAIL uart_tx_path interleave row=%0d", rows); $stop; // 独立于仲裁参考模型检查不可穿插。
                    end // 结束其他消息边界检查。
                    other_messages = other_messages+1; // 统计实际非 UART transport 消息完成。
                end // 结束当前消息服务的独立检查。
                if (stimulus[376] && fw_ready) begin // 只保存真实被 DUT 接受的固件原始输入。
                    scoreboard[score_write] = stimulus[375:344]; score_write = (score_write+1)%8192; score_count = score_count+1; writes = writes+1; // 允许真实发送与固件写入同沿发生。
                end // 结束真实固件接受事件记录。
            end // 结束沿前独立事件核验与下一状态建立。
            #1 i_clk = 1'b1; // 实际 SRAM、FIFO、发送源与仲裁器同时采样。
            #1; // 等待 SRAM 输出和非阻塞状态更新完成。
            if ((observed_after !== expected_after) || (buffered !== score_count[12:0]) || (tx_counter !== score_tx[11:0]) || (score_count > C_TX_DEPTH)) begin // 同时核对模型与端到端容量及信用守恒。
                $display("FAIL uart_tx_path post row=%0d actual=%h expected=%h count=%0d tx=%0d", rows, observed_after, expected_after, score_count, score_tx); $stop; // 保留完整沿后状态证据。
            end // 结束沿后比较。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成当前本地仿真周期。
            rows = rows+1; fields = $fscanf(fd, "%h %h %h", stimulus, expected, expected_after); // 读取下一个完整输入周期。
        end // 结束全部向量执行。
        if ((fields != -1) || (rows < 10000) || (payloads < 5000) || (score_count != 0) || (active_length != 0)) begin // 必须完成有活动的轨迹并排空全部未复位丢弃的数据。
            $display("FAIL uart_tx_path incomplete fields=%0d rows=%0d payloads=%0d count=%0d", fields, rows, payloads, score_count); $stop; // 拒绝截断文件与未排空通过。
        end // 结束最终活动量及所有权检查。
        $fclose(fd); // 完整读取后关闭向量文件。
        $display("PASS uart_tx_path rows=%0d writes=%0d payloads=%0d uart_messages=%0d other_messages=%0d resets=%0d", rows, writes, payloads, uart_messages, other_messages, resets); // 唯一真实完成标记供运行器校验。
        $finish; // 所有模型比较和端到端内容检查通过后正常退出。
    end // 结束实际存储路径自检流程。
endmodule // 结束 UART 实际存储路径测试模块。
