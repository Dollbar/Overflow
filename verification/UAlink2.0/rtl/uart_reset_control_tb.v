// 对实际复位控制器逐沿比较全部输出，并用绝对时间和环形队列独立检查协议事件。
`timescale 1ps/1ps // 所有重复行都推进真实时间，禁止跳过实际计时寄存器。
module uart_reset_control_tb; // 真实RTL的完整周期和独立事件记分板测试模块。
    parameter integer C_CLOCK_PERIOD_PS = 640; // 显式声明真实仿真周期并同值传入控制器。
    parameter integer C_RESPONSE_DEPTH = 4; // 同一向量配置下使用的响应存储容量。
    localparam [63:0] C_PERIOD = {32'd0, C_CLOCK_PERIOD_PS[31:0]}; // 绝对时间运算不使用三十二位有符号乘法。
    localparam [63:0] C_WAIT_CYCLES = (64'd10000000000+C_PERIOD-64'd1)/C_PERIOD; // 用真实十毫秒推导向上取整的等待沿数。
    reg i_clk; // 单一实际采样时钟由每个向量周期驱动。
    reg [9:0] stimulus; // 全部十位非时钟输入采用固定公开拼接顺序。
    reg [55:0] expected, expected_after; // 独立事件模型给出的完整沿前和最终沿后输出。
    wire [55:0] observed; // 实际模块的全部五十六位输出。
    wire local_ready, stream_reset, block_messages, pending; // 本地接纳资格和两类禁止状态。
    wire [31:0] word; // 实际发送边界提供的完整维护消息字。
    wire [1:0] kind; // 当前实际维护消息的唯一类型。
    wire waiting, local_start, local_done, retry, reply_done, fault, error; // 当前沿本地远端事件和故障诊断。
    wire [5:0] noops_left; // 实际控制器报告的排空余数。
    wire [4:0] response_count; // 实际待回复队列占用。
    reg [4095:0] vector_path; // 必须由调用方提供可追溯的精确向量文件。
    reg [33:0] repetitions, repetition; // 压缩行最多覆盖最小周期的完整十毫秒真实时钟。
    reg [63:0] edges, noops, requests, replies, starts, successes, retries, errors; // 只按真实沿前DUT事件累计活动量。
    integer fd, fields, rows, ignore_model; // 文件状态行数和独立记分板单独执行开关。
    reg flag_finished; // 独立完成进程读取实际循环统计以避免工具错误传播初值。
    reg sb_owned, sb_wait, sb_fault, sb_local_all; // 记分板只从公开事件建立独立所有权。
    reg sb_scope [0:15]; // 环形参考队列与DUT的移位存储具有不同组织。
    integer sb_head, sb_tail, sb_noops; // 环形索引与向上累计的实际NoOp字数。
    reg [63:0] sb_received, sb_replied, sb_request_edge, sb_request_time; // 无截断条数和Request实际提交时间。
    reg [63:0] sb_count; // 通过累计接收减累计响应计算当前有效队列深度。
    reg sb_ready, sb_start, sb_success, sb_retry, sb_pending, sb_reply, sb_error; // 从参考所有权和当前输入推导同沿事件。
    reg sb_stream, sb_block; // 参考数据流复位与普通消息禁止状态。
    reg [1:0] sb_kind; // 根据已提交字数而非DUT阶段编码选择期望类型。
    reg [31:0] sb_word; // 使用字面线编码及环形队首生成独立期望消息。
    reg [5:0] sb_left; // 由四十减累计真实提交形成独立余数。
    reg [55:0] sb_expected; // 独立记分板的全部公开输出期望。
    assign observed = {local_ready, stream_reset, block_messages, pending, word, kind, waiting, noops_left, response_count, local_start, local_done, retry, reply_done, fault, error}; // 全部输出参与模型和记分板双重检查。
    dl_uart_reset_control #( // 实际可综合控制器没有计时替换或内部寄存器强制。
        .C_CLOCK_PERIOD_PS(C_CLOCK_PERIOD_PS), .C_RESPONSE_DEPTH(C_RESPONSE_DEPTH) // 参数精确匹配保留向量摘要。
    ) Reset_Inst ( // 所有输入均由当前向量在同一个时钟域驱动。
        .i_clk(i_clk), .i_rstn(stimulus[9]), .i_local_request(stimulus[8]), .i_local_all(stimulus[7]), // 全局复位和固件请求范围。
        .i_rx_request(stimulus[6]), .i_rx_request_all(stimulus[5]), .i_rx_response(stimulus[4]), // 已解码且适用本流的远端事件。
        .i_rx_response_status(stimulus[3:1]), .i_tx_take(stimulus[0]), // 原始状态资格与真实维护字提交。
        .o_local_ready(local_ready), .o_stream_reset(stream_reset), .o_block_messages(block_messages), // 观察控制资格及完整禁止状态。
        .o_tx_pending(pending), .o_tx_word(word), .o_tx_kind(kind), .o_waiting(waiting), // 观察完整发送字和本地等待所有权。
        .o_noops_left(noops_left), .o_response_count(response_count), .o_local_start(local_start), // 观察两类计数及固件真实接纳。
        .o_local_done(local_done), .o_retry(retry), .o_reply_done(reply_done), .o_fault(fault), .o_error(error) // 成功重试远端完成及故障均独立检查。
    ); // 结束实际模块全部端口连接。
    initial begin // 每行可重复执行但不能跳过任何真实时钟和比较。
        i_clk = 1'b0; stimulus = 10'd0; // 第一条记录必须先建立同步复位状态。
        flag_finished = 1'b0; // 完成检查只有在文件实际执行到结束后才可触发。
        rows = 0; edges = 64'd0; noops = 64'd0; requests = 64'd0; replies = 64'd0; // 初始化实际传输计数。
        starts = 64'd0; successes = 64'd0; retries = 64'd0; errors = 64'd0; // 初始化实际控制事件统计。
        sb_owned = 1'b0; sb_wait = 1'b0; sb_fault = 1'b0; sb_local_all = 1'b0; // 记分板初值只在首条全局复位后参与有效观察。
        sb_head = 0; sb_tail = 0; sb_noops = 0; sb_received = 64'd0; sb_replied = 64'd0; // 空队列不读取尚未有效的参考槽位。
        sb_request_edge = 64'd0; sb_request_time = 64'd0; // 只有真正提交Request才重设时间锚点。
        ignore_model = $test$plusargs("NO_MODEL"); // 故障审查可单独运行事件记分板而不读取模型期望作判断。
        if ((C_CLOCK_PERIOD_PS < 4) || !$value$plusargs("VECTORS=%s", vector_path)) begin // 本TB需要前后稳定时间，最小器件参数另由展开和证明检查。
            $display("FAIL uart_reset_control period or missing VECTORS"); $stop; // 配置或入口错误不能被空跑掩盖。
        end // 结束测试入口合法性检查。
        fd = $fopen(vector_path, "r"); // 只读本次构建保存的独立向量。
        if (fd == 0) begin // 文件无法读取必须显式失败。
            $display("FAIL uart_reset_control vector open"); $stop; // 保留失败原因并终止仿真。
        end // 结束向量文件打开检查。
        fields = $fscanf(fd, "%h %h %h %h", repetitions, stimulus, expected, expected_after); // 记录包含重复数输入及两个完整输出期望。
        while (fields == 4) begin // 仅完整记录可以推进真实时钟。
            if ((repetitions == 34'd0) || ((rows == 0) && stimulus[9])) begin // 首行必须复位且重复数不得为空。
                $display("FAIL uart_reset_control invalid row=%0d", rows); $stop; // 避免初始寄存器默认值或空记录造成假通过。
            end // 结束每行基本前提检查。
            for (repetition = 34'd0; repetition < repetitions; repetition = repetition+34'd1) begin // 每个压缩重复都执行真实上升沿。
                #(C_CLOCK_PERIOD_PS/2-1); // 在时钟上升前等待输入组合路径稳定。
                if ((ignore_model == 0) && (observed !== expected)) begin // 全部控制状态和数据必须与事件模型逐位相等。
                    $display("FAIL uart_reset_control pre row=%0d repeat=%0d edge=%0d actual=%h expected=%h", rows, repetition, edges, observed, expected); $stop; // 定位压缩行内部第一个功能差异。
                end // 结束模型沿前比较。
                sb_count = sb_received-sb_replied; // 环形队列占用由独立累计事件差计算。
                sb_ready = !sb_fault && !sb_owned; sb_start = sb_ready && stimulus[8]; // 本地接纳只依赖独立本地所有权。
                sb_success = !sb_fault && sb_wait && stimulus[4] && (stimulus[3:1] == 3'd0); // 提前或保留状态响应不能完成当前等待。
                sb_retry = !sb_fault && sb_wait && ((edges-sb_request_edge) >= C_WAIT_CYCLES) && !sb_success; // 以绝对提交沿距离检查重试边界。
                sb_pending = !sb_fault && !sb_start && !sb_retry && ((sb_owned && !sb_wait) || (sb_count != 64'd0)); // 本地序列或独立远端所有权建立真实维护资格。
                sb_kind = !sb_pending ? 2'd0 : (sb_owned && !sb_wait) ? ((sb_noops < 40) ? 2'd1 : 2'd2) : 2'd3; // 按累计四十次提交决定何时允许Request。
                sb_word = 32'd0; // 无效和NoOp都要求全部三十二位清零。
                if (sb_kind == 2'd2) sb_word = sb_local_all ? 32'h00001184 : 32'h00000184; // 独立字面Request编码包含冻结的本地范围。
                if (sb_kind == 2'd3) sb_word = sb_scope[sb_head] ? 32'h000011C4 : 32'h000001C4; // 独立环形队首决定SUCCESS响应范围。
                sb_reply = (sb_kind == 2'd3) && stimulus[0]; // 只有真正接受的响应能释放队列容量。
                sb_error = !sb_fault && ((stimulus[0] && !sb_pending) || (stimulus[6] && (sb_count == {32'd0, C_RESPONSE_DEPTH[31:0]}) && !sb_reply)); // 独立推导非法提交和不可借位的满队列故障。
                sb_stream = sb_fault || sb_owned || (sb_count != 64'd0) || sb_start || stimulus[6]; // 两个所有权与新请求共同保持流清空。
                sb_block = sb_fault || sb_start || sb_retry || (sb_owned && !sb_wait); // WAIT期间普通消息重新允许发送。
                sb_left = (sb_owned && !sb_wait && !sb_fault) ? (6'd40-sb_noops[5:0]) : 6'd0; // 上计数记分板与RTL下计数独立交叉检查。
                sb_expected = {sb_ready, sb_stream, sb_block, sb_pending, sb_word, sb_kind, (sb_wait && !sb_fault), sb_left, sb_count[4:0], sb_start, (sb_success && !sb_error), (sb_retry && !sb_error), sb_reply, sb_fault, sb_error}; // 从事件历史构造全部公开输出。
                if (!stimulus[9]) sb_expected = {1'b0, 1'b1, 1'b1, 53'd0}; // 全局复位仅保留流清空和全部消息阻断。
                if (observed !== sb_expected) begin // 即使关闭模型比较也不能绕过独立事件和线编码检查。
                    $display("FAIL uart_reset_control scoreboard row=%0d edge=%0d actual=%h expected=%h", rows, edges, observed, sb_expected); $stop; // 完整给出第二参考的首个差异。
                end // 结束独立记分板沿前比较。
                if (retry && (($time-sb_request_time) != C_WAIT_CYCLES*C_PERIOD)) begin // 重试必须同时满足真实皮秒距离和实际沿计数。
                    $display("FAIL uart_reset_control physical deadline edge=%0d", edges); $stop; // 检出测试台或控制器错误缩短真实等待。
                end // 结束真实时钟十毫秒量化边界检查。
                if (pending && stimulus[0] && (kind == 2'd1)) noops = noops+64'd1; // 只把实际NoOp字提交计入总数。
                if (pending && stimulus[0] && (kind == 2'd2)) requests = requests+64'd1; // Request总数只来自实际发送边界。
                if (reply_done) replies = replies+64'd1; // 每条真实响应独立统计。
                if (local_start) starts = starts+64'd1; if (local_done) successes = successes+64'd1; // 本地请求和完成使用实际事件。
                if (retry) retries = retries+64'd1; if (error) errors = errors+64'd1; // 超时与注入故障不计为同一种结果。
                if (!stimulus[9] || error) begin // 全局或当前错误取消参考所有权并明确故障恢复边界。
                    sb_owned = 1'b0; sb_wait = 1'b0; sb_fault = stimulus[9]; sb_local_all = 1'b0; // 故障只能由后续全局复位清除。
                    sb_head = 0; sb_tail = 0; sb_noops = 0; sb_received = 64'd0; sb_replied = 64'd0; // 重新初始化逻辑队列而不依赖旧槽位内容。
                end else if (!sb_fault) begin // 正常事件更新完全由公开沿前事件和输入驱动。
                    if (local_done) begin // 成功只释放本地等待而保留远端回复义务。
                        sb_owned = 1'b0; sb_wait = 1'b0; // 远端队列在后续独立分支处理。
                    end // 结束本地成功所有权更新。
                    if (local_start || retry) begin // 新尝试均要求新的四十次真实NoOp提交。
                        sb_owned = 1'b1; sb_wait = 1'b0; sb_noops = 0; // 重试不能继承上次排空进度。
                        if (local_start) sb_local_all = stimulus[7]; // 重试期间保留原始范围而不采样无关固件输入。
                    end // 结束开始或重试事件更新。
                    if (pending && stimulus[0] && (kind == 2'd1)) sb_noops = sb_noops+1; // 停顿不改变已提交字数。
                    if (pending && stimulus[0] && (kind == 2'd2)) begin // 真正发出Request才建立唯一时间锚点。
                        sb_wait = 1'b1; sb_request_edge = edges; sb_request_time = $time; // 绝对时间和累计沿数同时记录。
                    end // 结束实际Request提交处理。
                    if (reply_done) begin // 先移除旧队首以允许满队列同拍替换。
                        sb_replied = sb_replied+64'd1; sb_head = (sb_head+1)%C_RESPONSE_DEPTH; // 环形队列使用独立读索引。
                    end // 结束实际响应提交处理。
                    if (stimulus[6]) begin // 每个容量允许的输入请求都占用独立槽位。
                        sb_scope[sb_tail] = stimulus[5]; sb_received = sb_received+64'd1; sb_tail = (sb_tail+1)%C_RESPONSE_DEPTH; // 环形队列按输入到达顺序保存原始范围。
                    end // 结束远端请求入队处理。
                end // 结束独立参考事件更新。
                #1 i_clk = 1'b1; // 推进实际RTL所有寄存器的真实共同上升沿。
                #1; // 等待非阻塞寄存更新后比较完整沿后输出。
                if ((ignore_model == 0) && (observed !== ((repetition+34'd1 == repetitions) ? expected_after : expected))) begin // 重复行中间沿后必须仍等于原沿前输出。
                    $display("FAIL uart_reset_control post row=%0d repeat=%0d edge=%0d actual=%h expected=%h", rows, repetition, edges, observed, ((repetition+34'd1 == repetitions) ? expected_after : expected)); $stop; // 检出任何被压缩行隐藏的中间状态变化。
                end // 结束模型沿后比较。
                #(C_CLOCK_PERIOD_PS-C_CLOCK_PERIOD_PS/2-1) i_clk = 1'b0; // 完成精确声明周期，奇数周期也不截断总时间。
                edges = edges+64'd1; // 每次实际上升沿恰好增加一次统计。
            end // 结束当前压缩行的全部真实周期。
            rows = rows+1; // 文件行数单独统计，不能冒充实际周期数。
            fields = $fscanf(fd, "%h %h %h %h", repetitions, stimulus, expected, expected_after); // 继续读取完整记录直到严格文件结束。
        end // 结束向量文件的全部实际执行。
        flag_finished = 1'b1; // 显式把完整执行完成事件交给独立终态检查。
    end // 结束复位控制实际周期自检序列。
    initial begin // 独立进程保留真实运行统计并执行严格终态检查。
        wait (flag_finished); // 等待所有重复周期和完整记录均被实际处理。
        #1; // 在最终运行变量稳定后读取真实终态。
        if ((fields != -1) || (rows < 100) || (noops < 64'd120) || (requests < 64'd3) || (retries == 64'd0) || (successes < 64'd2) || (errors < 64'd4) || sb_owned || sb_fault || (sb_received != sb_replied)) begin // 完成必须包含关键协议活动并回到已恢复空闲状态。
            $display("FAIL uart_reset_control incomplete fields=%0d rows=%0d edges=%0d", fields, rows, edges); $stop; // 拒绝破损文件和缺失实际边界事件的短跑。
        end // 结束活动量及最终恢复状态校验。
        $fclose(fd); // 所有实际周期完成后关闭独立向量文件。
        $display("PASS uart_reset_control rows=%0d edges=%0d noops=%0d requests=%0d replies=%0d starts=%0d successes=%0d retries=%0d errors=%0d", rows, edges, noops, requests, replies, starts, successes, retries, errors); // 唯一完成标记必须与独立摘要逐项相等。
        $finish; // 所有模型和独立记分板检查通过后正常结束。
    end // 结束独立终态及运行统计检查。
endmodule // 结束UART复位控制测试模块。
