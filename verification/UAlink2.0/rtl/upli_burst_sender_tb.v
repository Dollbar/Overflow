// Actual staged payload sender plus both credit banks against independent vectors.
// 日期2026-09-08；额外 journal 只按真实接受记录数据，不能用 DUT 输出生成期望。
`timescale 1ps/1ps // 同时支持正常和参考 UPLI 时钟仿真。
module upli_burst_sender_tb; // 完整暂存所有权及真实银行集成的自检模块。
    parameter integer C_NUM_PORTS = 1; // 原生 station 的有效端口数量。
    parameter integer C_CREDIT_WIDTH = 4; // 每个信用账户的计数宽度。
    parameter integer C_REQUEST_WIDTH = 96; // 不透明本地请求容器，不是标准打包宽度。
    parameter integer C_INIT_CYCLES = 2; // 两个银行的连续初始化过滤长度。
    parameter integer C_HALF_PERIOD_PS = 320; // 正常或参考时钟的半周期。
    parameter [C_CREDIT_WIDTH-1:0] C_DEFAULT_CAPACITY = 4; // 旧正常回归保持每账户四信用。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_REQ_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}; // 可显式传递真实 Req 容量，不预置 DUT 状态。
    parameter [C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0] C_DATA_CAPACITIES = {C_NUM_PORTS*5{C_DEFAULT_CAPACITY}}; // 独立的真实 OrigData 容量向量。
    parameter integer C_MIN_ROWS = 1000; // 旧回归非空门限不变；独立 profile 入口另核对精确行数。
    parameter integer C_MIN_REQUESTS = 200; // 全零容量配置允许显式声明零发送预期。
    parameter integer C_MIN_BEATS = 200; // profile 入口仍将真实数据计数与独立期望精确比较。
    parameter integer C_MIN_OVERLAYS = 1; // 只有无可用信用的 profile 可声明无 overlay。
    localparam integer C_INPUT_BITS = 2380+C_REQUEST_WIDTH; // 候选完整负载及两个真实返回通道。
    localparam integer C_EVENT_BITS = 592+C_REQUEST_WIDTH; // 完整请求和 OrigData 发出事件。
    localparam integer C_BANK_BITS = C_NUM_PORTS*5*C_CREDIT_WIDTH; // 每通道五账户的注册余额。
    localparam integer C_STATE_BITS = 18+2*C_BANK_BITS; // busy/phase、余额、初始化及诊断。
    reg i_clk; // 唯一同步 UPLI 时钟。
    reg [C_INPUT_BITS-1:0] stimulus; // 独立模型写出的全部本沿输入。
    reg [C_EVENT_BITS-1:0] expected; // 完整沿前输出，包含无效字段归零。
    reg [C_STATE_BITS-1:0] expected_before, expected_after, previous_state; // 模型状态与上一实际合法沿状态。
    wire rstn, credit_connected, beats_connected, candidate_valid, candidate_pool, candidate_has_data; // 连接资格和本地候选控制。
    wire [1:0] candidate_port, candidate_vc, candidate_num_beats; // 原候选元信息。
    wire [3:0] candidate_pools, candidate_error; // 每份数据的池选择及 Error。
    wire [C_REQUEST_WIDTH-1:0] candidate_request, req_payload; // 不透明请求容器进出。
    wire [2047:0] candidate_data; // offset 零位于最低的 512 位。
    wire [255:0] candidate_byte_enable; // 每份数据有独立的 64 个 ByteEn 位。
    wire [27:0] req_return, data_return; // 每通道返回 valid/pool/vc/num/init_done。
    wire accepted, req_valid, req_pool, data_valid, data_pool, data_last, data_error, known; // 实际事件与 TDM 资格。
    wire [1:0] req_port, req_vc, data_port, data_vc, data_offset, phase; // 实际完整元数据。
    wire [511:0] data_payload; // 实际 OrigData 字。
    wire [63:0] data_byte_enable; // 实际 OrigData 有效字节。
    wire [3:0] busy, req_init, data_init; // 寄存所有权与银行初始化。
    wire [C_BANK_BITS-1:0] req_balances, data_balances; // 实际两个银行的余额。
    wire req_credit_error, data_credit_error, credit_error_sticky; // 单沿诊断和持续本地汇总。
    wire [C_EVENT_BITS-1:0] observed; // 完整实际发出事件。
    wire [C_STATE_BITS-1:0] state_observed; // 状态直接来自真实 RTL 接口。
    reg [576:0] journal [0:C_NUM_PORTS*4-1]; // 独立 shift journal 与 RTL 静态槽实现不同。
    integer remaining [0:C_NUM_PORTS-1]; // 每端口 journal 尚待发出的字数。
    reg [4095:0] vector_path; // 运行入口显式传入的向量路径。
    integer fd, fields, row, requests, beats, overlays, journal_beats, p, n, slot; // 文件消费和非空测试计数。
    assign {rstn, credit_connected, beats_connected, candidate_valid, candidate_port, candidate_vc, candidate_pool, candidate_has_data, candidate_num_beats, candidate_pools, candidate_request, candidate_data, candidate_byte_enable, candidate_error, req_return, data_return} = stimulus; // 与独立生成器的字段顺序一一对应。
    assign observed = {req_valid, req_port, req_vc, req_pool, data_valid, data_port, data_vc, data_pool, data_offset, data_last, req_payload, data_payload, data_byte_enable, data_error}; // 不忽略任何无效输出字段。
    assign state_observed = {busy, known, phase, req_balances, data_balances, req_init, data_init, req_credit_error, data_credit_error, credit_error_sticky}; // 预约应包含在真实余额内。
    upli_burst_sender #( // 实际控制、寄存暂存和两个银行组成的 DUT。
        .C_NUM_PORTS(C_NUM_PORTS), .C_CREDIT_WIDTH(C_CREDIT_WIDTH), .C_REQUEST_WIDTH(C_REQUEST_WIDTH), // 显式匹配向量参数。
        .C_INIT_CYCLES(C_INIT_CYCLES), .C_DEFAULT_CAPACITY(C_DEFAULT_CAPACITY), .C_REQ_CAPACITIES(C_REQ_CAPACITIES), .C_DATA_CAPACITIES(C_DATA_CAPACITIES) // 显式传递默认及实际容量，避免覆盖向量后留下未使用默认参数。
    ) Sender_Inst ( // 不使用 TB 代替信用银行或 payload 保存。
        .i_clk(i_clk), .i_rstn(rstn), .i_credit_connected(credit_connected), .i_beats_connected(beats_connected), // 同步域与连接方向资格。
        .i_candidate_valid(candidate_valid), .i_candidate_port(candidate_port), .i_candidate_vc(candidate_vc), // 本地描述符控制。
        .i_candidate_pool(candidate_pool), .i_candidate_has_data(candidate_has_data), .i_candidate_num_beats(candidate_num_beats), .i_candidate_data_pools(candidate_pools), // 完整突发信用需求。
        .i_candidate_request(candidate_request), .i_candidate_data(candidate_data), .i_candidate_byte_enable(candidate_byte_enable), .i_candidate_error(candidate_error), // 接受前全部就绪的负载。
        .i_req_credit_valid(req_return[24 +: 4]), .i_req_credit_pool(req_return[20 +: 4]), .i_req_credit_vc(req_return[12 +: 8]), .i_req_credit_num(req_return[4 +: 8]), .i_req_credit_init_done(req_return[0 +: 4]), // 真实 Req 银行输入。
        .i_data_credit_valid(data_return[24 +: 4]), .i_data_credit_pool(data_return[20 +: 4]), .i_data_credit_vc(data_return[12 +: 8]), .i_data_credit_num(data_return[4 +: 8]), .i_data_credit_init_done(data_return[0 +: 4]), // 真实 OrigData 银行输入。
        .o_candidate_accepted(accepted), .o_req_valid(req_valid), .o_req_port(req_port), .o_req_vc(req_vc), .o_req_pool(req_pool), .o_req_payload(req_payload), // 请求与本地接受在同沿。
        .o_data_valid(data_valid), .o_data_port(data_port), .o_data_vc(data_vc), .o_data_pool(data_pool), .o_data_offset(data_offset), .o_data_last(data_last), // 真实首尾元数据。
        .o_data_payload(data_payload), .o_data_byte_enable(data_byte_enable), .o_data_error(data_error), // 完整 OrigData 字段。
        .o_req_balances(req_balances), .o_data_balances(data_balances), .o_req_init(req_init), .o_data_init(data_init), // 真实银行注册状态。
        .o_req_credit_error(req_credit_error), .o_data_credit_error(data_credit_error), .o_credit_error_sticky(credit_error_sticky), // 不把本地诊断伪装协议恢复。
        .o_busy(busy), .o_tdm_known(known), .o_tdm_port(phase) // 逐沿检查实际调度相位。
    ); // 结束真实集成 DUT 实例。
    initial begin // 完整有限轨迹及独立历史 journal 自检。
        i_clk = 1'b0; stimulus = {C_INPUT_BITS{1'b0}}; // 初始保持同步复位输入。
        row = 0; requests = 0; beats = 0; overlays = 0; journal_beats = 0; // 计数只依据实际事件。
        for (p = 0; p < C_NUM_PORTS; p = p+1) remaining[p] = 0; // TB 历史从空开始。
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin // 不允许缺失向量的空跑。
            $display("FAIL payload missing VECTORS"); $stop; // 缺参显式失败。
        end // 结束参数检查。
        fd = $fopen(vector_path, "r"); // 只读已生成的独立向量。
        if (fd == 0) begin // 文件不可访问不能跳过。
            $display("FAIL payload vector open"); $stop; // 确保错误退出。
        end // 结束文件检查。
        previous_state = state_observed; // 首次同步复位前不约束物理上电状态。
        fields = $fscanf(fd, "%h %h %h %h", stimulus, expected, expected_before, expected_after); // 每行显式带沿前与沿后状态。
        while (fields == 4) begin // 仅接受完整的四字段记录。
            #(C_HALF_PERIOD_PS-1); // 给组合输入到事件的路径稳定时间。
            if ((row > 0) && (state_observed !== previous_state)) begin // 输入变化不应异步清掉任何寄存观察。
                $display("FAIL payload asynchronous state row=%0d", row); $stop; // 捕获异步复位或组合余额。
            end // 结束状态稳定性检查。
            if ((row > 0) && ((observed !== expected) || (state_observed !== expected_before) || (accepted !== req_valid))) begin // 正常向量的银行诊断也必须为零。
                $display("FAIL payload pre row=%0d actual=%h expected=%h state=%h wanted=%h", row, observed, expected, state_observed, expected_before); $stop; // 第一处完整差异立即停止。
            end // 结束沿前模型比较。
            if (!rstn) begin // Journal 按实际同步采样沿复位，不保留旧尾部。
                for (p = 0; p < C_NUM_PORTS; p = p+1) remaining[p] = 0; // 丢弃所有尚未发出的历史。
            end else begin // 正常事件只在非复位沿写入测试历史。
                if (accepted && candidate_has_data) begin // 真实接受时抓取所有数据，不依赖期望文件。
                    p = {30'd0, candidate_port}; // 将两位端口显式扩展到 TB 整数。
                    if ((p >= C_NUM_PORTS) || (remaining[p] != 0)) begin // 旧 burst 尚未完成时不得覆盖。
                        $display("FAIL payload journal overwrite row=%0d port=%0d", row, p); $stop; // 捕获所有权丢失。
                    end // 结束 journal 所有权检查。
                    remaining[p] = {30'd0, candidate_num_beats}+1; // 独立记录原声明长度。
                    for (n = 0; n < 4; n = n+1) journal[p*4+n] = {candidate_data[n*512 +: 512], candidate_byte_enable[n*64 +: 64], candidate_error[n]}; // 完整保存每个字。
                end // 结束实际接受时的数据采样。
                if (data_valid) begin // 每个实际字都必须等于最早尚未发出的原始字。
                    p = {30'd0, data_port}; slot = p*4; // 当前 port 的独立队列头。
                    if ((p >= C_NUM_PORTS) || (remaining[p] == 0) || ({data_payload, data_byte_enable, data_error} !== journal[slot]) || (data_last !== (remaining[p] == 1))) begin // 队列语义不同于 RTL 静态 offset 选址。
                        $display("FAIL payload journal row=%0d port=%0d", row, p); $stop; // 检出污染、倒序及错 Last。
                    end // 结束原始所有权数据检查。
                    for (n = 0; n < 3; n = n+1) journal[slot+n] = journal[slot+n+1]; // 在 TB 中真实移除已发队首。
                    remaining[p] = remaining[p]-1; journal_beats = journal_beats+1; // 一次实际发送只退休一个原字。
                end // 结束 journal 退休。
            end // 结束正常历史采样。
            if (req_valid) requests = requests+1; // 只计真实发送请求。
            if (data_valid) beats = beats+1; // 只计真实发送数据。
            if (req_valid && !candidate_has_data && data_valid) overlays = overlays+1; // read 与原写数据同时发出。
            #1 i_clk = 1'b1; // 所有实际银行、控制和负载在同一沿更新。
            #1; // 等待 NBA 完成再观察状态。
            if (state_observed !== expected_after) begin // 比较实际扣减而非预置的银行快照。
                $display("FAIL payload post row=%0d actual=%h expected=%h", row, state_observed, expected_after); $stop; // 捕获重复扣减或初始化旁路。
            end // 结束沿后状态检查。
            #(C_HALF_PERIOD_PS-1) i_clk = 1'b0; // 完成本周期。
            row = row+1; previous_state = state_observed; // 保存实际状态用于下一沿稳定性检查。
            fields = $fscanf(fd, "%h %h %h %h", stimulus, expected, expected_before, expected_after); // 消费下一份独立记录。
        end // 结束全部轨迹。
        if ((fields != -1) || !$feof(fd) || (row < C_MIN_ROWS) || (requests < C_MIN_REQUESTS) || (beats < C_MIN_BEATS) || (overlays < C_MIN_OVERLAYS) || (journal_beats != beats)) begin // 旧回归门限保持，profile 入口另核对精确全部计数以拒绝截断。
            $display("FAIL payload incomplete rows=%0d requests=%0d beats=%0d overlays=%0d fields=%0d", row, requests, beats, overlays, fields); $stop; // 结果必须来自足量真实事件。
        end // 结束轨迹完整性检查。
        for (p = 0; p < C_NUM_PORTS; p = p+1) begin // 正常结束不能遗留未发送历史。
            if (remaining[p] != 0) begin $display("FAIL payload journal not drained port=%0d", p); $stop; end // 除 reset 明确丢弃外全部必须发完。
        end // 结束最终所有权检查。
        $fclose(fd); // 关闭读取完毕的有限向量。
        $display("PASS burst_payload rows=%0d ports=%0d credit_width=%0d request_width=%0d init_cycles=%0d period_ps=%0d requests=%0d data=%0d read_overlays=%0d journal=%0d", row, C_NUM_PORTS, C_CREDIT_WIDTH, C_REQUEST_WIDTH, C_INIT_CYCLES, C_HALF_PERIOD_PS*2, requests, beats, overlays, journal_beats); // 准确限定为本包装器真实仿真。
        $finish; // 全部比较通过后正常结束。
    end // 结束正常集成自检。
    initial begin // 独立超时保护。
        #(64'd1000000000000); // 留足参数矩阵最长轨迹时间。
        $display("FAIL payload timeout"); $stop; // 异常悬挂不视为通过。
    end // 结束测试看门狗。
endmodule // 结束完整暂存发送器自检模块。
