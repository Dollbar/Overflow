`timescale 1ps/1ps // 以皮秒真实推进稳定控制时钟。
module dl_basic_control_tb; // 模块逐沿比较全部原生输入和独立参考输出。
    parameter C_CLOCK_PERIOD_PS = 640; // 本次仿真采用的真实控制周期。
    localparam C_LOW_PS = C_CLOCK_PERIOD_PS/2; // 奇数周期也保留完整低电平时长。
    localparam C_HIGH_PS = C_CLOCK_PERIOD_PS-C_LOW_PS; // 两个半周期之和恰为声明周期。
    reg i_clk; // 唯一未门控的原始采样时钟。
    reg [102:0] vec_inputs; // 向量全部原生输入，最高位为低有效复位。
    reg [193:0] expected_before, expected_after; // 独立参考的沿前及沿后完整输出。
    wire [193:0] actual; // 所有公开输出按契约顺序拼接。
    reg [4095:0] path_vectors; // 从运行参数取得向量路径。
    integer file_vectors, scan_status; // 保存文件和完整三字段解析状态。
    reg [31:0] cnt_rows; // 仅统计实际执行且两侧检查通过的时钟沿。
    wire i_rstn; // 原生输入 reset。
    wire i_local_valid; // 原生输入 local_valid。
    wire [2:0] i_local_kind; // 原生输入 local_kind。
    wire [15:0] i_local_rate; // 原生输入 local_rate。
    wire i_device_valid; // 原生输入 device_valid。
    wire [9:0] i_device_id; // 原生输入 device_id。
    wire i_device_type; // 原生输入 device_type。
    wire i_port_valid; // 原生输入 port_valid。
    wire [11:0] i_port; // 原生输入 port。
    wire i_folding; // 原生输入 folding。
    wire i_tx_ready_advertised; // 原生输入 tx_ready_advertised。
    wire i_symbols_valid; // 原生输入 symbols_valid。
    wire i_tx_limit_valid; // 原生输入 tx_limit_valid。
    wire [15:0] i_tx_limit; // 原生输入 tx_limit。
    wire i_rx_valid; // 原生输入 rx_valid。
    wire [31:0] i_rx_word; // 原生输入 rx_word。
    wire [3:0] i_source_take; // 原生输入 source_take。
    wire o_local_ready; // 独立参考观察 local_ready。
    wire o_local_pending; // 独立参考观察 local_pending。
    wire o_local_waiting; // 独立参考观察 local_waiting。
    wire o_remote_pending; // 独立参考观察 remote_pending。
    wire [3:0] o_source_pending; // 独立参考观察 source_pending。
    wire [127:0] o_source_words; // 独立参考观察 source_words。
    wire o_local_start; // 独立参考观察 local_start。
    wire o_local_commit; // 独立参考观察 local_commit。
    wire o_local_done; // 独立参考观察 local_done。
    wire o_reply_done; // 独立参考观察 reply_done。
    wire o_rx_request; // 独立参考观察 rx_request。
    wire o_rx_noop; // 独立参考观察 rx_noop。
    wire o_rx_unhandled; // 独立参考观察 rx_unhandled。
    wire o_rx_unsupported; // 独立参考观察 rx_unsupported。
    wire o_rx_unmatched_ack; // 独立参考观察 rx_unmatched_ack。
    wire o_rx_overlap; // 独立参考观察 rx_overlap。
    wire o_peer_rate_valid; // 独立参考观察 peer_rate_valid。
    wire [15:0] o_peer_rate; // 独立参考观察 peer_rate。
    wire o_peer_device_valid; // 独立参考观察 peer_device_valid。
    wire [1:0] o_peer_device_type; // 独立参考观察 peer_device_type。
    wire [9:0] o_peer_device_id; // 独立参考观察 peer_device_id。
    wire o_peer_port_valid; // 独立参考观察 peer_port_valid。
    wire [11:0] o_peer_port; // 独立参考观察 peer_port。
    wire o_peer_rate_update; // 独立参考观察 peer_rate_update。
    wire o_deadline_miss; // 独立参考观察 deadline_miss。
    wire o_deadline_fault; // 独立参考观察 deadline_fault。
    wire o_protocol_fault; // 独立参考观察 protocol_fault。
    wire o_error; // 独立参考观察 error。
    reg [31:0] cnt_local_start; // 独立累计真实沿前事件 local_start。
    reg [31:0] cnt_local_commit; // 独立累计真实沿前事件 local_commit。
    reg [31:0] cnt_local_done; // 独立累计真实沿前事件 local_done。
    reg [31:0] cnt_reply_done; // 独立累计真实沿前事件 reply_done。
    reg [31:0] cnt_rx_request; // 独立累计真实沿前事件 rx_request。
    reg [31:0] cnt_rx_noop; // 独立累计真实沿前事件 rx_noop。
    reg [31:0] cnt_rx_unhandled; // 独立累计真实沿前事件 rx_unhandled。
    reg [31:0] cnt_rx_unsupported; // 独立累计真实沿前事件 rx_unsupported。
    reg [31:0] cnt_rx_unmatched_ack; // 独立累计真实沿前事件 rx_unmatched_ack。
    reg [31:0] cnt_rx_overlap; // 独立累计真实沿前事件 rx_overlap。
    reg [31:0] cnt_peer_rate_update; // 独立累计真实沿前事件 peer_rate_update。
    reg [31:0] cnt_deadline_miss; // 独立累计真实沿前事件 deadline_miss。
    reg [31:0] cnt_error; // 独立累计真实沿前事件 error。
    assign {i_rstn, i_local_valid, i_local_kind, i_local_rate, i_device_valid, i_device_id, i_device_type, i_port_valid, i_port, i_folding, i_tx_ready_advertised, i_symbols_valid, i_tx_limit_valid, i_tx_limit, i_rx_valid, i_rx_word, i_source_take} = vec_inputs; // 无截断解包全部输入字段。
    assign actual = {o_local_ready, o_local_pending, o_local_waiting, o_remote_pending, o_source_pending, o_source_words, o_local_start, o_local_commit, o_local_done, o_reply_done, o_rx_request, o_rx_noop, o_rx_unhandled, o_rx_unsupported, o_rx_unmatched_ack, o_rx_overlap, o_peer_rate_valid, o_peer_rate, o_peer_device_valid, o_peer_device_type, o_peer_device_id, o_peer_port_valid, o_peer_port, o_peer_rate_update, o_deadline_miss, o_deadline_fault, o_protocol_fault, o_error}; // 不排除无效周期或任何公开诊断。
    dl_basic_message_control #(.C_CLOCK_PERIOD_PS(C_CLOCK_PERIOD_PS)) DUT ( // 实例化实际待测控制RTL。
        .i_clk(i_clk), // 连接同名原生端口。
        .i_rstn(i_rstn), // 连接同名原生端口。
        .i_local_valid(i_local_valid), // 连接同名原生端口。
        .i_local_kind(i_local_kind), // 连接同名原生端口。
        .i_local_rate(i_local_rate), // 连接同名原生端口。
        .i_device_valid(i_device_valid), // 连接同名原生端口。
        .i_device_id(i_device_id), // 连接同名原生端口。
        .i_device_type(i_device_type), // 连接同名原生端口。
        .i_port_valid(i_port_valid), // 连接同名原生端口。
        .i_port(i_port), // 连接同名原生端口。
        .i_folding(i_folding), // 连接同名原生端口。
        .i_tx_ready_advertised(i_tx_ready_advertised), // 连接同名原生端口。
        .i_symbols_valid(i_symbols_valid), // 连接同名原生端口。
        .i_tx_limit_valid(i_tx_limit_valid), // 连接同名原生端口。
        .i_tx_limit(i_tx_limit), // 连接同名原生端口。
        .i_rx_valid(i_rx_valid), // 连接同名原生端口。
        .i_rx_word(i_rx_word), // 连接同名原生端口。
        .i_source_take(i_source_take), // 连接同名原生端口。
        .o_local_ready(o_local_ready), // 连接同名原生端口。
        .o_local_pending(o_local_pending), // 连接同名原生端口。
        .o_local_waiting(o_local_waiting), // 连接同名原生端口。
        .o_remote_pending(o_remote_pending), // 连接同名原生端口。
        .o_source_pending(o_source_pending), // 连接同名原生端口。
        .o_source_words(o_source_words), // 连接同名原生端口。
        .o_local_start(o_local_start), // 连接同名原生端口。
        .o_local_commit(o_local_commit), // 连接同名原生端口。
        .o_local_done(o_local_done), // 连接同名原生端口。
        .o_reply_done(o_reply_done), // 连接同名原生端口。
        .o_rx_request(o_rx_request), // 连接同名原生端口。
        .o_rx_noop(o_rx_noop), // 连接同名原生端口。
        .o_rx_unhandled(o_rx_unhandled), // 连接同名原生端口。
        .o_rx_unsupported(o_rx_unsupported), // 连接同名原生端口。
        .o_rx_unmatched_ack(o_rx_unmatched_ack), // 连接同名原生端口。
        .o_rx_overlap(o_rx_overlap), // 连接同名原生端口。
        .o_peer_rate_valid(o_peer_rate_valid), // 连接同名原生端口。
        .o_peer_rate(o_peer_rate), // 连接同名原生端口。
        .o_peer_device_valid(o_peer_device_valid), // 连接同名原生端口。
        .o_peer_device_type(o_peer_device_type), // 连接同名原生端口。
        .o_peer_device_id(o_peer_device_id), // 连接同名原生端口。
        .o_peer_port_valid(o_peer_port_valid), // 连接同名原生端口。
        .o_peer_port(o_peer_port), // 连接同名原生端口。
        .o_peer_rate_update(o_peer_rate_update), // 连接同名原生端口。
        .o_deadline_miss(o_deadline_miss), // 连接同名原生端口。
        .o_deadline_fault(o_deadline_fault), // 连接同名原生端口。
        .o_protocol_fault(o_protocol_fault), // 连接同名原生端口。
        .o_error(o_error) // 连接同名原生端口。
    ); // 结束完整被测端口连接。
    initial begin // 驱动真实时钟并对每个向量执行两次比较。
        i_clk = 1'b0; // 初始原始时钟为低电平。
        vec_inputs = 103'd0; // 首个真实复位沿前禁止全部接口事件。
        cnt_rows = 32'd0; // 尚未执行任何有效向量。
        cnt_local_start = 32'd0; // 清零事件统计 local_start。
        cnt_local_commit = 32'd0; // 清零事件统计 local_commit。
        cnt_local_done = 32'd0; // 清零事件统计 local_done。
        cnt_reply_done = 32'd0; // 清零事件统计 reply_done。
        cnt_rx_request = 32'd0; // 清零事件统计 rx_request。
        cnt_rx_noop = 32'd0; // 清零事件统计 rx_noop。
        cnt_rx_unhandled = 32'd0; // 清零事件统计 rx_unhandled。
        cnt_rx_unsupported = 32'd0; // 清零事件统计 rx_unsupported。
        cnt_rx_unmatched_ack = 32'd0; // 清零事件统计 rx_unmatched_ack。
        cnt_rx_overlap = 32'd0; // 清零事件统计 rx_overlap。
        cnt_peer_rate_update = 32'd0; // 清零事件统计 peer_rate_update。
        cnt_deadline_miss = 32'd0; // 清零事件统计 deadline_miss。
        cnt_error = 32'd0; // 清零事件统计 error。
        if (!$value$plusargs("VECTORS=%s", path_vectors)) begin // 缺失向量路径时明确失败。
            $display("FAIL missing VECTORS"); $stop; // 不允许空跑冒充验证。
        end // 结束路径检查。
        file_vectors = $fopen(path_vectors, "r"); // 打开本次不可变完整向量。
        if (file_vectors == 0) begin // 无法打开数据时中止。
            $display("FAIL vectors open"); $stop; // 保留明确失败退出。
        end // 结束文件状态检查。
        while (!$feof(file_vectors)) begin // 每行实际执行一个完整时钟周期。
            scan_status = $fscanf(file_vectors, "%h %h %h", vec_inputs, expected_before, expected_after); // 读取全部三字段。
            if (scan_status == 3) begin // 仅接受完整合法记录。
                #(C_LOW_PS); // 真实低电平等待而非跳过时钟沿。
                if (actual !== expected_before) begin // 完整检查沿前输出。
                    $display("FAIL pre row=%0d actual=%h expected=%h", cnt_rows, actual, expected_before); $stop; // 记录实际不一致。
                end // 结束沿前检查。
                if (o_local_start) cnt_local_start = cnt_local_start+32'd1; // 累计真实沿前 local_start。
                if (o_local_commit) cnt_local_commit = cnt_local_commit+32'd1; // 累计真实沿前 local_commit。
                if (o_local_done) cnt_local_done = cnt_local_done+32'd1; // 累计真实沿前 local_done。
                if (o_reply_done) cnt_reply_done = cnt_reply_done+32'd1; // 累计真实沿前 reply_done。
                if (o_rx_request) cnt_rx_request = cnt_rx_request+32'd1; // 累计真实沿前 rx_request。
                if (o_rx_noop) cnt_rx_noop = cnt_rx_noop+32'd1; // 累计真实沿前 rx_noop。
                if (o_rx_unhandled) cnt_rx_unhandled = cnt_rx_unhandled+32'd1; // 累计真实沿前 rx_unhandled。
                if (o_rx_unsupported) cnt_rx_unsupported = cnt_rx_unsupported+32'd1; // 累计真实沿前 rx_unsupported。
                if (o_rx_unmatched_ack) cnt_rx_unmatched_ack = cnt_rx_unmatched_ack+32'd1; // 累计真实沿前 rx_unmatched_ack。
                if (o_rx_overlap) cnt_rx_overlap = cnt_rx_overlap+32'd1; // 累计真实沿前 rx_overlap。
                if (o_peer_rate_update) cnt_peer_rate_update = cnt_peer_rate_update+32'd1; // 累计真实沿前 peer_rate_update。
                if (o_deadline_miss) cnt_deadline_miss = cnt_deadline_miss+32'd1; // 累计真实沿前 deadline_miss。
                if (o_error) cnt_error = cnt_error+32'd1; // 累计真实沿前 error。
                i_clk = 1'b1; // 触发唯一原始上升沿。
                #1; // 等待非阻塞寄存赋值完成。
                if (actual !== expected_after) begin // 完整检查沿后状态和组合输出。
                    $display("FAIL post row=%0d actual=%h expected=%h", cnt_rows, actual, expected_after); $stop; // 记录寄存边界错误。
                end // 结束沿后检查。
                #(C_HIGH_PS-1); // 完成完整高电平预算。
                i_clk = 1'b0; // 回到下一行的低电平阶段。
                cnt_rows = cnt_rows+32'd1; // 一次计数对应一个实际已验证沿。
            end else if (scan_status != -1) begin // 非文件末尾的不完整记录必须失败。
                $display("FAIL vector format"); $stop; // 不忽略损坏输入。
            end // 结束三字段记录处理。
        end // 结束实际向量时钟循环。
        $fclose(file_vectors); // 关闭已消费的输入文件。
        $display("PASS dl_basic_control rows=%0d local_start=%0d local_commit=%0d local_done=%0d reply_done=%0d rx_request=%0d rx_noop=%0d rx_unhandled=%0d rx_unsupported=%0d rx_unmatched_ack=%0d rx_overlap=%0d peer_rate_update=%0d deadline_miss=%0d error=%0d", cnt_rows, cnt_local_start, cnt_local_commit, cnt_local_done, cnt_reply_done, cnt_rx_request, cnt_rx_noop, cnt_rx_unhandled, cnt_rx_unsupported, cnt_rx_unmatched_ack, cnt_rx_overlap, cnt_peer_rate_update, cnt_deadline_miss, cnt_error); // 输出完整实际计数供运行器交叉核验。
        $finish; // 所有实际沿和公开输出比较通过后结束。
    end // 结束单一仿真驱动过程。
endmodule // 结束Basic控制器自检模块。
